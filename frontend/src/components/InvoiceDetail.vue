<script setup lang="ts">
import { FileText, ExternalLink } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import { locale, t } from '../i18n';
import { money } from '../lib/money';
import type { InvoiceDetail } from '../types';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void }>();
const config = readConfig();
const inv = ref<InvoiceDetail | null>(null);
const loading = ref(false);
const error = ref('');

let seq = 0;
watch(() => props.id, async () => {
  const mine = ++seq; loading.value = true; inv.value = null; error.value = '';
  try { const r = await api.invoice(props.id); if (mine === seq) inv.value = r.invoice; }
  catch (e) { if (mine === seq) error.value = (e as ApiError).status === 404 ? t('inv.not_found') : (e as Error).message; }
  finally { if (mine === seq) loading.value = false; }
}, { immediate: true });

const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '—');
const m = (v: number) => money(v, inv.value?.currency ?? '');
const classic = computed(() => `${config.root}/invoices/${props.id}`);
const pdf = computed(() => `${config.root}/invoices/${props.id}.pdf`);
const paymentUrl = computed(() => `${config.root}/invoices/${props.id}/invoice_payments/new`);
const editUrl = computed(() => `${config.root}/invoices/${props.id}/edit`);
</script>

<template>
  <aside class="detail" aria-label="Invoice">
    <header class="detail-head">
      <button class="icon-btn" :aria-label="t('detail.close')" :title="t('detail.close') + ' (Esc)'" @click="emit('close')">✕</button>
      <span class="muted">{{ inv?.number }}</span>
      <span class="spacer" />
      <a :href="pdf" target="_blank" rel="noopener" class="muted small pdf-link"><FileText :size="13" /> PDF</a>
      <a :href="classic" class="muted small">{{ t('detail.classic') }}</a>
    </header>
    <p v-if="loading" class="muted pad">{{ t('detail.loading') }}</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>

    <div v-else-if="inv" class="detail-body">
      <h2>{{ inv.number }} <span class="pill" :class="{ 'pill-closed': inv.status.id === 3 }">{{ inv.status.name }}</span>
        <span v-if="inv.overdue" class="pill overdue">{{ t('inv.overdue') }}</span></h2>
      <p v-if="inv.subject" class="muted">{{ inv.subject }}</p>

      <dl class="fields">
        <dt>{{ t('inv.contact') }}</dt>
        <dd><a v-if="inv.contact && inv.contact_visible" href="#" @click.prevent="$router.push('/contacts/' + inv.contact.id)">{{ inv.contact.name }}</a><template v-else>{{ inv.contact?.name ?? '—' }}</template></dd>
        <dt>{{ t('col.project') }}</dt><dd>{{ inv.project }}</dd>
        <dt>{{ t('inv.date') }}</dt><dd>{{ fmtDate(inv.invoice_date) }}</dd>
        <dt>{{ t('inv.due') }}</dt><dd>{{ fmtDate(inv.due_date) }}</dd>
        <template v-if="inv.paid_date"><dt>{{ t('inv.paid_on') }}</dt><dd>{{ fmtDate(inv.paid_date) }}</dd></template>
        <template v-if="inv.order_number"><dt>{{ t('inv.order') }}</dt><dd>{{ inv.order_number }}</dd></template>
        <dt>{{ t('col.assigned_to') }}</dt><dd>{{ inv.assigned_to?.name ?? '—' }}</dd>
      </dl>

      <h3>{{ t('inv.lines') }}</h3>
      <div class="table-wrap">
        <table class="inv-lines">
          <thead><tr><th>{{ t('inv.line.description') }}</th><th class="num">{{ t('inv.line.qty') }}</th><th class="num">{{ t('inv.line.price') }}</th><th class="num">{{ t('inv.line.tax') }}</th><th class="num">{{ t('inv.line.total') }}</th></tr></thead>
          <tbody>
            <tr v-for="l in inv.lines" :key="l.id">
              <td>{{ l.description }}</td><td class="num">{{ l.quantity }} {{ l.units }}</td><td class="num">{{ m(l.price) }}</td>
              <td class="num">{{ l.tax ? l.tax + ' %' : '' }}</td><td class="num">{{ m(l.total) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
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
      <ul v-else class="ct-list"><li v-for="p in inv.payments" :key="p.id">{{ fmtDate(p.date) }} · <strong>{{ m(p.amount) }}</strong> <span class="muted small">{{ p.description }}</span></li></ul>

      <p v-if="inv.description" class="small muted inv-desc">{{ inv.description }}</p>
      <p class="inv-actions">
        <a v-if="inv.can_pay && inv.remaining > 0" :href="paymentUrl" class="btn"><ExternalLink :size="13" class="inline" /> {{ t('inv.add_payment') }}</a>
        <a v-if="inv.can_edit" :href="editUrl" class="btn"><ExternalLink :size="13" class="inline" /> {{ t('inv.edit_classic') }}</a>
      </p>
      <p class="muted small">{{ t('inv.readonly_hint') }}</p>
    </div>
  </aside>
</template>

<style>
.num { text-align: right; white-space: nowrap; }
.inv-lines td, .inv-lines th { padding: 6px 8px; }
.inv-totals { display: grid; grid-template-columns: 1fr max-content; gap: 4px 18px; margin: 12px 0 0 auto; max-width: 340px; }
.inv-totals dd { margin: 0; text-align: right; }
.inv-due { color: var(--danger); }
.inv-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 14px; }
.inv-actions .btn { text-decoration: none; }
.pill.overdue { background: color-mix(in srgb, var(--danger) 18%, transparent); color: var(--danger); }
</style>
