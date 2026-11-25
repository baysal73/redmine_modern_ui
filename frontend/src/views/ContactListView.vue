<script setup lang="ts">
import { Building2, Search } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api } from '../api/client';
import ContactDetail from '../components/ContactDetail.vue';
import Avatar from '../components/ui/Avatar.vue';
import { locale, t } from '../i18n';
import BulkBar from '../components/BulkBar.vue';
import { downloadCsv } from '../lib/csv';
import { useSelection } from '../lib/selection';
import { toast } from '../lib/toast';
import type { ContactList, ContactOptions } from '../types';

const route = useRoute();
const router = useRouter();
const list = ref<ContactList | null>(null);
const opts = ref<ContactOptions | null>(null);
const sel = useSelection(() => list.value?.contacts.map((r) => r.id) ?? []);
const bulkBusy = ref(false);
async function bulkDelete() {
  const ids = [...sel.selected.value];
  if (!ids.length || bulkBusy.value || !window.confirm(t('bulk2.confirm_delete', { n: ids.length }))) return;
  bulkBusy.value = true;
  try {
    const r = await api.bulkContacts(ids);
    toast(r.failed.length ? t('bulk2.partial', { ok: r.done, failed: r.failed.length, reason: `${r.failed[0].name}: ${r.failed[0].error}` }) : t('bulk2.deleted', { n: r.done }), r.failed.length ? 'error' : 'ok');
    await load(); sel.set(r.failed.map((f) => f.id));
    if (selectedId.value && ids.includes(selectedId.value)) openContact(null);
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { bulkBusy.value = false; }
}
function exportCsv() {
  const rows = (list.value?.contacts ?? []).filter((r) => sel.selected.value.has(r.id));
  downloadCsv('contacts.csv', [t('ct.name'), t('ct.company'), t('ct.email'), t('ct.phone'), t('ct.city'), t('col.assigned_to')],
    rows.map((r) => [r.name, r.company, r.email, r.phone, r.city, r.assigned_to?.name]));
}
const loading = ref(false);
const error = ref('');
const searchText = ref('');
const searchBox = ref<HTMLInputElement | null>(null);
const creating = ref(false);
const draft = ref({ is_company: false, first_name: '', last_name: '', company: '', email: '', phone: '', project_id: '' });
const saving = ref(false);

const q = computed(() => route.query);
const s = (k: string) => String(q.value[k] ?? '');
const selectedId = computed(() => (route.params.id ? Number(route.params.id) : null));
const sort = computed(() => s('sort') || 'name:asc');
const sortCol = computed(() => sort.value.split(':')[0]);
const sortDir = computed(() => sort.value.split(':')[1] ?? 'asc');

function go(patch: Record<string, string>, resetPage = true) {
  const next: Record<string, string> = { ...(q.value as Record<string, string>), ...patch };
  if (resetPage) delete next.page;
  for (const k of Object.keys(next)) if (!next[k]) delete next[k];
  router.push({ path: selectedId.value ? `/contacts/${selectedId.value}` : '/contacts', query: next });
}
function params() {
  const p: Record<string, string | number | undefined> = { q: s('q'), kind: s('kind'), assigned_to_id: s('mine') ? 'me' : '', sort: sort.value, page: s('page') || 1, per_page: 50 };
  for (const [k, v] of Object.entries(q.value)) if (k.startsWith('cf') && v) p[`cf[${k.slice(2)}]`] = String(v);
  return p;
}
let seq = 0;
async function load() {
  const mine = ++seq; loading.value = true; error.value = '';
  try { const r = await api.contacts(params()); if (mine === seq) list.value = r; }
  catch (e) { if (mine === seq) error.value = (e as ApiError).message; }
  finally { if (mine === seq) loading.value = false; }
}
let timer: number | undefined;
function onSearch() { window.clearTimeout(timer); timer = window.setTimeout(() => go({ q: searchText.value.trim() }), 250); }
watch(() => [route.query, route.name], () => {
  if (s('new')) { creating.value = true; const { new: _n, ...rest } = route.query; router.replace({ path: route.path, query: rest }); return; }
  searchText.value = s('q'); load();
}, { immediate: true });
onMounted(() => { api.contactOptions().then((o) => { opts.value = o; }).catch(() => {}); window.addEventListener('keydown', onKey); });
onUnmounted(() => window.removeEventListener('keydown', onKey));
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey) return;
  if (e.key === '/') { e.preventDefault(); searchBox.value?.focus(); }
  else if (e.key === 'Escape' && selectedId.value) openContact(null);
}
function openContact(id: number | null) { router.push({ path: id ? `/contacts/${id}` : '/contacts', query: q.value }); }
function sortBy(col: string) { go({ sort: sortCol.value === col ? `${col}:${sortDir.value === 'asc' ? 'desc' : 'asc'}` : `${col}:asc` }, false); }
const kinds = ['', 'company', 'person'];
const fmtShort = (d: string) => new Date(d).toLocaleDateString(locale, { dateStyle: 'medium' });
const anyFilter = computed(() => Object.keys(q.value).some((k) => ['q', 'kind', 'mine'].includes(k) || k.startsWith('cf')));

async function create() {
  if (saving.value || !draft.value.first_name.trim() || !draft.value.project_id) return;
  saving.value = true;
  try {
    const r = await api.createContact({ ...draft.value, last_name: draft.value.is_company ? '' : draft.value.last_name, company: draft.value.is_company ? '' : draft.value.company });
    toast(t('ct.created')); creating.value = false;
    draft.value = { is_company: false, first_name: '', last_name: '', company: '', email: '', phone: '', project_id: draft.value.project_id };
    router.push({ path: `/contacts/${r.contact.id}`, query: q.value }); load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { saving.value = false; }
}
</script>

<template>
  <section class="list-view">
    <div class="page-head"><h1>{{ t('nav.contacts') }}</h1><span v-if="list" class="muted">{{ t('ct.results', { total: list.total }) }}</span></div>

    <form v-if="creating" class="ct-new" @submit.prevent="create">
      <label class="inline"><input v-model="draft.is_company" type="checkbox"> {{ t('ct.kind.company') }}</label>
      <input v-model="draft.first_name" required :placeholder="draft.is_company ? t('ct.company_name') : t('ct.first_name')" :aria-label="t('ct.first_name')">
      <input v-if="!draft.is_company" v-model="draft.last_name" :placeholder="t('ct.last_name')" :aria-label="t('ct.last_name')">
      <input v-if="!draft.is_company" v-model="draft.company" :placeholder="t('ct.company')" :aria-label="t('ct.company')">
      <input v-model="draft.email" type="text" :placeholder="t('ct.email')" :aria-label="t('ct.email')">
      <input v-model="draft.phone" :placeholder="t('ct.phone')" :aria-label="t('ct.phone')">
      <select v-model="draft.project_id" required :aria-label="t('ct.project')"><option value="">{{ t('ct.project') }}…</option><option v-for="p in opts?.projects" :key="p.id" :value="p.identifier">{{ p.name }}</option></select>
      <button class="btn primary" type="submit" :disabled="saving || !draft.first_name.trim() || !draft.project_id">{{ t('ct.create') }}</button>
      <button class="btn" type="button" @click="creating = false">{{ t('create.cancel') }}</button>
    </form>

    <div class="list-toolbar">
      <div class="fbar" role="search">
        <label class="fsearch"><Search :size="15" class="text-muted" aria-hidden="true" />
          <input ref="searchBox" type="search" :value="searchText" :placeholder="t('ct.search') + '  ( / )'" :aria-label="t('ct.search')" @input="searchText = ($event.target as HTMLInputElement).value; onSearch()">
        </label>
        <div class="seg" role="group" :aria-label="t('ct.kind')">
          <button v-for="k in kinds" :key="k" class="seg-btn" :class="{ on: s('kind') === k }" :aria-pressed="s('kind') === k" @click="go({ kind: k })">{{ t('ct.kind.' + (k || 'all')) }}</button>
        </div>
        <button class="seg-btn solo" :class="{ on: !!s('mine') }" :aria-pressed="!!s('mine')" @click="go({ mine: s('mine') ? '' : '1' })">{{ t('ct.mine') }}</button>
        <select v-for="f in opts?.custom_fields" :key="f.id" class="tb-select-plain" :value="s('cf' + f.id)" :aria-label="f.name" @change="go({ ['cf' + f.id]: ($event.target as HTMLSelectElement).value })">
          <option value="">{{ f.name }}</option><option v-for="v in f.values" :key="v" :value="v">{{ v }}</option>
        </select>
        <button v-if="anyFilter" class="link-btn" @click="router.push({ path: '/contacts' })">{{ t('filter.reset') }}</button>
      </div>
    </div>

    <BulkBar :count="sel.count.value" @clear="sel.clear">
      <button class="btn" @click="exportCsv">{{ t('bulk2.csv') }}</button>
      <button class="btn danger-text" :disabled="bulkBusy" @click="bulkDelete">{{ t('bulk2.delete') }}</button>
    </BulkBar>

    <div class="split" :class="{ open: !!selectedId }">
      <div class="split-list">
        <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
        <div class="table-wrap" :class="{ busy: loading }">
          <table v-if="list" class="m-contacts">
            <thead><tr>
              <th class="sel"><input type="checkbox" :checked="sel.allSelected.value" :aria-label="t('bulk.select_all')" @change="sel.toggleAll"></th>
              <th :aria-sort="sortCol === 'name' ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'"><button class="th-btn" @click="sortBy('name')">{{ t('ct.name') }}<span class="arrow">{{ sortCol === 'name' ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '' }}</span></button></th>
              <th v-if="!selectedId"><button class="th-btn" @click="sortBy('company')">{{ t('ct.company') }}<span class="arrow">{{ sortCol === 'company' ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '' }}</span></button></th>
              <th v-if="!selectedId">{{ t('ct.email') }}</th><th v-if="!selectedId">{{ t('ct.phone') }}</th><th v-if="!selectedId">{{ t('ct.city') }}</th>
              <th v-if="!selectedId">{{ t('col.assigned_to') }}</th>
              <th><button class="th-btn" @click="sortBy('updated_on')">{{ t('col.updated_on') }}<span class="arrow">{{ sortCol === 'updated_on' ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '' }}</span></button></th>
            </tr></thead>
            <tbody>
              <tr v-for="r in list.contacts" :key="r.id" :class="{ selected: r.id === selectedId }" :aria-selected="r.id === selectedId" @click="openContact(r.id)">
                <td class="sel" @click.stop><input type="checkbox" :checked="sel.selected.value.has(r.id)" :aria-label="t('bulk2.select_row', { name: r.name })" @change="sel.toggle(r.id)"></td>
                <td><span class="inline-flex items-center gap-2"><Building2 v-if="r.is_company" :size="18" class="text-muted" aria-label="company" /><Avatar v-else :name="r.name" :size="22" /><a class="subject" :href="'#'" @click.prevent>{{ r.name }}</a></span>
                  <span v-if="selectedId" class="muted small block">{{ r.company || r.job_title }}</span></td>
                <td v-if="!selectedId">{{ r.is_company ? '' : r.company }}<span v-if="r.job_title" class="muted small block">{{ r.job_title }}</span></td>
                <td v-if="!selectedId">{{ r.email }}</td><td v-if="!selectedId">{{ r.phone }}</td><td v-if="!selectedId">{{ r.city }}</td>
                <td v-if="!selectedId">{{ r.assigned_to?.name }}</td>
                <td>{{ fmtShort(r.updated_on) }}</td>
              </tr>
            </tbody>
          </table>
          <p v-if="loading && !list" class="muted">{{ t('loading') }}</p>
          <p v-else-if="list && !list.contacts.length" class="muted empty">{{ t('ct.empty') }}</p>
        </div>
        <footer v-if="list" class="pager">
          <span class="muted">{{ t('ct.results', { total: list.total }) }}</span><span class="spacer" />
          <button class="btn" :disabled="list.page <= 1" @click="go({ page: String(list.page - 1) }, false)">{{ t('page.prev') }}</button>
          <span>{{ t('page.of', { page: list.page, pages: Math.max(list.pages, 1) }) }}</span>
          <button class="btn" :disabled="list.page >= list.pages" @click="go({ page: String(list.page + 1) }, false)">{{ t('page.next') }}</button>
        </footer>
      </div>
      <ContactDetail v-if="selectedId" :id="selectedId" class="split-detail" @close="openContact(null)" @updated="load" />
    </div>
  </section>
</template>

<style>
.ct-new { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 10px; margin-bottom: 12px; }
.ct-new input[type=text], .ct-new input:not([type]), .ct-new select, .tb-select-plain { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; }
.seg { display: inline-flex; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; background: var(--surface); }
.seg-btn { font: inherit; color: var(--muted); background: none; border: 0; padding: 6px 12px; cursor: pointer; }
.seg-btn + .seg-btn { border-left: 1px solid var(--border); }
.seg-btn.on { background: var(--accent); color: #fff; }
.seg-btn.solo { border: 1px solid var(--border); border-radius: 8px; background: var(--surface); }
.seg-btn.solo.on { background: var(--accent); }
.block { display: block; }
</style>
