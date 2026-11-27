<script setup lang="ts">
import AdvancedFilters from '../components/AdvancedFilters.vue';
import SavedViews from '../components/SavedViews.vue';
import { Package, Search } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api } from '../api/client';
import ProductDetail from '../components/ProductDetail.vue';
import { t } from '../i18n';
import BulkBar from '../components/BulkBar.vue';
import { downloadCsv } from '../lib/csv';
import { money } from '../lib/money';
import { useSelection } from '../lib/selection';
import { toast } from '../lib/toast';
import type { ProductList, ProductOptions } from '../types';

const route = useRoute();
const router = useRouter();
const list = ref<ProductList | null>(null);
const opts = ref<ProductOptions | null>(null);
const sel = useSelection(() => list.value?.products.map((r) => r.id) ?? []);
const bulkBusy = ref(false);
async function bulk(op: 'status' | 'delete', statusId?: number) {
  const ids = [...sel.selected.value];
  if (!ids.length || bulkBusy.value || (op === 'delete' && !window.confirm(t('bulk2.confirm_delete', { n: ids.length })))) return;
  bulkBusy.value = true;
  try {
    const r = await api.bulkProducts(ids, op, statusId);
    toast(r.failed.length ? t('bulk2.partial', { ok: r.done, failed: r.failed.length, reason: `${r.failed[0].name}: ${r.failed[0].error}` }) : t(op === 'delete' ? 'bulk2.deleted' : 'bulk2.done', { n: r.done }), r.failed.length ? 'error' : 'ok');
    await load(); sel.set(r.failed.map((f) => f.id));
    if (selectedId.value && op === 'delete' && ids.includes(selectedId.value)) openProduct(null);
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { bulkBusy.value = false; }
}
function exportCsv() {
  const rows = (list.value?.products ?? []).filter((r) => sel.selected.value.has(r.id));
  downloadCsv('products.csv', [t('pr.name'), t('pr.code'), t('pr.category'), t('col.project'), t('pr.status'), t('pr.price'), t('pr.currency')],
    rows.map((r) => [r.name, r.code, r.category, r.project, r.status.name, r.price, r.currency]));
}
const loading = ref(false);
const error = ref('');
const searchText = ref('');
const searchBox = ref<HTMLInputElement | null>(null);
const creating = ref(false);
const saving = ref(false);
const draft = ref({ project_id: '', name: '', code: '', price: '', currency: '', status_id: '', category_id: '' });

const q = computed(() => route.query);
const s = (k: string) => String(q.value[k] ?? '');
const selectedId = computed(() => (route.params.id ? Number(route.params.id) : null));
const sort = computed(() => s('sort') || 'name:asc');
const sortCol = computed(() => sort.value.split(':')[0]);
const sortDir = computed(() => sort.value.split(':')[1] ?? 'asc');
const status = computed(() => s('status') || 'all');

function go(patch: Record<string, string>, resetPage = true) {
  const next: Record<string, string> = { ...(q.value as Record<string, string>), ...patch };
  if (resetPage) delete next.page;
  for (const k of Object.keys(next)) if (!next[k]) delete next[k];
  router.push({ path: selectedId.value ? `/products/${selectedId.value}` : '/products', query: next });
}
let seq = 0;
async function load() {
  const mine = ++seq; loading.value = true; error.value = '';
  try { const r = await api.products({ q: s('q'), status: status.value === 'all' ? '' : status.value, category_id: s('category'), sort: sort.value, page: s('page') || 1, filters: s('filters') }); if (mine === seq) list.value = r; }
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
onMounted(() => {
  api.productOptions().then((o) => {
    opts.value = o;
    draft.value = { ...draft.value, currency: o.default_currency, status_id: String(o.default_status_id), project_id: o.projects.length === 1 ? String(o.projects[0].id) : '' };
  }).catch(() => {});
  window.addEventListener('keydown', onKey);
});
onUnmounted(() => window.removeEventListener('keydown', onKey));
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey) return;
  if (e.key === '/') { e.preventDefault(); searchBox.value?.focus(); }
  else if (e.key === 'Escape' && selectedId.value) openProduct(null);
}
function openProduct(id: number | null) { router.push({ path: id ? `/products/${id}` : '/products', query: q.value }); }
function sortBy(col: string) { go({ sort: sortCol.value === col ? `${col}:${sortDir.value === 'asc' ? 'desc' : 'asc'}` : `${col}:asc` }, false); }
const arrow = (c: string) => (sortCol.value === c ? (sortDir.value === 'asc' ? ' ▲' : ' ▼') : '');
const anyFilter = computed(() => !!(s('q') || s('status') || s('category') || s('filters')));

async function create() {
  const d = draft.value;
  if (saving.value || !d.name.trim() || !d.project_id) return;
  saving.value = true;
  try {
    const r = await api.createProduct({ ...d });
    toast(t('pr.created')); creating.value = false;
    draft.value = { ...d, name: '', code: '', price: '', category_id: '' };
    router.push({ path: `/products/${r.product.id}`, query: q.value }); load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { saving.value = false; }
}
</script>

<template>
  <section class="list-view">
    <div class="page-head"><h1>{{ t('nav.products') }}</h1><span v-if="list" class="muted">{{ t('pr.results', { total: list.total }) }}</span></div>

    <form v-if="creating" class="ct-new" @submit.prevent="create">
      <select v-model="draft.project_id" required :aria-label="t('pr.project')"><option value="">{{ t('pr.project') }}…</option><option v-for="p in opts?.projects" :key="p.id" :value="String(p.id)">{{ p.name }}</option></select>
      <input v-model="draft.name" required :placeholder="t('pr.name')" :aria-label="t('pr.name')">
      <input v-model="draft.code" :placeholder="t('pr.code')" :aria-label="t('pr.code')">
      <input v-model="draft.price" inputmode="decimal" :placeholder="t('pr.price')" :aria-label="t('pr.price')">
      <select v-model="draft.currency" :aria-label="t('pr.currency')"><option v-for="c in opts?.currencies" :key="c" :value="c">{{ c }}</option></select>
      <select v-model="draft.status_id" :aria-label="t('pr.status')"><option v-for="st in opts?.statuses" :key="st.id" :value="String(st.id)">{{ st.name }}</option></select>
      <select v-model="draft.category_id" :aria-label="t('pr.category')"><option value="">{{ t('pr.category') }}…</option><option v-for="c in opts?.categories" :key="c.id" :value="String(c.id)">{{ c.name }}</option></select>
      <button class="btn primary" type="submit" :disabled="saving || !draft.name.trim() || !draft.project_id">{{ t('pr.create') }}</button>
      <button class="btn" type="button" @click="creating = false">{{ t('create.cancel') }}</button>
    </form>

    <div class="list-toolbar">
      <div class="fbar" role="search">
        <label class="fsearch"><Search :size="15" class="text-muted" aria-hidden="true" />
          <input ref="searchBox" type="search" :value="searchText" :placeholder="t('pr.search') + '  ( / )'" :aria-label="t('pr.search')" @input="searchText = ($event.target as HTMLInputElement).value; onSearch()">
        </label>
        <div class="seg" role="group" :aria-label="t('pr.status')">
          <button v-for="k in ['all', '1', '2']" :key="k" class="seg-btn" :class="{ on: status === k }" :aria-pressed="status === k" @click="go({ status: k === 'all' ? '' : k })">{{ t('pr.status.' + k) }}</button>
        </div>
        <select v-if="opts?.categories.length" class="tb-select-plain" :value="s('category')" :aria-label="t('pr.category')" @change="go({ category: ($event.target as HTMLSelectElement).value })">
          <option value="">{{ t('pr.category') }}…</option><option v-for="c in opts.categories" :key="c.id" :value="String(c.id)">{{ c.name }}</option>
        </select>
        <AdvancedFilters :filters="s('filters')" module="products" @change="(json) => go({ filters: json })" />
        <SavedViews module="products" path="/products" :current="q as Record<string, string>" />
        <button v-if="anyFilter" class="link-btn" @click="router.push({ path: '/products' })">{{ t('filter.reset') }}</button>
      </div>
    </div>

    <BulkBar :count="sel.count.value" @clear="sel.clear">
      <select :disabled="bulkBusy" :aria-label="t('pr.status')" @change="bulk('status', Number(($event.target as HTMLSelectElement).value)); ($event.target as HTMLSelectElement).value = ''">
        <option value="">{{ t('bulk.set_status') }}</option><option v-for="st in opts?.statuses" :key="st.id" :value="st.id">{{ st.name }}</option>
      </select>
      <button class="btn" @click="exportCsv">{{ t('bulk2.csv') }}</button>
      <button class="btn danger-text" :disabled="bulkBusy" @click="bulk('delete')">{{ t('bulk2.delete') }}</button>
    </BulkBar>

    <div class="split" :class="{ open: !!selectedId }">
      <div class="split-list">
        <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
        <div class="table-wrap" :class="{ busy: loading }">
          <table v-if="list" class="m-products">
            <thead><tr>
              <th class="sel"><input type="checkbox" :checked="sel.allSelected.value" :aria-label="t('bulk.select_all')" @change="sel.toggleAll"></th>
              <th><button class="th-btn" @click="sortBy('name')">{{ t('pr.name') }}<span class="arrow">{{ arrow('name') }}</span></button></th>
              <th v-if="!selectedId"><button class="th-btn" @click="sortBy('code')">{{ t('pr.code') }}<span class="arrow">{{ arrow('code') }}</span></button></th>
              <th v-if="!selectedId">{{ t('pr.category') }}</th>
              <th v-if="!selectedId">{{ t('col.project') }}</th>
              <th>{{ t('pr.status') }}</th>
              <th class="num"><button class="th-btn" @click="sortBy('price')">{{ t('pr.price') }}<span class="arrow">{{ arrow('price') }}</span></button></th>
            </tr></thead>
            <tbody>
              <tr v-for="r in list.products" :key="r.id" :class="{ selected: r.id === selectedId }" :aria-selected="r.id === selectedId" @click="openProduct(r.id)">
                <td class="sel" @click.stop><input type="checkbox" :checked="sel.selected.value.has(r.id)" :aria-label="t('bulk2.select_row', { name: r.name })" @change="sel.toggle(r.id)"></td>
                <td><span class="inline-flex items-center gap-2"><img v-if="r.image_url" :src="r.image_url" alt="" class="pr-thumb" @error="($event.target as HTMLElement).style.display = 'none'"><Package v-else :size="18" class="text-muted" aria-hidden="true" /><a class="subject" href="#" @click.prevent>{{ r.name }}</a></span>
                  <span v-if="selectedId && r.code" class="muted small block">{{ r.code }}</span></td>
                <td v-if="!selectedId">{{ r.code }}</td>
                <td v-if="!selectedId">{{ r.category }}</td>
                <td v-if="!selectedId">{{ r.project }}</td>
                <td><span class="pill" :class="{ 'pill-closed': r.status.id === 2 }">{{ r.status.name }}</span></td>
                <td class="num">{{ r.price === null ? '' : money(r.price, r.currency) }}</td>
              </tr>
            </tbody>
          </table>
          <p v-if="loading && !list" class="muted">{{ t('loading') }}</p>
          <p v-else-if="list && !list.products.length" class="muted empty">{{ t('pr.empty') }}</p>
        </div>
        <footer v-if="list" class="pager">
          <span class="muted">{{ t('pr.results', { total: list.total }) }}</span><span class="spacer" />
          <button class="btn" :disabled="list.page <= 1" @click="go({ page: String(list.page - 1) }, false)">{{ t('page.prev') }}</button>
          <span>{{ t('page.of', { page: list.page, pages: Math.max(list.pages, 1) }) }}</span>
          <button class="btn" :disabled="list.page >= list.pages" @click="go({ page: String(list.page + 1) }, false)">{{ t('page.next') }}</button>
        </footer>
      </div>
      <ProductDetail v-if="selectedId" :id="selectedId" :opts="opts" class="split-detail" @close="openProduct(null)" @changed="load" @deleted="() => { openProduct(null); load(); }" />
    </div>
  </section>
</template>

<style>
.pr-thumb { width: 22px; height: 22px; object-fit: cover; border-radius: 4px; }
</style>
