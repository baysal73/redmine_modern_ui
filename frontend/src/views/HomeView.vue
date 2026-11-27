<script setup lang="ts">
import { AlertTriangle, ArrowDown, ArrowUp, BarChart3, Bookmark, CalendarClock, CalendarDays, CalendarRange, ChevronRight, Clock, Eye, GripVertical, Inbox, LayoutGrid, PenLine, UserCheck, X } from 'lucide-vue-next';
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { api } from '../api/client';
import CalendarWidget from '../components/home/CalendarWidget.vue';
import IssueRows from '../components/home/IssueRows.vue';
import IssuesWidget from '../components/home/IssuesWidget.vue';
import { locale, t } from '../i18n';
import { defaultState, type ListState, stateFromQuery, stateToQuery, toApiParams } from '../lib/listQuery';
import { loadMeta, store } from '../lib/store';
import { toast } from '../lib/toast';
import { ui } from '../lib/ui';
import type { Home, HomeWidget, SavedQuery, WidgetSize, WidgetType } from '../types';

// "My week": a dashboard of widgets the user arranges (order, width, rows). The layout is stored in the user's
// Redmine preferences; without one the default below is shown.
const widgets = ref<HomeWidget[]>([]);
const loaded = ref(false);
const editing = ref(false);
const home = ref<Home | null>(null);
const queries = ref<SavedQuery[] | null>(null);
const totals = reactive<Record<string, number>>({});
const error = ref('');
const hasCal = computed(() => !!store.meta?.features?.calendar);

const uid = () => Math.random().toString(36).slice(2, 10);
function defaults(): HomeWidget[] {
  return [
    { id: uid(), type: 'stats', size: 'full' },
    { id: uid(), type: 'overdue', size: 'm' },
    { id: uid(), type: 'due_soon', size: 'm' },
    ...(hasCal.value ? [{ id: uid(), type: 'cal_week', size: 'full' } as HomeWidget] : []),
    { id: uid(), type: 'undated', size: 'm' },
    { id: uid(), type: hasCal.value ? 'cal_day' : 'recent', size: 'm' } as HomeWidget,
    ...(hasCal.value ? [{ id: uid(), type: 'recent', size: 'full' } as HomeWidget] : []),
  ];
}

// ---- widget catalogue ----
const me = (field: string) => JSON.stringify([{ field, op: '=', values: ['me'] }]);
const PRESETS: Partial<Record<WidgetType, { title: string; icon: unknown; tone: string; state: Partial<ListState> }>> = {
  overdue: { title: 'home.overdue', icon: AlertTriangle, tone: 'text-danger', state: { assignee: 'me', due: 'overdue', sort: 'due_date:asc' } },
  due_soon: { title: 'home.due_soon', icon: CalendarClock, tone: 'text-warn', state: { assignee: 'me', due: 'week', sort: 'due_date:asc' } },
  undated: { title: 'home.undated', icon: Inbox, tone: 'text-muted', state: { assignee: 'me', due: 'none', sort: 'priority:desc,updated_on:desc' } },
  assigned: { title: 'home.assigned_open', icon: UserCheck, tone: 'text-accent', state: { assignee: 'me', sort: 'updated_on:desc' } },
  reported: { title: 'home.reported', icon: PenLine, tone: 'text-muted', state: { filters: me('author_id'), sort: 'updated_on:desc' } },
  watched: { title: 'home.watched', icon: Eye, tone: 'text-muted', state: { filters: me('watcher_id'), sort: 'updated_on:desc' } },
};
const OTHER: Partial<Record<WidgetType, { title: string; icon: unknown; tone: string }>> = {
  stats: { title: 'home.stats', icon: BarChart3, tone: 'text-accent' },
  recent: { title: 'home.recent', icon: Clock, tone: 'text-muted' },
  query: { title: 'home.saved_view', icon: Bookmark, tone: 'text-accent' },
  cal_day: { title: 'home.cal_day', icon: CalendarDays, tone: 'text-accent' },
  cal_week: { title: 'home.cal_week', icon: CalendarRange, tone: 'text-accent' },
};
const info = (w: HomeWidget) => PRESETS[w.type] ?? OTHER[w.type]!;
const isList = (w: HomeWidget) => !!PRESETS[w.type] || w.type === 'query';
const DEFAULT_LIMIT = 8;
const LIMITS = [5, 8, 12, 20];
const SIZES: WidgetSize[] = ['s', 'm', 'l', 'full'];
const sizeLabel = (s: WidgetSize) => ({ s: '⅓', m: '½', l: '⅔', full: t('home.size_full') }[s]);
// literal class names, so Tailwind keeps them
const sizeClass: Record<WidgetSize, string> = { s: 'lg:col-span-2', m: 'lg:col-span-3', l: 'lg:col-span-4', full: 'lg:col-span-6' };

const queryOf = (w: HomeWidget) => queries.value?.find((q) => q.id === w.query_id) ?? null;
function stateOf(w: HomeWidget): ListState | null {
  if (w.type === 'query') { const q = queryOf(w); return q ? { ...stateFromQuery(q.state), page: 1 } : null; }
  const p = PRESETS[w.type];
  return p ? { ...defaultState, ...p.state } : null;
}
const paramsOf = (w: HomeWidget) => { const s = stateOf(w); return s ? toApiParams(s, w.limit ?? DEFAULT_LIMIT) : null; };
const linkOf = (w: HomeWidget) => { const s = stateOf(w); return s ? stateToQuery(s) : null; };
const titleOf = (w: HomeWidget) => (w.type === 'query' ? (queryOf(w)?.name ?? t('home.saved_view')) : t(info(w).title));

const visible = computed(() => widgets.value.filter((w) => hasCal.value || !w.type.startsWith('cal_')));
const needsHome = computed(() => widgets.value.some((w) => w.type === 'stats' || w.type === 'recent'));
const needsQueries = computed(() => editing.value || widgets.value.some((w) => w.type === 'query'));

// ---- loading ----
async function loadHome() {
  if (!needsHome.value) return;
  try { home.value = await api.home(); error.value = ''; } catch (e) { error.value = (e as Error).message; }
}
async function loadQueries() {
  if (queries.value || !needsQueries.value) return;
  try { queries.value = (await api.issueQueries()).queries; } catch { queries.value = []; }
}
onMounted(async () => {
  await loadMeta().catch(() => {});
  try { widgets.value = (await api.homeLayout()).widgets ?? defaults(); } catch { widgets.value = defaults(); }
  loaded.value = true;
  loadHome(); loadQueries();
});
watch(() => ui.refresh, () => { home.value = null; loadHome(); });
watch(needsHome, (v) => { if (v && !home.value) loadHome(); });
watch(needsQueries, loadQueries);

// ---- editing (every change is saved right away, debounced) ----
let saveTimer: number | undefined;
function persist() {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(async () => {
    try { await api.saveHomeLayout(widgets.value); } catch (e) { toast(t('home.save_failed', { message: (e as Error).message }), 'error'); }
  }, 400);
}
const update = (w: HomeWidget, patch: Partial<HomeWidget>) => { Object.assign(w, patch); persist(); };
function move(w: HomeWidget, dir: -1 | 1) {
  const list = widgets.value; const i = list.indexOf(w); const j = i + dir;
  if (j < 0 || j >= list.length) return;
  [list[i], list[j]] = [list[j], list[i]]; persist();
}
function remove(w: HomeWidget) { widgets.value = widgets.value.filter((x) => x !== w); delete totals[w.id]; persist(); }
function add(value: string) {
  if (!value) return;
  const [type, qid] = value.split(':') as [WidgetType, string?];
  const size: WidgetSize = type === 'stats' || type === 'cal_week' ? 'full' : 'm';
  widgets.value = [...widgets.value, { id: uid(), type, size, ...(qid ? { query_id: Number(qid) } : {}) }];
  persist();
}
async function reset() {
  if (!window.confirm(t('home.reset_confirm'))) return;
  window.clearTimeout(saveTimer);
  try { await api.resetHomeLayout(); widgets.value = defaults(); } catch (e) { toast(t('home.save_failed', { message: (e as Error).message }), 'error'); }
}

// drag and drop (edit mode): drop a widget onto another to put it in that place
const dragId = ref<string | null>(null);
const overId = ref<string | null>(null);
function drop(target: HomeWidget) {
  const from = widgets.value.findIndex((x) => x.id === dragId.value);
  const to = widgets.value.indexOf(target);
  if (from >= 0 && to >= 0 && from !== to) { const list = [...widgets.value]; const [m] = list.splice(from, 1); list.splice(to, 0, m); widgets.value = list; persist(); }
  dragId.value = overId.value = null;
}

const addOptions = computed(() => [
  { label: t('home.group_issues'), items: [...(['stats', 'overdue', 'due_soon', 'undated', 'assigned', 'reported', 'watched', 'recent'] as WidgetType[]).map((x) => ({ value: x, label: t(info({ type: x } as HomeWidget).title) }))] },
  ...(queries.value?.length ? [{ label: t('home.group_views'), items: queries.value.map((q) => ({ value: `query:${q.id}`, label: q.name })) }] : []),
  ...(hasCal.value ? [{ label: t('home.group_calendar'), items: [{ value: 'cal_day', label: t('home.cal_day') }, { value: 'cal_week', label: t('home.cal_week') }] }] : []),
]);

// ---- header ----
const hour = new Date().getHours();
const greeting = computed(() => t(hour < 11 ? 'home.greeting_morning' : hour < 18 ? 'home.greeting_day' : 'home.greeting_evening'));
const firstName = computed(() => (store.meta?.user.name ?? '').split(' ')[0]);
const todayLong = computed(() => new Date().toLocaleDateString(locale, { weekday: 'long', day: 'numeric', month: 'long' }));
const tiles = computed(() => !home.value ? [] : [
  { n: home.value.counts.overdue, l: t('home.overdue'), q: { assignee: 'me', due: 'overdue' }, tone: home.value.counts.overdue ? 'text-danger' : '' },
  { n: home.value.counts.due_soon, l: t('filter.due.week'), q: { assignee: 'me', due: 'week' }, tone: '' },
  { n: home.value.counts.undated, l: t('home.undated'), q: { assignee: 'me', due: 'none' }, tone: '' },
  { n: home.value.counts.assigned_open, l: t('home.assigned_open'), q: { assignee: 'me' }, tone: 'text-accent' },
]);
</script>

<template>
  <section class="mx-auto max-w-6xl">
    <header class="mb-5 flex flex-wrap items-end gap-3">
      <div class="min-w-0 flex-1">
        <h1 class="text-2xl font-semibold tracking-tight">{{ greeting }}<span v-if="firstName">, {{ firstName }}</span></h1>
        <p class="muted mt-1">{{ todayLong }} · {{ t('home.subtitle') }}</p>
      </div>
      <template v-if="editing">
        <button class="link-btn" @click="reset">{{ t('home.reset') }}</button>
        <button class="btn primary" @click="editing = false">{{ t('home.done') }}</button>
      </template>
      <button v-else-if="loaded" class="btn flex items-center gap-1" @click="editing = true"><LayoutGrid :size="14" /> {{ t('home.customize') }}</button>
    </header>

    <p v-if="editing" class="muted mb-4 text-[0.88rem]">{{ t('home.edit_hint') }}</p>
    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="loadHome">{{ t('retry') }}</button></p>
    <p v-if="loaded && !visible.length && !editing" class="muted card-surface px-4 py-6 text-center">{{ t('home.empty') }}</p>

    <div class="dash-grid grid gap-5 lg:grid-cols-6" :class="{ editing }">
      <div v-for="w in visible" :key="w.id" class="dash-cell min-w-0" :class="[sizeClass[w.size], { over: overId === w.id && dragId !== w.id, dragging: dragId === w.id }]"
           :draggable="editing" @dragstart="dragId = w.id" @dragover.prevent="editing && (overId = w.id)" @dragleave="overId === w.id && (overId = null)"
           @drop.prevent="drop(w)" @dragend="dragId = overId = null">
        <section :class="w.type === 'stats' && !editing ? '' : 'card-surface overflow-hidden'">
          <h2 v-if="w.type !== 'stats' || editing" class="dash-head">
            <GripVertical v-if="editing" :size="15" class="dash-grip" aria-hidden="true" />
            <component :is="info(w).icon" :size="16" :class="info(w).tone" />
            <span class="truncate">{{ titleOf(w) }}</span>
            <span v-if="totals[w.id] !== undefined" class="muted font-normal">{{ totals[w.id] }}</span>
            <router-link v-if="!editing && linkOf(w) && (totals[w.id] ?? 0) > (w.limit ?? DEFAULT_LIMIT)" :to="{ path: '/issues', query: linkOf(w)! }" class="dash-all">{{ t('home.show_all') }} <ChevronRight :size="13" class="inline" /></router-link>
            <span v-if="editing" class="dash-tools">
              <select :value="w.size" :aria-label="t('home.size')" :title="t('home.size')" @change="update(w, { size: ($event.target as HTMLSelectElement).value as WidgetSize })">
                <option v-for="s in SIZES" :key="s" :value="s">{{ sizeLabel(s) }}</option>
              </select>
              <select v-if="isList(w)" :value="w.limit ?? DEFAULT_LIMIT" :aria-label="t('home.limit_n', { n: '' })" @change="update(w, { limit: Number(($event.target as HTMLSelectElement).value) })">
                <option v-for="n in LIMITS" :key="n" :value="n">{{ t('home.limit_n', { n }) }}</option>
              </select>
              <button class="dash-ibtn" :title="t('home.move_up')" :aria-label="t('home.move_up')" @click="move(w, -1)"><ArrowUp :size="14" /></button>
              <button class="dash-ibtn" :title="t('home.move_down')" :aria-label="t('home.move_down')" @click="move(w, 1)"><ArrowDown :size="14" /></button>
              <button class="dash-ibtn danger" :title="t('home.remove')" :aria-label="t('home.remove')" @click="remove(w)"><X :size="14" /></button>
            </span>
          </h2>

          <div class="dash-body">
            <div v-if="w.type === 'stats'" class="dash-tiles" :class="{ 'p-3': editing }">
              <router-link v-for="c in tiles" :key="c.l" :to="{ path: '/issues', query: c.q }" class="card-surface block p-4 no-underline transition hover:border-accent">
                <div class="text-3xl font-semibold tabular-nums" :class="c.tone">{{ c.n }}</div>
                <div class="muted mt-1 text-[0.85rem]">{{ c.l }}</div>
              </router-link>
            </div>
            <IssueRows v-else-if="w.type === 'recent'" :rows="home?.recent ?? []" recent />
            <CalendarWidget v-else-if="w.type === 'cal_day' || w.type === 'cal_week'" :mode="w.type === 'cal_day' ? 'day' : 'week'" />
            <p v-else-if="w.type === 'query' && queries && !queryOf(w)" class="muted px-4 py-5 text-[0.9rem]">{{ t('home.view_missing') }}</p>
            <IssuesWidget v-else-if="paramsOf(w)" :params="paramsOf(w)!" @total="(n) => (totals[w.id] = n)" />
          </div>
        </section>
      </div>

      <div v-if="editing" class="dash-cell lg:col-span-2">
        <label class="dash-add">
          <select value="" :aria-label="t('home.add')" @change="add(($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''">
            <option value="" disabled>{{ t('home.add') }}</option>
            <optgroup v-for="g in addOptions" :key="g.label" :label="g.label">
              <option v-for="o in g.items" :key="o.value" :value="o.value">{{ o.label }}</option>
            </optgroup>
          </select>
        </label>
      </div>
    </div>
  </section>
</template>

<style>
.dash-head { display: flex; align-items: center; gap: 8px; margin: 0; padding: 10px 16px; border-bottom: 1px solid var(--border); font-size: 0.95rem; font-weight: 600; min-height: 46px; box-sizing: border-box; }
.dash-all { margin-left: auto; font-size: 0.82rem; font-weight: 400; white-space: nowrap; }
.dash-tools { margin-left: auto; display: flex; align-items: center; gap: 4px; flex: none; }
.dash-tools select { font: inherit; font-size: 0.8rem; font-weight: 400; height: 28px; padding: 0 4px; border: 1px solid var(--border); border-radius: 6px; background: var(--surface); color: var(--fg); }
.dash-ibtn { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border: 1px solid var(--border); border-radius: 6px; background: var(--surface); color: var(--fg); cursor: pointer; }
.dash-ibtn:hover { background: var(--hover); }
.dash-ibtn.danger:hover { color: var(--danger); border-color: var(--danger); }
.dash-grip { color: var(--muted); cursor: grab; flex: none; }
.dash-body { container-type: inline-size; }
.dash-tiles { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
@container (max-width: 560px) { .dash-tiles { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
.dash-grid.editing .dash-cell > section { outline: 2px dashed color-mix(in srgb, var(--accent) 45%, transparent); outline-offset: 2px; }
.dash-grid.editing .dash-body { pointer-events: none; opacity: 0.8; max-height: 320px; overflow: hidden; }
.dash-cell.over > section { outline-color: var(--accent); outline-style: solid; }
.dash-cell.dragging { opacity: 0.4; }
.dash-add { display: flex; align-items: center; justify-content: center; height: 100%; min-height: 90px; border: 2px dashed var(--border); border-radius: 12px; padding: 12px; box-sizing: border-box; }
.dash-add select { font: inherit; padding: 6px 10px; border: 1px solid var(--border); border-radius: 8px; background: var(--surface); color: var(--fg); max-width: 100%; }
@media (max-width: 600px) { .dash-tools select { max-width: 92px; } .dash-head { flex-wrap: wrap; } }
</style>
