<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api } from '../api/client';
import InlineCell from '../components/InlineCell.vue';
import IssueDetail from '../components/IssueDetail.vue';
import { locale, t } from '../i18n';
import { defaultState, nextSort, stateFromQuery, stateToQuery, toApiParams, type ListState } from '../lib/listQuery';
import { toast } from '../lib/toast';
import type { IssueList, IssueOptions, IssueRow, Meta } from '../types';

const route = useRoute();
const router = useRouter();

const meta = ref<Meta | null>(null);
const list = ref<IssueList | null>(null);
const loading = ref(true);
const error = ref('');
const searchBox = ref<HTMLInputElement | null>(null);
const searchText = ref('');
const perPage = ref(Number(safeGet('modern_ui_per_page')) || 50);

// ---- columns (user choice persisted in localStorage) ----
const PER_PAGE_OPTIONS = [25, 50, 100];
const ALL_COLUMNS = ['id', 'subject', 'project', 'tracker', 'status', 'priority', 'assigned_to', 'author', 'start_date', 'due_date', 'done_ratio', 'updated_on', 'created_on'];
const DEFAULT_COLUMNS = ['id', 'subject', 'project', 'status', 'priority', 'assigned_to', 'due_date', 'updated_on'];
const columns = ref<string[]>(loadColumns());
const selectedId = computed(() => (route.params.id ? Number(route.params.id) : null));
// With the detail panel open the list shrinks to the essentials
const COMPACT_COLUMNS = ['id', 'subject', 'status'];
const shownColumns = computed(() => ALL_COLUMNS.filter((c) => (selectedId.value ? COMPACT_COLUMNS.includes(c) : columns.value.includes(c))));
function openIssue(id: number | null) {
  router.push({ name: 'issues', params: { id: id ?? undefined }, query: route.query });
}
function onRowClick(e: MouseEvent, id: number) {
  if (e.ctrlKey || e.metaKey || e.shiftKey || e.button !== 0) return; // let the browser handle new-tab clicks
  if ((e.target as HTMLElement).closest('.cell, .cell-input, select, input')) return;
  e.preventDefault();
  openIssue(id);
}
function onDetailUpdated(row: IssueRow) {
  const i = list.value?.issues.findIndex((x) => x.id === row.id) ?? -1;
  if (i >= 0) list.value!.issues[i] = row;
}
const columnMenu = ref(false);
function safeGet(k: string): string | null { try { return localStorage.getItem(k); } catch { return null; } }
function safeSet(k: string, v: string) { try { localStorage.setItem(k, v); } catch { /* ignore */ } }
function loadColumns(): string[] {
  try {
    const v = JSON.parse(safeGet('modern_ui_columns') ?? 'null');
    if (Array.isArray(v) && v.length) return ALL_COLUMNS.filter((c) => v.includes(c));
  } catch { /* fall through */ }
  return DEFAULT_COLUMNS;
}
function toggleColumn(c: string) {
  if (c === 'subject') return; // always visible
  columns.value = ALL_COLUMNS.filter((x) => (x === c ? !columns.value.includes(c) : columns.value.includes(x)));
  safeSet('modern_ui_columns', JSON.stringify(columns.value));
}

// ---- state <-> URL ----
const state = computed<ListState>(() => stateFromQuery(route.query as Record<string, string>));
function go(patch: Partial<ListState>, resetPage = true) {
  const next = { ...state.value, ...patch };
  if (resetPage && !('page' in patch)) next.page = 1;
  router.push({ query: stateToQuery(next) });
}
const filtersActive = computed(() => JSON.stringify(stateToQuery({ ...state.value, sort: defaultState.sort, page: 1 })) !== '{}');

let seq = 0;
async function load() {
  const mine = ++seq;
  loading.value = true;
  error.value = '';
  try {
    const res = await api.issues(toApiParams(state.value, perPage.value));
    if (mine === seq) list.value = res;
  } catch (e) {
    if (mine === seq) error.value = (e as Error).message;
  } finally {
    if (mine === seq) loading.value = false;
  }
}
watch(() => route.query, () => { searchText.value = state.value.q; load(); }, { immediate: true });

let searchTimer: number | undefined;
function onSearchInput() {
  window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(() => go({ q: searchText.value.trim() }), 300);
}
function setPerPage(n: number) { perPage.value = n; safeSet('modern_ui_per_page', String(n)); go({}); }

// ---- inline editing ----
const optionsCache = new Map<number, Promise<IssueOptions>>();
function optionsFor(id: number) {
  if (!optionsCache.has(id)) {
    const p = api.issueOptions(id);
    p.catch(() => optionsCache.delete(id));
    optionsCache.set(id, p);
  }
  return optionsCache.get(id)!;
}
async function loadOpts(id: number, what: 'statuses' | 'assignees' | 'priorities') {
  try {
    const o = await optionsFor(id);
    return what === 'statuses' ? o.allowed_statuses : what === 'assignees' ? o.assignees : o.priorities;
  } catch (e) { toast(t('error.load', { message: (e as Error).message }), 'error'); throw e; }
}
async function save(row: IssueRow, field: string, value: string | number | null) {
  const idx = list.value!.issues.findIndex((i) => i.id === row.id);
  try {
    const res = await api.updateIssue(row.id, { [field]: value });
    optionsCache.delete(row.id);
    if (idx >= 0) list.value!.issues[idx] = res.issue;
    toast(t('edit.saved'));
  } catch (e) {
    toast(t('edit.failed', { message: (e as ApiError).message }), 'error');
  }
}

// ---- helpers ----
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '');
const fmtDateTime = (s: string) => new Date(s).toLocaleString(locale, { dateStyle: 'short', timeStyle: 'short' });
const isOverdue = (r: IssueRow) => !!r.due_date && !r.status.is_closed && new Date(r.due_date) < new Date(new Date().toDateString());
const appUrl = (id: number) => router.resolve({ name: 'issues', params: { id }, query: route.query }).href;
const sortCol = computed(() => state.value.sort.split(':')[0]);
const sortDir = computed(() => state.value.sort.split(':')[1]);
const SORTABLE = new Set(['id', 'subject', 'project', 'tracker', 'status', 'priority', 'assigned_to', 'author', 'start_date', 'due_date', 'done_ratio', 'updated_on', 'created_on']);
const projectOptions = computed(() => {
  const ps = meta.value?.projects ?? [];
  const depth = (p: (typeof ps)[number]): number => { let d = 0; let cur: typeof p | undefined = p; while (cur?.parent_id) { d++; cur = ps.find((x) => x.id === cur!.parent_id); } return d; };
  return ps.map((p) => ({ id: p.identifier, label: `${' '.repeat(depth(p))}${p.name}` }));
});

function onKey(e: KeyboardEvent) {
  const tag = (e.target as HTMLElement).tagName;
  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes(tag);
  if (e.key === '/' && !typing) { e.preventDefault(); searchBox.value?.focus(); }
  if (e.key === 'Escape' && selectedId.value && !typing) openIssue(null);
  if ((e.key === 'j' || e.key === 'k') && !typing && !e.ctrlKey && !e.metaKey && list.value?.issues.length) {
    const ids = list.value.issues.map((i) => i.id);
    const cur = selectedId.value ? ids.indexOf(selectedId.value) : -1;
    const nxt = e.key === 'j' ? Math.min(cur + 1, ids.length - 1) : Math.max(cur - 1, 0);
    openIssue(ids[nxt]);
  }
}
function onDocClick(e: MouseEvent) { if (!(e.target as HTMLElement).closest('.col-menu-wrap')) columnMenu.value = false; }
onMounted(async () => {
  window.addEventListener('keydown', onKey);
  document.addEventListener('click', onDocClick);
  try { meta.value = await api.meta(); } catch (e) { error.value = (e as Error).message; }
});
onUnmounted(() => { window.removeEventListener('keydown', onKey); document.removeEventListener('click', onDocClick); });
</script>

<template>
  <section class="list-view">
    <div class="filters" role="search">
      <input ref="searchBox" v-model="searchText" class="search" type="search" :placeholder="t('filter.search') + '  ( / )'"
             :aria-label="t('filter.search')" @input="onSearchInput">
      <select :value="state.project" :aria-label="t('filter.project')" @change="go({ project: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.project') }}</option>
        <option v-for="p in projectOptions" :key="p.id" :value="p.id">{{ p.label }}</option>
      </select>
      <select :value="state.status" :aria-label="t('col.status')" @change="go({ status: ($event.target as HTMLSelectElement).value })">
        <option value="open">{{ t('filter.status.open') }}</option>
        <option value="closed">{{ t('filter.status.closed') }}</option>
        <option value="all">{{ t('filter.status.all') }}</option>
        <option v-for="s in meta?.statuses" :key="s.id" :value="String(s.id)">{{ s.name }}</option>
      </select>
      <select :value="state.tracker" :aria-label="t('col.tracker')" @change="go({ tracker: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.tracker') }}</option>
        <option v-for="x in meta?.trackers" :key="x.id" :value="String(x.id)">{{ x.name }}</option>
      </select>
      <select :value="state.priority" :aria-label="t('col.priority')" @change="go({ priority: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.priority') }}</option>
        <option v-for="x in meta?.priorities" :key="x.id" :value="String(x.id)">{{ x.name }}</option>
      </select>
      <select :value="state.assignee" :aria-label="t('col.assigned_to')" @change="go({ assignee: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.assignee') }}</option>
        <option value="me">{{ t('filter.assignee.me') }}</option>
        <option value="none">{{ t('filter.assignee.none') }}</option>
      </select>
      <button v-if="filtersActive" class="link-btn" @click="router.push({ query: {} })">{{ t('filter.reset') }}</button>
      <span class="spacer" />
      <div class="col-menu-wrap">
        <button class="btn" aria-haspopup="true" :aria-expanded="columnMenu" @click.stop="columnMenu = !columnMenu">{{ t('columns') }} ▾</button>
        <div v-if="columnMenu" class="col-menu" role="menu">
          <label v-for="c in ALL_COLUMNS" :key="c" :class="{ disabled: c === 'subject' }">
            <input type="checkbox" :checked="columns.includes(c)" :disabled="c === 'subject'" @change="toggleColumn(c)"> {{ t('col.' + c) }}
          </label>
        </div>
      </div>
    </div>

    <div class="split" :class="{ open: !!selectedId }">
    <div class="split-list">
    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>

    <div class="table-wrap" :class="{ busy: loading }">
      <table v-if="list">
        <thead>
          <tr>
            <th v-for="c in shownColumns" :key="c" :class="'c-' + c"
                :aria-sort="sortCol === c ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'">
              <button v-if="SORTABLE.has(c)" class="th-btn" @click="go({ sort: nextSort(state.sort, c) }, false)">
                {{ t('col.' + c) }}<span class="arrow">{{ sortCol === c ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '' }}</span>
              </button>
              <span v-else>{{ t('col.' + c) }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in list.issues" :key="r.id" :class="{ closed: r.status.is_closed, selected: r.id === selectedId }"
              :aria-selected="r.id === selectedId" @click="onRowClick($event, r.id)">
            <td v-for="c in shownColumns" :key="c" :class="'c-' + c">
              <template v-if="c === 'id'"><a :href="appUrl(r.id)">{{ r.id }}</a></template>
              <template v-else-if="c === 'subject'"><a class="subject" :href="appUrl(r.id)">{{ r.subject }}</a><span v-if="r.is_private" class="lock" title="private"> 🔒</span></template>
              <template v-else-if="c === 'project'">{{ r.project.name }}</template>
              <template v-else-if="c === 'tracker'">{{ r.tracker.name }}</template>
              <template v-else-if="c === 'author'">{{ r.author?.name }}</template>
              <InlineCell v-else-if="c === 'status'" kind="select" editable :label="r.status.name" :value="r.status.id"
                          :badge="'pill ' + (r.status.is_closed ? 'pill-closed' : 'pill-open')"
                          :load-options="() => loadOpts(r.id, 'statuses')" @save="(v) => save(r, 'status_id', v)" />
              <InlineCell v-else-if="c === 'priority'" kind="select" editable :label="r.priority.name" :value="r.priority.id"
                          :load-options="() => loadOpts(r.id, 'priorities')" @save="(v) => save(r, 'priority_id', v)" />
              <InlineCell v-else-if="c === 'assigned_to'" kind="select" editable allow-empty :label="r.assigned_to?.name ?? ''" :value="r.assigned_to?.id ?? null"
                          :load-options="() => loadOpts(r.id, 'assignees')" @save="(v) => save(r, 'assigned_to_id', v)" />
              <InlineCell v-else-if="c === 'due_date'" kind="date" editable :label="fmtDate(r.due_date)" :value="r.due_date"
                          :badge="isOverdue(r) ? 'overdue' : ''" @save="(v) => save(r, 'due_date', v)" />
              <template v-else-if="c === 'start_date'">{{ fmtDate(r.start_date) }}</template>
              <template v-else-if="c === 'done_ratio'"><progress :value="r.done_ratio" max="100" /> {{ r.done_ratio }}%</template>
              <template v-else-if="c === 'updated_on'">{{ fmtDateTime(r.updated_on) }}</template>
              <template v-else-if="c === 'created_on'">{{ fmtDateTime(r.created_on) }}</template>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="loading && !list" class="muted">{{ t('loading') }}</p>
      <p v-else-if="list && !list.issues.length" class="muted empty">{{ t('empty') }}</p>
    </div>

    <footer v-if="list" class="pager">
      <span class="muted">{{ t('results', { total: list.total }) }}</span>
      <span class="spacer" />
      <select :value="perPage" :aria-label="t('page.size')" @change="setPerPage(Number(($event.target as HTMLSelectElement).value))">
        <option v-for="n in PER_PAGE_OPTIONS" :key="n" :value="n">{{ n }} {{ t('page.size') }}</option>
      </select>
      <button class="btn" :disabled="list.page <= 1" @click="go({ page: list.page - 1 })">{{ t('page.prev') }}</button>
      <span>{{ t('page.of', { page: list.page, pages: Math.max(list.pages, 1) }) }}</span>
      <button class="btn" :disabled="list.page >= list.pages" @click="go({ page: list.page + 1 })">{{ t('page.next') }}</button>
    </footer>
    </div>
    <IssueDetail v-if="selectedId" :id="selectedId" class="split-detail" @close="openIssue(null)" @updated="onDetailUpdated" />
    </div>
  </section>
</template>
