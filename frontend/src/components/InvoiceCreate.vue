<script setup lang="ts">
import { Plus, Trash2 } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api } from '../api/client';
import { t } from '../i18n';
import { money } from '../lib/money';
import { toast } from '../lib/toast';
import { store } from '../lib/store';
import type { ContactRow, InvoiceDefaults, InvoiceOptions, ProductRow } from '../types';
import ProductPick from './ProductPick.vue';

const props = defineProps<{ opts: InvoiceOptions | null }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'created', id: number): void }>();

const projectId = ref('');
const defaults = ref<InvoiceDefaults | null>(null);
const saving = ref(false);
const error = ref('');
const f = ref({ number: '', subject: '', invoice_date: '', due_date: '', currency: '', status_id: '', assigned_to_id: '', order_number: '', description: '', discount: '' });
type Line = { description: string; quantity: string; units: string; price: string; tax: string };
const blank = (tax = ''): Line => ({ description: '', quantity: '1', units: '', price: '', tax });
const lines = ref<Line[]>([blank()]);

// declared before the watcher below (it runs immediately)
const contact = ref<{ id: number; name: string } | null>(null);
const cq = ref('');
const hits = ref<ContactRow[]>([]);
let timer: number | undefined;

watch(() => props.opts, (o) => { if (o && !projectId.value && o.addable_projects.length === 1) projectId.value = String(o.addable_projects[0].id); }, { immediate: true });
watch(projectId, async (id) => {
  defaults.value = null; if (!id) return;
  try {
    const d = await api.invoiceDefaults(Number(id)); defaults.value = d;
    f.value = { ...f.value, number: d.number, invoice_date: d.invoice_date, currency: d.currency, status_id: String(d.statuses.find((s) => s.id === 1)?.id ?? d.statuses[0]?.id ?? ''), assigned_to_id: String(d.assigned_to_id) };
    lines.value = lines.value.map((l) => (l.price === '' && l.description === '' ? blank(d.tax ? String(d.tax) : '') : l));
  } catch (e) { error.value = (e as Error).message; }
});
function searchContacts() {
  window.clearTimeout(timer);
  timer = window.setTimeout(async () => {
    if (cq.value.trim().length < 2) { hits.value = []; return; }
    try { hits.value = (await api.contacts({ q: cq.value.trim(), per_page: 8 })).contacts; } catch { hits.value = []; }
  }, 250);
}
// like the classic form: description, price and quantity 1 come from the product, tax from the default
function addProduct(p: ProductRow) {
  const line = { ...blank(defaults.value?.tax ? String(defaults.value.tax) : ''), description: p.name, price: p.price === null ? '' : String(p.price), units: 'products' };
  const first = lines.value[0];
  if (lines.value.length === 1 && !first.description.trim() && first.price === '') lines.value[0] = line; else lines.value.push(line);
}
function pick(c: ContactRow) { contact.value = { id: c.id, name: c.name }; hits.value = []; cq.value = ''; }

const filled = computed(() => lines.value.filter((l) => l.description.trim() || l.price !== ''));
const total = computed(() => filled.value.reduce((a, l) => {
  const n = (v: string) => Number(String(v).replace(',', '.')) || 0;
  const net = n(l.quantity) * n(l.price); return a + net * (1 + n(l.tax) / 100);
}, 0) * (1 - (Number(String(f.value.discount).replace(',', '.')) || 0) / 100));
const ready = computed(() => !!projectId.value && !!defaults.value && !!f.value.invoice_date && !saving.value);

async function create() {
  if (!ready.value) return;
  saving.value = true; error.value = '';
  try {
    const body: Record<string, unknown> = { ...f.value, project_id: projectId.value, contact_id: contact.value?.id ?? null,
      assigned_to_id: f.value.assigned_to_id || null, lines: filled.value.map((l) => ({ ...l, tax: l.tax === '' ? null : l.tax })) };
    for (const k of ['due_date', 'discount', 'order_number', 'description', 'subject']) if (body[k] === '') delete body[k];
    const r = await api.createInvoice(body);
    toast(t('inv.created', { number: r.invoice.number }));
    emit('created', r.invoice.id);
  } catch (e) { error.value = (e as ApiError).message; }
  finally { saving.value = false; }
}
</script>

<template>
  <form class="inv-create" @submit.prevent="create">
    <div class="inv-grid">
      <label>{{ t('inv.project') }}
        <select v-model="projectId" required><option value="">…</option><option v-for="p in opts?.addable_projects" :key="p.id" :value="String(p.id)">{{ p.name }}</option></select>
      </label>
      <div class="inv-contact">
        <span class="lbl">{{ t('inv.contact') }}</span>
        <span v-if="contact" class="chip">{{ contact.name }} <button type="button" class="icon-btn" :aria-label="t('create.cancel')" @click="contact = null">×</button></span>
        <template v-else>
          <input v-model="cq" type="search" :placeholder="t('inv.pick_contact')" :aria-label="t('inv.contact')" autocomplete="off" @input="searchContacts">
          <ul v-if="hits.length" class="inv-hits"><li v-for="c in hits" :key="c.id"><button type="button" @click="pick(c)">{{ c.name }}<span v-if="c.company && !c.is_company" class="muted small"> · {{ c.company }}</span></button></li></ul>
        </template>
      </div>
      <label>{{ t('inv.number') }}<input v-model="f.number" :placeholder="t('inv.number')"></label>
      <label>{{ t('inv.subject') }}<input v-model="f.subject"></label>
      <label>{{ t('inv.date') }}<input v-model="f.invoice_date" type="date" required></label>
      <label>{{ t('inv.due') }}<input v-model="f.due_date" type="date"></label>
      <label>{{ t('inv.currency') }}
        <select v-model="f.currency"><option v-for="c in defaults?.currencies" :key="c" :value="c">{{ c }}</option><option v-if="defaults && !defaults.currencies.includes(f.currency) && f.currency" :value="f.currency">{{ f.currency }}</option></select>
      </label>
      <label>{{ t('inv.status') }}<select v-model="f.status_id"><option v-for="s in defaults?.statuses" :key="s.id" :value="String(s.id)">{{ s.name }}</option></select></label>
      <label>{{ t('inv.discount') }} %<input v-model="f.discount" inputmode="decimal"></label>
      <label>{{ t('inv.order') }}<input v-model="f.order_number"></label>
    </div>

    <table class="inv-lines">
      <thead><tr><th>{{ t('inv.line.description') }}</th><th class="num">{{ t('inv.line.qty') }}</th><th class="num">{{ t('inv.line.price') }}</th><th class="num">{{ t('inv.line.default_tax') }}</th><th /></tr></thead>
      <tbody>
        <tr v-for="(l, i) in lines" :key="i">
          <td><input v-model="l.description" :aria-label="t('inv.line.description')"></td>
          <td class="num"><input v-model="l.quantity" class="narrow" inputmode="decimal" :aria-label="t('inv.line.qty')"></td>
          <td class="num"><input v-model="l.price" class="narrow" inputmode="decimal" :aria-label="t('inv.line.price')"></td>
          <td class="num"><input v-model="l.tax" class="narrow" inputmode="decimal" :aria-label="t('inv.line.default_tax')"></td>
          <td><button v-if="lines.length > 1" type="button" class="icon-btn" :aria-label="t('inv.line.remove')" @click="lines.splice(i, 1)"><Trash2 :size="14" /></button></td>
        </tr>
      </tbody>
    </table>
    <ProductPick v-if="store.meta?.features?.products" @pick="addProduct" />
    <button type="button" class="link-btn" @click="lines.push(blank(defaults?.tax ? String(defaults.tax) : ''))"><Plus :size="13" class="inline" /> {{ t('inv.line.new') }}</button>

    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <div class="inv-create-foot">
      <strong v-if="filled.length">{{ t('inv.total') }}: ≈ {{ money(total, f.currency) }}</strong>
      <span class="spacer" />
      <button class="btn primary" type="submit" :disabled="!ready">{{ t('inv.create') }}</button>
      <button class="btn" type="button" @click="emit('close')">{{ t('create.cancel') }}</button>
    </div>
  </form>
</template>

<style>
.inv-create { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px; margin-bottom: 12px; display: flex; flex-direction: column; gap: 10px; }
.inv-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
.inv-grid label, .inv-contact { display: flex; flex-direction: column; gap: 3px; font-size: 12px; color: var(--muted); position: relative; }
.inv-create input, .inv-create select { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; }
.inv-create .narrow { width: 90px; text-align: right; }
.inv-lines td input:not(.narrow) { width: 100%; }
.inv-hits { position: absolute; top: 100%; left: 0; right: 0; z-index: 5; list-style: none; margin: 2px 0 0; padding: 4px; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; box-shadow: 0 6px 20px rgba(0,0,0,.15); }
.inv-hits button { all: unset; display: block; width: 100%; padding: 5px 8px; border-radius: 6px; cursor: pointer; color: var(--fg); box-sizing: border-box; }
.inv-hits button:hover, .inv-hits button:focus-visible { background: var(--hover, rgba(127,127,127,.15)); }
.inv-create-foot { display: flex; gap: 8px; align-items: center; }
</style>
