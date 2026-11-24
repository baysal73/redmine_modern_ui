<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { Bookmark, ChevronDown, ChevronRight, Layers, Lock, Trash2 } from 'lucide-vue-next';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api } from '../api/client';
import ReportMenu from '../components/ReportMenu.vue';
import FilterBar from '../components/FilterBar.vue';
import InlineCell from '../components/InlineCell.vue';
import IssueDetail from '../components/IssueDetail.vue';
import Avatar from '../components/ui/Avatar.vue';
import PriorityIcon from '../components/ui/PriorityIcon.vue';
import StatusBadge from '../components/ui/StatusBadge.vue';
import { loadMeta, store } from '../lib/store';
import { locale, t } from '../i18n';
import { GROUPS, defaultState, nextSort, stateFromQuery, stateToQuery, toApiParams, type ListState } from '../lib/listQuery';
import { toast } from '../lib/toast';
import { offerUndo } from '../lib/undo';
import { ui } from '../lib/ui';
import type { IssueList, IssueOptions, IssueRow } from '../types';

const route = useRoute();
const router = useRouter();

const meta = computed(() => store.meta);
const list = ref<IssueList | null>(null);
const loading = ref(true);
const error = ref('');
const filterBar = ref<InstanceType<typeof FilterBar> | null>(null);
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
  if ((e.target as HTMLElement).closest('.cell, .cell-input, select, input, .sel')) return;
  e.preventDefault();
  openIssue(id);
}
function onDetailUpdated(row: IssueRow) {
  const i = list.value?.issues.findIndex((x) => x.id === row.id) ?? -1;
  if (i >= 0) list.value!.issues[i] = row;
}
const columnMenu = ref(false);
const viewsMenu = ref(false);
const selected = ref<Set<number>>(new Set());
// reports cover the selected issues, or the issues on the current page when nothing is selected
const reportIds = computed(() => selected.value.size ? [...selected.value] : (list.value?.issues.map((i) => i.id) ?? []));
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

watch(() => ui.refresh, () => load());

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
watch(() => route.query, () => { searchText.value = state.value.q; selected.value = new Set(); load(); }, { immediate: true });

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
function previousValue(row: IssueRow, field: string): string | number | null {
  switch (field) {
    case 'status_id': return row.status.id;
    case 'priority_id': return row.priority.id;
    case 'assigned_to_id': return row.assigned_to?.id ?? null;
    case 'due_date': return row.due_date;
    default: return null;
  }
}
async function save(row: IssueRow, field: string, value: string | number | null) {
  const idx = list.value!.issues.findIndex((i) => i.id === row.id);
  const before = previousValue(row, field);
  try {
    const res = await api.updateIssue(row.id, { [field]: value });
    optionsCache.delete(row.id);
    if (idx >= 0) list.value!.issues[idx] = res.issue;
    offerUndo(t('edit.saved'), async () => {
      const back = await api.updateIssue(row.id, { [field]: before });
      optionsCache.delete(row.id);
      const i = list.value?.issues.findIndex((x) => x.id === row.id) ?? -1;
      if (i >= 0) list.value!.issues[i] = back.issue;
    });
  } catch (e) {
    toast(t('edit.failed', { message: (e as ApiError).message }), 'error');
  }
}

// ---- selection and bulk edit ----
const allSelected = computed(() => !!list.value?.issues.length && list.value.issues.every((i) => selected.value.has(i.id)));
function toggleRow(id: number) {
  const next = new Set(selected.value);
  if (next.has(id)) next.delete(id); else next.add(id);
  selected.value = next;
}
function toggleAll() {
  selected.value = allSelected.value ? new Set() : new Set(list.value?.issues.map((i) => i.id) ?? []);
}
const bulkBusy = ref(false);
async function bulk(field: 'status_id' | 'assigned_to_id' | 'priority_id', raw: string, el: HTMLSelectElement) {
  el.value = '';
  if (raw === '') return;
  const ids = [...selected.value];
  const before = new Map<number, string | number | null>((list.value?.issues ?? []).filter((i) => selected.value.has(i.id)).map((i) => [i.id, previousValue(i, field)]));
  bulkBusy.value = true;
  try {
    const value = raw === 'none' ? null : Number(raw);
    const res = await api.bulkUpdate(ids, { [field]: value });
    if (res.failed.length) toast(t('bulk.partial', { ok: res.updated.length, failed: res.failed.length, reason: res.failed[0].error }), 'error');
    else offerUndo(t('bulk.done', { n: res.updated.length }), async () => {
      const groups = new Map<string, number[]>();
      for (const u of res.updated) { const k = JSON.stringify(before.get(u.id) ?? null); groups.set(k, [...(groups.get(k) ?? []), u.id]); }
      for (const [k, gids] of groups) await api.bulkUpdate(gids, { [field]: JSON.parse(k) });
      optionsCache.clear();
      await load();
    });
    selected.value = new Set(res.failed.map((f) => f.id));
    optionsCache.clear();
    await load();
  } catch (e) {
    toast(t('edit.failed', { message: (e as ApiError).message }), 'error');
  } finally { bulkBusy.value = false; }
}

// ---- grouping ----
const groupLabel = (r: IssueRow, g: string): string => {
  switch (g) {
    case 'status': return r.status.name;
    case 'priority': return r.priority.name;
    case 'assigned_to': return r.assigned_to?.name ?? t('filter.assignee.none');
    case 'project': return r.project.name;
    case 'tracker': return r.tracker.name;
    default: return '';
  }
};
const collapsed = ref<Set<string>>(new Set());
function toggleGroup(g: string) {
  const next = new Set(collapsed.value);
  if (next.has(g)) next.delete(g); else next.add(g);
  collapsed.value = next;
}
type Entry = { head: true; key: string; uid: string; count: number } | { head: false; r: IssueRow };
const entries = computed<Entry[]>(() => {
  const rows = list.value?.issues ?? [];
  const g = state.value.group;
  if (!g) return rows.map((r) => ({ head: false, r }));
  const out: Entry[] = [];
  const counts = new Map<string, number>();
  rows.forEach((r) => counts.set(groupLabel(r, g), (counts.get(groupLabel(r, g)) ?? 0) + 1));
  let last: string | null = null;
  for (const r of rows) {
    const key = groupLabel(r, g);
    if (key !== last) { out.push({ head: true, key, uid: `g${out.length}:${key}`, count: counts.get(key) ?? 0 }); last = key; }
    if (!collapsed.value.has(key)) out.push({ head: false, r });
  }
  return out;
});

// ---- saved views (kept in this browser) ----
interface SavedView { name: string; query: Record<string, string> }
const views = ref<SavedView[]>(loadViews());
const newViewName = ref('');
function loadViews(): SavedView[] {
  try {
    const v = JSON.parse(safeGet('modern_ui_views') ?? '[]');
    return Array.isArray(v) ? v.filter((x) => x && typeof x.name === 'string' && x.query && typeof x.query === 'object') : [];
  } catch { return []; }
}
function persistViews() { safeSet('modern_ui_views', JSON.stringify(views.value)); }
function saveView() {
  const name = newViewName.value.trim();
  if (!name) return;
  const q = stateToQuery({ ...state.value, page: 1 });
  views.value = [...views.value.filter((v) => v.name !== name), { name, query: q }];
  persistViews();
  newViewName.value = '';
  toast(t('views.saved', { name }));
}
function applyView(v: SavedView) { router.push({ query: v.query }); viewsMenu.value = false; }
function deleteView(name: string) { views.value = views.value.filter((v) => v.name !== name); persistViews(); }
const currentViewName = computed(() => {
  const cur = JSON.stringify(Object.entries(stateToQuery({ ...state.value, page: 1 })).sort());
  return views.value.find((v) => JSON.stringify(Object.entries(v.query).sort()) === cur)?.name ?? '';
});

// ---- helpers ----
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '');
const fmtDateTime = (s: string) => new Date(s).toLocaleString(locale, { dateStyle: 'short', timeStyle: 'short' });
const fmtShort = (s: string) => new Date(s).toLocaleDateString(locale, { day: 'numeric', month: 'short', year: '2-digit' });
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
  if (e.key === '/' && !typing) { e.preventDefault(); filterBar.value?.focusSearch(); }
  if (e.key === 'Escape' && selectedId.value && !typing) openIssue(null);
  if ((e.key === 'j' || e.key === 'k') && !typing && !e.ctrlKey && !e.metaKey && list.value?.issues.length) {
    const ids = list.value.issues.map((i) => i.id);
    const cur = selectedId.value ? ids.indexOf(selectedId.value) : -1;
    const nxt = e.key === 'j' ? Math.min(cur + 1, ids.length - 1) : Math.max(cur - 1, 0);
    openIssue(ids[nxt]);
  }
}
function onDocClick(e: MouseEvent) { if (!(e.target as HTMLElement).closest('.col-menu-wrap')) { columnMenu.value = false; viewsMenu.value = false; } }
onMounted(async () => {
  window.addEventListener('keydown', onKey);
  document.addEventListener('click', onDocClick);
  try { await loadMeta(); } catch (e) { error.value = (e as Error).message; }
});
onUnmounted(() => { window.removeEventListener('keydown', onKey); document.removeEventListener('click', onDocClick); });
</script>

<template>
  <section class="list-view">
    <div class="page-head"><h1>{{ t('nav.issues') }}</h1><span v-if="list" class="muted">{{ t('results', { total: list.total }) }}</span></div>
    <div class="list-toolbar">
      <FilterBar ref="filterBar" :state="state" :meta="meta" :search-text="searchText"
                 @change="go($event)" @search="(v) => { searchText = v; onSearchInput(); }" @reset="router.push({ query: {} })" />
      <span class="spacer" />
      <label class="tb-select" :class="{ on: state.group }"><Layers :size="14" aria-hidden="true" />
        <select :value="state.group" :aria-label="t('group.by')" @change="go({ group: ($event.target as HTMLSelectElement).value }, false)">
          <option value="">{{ t('group.none') }}</option>
          <option v-for="g in GROUPS" :key="g" :value="g">{{ t('group.by') }}: {{ t('col.' + g) }}</option>
        </select>
      </label>
      <ReportMenu :issue-ids="reportIds" :project-id="state.project || undefined" />
      <div class="col-menu-wrap">
        <button class="btn tb-btn" aria-haspopup="true" :aria-expanded="viewsMenu" @click.stop="viewsMenu = !viewsMenu"><Bookmark :size="14" /> {{ currentViewName || t('views.title') }} <ChevronDown :size="13" /></button>
        <div v-if="viewsMenu" class="col-menu views-menu" role="menu" @click.stop>
          <p v-if="!views.length" class="muted small px-2 py-1">{{ t('views.empty') }}</p>
          <div v-for="v in views" :key="v.name" class="view-row">
            <button class="view-name" :class="{ on: v.name === currentViewName }" @click="applyView(v)">{{ v.name }}</button>
            <button class="icon-btn view-del" :aria-label="t('views.delete', { name: v.name })" @click="deleteView(v.name)"><Trash2 :size="13" /></button>
          </div>
          <form class="view-save" @submit.prevent="saveView">
            <input v-model="newViewName" :placeholder="t('views.name_ph')" :aria-label="t('views.name_ph')" maxlength="60">
            <button class="btn primary" :disabled="!newViewName.trim()">{{ t('views.save') }}</button>
          </form>
          <p class="muted small px-2">{{ t('views.local_hint') }}</p>
        </div>
      </div>
      <div class="col-menu-wrap">
        <button class="btn tb-btn" aria-haspopup="true" :aria-expanded="columnMenu" @click.stop="columnMenu = !columnMenu">{{ t('columns') }} <ChevronDown :size="13" /></button>
        <div v-if="columnMenu" class="col-menu" role="menu">
          <label v-for="c in ALL_COLUMNS" :key="c" :class="{ disabled: c === 'subject' }">
            <input type="checkbox" :checked="columns.includes(c)" :disabled="c === 'subject'" @change="toggleColumn(c)"> {{ t('col.' + c) }}
          </label>
        </div>
      </div>
    </div>

    <div v-if="selected.size" class="bulkbar" role="region" :aria-label="t('bulk.title')">
      <strong>{{ t('bulk.selected', { n: selected.size }) }}</strong>
      <select :disabled="bulkBusy" :aria-label="t('col.status')" @change="bulk('status_id', ($event.target as HTMLSelectElement).value, $event.target as HTMLSelectElement)">
        <option value="">{{ t('bulk.set_status') }}</option>
        <option v-for="s in meta?.statuses" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
      <select :disabled="bulkBusy" :aria-label="t('col.assigned_to')" @change="bulk('assigned_to_id', ($event.target as HTMLSelectElement).value, $event.target as HTMLSelectElement)">
        <option value="">{{ t('bulk.set_assignee') }}</option>
        <option value="none">{{ t('filter.assignee.none') }}</option>
        <option v-for="u in meta?.users" :key="u.id" :value="u.id">{{ u.name }}</option>
      </select>
      <select :disabled="bulkBusy" :aria-label="t('col.priority')" @change="bulk('priority_id', ($event.target as HTMLSelectElement).value, $event.target as HTMLSelectElement)">
        <option value="">{{ t('bulk.set_priority') }}</option>
        <option v-for="p in meta?.priorities" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select>
      <span class="spacer" />
      <button class="link-btn" @click="selected = new Set()">{{ t('bulk.clear') }}</button>
    </div>

    <div class="split" :class="{ open: !!selectedId }">
    <div class="split-list">
    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>

    <div class="table-wrap" :class="{ busy: loading }">
      <table v-if="list">
        <thead>
          <tr>
            <th class="sel"><input type="checkbox" :checked="allSelected" :aria-label="t('bulk.select_all')" @change="toggleAll"></th>
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
          <template v-for="en in entries" :key="en.head ? en.uid : en.r.id">
          <tr v-if="en.head" class="group-row">
            <td :colspan="shownColumns.length + 1">
              <button class="group-btn" :aria-expanded="!collapsed.has(en.key)" @click="toggleGroup(en.key)">
                <component :is="collapsed.has(en.key) ? ChevronRight : ChevronDown" :size="15" /> {{ en.key }} <span class="muted">{{ en.count }}</span>
              </button>
            </td>
          </tr>
          <tr v-else :class="{ closed: en.r.status.is_closed, selected: en.r.id === selectedId }"
              :aria-selected="en.r.id === selectedId" @click="onRowClick($event, en.r.id)">
            <td class="sel"><input type="checkbox" :checked="selected.has(en.r.id)" :aria-label="t('bulk.select_row', { id: en.r.id })" @change="toggleRow(en.r.id)"></td>
            <td v-for="c in shownColumns" :key="c" :class="'c-' + c">
              <template v-if="c === 'id'"><a :href="appUrl(en.r.id)">{{ en.r.id }}</a></template>
              <template v-else-if="c === 'subject'"><a class="subject" :href="appUrl(en.r.id)">{{ en.r.subject }}</a><Lock v-if="en.r.is_private" :size="12" class="ml-1 inline text-muted" aria-label="private" /></template>
              <template v-else-if="c === 'project'">{{ en.r.project.name }}</template>
              <template v-else-if="c === 'tracker'">{{ en.r.tracker.name }}</template>
              <template v-else-if="c === 'author'"><span v-if="en.r.author" class="inline-flex items-center gap-2"><Avatar :name="en.r.author.name" :size="20" />{{ en.r.author.name }}</span></template>
              <InlineCell v-else-if="c === 'status'" kind="select" editable :label="en.r.status.name" :value="en.r.status.id"
                          :load-options="() => loadOpts(en.r.id, 'statuses')" @save="(v) => save(en.r, 'status_id', v)"><StatusBadge :status="en.r.status" plain /></InlineCell>
              <InlineCell v-else-if="c === 'priority'" kind="select" editable :label="en.r.priority.name" :value="en.r.priority.id"
                          :load-options="() => loadOpts(en.r.id, 'priorities')" @save="(v) => save(en.r, 'priority_id', v)"><PriorityIcon :priority="en.r.priority" /></InlineCell>
              <InlineCell v-else-if="c === 'assigned_to'" kind="select" editable allow-empty :label="en.r.assigned_to?.name ?? ''" :value="en.r.assigned_to?.id ?? null"
                          :load-options="() => loadOpts(en.r.id, 'assignees')" @save="(v) => save(en.r, 'assigned_to_id', v)">
                <span v-if="en.r.assigned_to" class="inline-flex items-center gap-2"><Avatar :name="en.r.assigned_to.name" :size="20" />{{ en.r.assigned_to.name }}</span><span v-else class="muted">—</span>
              </InlineCell>
              <InlineCell v-else-if="c === 'due_date'" kind="date" editable :label="fmtDate(en.r.due_date)" :value="en.r.due_date"
                          :badge="isOverdue(en.r) ? 'overdue' : ''" @save="(v) => save(en.r, 'due_date', v)" />
              <template v-else-if="c === 'start_date'">{{ fmtDate(en.r.start_date) }}</template>
              <template v-else-if="c === 'done_ratio'"><progress :value="en.r.done_ratio" max="100" /> {{ en.r.done_ratio }}%</template>
              <template v-else-if="c === 'updated_on'"><span :title="fmtDateTime(en.r.updated_on)">{{ fmtShort(en.r.updated_on) }}</span></template>
              <template v-else-if="c === 'created_on'"><span :title="fmtDateTime(en.r.created_on)">{{ fmtShort(en.r.created_on) }}</span></template>
            </td>
          </tr>
          </template>
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
