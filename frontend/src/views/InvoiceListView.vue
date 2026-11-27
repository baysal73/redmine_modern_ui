<script setup lang="ts">
import AdvancedFilters from '../components/AdvancedFilters.vue';
import SavedViews from '../components/SavedViews.vue';
import { Search } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api } from '../api/client';
import InvoiceCreate from '../components/InvoiceCreate.vue';
import InvoiceDetail from '../components/InvoiceDetail.vue';
import { locale, t } from '../i18n';
import BulkBar from '../components/BulkBar.vue';
import { downloadCsv } from '../lib/csv';
import { money } from '../lib/money';
import { useSelection } from '../lib/selection';
import { toast } from '../lib/toast';
import type { InvoiceList, InvoiceOptions } from '../types';

const route = useRoute();
const router = useRouter();
const list = ref<InvoiceList | null>(null);
const opts = ref<InvoiceOptions | null>(null);
const sel = useSelection(() => list.value?.invoices.map((r) => r.id) ?? []);
const bulkBusy = ref(false);
async function bulk(op: 'status' | 'delete', statusId?: number) {
  const ids = [...sel.selected.value];
  if (!ids.length || bulkBusy.value || (op === 'delete' && !window.confirm(t('bulk2.confirm_delete', { n: ids.length })))) return;
  bulkBusy.value = true;
  try {
    const r = await api.bulkInvoices(ids, op, statusId);
    toast(r.failed.length ? t('bulk2.partial', { ok: r.done, failed: r.failed.length, reason: `${r.failed[0].name}: ${r.failed[0].error}` }) : t(op === 'delete' ? 'bulk2.deleted' : 'bulk2.done', { n: r.done }), r.failed.length ? 'error' : 'ok');
    await load(); sel.set(r.failed.map((f) => f.id));
    if (selectedId.value && op === 'delete' && ids.includes(selectedId.value)) openInvoice(null);
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { bulkBusy.value = false; }
}
function exportCsv() {
  const rows = (list.value?.invoices ?? []).filter((r) => sel.selected.value.has(r.id));
  downloadCsv('invoices.csv', [t('inv.number'), t('inv.contact'), t('col.project'), t('inv.date'), t('inv.due'), t('col.status'), t('inv.total'), t('inv.remaining'), 'Currency'],
    rows.map((r) => [r.number, r.contact?.name, r.project, r.invoice_date, r.due_date, r.status.name, r.amount, r.remaining, r.currency]));
}
const loading = ref(false);
const creating = ref(false);
const error = ref('');
const searchText = ref('');
const searchBox = ref<HTMLInputElement | null>(null);

const q = computed(() => route.query);
const s = (k: string) => String(q.value[k] ?? '');
const selectedId = computed(() => (route.params.id ? Number(route.params.id) : null));
const sort = computed(() => s('sort') || 'invoice_date:desc');
const sortCol = computed(() => sort.value.split(':')[0]);
const sortDir = computed(() => sort.value.split(':')[1] ?? 'desc');
const status = computed(() => s('status') || 'open');

function go(patch: Record<string, string>, resetPage = true) {
  const next: Record<string, string> = { ...(q.value as Record<string, string>), ...patch };
  if (resetPage) delete next.page;
  for (const k of Object.keys(next)) if (!next[k]) delete next[k];
  router.push({ path: selectedId.value ? `/invoices/${selectedId.value}` : '/invoices', query: next });
}
let seq = 0;
async function load() {
  const mine = ++seq; loading.value = true; error.value = '';
  try { const r = await api.invoices({ q: s('q'), status: status.value, project_id: s('project'), overdue: s('overdue'), sort: sort.value, page: s('page') || 1, filters: s('filters') }); if (mine === seq) list.value = r; }
  catch (e) { if (mine === seq) error.value = (e as ApiError).message; }
  finally { if (mine === seq) loading.value = false; }
}
let timer: number | undefined;
function onSearch() { window.clearTimeout(timer); timer = window.setTimeout(() => go({ q: searchText.value.trim() }), 250); }
watch(() => route.query, () => {
  sel.clear();
  if (s('new')) { creating.value = true; const { new: _n, ...rest } = route.query; router.replace({ path: route.path, query: rest }); return; }
  searchText.value = s('q'); load();
}, { immediate: true });
onMounted(() => { api.invoiceOptions().then((o) => { opts.value = o; }).catch(() => {}); window.addEventListener('keydown', onKey); });
onUnmounted(() => window.removeEventListener('keydown', onKey));
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey) return;
  if (e.key === '/') { e.preventDefault(); searchBox.value?.focus(); }
  else if (e.key === 'Escape' && selectedId.value) openInvoice(null);
}
function openInvoice(id: number | null) { router.push({ path: id ? `/invoices/${id}` : '/invoices', query: q.value }); }
function sortBy(col: string) { go({ sort: sortCol.value === col ? `${col}:${sortDir.value === 'asc' ? 'desc' : 'asc'}` : `${col}:desc` }, false); }
const arrow = (c: string) => (sortCol.value === c ? (sortDir.value === 'asc' ? ' ▲' : ' ▼') : '');
const fmtDate = (d: string | null) => (d ? new Date(d).toLocaleDateString(locale) : '');
const presets = ['open', 'all'];
const anyFilter = computed(() => !!(s('q') || s('status') || s('project') || s('overdue') || s('filters')));
</script>

<template>
  <section class="list-view">
    <div class="page-head"><h1>{{ t('nav.invoices') }}</h1><span v-if="list" class="muted">{{ t('inv.results', { total: list.total }) }}</span></div>
    <InvoiceCreate v-if="creating" :opts="opts" @close="creating = false" @created="(id) => { creating = false; load(); openInvoice(id); }" />

    <div class="list-toolbar">
      <div class="fbar" role="search">
        <label class="fsearch"><Search :size="15" class="text-muted" aria-hidden="true" />
          <input ref="searchBox" type="search" :value="searchText" :placeholder="t('inv.search') + '  ( / )'" :aria-label="t('inv.search')" @input="searchText = ($event.target as HTMLInputElement).value; onSearch()">
        </label>
        <div class="seg" role="group" :aria-label="t('inv.status')">
          <button v-for="p in presets" :key="p" class="seg-btn" :class="{ on: status === p && !s('overdue') }" :aria-pressed="status === p && !s('overdue')" @click="go({ status: p === 'open' ? '' : p, overdue: '' })">{{ t('inv.status.' + p) }}</button>
        </div>
        <button class="seg-btn solo" :class="{ on: !!s('overdue') }" :aria-pressed="!!s('overdue')" @click="go({ overdue: s('overdue') ? '' : '1', status: '' })">{{ t('inv.overdue') }}</button>
        <select class="tb-select-plain" :value="presets.includes(status) ? '' : status" :aria-label="t('inv.status')" @change="go({ status: ($event.target as HTMLSelectElement).value, overdue: '' })">
          <option value="">{{ t('inv.status') }}…</option><option v-for="st in opts?.statuses" :key="st.id" :value="String(st.id)">{{ st.name }}</option>
        </select>
        <select class="tb-select-plain" :value="s('project')" :aria-label="t('col.project')" @change="go({ project: ($event.target as HTMLSelectElement).value })">
          <option value="">{{ t('col.project') }}…</option><option v-for="p in opts?.projects" :key="p.id" :value="p.identifier">{{ p.name }}</option>
        </select>
        <AdvancedFilters :filters="s('filters')" module="invoices" @change="(json) => go({ filters: json })" />
        <SavedViews module="invoices" path="/invoices" :current="q as Record<string, string>" />
        <button v-if="anyFilter" class="link-btn" @click="router.push({ path: '/invoices' })">{{ t('filter.reset') }}</button>
      </div>
    </div>

    <div v-if="list?.sums.length" class="inv-sums" role="group" :aria-label="t('inv.sums')">
      <div v-for="x in list.sums" :key="x.currency" class="inv-sum">
        <span class="muted small">{{ x.currency }}</span>
        <strong>{{ money(x.open, x.currency) }}</strong><span class="muted small">{{ t('inv.sum_open') }}</span>
        <span class="muted small">· {{ t('inv.sum_total') }} {{ money(x.amount, x.currency) }}</span>
      </div>
    </div>

    <BulkBar :count="sel.count.value" @clear="sel.clear">
      <select :disabled="bulkBusy" :aria-label="t('col.status')" @change="bulk('status', Number(($event.target as HTMLSelectElement).value)); ($event.target as HTMLSelectElement).value = ''">
        <option value="">{{ t('bulk.set_status') }}</option><option v-for="st in opts?.statuses.filter((x) => x.id !== 3)" :key="st.id" :value="st.id">{{ st.name }}</option>
      </select>
      <button class="btn" @click="exportCsv">{{ t('bulk2.csv') }}</button>
      <button class="btn danger-text" :disabled="bulkBusy" @click="bulk('delete')">{{ t('bulk2.delete') }}</button>
    </BulkBar>

    <div class="split" :class="{ open: !!selectedId }">
      <div class="split-list">
        <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
        <div class="table-wrap" :class="{ busy: loading }">
          <table v-if="list" class="m-invoices">
            <thead><tr>
              <th class="sel"><input type="checkbox" :checked="sel.allSelected.value" :aria-label="t('bulk.select_all')" @change="sel.toggleAll"></th>
              <th><button class="th-btn" @click="sortBy('number')">{{ t('inv.number') }}<span class="arrow">{{ arrow('number') }}</span></button></th>
              <th>{{ t('inv.contact') }}</th>
              <th v-if="!selectedId">{{ t('col.project') }}</th>
              <th v-if="!selectedId"><button class="th-btn" @click="sortBy('invoice_date')">{{ t('inv.date') }}<span class="arrow">{{ arrow('invoice_date') }}</span></button></th>
              <th v-if="!selectedId"><button class="th-btn" @click="sortBy('due_date')">{{ t('inv.due') }}<span class="arrow">{{ arrow('due_date') }}</span></button></th>
              <th>{{ t('col.status') }}</th>
              <th class="num"><button class="th-btn" @click="sortBy('amount')">{{ t('inv.total') }}<span class="arrow">{{ arrow('amount') }}</span></button></th>
              <th v-if="!selectedId" class="num">{{ t('inv.remaining') }}</th>
            </tr></thead>
            <tbody>
              <tr v-for="r in list.invoices" :key="r.id" :class="{ selected: r.id === selectedId }" :aria-selected="r.id === selectedId" @click="openInvoice(r.id)">
                <td class="sel" @click.stop><input type="checkbox" :checked="sel.selected.value.has(r.id)" :aria-label="t('bulk2.select_row', { name: r.number })" @change="sel.toggle(r.id)"></td>
                <td><a class="subject" href="#" @click.prevent>{{ r.number }}</a><span v-if="r.subject && !selectedId" class="muted small block">{{ r.subject }}</span></td>
                <td>{{ r.contact?.name }}</td>
                <td v-if="!selectedId">{{ r.project }}</td>
                <td v-if="!selectedId">{{ fmtDate(r.invoice_date) }}</td>
                <td v-if="!selectedId"><span :class="{ 'inv-due': r.overdue }">{{ fmtDate(r.due_date) }}</span></td>
                <td><span class="pill" :class="{ 'pill-closed': r.status.id === 3 }">{{ r.status.name }}</span></td>
                <td class="num">{{ money(r.amount, r.currency) }}</td>
                <td v-if="!selectedId" class="num"><span :class="{ 'inv-due': r.remaining > 0 && r.status.id !== 4 }">{{ r.status.id === 4 ? '—' : money(r.remaining, r.currency) }}</span></td>
              </tr>
            </tbody>
          </table>
          <p v-if="loading && !list" class="muted">{{ t('loading') }}</p>
          <p v-else-if="list && !list.invoices.length" class="muted empty">{{ t('inv.empty') }}</p>
        </div>
        <footer v-if="list" class="pager">
          <span class="muted">{{ t('inv.results', { total: list.total }) }}</span><span class="spacer" />
          <button class="btn" :disabled="list.page <= 1" @click="go({ page: String(list.page - 1) }, false)">{{ t('page.prev') }}</button>
          <span>{{ t('page.of', { page: list.page, pages: Math.max(list.pages, 1) }) }}</span>
          <button class="btn" :disabled="list.page >= list.pages" @click="go({ page: String(list.page + 1) }, false)">{{ t('page.next') }}</button>
        </footer>
      </div>
      <InvoiceDetail v-if="selectedId" :id="selectedId" class="split-detail" @close="openInvoice(null)" @changed="load" @deleted="() => { openInvoice(null); load(); }" />
    </div>
  </section>
</template>

<style>
.inv-sums { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 12px; }
.inv-sum { display: flex; gap: 8px; align-items: baseline; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 8px 12px; }
</style>
