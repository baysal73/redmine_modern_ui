<script setup lang="ts">
import { ExternalLink, FileText, Mail, Plus, Trash2 } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import { locale, t } from '../i18n';
import { money } from '../lib/money';
import { toast } from '../lib/toast';
import { offerUndo } from '../lib/undo';
import type { InvoiceDetail, InvoiceForm, ProductRow } from '../types';
import { store } from '../lib/store';
import EditableField from './EditableField.vue';
import InvoiceMailDialog from './InvoiceMailDialog.vue';
import ProductPick from './ProductPick.vue';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'changed'): void; (e: 'deleted'): void }>();
const config = readConfig();
const inv = ref<InvoiceDetail | null>(null);
const form = ref<InvoiceForm | null>(null);
const loading = ref(false);
const error = ref('');
const busy = ref(false);
const adding = ref(false);
const paying = ref(false);
const mailing = ref(false);

let seq = 0;
async function load(spinner = true) {
  const mine = ++seq;
  if (spinner) { loading.value = true; inv.value = null; form.value = null; }
  error.value = '';
  try {
    const r = await api.invoice(props.id);
    if (mine !== seq) return;
    inv.value = r.invoice;
    if (r.invoice.can_edit || r.invoice.can_pay) api.invoiceForm(props.id).then((f) => { if (mine === seq) form.value = f; }).catch(() => {});
  } catch (e) { if (mine === seq) error.value = (e as ApiError).status === 404 ? t('inv.not_found') : (e as Error).message; }
  finally { if (mine === seq) loading.value = false; }
}
watch(() => props.id, () => { adding.value = false; paying.value = false; load(); }, { immediate: true });

const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '—');
const m = (v: number) => money(v, inv.value?.currency ?? '');
const classic = computed(() => `${config.root}/invoices/${props.id}`);
const pdf = computed(() => `${config.root}/invoices/${props.id}.pdf`);
async function removeInvoice() {
  const cur = inv.value; if (!cur || busy.value || !window.confirm(t('inv.confirm_delete', { number: cur.number }))) return;
  busy.value = true;
  try { await api.deleteInvoice(props.id); toast(t('inv.deleted', { number: cur.number })); emit('deleted'); }
  catch (e) { toast((e as Error).message, 'error'); }
  finally { busy.value = false; }
}
const ed = computed(() => !!inv.value?.can_edit);
const opts = (l: { id: number; name: string }[] = []) => l.map((o) => ({ value: String(o.id), label: o.name }));
const num = (v: unknown) => String(v ?? '');

// One write path for everything: sends the version token, shows the server's message on refusal (409/422), offers undo.
async function send(fields: Record<string, unknown>, undo: (() => Record<string, unknown>) | null, message = t('edit.saved')) {
  const cur = inv.value; if (!cur || busy.value) return false;
  busy.value = true;
  try {
    const r = await api.updateInvoice(props.id, { ...fields, lock: cur.lock });
    inv.value = r.invoice; emit('changed');
    const u = undo?.();
    if (u) offerUndo(message, async () => {
      if (!inv.value) return;
      const x = await api.updateInvoice(props.id, { ...u, lock: inv.value.lock }); inv.value = x.invoice; emit('changed');
    });
    else toast(message);
    return true;
  } catch (e) {
    toast(t('edit.failed', { message: (e as Error).message }), 'error');
    if ((e as ApiError).status === 409) await load(false);
    return false;
  } finally { busy.value = false; }
}

const headerValue = (k: string): unknown => {
  const i = inv.value!;
  switch (k) {
    case 'status_id': return i.status.id; case 'assigned_to_id': return i.assigned_to_id; case 'discount': return i.discount;
    case 'invoice_date': return i.invoice_date ?? ''; case 'due_date': return i.due_date ?? '';
    case 'subject': return i.subject; case 'description': return i.description; default: return i.order_number;
  }
};
function saveHeader(k: string, v: unknown) {
  const old = headerValue(k);
  const value = ['status_id', 'assigned_to_id'].includes(k) ? (v === '' ? null : Number(v)) : v;
  send({ [k]: value }, () => ({ [k]: old }));
}

// Items. A cell change sends only that field; undo restores the old value (re-adds a deleted item, deletes an added one).
type Line = InvoiceDetail['lines'][number];
const LINE_KEYS = ['description', 'quantity', 'units', 'price', 'tax', 'discount'] as const;
function saveLine(l: Line, k: (typeof LINE_KEYS)[number], v: unknown) {
  const old = l[k] ?? '';
  send({ lines: [{ id: l.id, [k]: v }] }, () => ({ lines: [{ id: l.id, [k]: old }] }));
}
function removeLine(l: Line) {
  const keep = LINE_KEYS.reduce((a, k) => ({ ...a, [k]: l[k] ?? '' }), {} as Record<string, unknown>);
  send({ lines: [{ id: l.id, _destroy: true }] }, () => ({ lines: [keep] }), t('inv.line.removed'));
}
async function addProduct(p: ProductRow) {
  const known = new Set(inv.value!.lines.map((x) => x.id));
  await send({ lines: [{ description: p.name, quantity: '1', units: 'products', price: p.price === null ? '0' : String(p.price), tax: null }] },
    () => ({ lines: inv.value!.lines.filter((x) => !known.has(x.id)).map((x) => ({ id: x.id, _destroy: true })) }), t('inv.line.added'));
}
const draft = ref({ description: '', quantity: '1', units: '', price: '', tax: '' });
async function addLine() {
  const d = draft.value; const known = new Set(inv.value!.lines.map((x) => x.id));
  if (!d.description.trim() || d.price === '') return;
  const ok = await send({ lines: [{ ...d, tax: d.tax === '' ? null : d.tax }] },
    () => ({ lines: inv.value!.lines.filter((x) => !known.has(x.id)).map((x) => ({ id: x.id, _destroy: true })) }), t('inv.line.added'));
  if (ok) { draft.value = { description: '', quantity: '1', units: '', price: '', tax: '' }; adding.value = false; }
}

// Payments
const today = () => new Date().toISOString().slice(0, 10);
const pay = ref({ amount: '', payment_date: today(), description: '', account_id: '', category_id: '' });
function startPay() { pay.value = { amount: String(inv.value!.remaining || ''), payment_date: today(), description: '', account_id: '', category_id: '' }; paying.value = true; }
async function addPayment() {
  const i = inv.value; if (!i || busy.value || !pay.value.amount) return;
  busy.value = true;
  try {
    const r = await api.addInvoicePayment(props.id, { ...pay.value, lock: i.lock });
    inv.value = r.invoice; paying.value = false; emit('changed'); toast(t('inv.payment.added'));
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); if ((e as ApiError).status === 409) await load(false); }
  finally { busy.value = false; }
}
async function removePayment(pid: number) {
  const i = inv.value; if (!i || busy.value || !window.confirm(t('inv.payment.confirm_remove'))) return;
  busy.value = true;
  try { const r = await api.removeInvoicePayment(props.id, pid, i.lock); inv.value = r.invoice; emit('changed'); toast(t('inv.payment.removed')); }
  catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); if ((e as ApiError).status === 409) await load(false); }
  finally { busy.value = false; }
}
</script>

<template>
  <aside class="detail" aria-label="Invoice">
    <header class="detail-head">
      <button class="icon-btn" :aria-label="t('detail.close')" :title="t('detail.close') + ' (Esc)'" @click="emit('close')">✕</button>
      <span class="muted">{{ inv?.number }}</span>
      <span class="spacer" />
      <button v-if="inv?.can_send" class="btn flex items-center gap-1" @click="mailing = true"><Mail :size="14" /> {{ t('inv.mail.button') }}</button>
      <a :href="pdf" target="_blank" rel="noopener" class="btn flex items-center gap-1 no-underline"><FileText :size="14" /> PDF</a>
      <button v-if="inv?.can_delete" class="icon-btn danger" :aria-label="t('delete')" :title="t('delete')" @click="removeInvoice"><Trash2 :size="15" /></button>
      <a :href="classic" class="muted small">{{ t('detail.classic') }}</a>
    </header>
    <p v-if="loading" class="muted pad">{{ t('detail.loading') }}</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>

    <div v-else-if="inv" class="detail-body" :class="{ busy }">
      <h2>{{ inv.number }} <span class="pill" :class="{ 'pill-closed': inv.status.id === 3 }">{{ inv.status.name }}</span>
        <span v-if="inv.overdue" class="pill overdue">{{ t('inv.overdue') }}</span></h2>
      <EditableField kind="text" allow-empty :editable="ed" :label="t('inv.subject')" :model-value="inv.subject" @save="(v) => saveHeader('subject', v)">
        <span v-if="inv.subject" class="muted">{{ inv.subject }}</span><span v-else class="muted">{{ ed ? t('inv.add_subject') : '' }}</span>
      </EditableField>

      <dl class="fields">
        <dt>{{ t('col.status') }}</dt>
        <dd><EditableField kind="select" :editable="ed && !!form" :label="t('col.status')" :model-value="String(inv.status.id)" :options="opts(form?.statuses)" @save="(v) => saveHeader('status_id', v)">{{ inv.status.name }}</EditableField></dd>
        <dt>{{ t('inv.contact') }}</dt>
        <dd><a v-if="inv.contact && inv.contact_visible" href="#" @click.prevent="$router.push('/contacts/' + inv.contact.id)">{{ inv.contact.name }}</a><template v-else>{{ inv.contact?.name ?? '—' }}</template></dd>
        <dt>{{ t('col.project') }}</dt><dd>{{ inv.project }}</dd>
        <dt>{{ t('inv.date') }}</dt>
        <dd><EditableField kind="date" :editable="ed" :label="t('inv.date')" :model-value="inv.invoice_date ?? ''" @save="(v) => saveHeader('invoice_date', v)">{{ fmtDate(inv.invoice_date) }}</EditableField></dd>
        <dt>{{ t('inv.due') }}</dt>
        <dd><EditableField kind="date" allow-empty :editable="ed" :label="t('inv.due')" :model-value="inv.due_date ?? ''" @save="(v) => saveHeader('due_date', v)">{{ fmtDate(inv.due_date) }}</EditableField></dd>
        <template v-if="inv.paid_date"><dt>{{ t('inv.paid_on') }}</dt><dd>{{ fmtDate(inv.paid_date) }}</dd></template>
        <dt>{{ t('inv.order') }}</dt>
        <dd><EditableField kind="text" allow-empty :editable="ed" :label="t('inv.order')" :model-value="inv.order_number" @save="(v) => saveHeader('order_number', v)">{{ inv.order_number || '—' }}</EditableField></dd>
        <dt>{{ t('col.assigned_to') }}</dt>
        <dd><EditableField kind="select" allow-empty :editable="ed && !!form" :label="t('col.assigned_to')" :model-value="String(inv.assigned_to_id ?? '')" :options="opts(form?.assignees)" @save="(v) => saveHeader('assigned_to_id', v)">{{ inv.assigned_to?.name ?? '—' }}</EditableField></dd>
        <dt>{{ t('inv.discount') }} %</dt>
        <dd><EditableField kind="number" step="0.01" :editable="ed" :label="t('inv.discount')" :model-value="num(inv.discount)" @save="(v) => saveHeader('discount', v === '' ? 0 : v)">{{ inv.discount }} %</EditableField></dd>
      </dl>

      <h3>{{ t('inv.lines') }}</h3>
      <div class="table-wrap">
        <table class="inv-lines">
          <thead><tr><th>{{ t('inv.line.description') }}</th><th class="num">{{ t('inv.line.qty') }}</th><th class="num">{{ t('inv.line.price') }}</th><th class="num">{{ t('inv.line.tax') }}</th><th class="num">{{ t('inv.line.total') }}</th><th v-if="ed" /></tr></thead>
          <tbody>
            <tr v-for="l in inv.lines" :key="l.id">
              <td><EditableField kind="text" :editable="ed" :label="t('inv.line.description')" :model-value="l.description" @save="(v) => saveLine(l, 'description', v)">{{ l.description }}</EditableField></td>
              <td class="num"><EditableField kind="number" :editable="ed" :label="t('inv.line.qty')" :model-value="num(l.quantity)" @save="(v) => saveLine(l, 'quantity', v)">{{ l.quantity }}<template v-if="l.units"> {{ l.units }}</template></EditableField></td>
              <td class="num"><EditableField kind="number" step="0.01" :editable="ed" :label="t('inv.line.price')" :model-value="num(l.price)" @save="(v) => saveLine(l, 'price', v)">{{ m(l.price) }}</EditableField></td>
              <td class="num"><EditableField kind="number" step="0.01" allow-empty :editable="ed" :label="t('inv.line.tax')" :model-value="num(l.tax)" @save="(v) => saveLine(l, 'tax', v)">{{ l.tax ? l.tax + ' %' : '—' }}</EditableField></td>
              <td class="num">{{ m(l.total) }}</td>
              <td v-if="ed" class="num"><button class="icon-btn" :aria-label="t('inv.line.remove')" :title="t('inv.line.remove')" @click="removeLine(l)"><Trash2 :size="14" /></button></td>
            </tr>
            <tr v-if="adding" class="inv-new">
              <td><input v-model="draft.description" :placeholder="t('inv.line.description')" :aria-label="t('inv.line.description')" @keydown.enter.prevent="addLine"></td>
              <td class="num"><input v-model="draft.quantity" type="number" step="any" class="narrow" :aria-label="t('inv.line.qty')" @keydown.enter.prevent="addLine"></td>
              <td class="num"><input v-model="draft.price" type="number" step="0.01" class="narrow" :aria-label="t('inv.line.price')" @keydown.enter.prevent="addLine"></td>
              <td class="num"><input v-model="draft.tax" type="number" step="0.01" class="narrow" :aria-label="t('inv.line.tax')" @keydown.enter.prevent="addLine"></td>
              <td colspan="2" class="num"><button class="btn primary" :disabled="busy || !draft.description.trim() || draft.price === ''" @click="addLine">{{ t('inv.line.add') }}</button> <button class="btn" @click="adding = false">{{ t('create.cancel') }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="ed && !adding" class="flex flex-wrap items-center gap-3"><button class="link-btn" @click="adding = true"><Plus :size="13" class="inline" /> {{ t('inv.line.new') }}</button>
        <ProductPick v-if="store.meta?.features?.products" @pick="addProduct" /></p>

      <dl class="inv-totals">
        <dt>{{ t('inv.subtotal') }}</dt><dd>{{ m(inv.subtotal) }}</dd>
        <template v-if="inv.discount_amount"><dt>{{ t('inv.discount') }} ({{ inv.discount }} %)</dt><dd>−{{ m(Math.abs(inv.discount_amount)) }}</dd></template>
        <template v-if="inv.tax_amount"><dt>{{ t('inv.tax') }}</dt><dd>{{ m(inv.tax_amount) }}</dd></template>
        <dt><strong>{{ t('inv.total') }}</strong></dt><dd><strong>{{ m(inv.amount) }}</strong></dd>
        <dt>{{ t('inv.paid') }}</dt><dd>{{ m(inv.balance) }}</dd>
        <dt><strong>{{ t('inv.remaining') }}</strong></dt><dd><strong :class="{ 'inv-due': inv.remaining > 0 }">{{ m(inv.remaining) }}</strong></dd>
      </dl>

      <h3>{{ t('inv.payments') }}</h3>
      <p v-if="!inv.payments.length" class="muted">{{ t('inv.no_payments') }}</p>
      <ul v-else class="ct-list">
        <li v-for="p in inv.payments" :key="p.id">{{ fmtDate(p.date) }} · <strong>{{ m(p.amount) }}</strong> <span class="muted small">{{ p.description }}</span>
          <button v-if="p.can_remove" class="icon-btn" :aria-label="t('inv.payment.remove')" :title="t('inv.payment.remove')" @click="removePayment(p.id)"><Trash2 :size="13" /></button></li>
      </ul>
      <form v-if="paying" class="inv-pay" @submit.prevent="addPayment">
        <label>{{ t('inv.payment.amount') }}<input v-model="pay.amount" type="number" step="0.01" min="0.01" required></label>
        <label>{{ t('inv.payment.date') }}<input v-model="pay.payment_date" type="date" required></label>
        <label>{{ t('inv.payment.note') }}<input v-model="pay.description"></label>
        <template v-if="form?.finance.enabled">
          <label>{{ t('inv.payment.account') }}<select v-model="pay.account_id"><option value="" /><option v-for="a in form.finance.accounts" :key="a.id" :value="a.id">{{ a.name }}</option></select></label>
          <label>{{ t('inv.payment.category') }}<select v-model="pay.category_id"><option value="" /><option v-for="c in form.finance.categories" :key="c.id" :value="c.id">{{ c.name }}</option></select></label>
        </template>
        <div class="inv-actions"><button class="btn primary" type="submit" :disabled="busy || !pay.amount">{{ t('inv.payment.save') }}</button><button class="btn" type="button" @click="paying = false">{{ t('create.cancel') }}</button></div>
      </form>
      <p v-else-if="inv.can_pay" class="inv-actions"><button class="btn" @click="startPay"><Plus :size="13" class="inline" /> {{ t('inv.add_payment') }}</button></p>

      <p v-if="inv.description || ed" class="muted small" style="margin-bottom: 2px">{{ t('inv.notes') }}</p>
      <EditableField v-if="inv.description || ed" kind="textarea" allow-empty :editable="ed" :label="t('inv.notes')" :model-value="inv.description" @save="(v) => saveHeader('description', v)">
        <span v-if="inv.description" class="small inv-desc">{{ inv.description }}</span><span v-else class="muted small">—</span>
      </EditableField>
      <p v-if="ed" class="muted small"><ExternalLink :size="12" class="inline" /> {{ t('inv.readonly_hint') }}</p>
    </div>
  </aside>
  <InvoiceMailDialog v-if="mailing && inv" :id="id" :number="inv.number" @close="mailing = false" @sent="(i) => { inv = i; emit('changed'); }" />
</template>

<style>
.num { text-align: right; white-space: nowrap; }
.inv-lines td, .inv-lines th { padding: 6px 8px; }
.inv-totals { display: grid; grid-template-columns: 1fr max-content; gap: 4px 18px; margin: 12px 0 0 auto; max-width: 340px; }
.inv-totals dd { margin: 0; text-align: right; }
.inv-due { color: var(--danger); }
.inv-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px; }
.inv-desc { white-space: pre-wrap; }
.pill.overdue { background: color-mix(in srgb, var(--danger) 18%, transparent); color: var(--danger); }
.inv-new input, .inv-pay input, .inv-pay select { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 5px 7px; width: 100%; }
.inv-new input.narrow { width: 90px; text-align: right; }
.inv-pay { display: grid; gap: 8px; max-width: 360px; margin-top: 10px; }
.inv-pay label { display: grid; gap: 3px; font-size: 0.85rem; color: var(--muted); }
.detail-body.busy { opacity: 0.7; }
</style>
