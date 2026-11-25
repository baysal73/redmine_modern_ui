<script setup lang="ts">
import { CalendarDays, ChevronLeft, ChevronRight, ExternalLink, RefreshCw, Search, Trash2 } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api, readConfig } from '../api/client';
import { t } from '../i18n';
import { store } from '../lib/store';
import { toast } from '../lib/toast';
import type { CalendarData, CalEvent, CalIssue } from '../types';

const route = useRoute();
const router = useRouter();
const config = readConfig();
const data = ref<CalendarData | null>(null);
const loading = ref(false);
const error = ref('');
const searchText = ref('');
const searchBox = ref<HTMLInputElement | null>(null);
const expanded = ref<Set<string>>(new Set());
// On phones the month grid only shows coloured bars; tapping a day lists its entries underneath
const mq = window.matchMedia('(max-width: 720px)');
const mobile = ref(mq.matches);
const onMq = () => { mobile.value = mq.matches; };
const dayPick = ref<string | null>(null);
const onDay = (d: string) => { if (mobile.value) dayPick.value = d; else if (canManage.value) openNew(d, true); };

// ---- dates as plain YYYY-MM-DD strings (the server already delivers them in the user's time zone) ----
const pad = (n: number) => String(n).padStart(2, '0');
const iso = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
const parse = (s: string) => { const [y, m, d] = s.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
const addDays = (s: string, n: number) => { const d = parse(s); d.setUTCDate(d.getUTCDate() + n); return iso(d); };
const today = (() => { const n = new Date(); return `${n.getFullYear()}-${pad(n.getMonth() + 1)}-${pad(n.getDate())}`; })();

const q = computed(() => route.query);
const s = (k: string) => String(q.value[k] ?? '');
const month = computed(() => (/^\d{4}-\d{2}$/.test(s('month')) ? s('month') : today.slice(0, 7)));
const view = computed(() => (s('view') === 'list' ? 'list' : 'month'));
const mine = computed(() => s('mine') === '1');
const category = computed(() => s('category'));

const monthStart = computed(() => `${month.value}-01`);
const monthEnd = computed(() => { const d = parse(monthStart.value); d.setUTCMonth(d.getUTCMonth() + 1, 0); return iso(d); });
// Monday-first grid covering the month
const gridStart = computed(() => { const d = parse(monthStart.value); return addDays(monthStart.value, -((d.getUTCDay() + 6) % 7)); });
const gridEnd = computed(() => { const d = parse(monthEnd.value); return addDays(monthEnd.value, (7 - d.getUTCDay()) % 7); });
const weeks = computed(() => {
  const out: string[][] = [];
  for (let day = gridStart.value; day <= gridEnd.value;) { const w: string[] = []; for (let i = 0; i < 7; i++) { w.push(day); day = addDays(day, 1); } out.push(w); }
  return out;
});
const locale = (config.lang || 'en').toLowerCase();
const monthTitle = computed(() => new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(parse(monthStart.value)));
const weekdays = computed(() => weeks.value[0].map((d) => new Intl.DateTimeFormat(locale, { weekday: 'short', timeZone: 'UTC' }).format(parse(d))));
const dayLabel = (d: string) => new Intl.DateTimeFormat(locale, { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(parse(d));

// ---- items per day ----
interface Item { key: string; kind: 'event' | 'issue'; label: string; time: string; color: string; ev?: CalEvent; issue?: CalIssue; first: string; last: string }
function evRange(e: CalEvent): [string, string] {
  if (e.all_day) return [e.start_date!, e.end_date!];
  const first = e.starts_at!.slice(0, 10);
  let last = e.ends_at!.slice(0, 10);
  if (last > first && e.ends_at!.slice(11, 16) === '00:00') last = addDays(last, -1);
  return [first, last < first ? first : last];
}
const items = computed<Item[]>(() => {
  const out: Item[] = [];
  for (const e of data.value?.events ?? []) { const [first, last] = evRange(e); out.push({ key: 'e' + e.id, kind: 'event', label: e.title, time: e.all_day ? '' : e.starts_at!.slice(11, 16), color: e.color, ev: e, first, last }); }
  for (const i of data.value?.issues ?? []) { const first = i.start_date ?? i.due_date!; const last = i.due_date ?? first; out.push({ key: 'i' + i.id, kind: 'issue', label: `#${i.id} ${i.subject}`, time: '', color: i.color, issue: i, first, last: last < first ? first : last }); }
  return out;
});
const byDay = computed(() => {
  const m = new Map<string, Item[]>();
  for (const it of items.value) for (let d = it.first < gridStart.value ? gridStart.value : it.first; d <= it.last && d <= gridEnd.value; d = addDays(d, 1)) { if (!m.has(d)) m.set(d, []); m.get(d)!.push(it); }
  for (const list of m.values()) list.sort((a, b) => Number(!!b.ev?.all_day) - Number(!!a.ev?.all_day) || a.time.localeCompare(b.time));
  return m;
});
const listDays = computed(() => [...byDay.value.keys()].filter((d) => d >= monthStart.value && d <= monthEnd.value).sort());
const shown = (d: string) => { const l = byDay.value.get(d) ?? []; return expanded.value.has(d) ? l : l.slice(0, 3); };

// ---- loading ----
let seq = 0;
async function load() {
  const mine_ = ++seq; loading.value = true; error.value = '';
  try {
    const r = await api.calendar({ from: gridStart.value, to: gridEnd.value, q: s('q'), category: category.value, mine: mine.value ? 1 : undefined });
    if (mine_ === seq) data.value = r;
  } catch (e) { if (mine_ === seq) error.value = (e as ApiError).message; }
  finally { if (mine_ === seq) loading.value = false; }
}
function go(patch: Record<string, string>) {
  const next: Record<string, string> = { ...(q.value as Record<string, string>), ...patch };
  for (const k of Object.keys(next)) if (!next[k]) delete next[k];
  router.push({ path: '/calendar', query: next });
}
const shift = (n: number) => { const d = parse(monthStart.value); d.setUTCMonth(d.getUTCMonth() + n, 1); go({ month: iso(d).slice(0, 7) }); };
let timer: number | undefined;
function onSearch() { window.clearTimeout(timer); timer = window.setTimeout(() => go({ q: searchText.value.trim() }), 250); }

// ---- edit dialog ----
interface Draft { id: number | null; title: string; all_day: boolean; start: string; end: string; location: string; category: string; description: string }
const dlg = ref<Draft | null>(null);
const dlgEvent = ref<CalEvent | null>(null);
const saving = ref(false);
const canManage = computed(() => !!data.value?.can_manage);
const hour = () => `${pad(new Date().getHours() + 1 > 23 ? 23 : new Date().getHours() + 1)}:00`;
function openNew(day = today, allDay = false) {
  const t0 = hour();
  dlgEvent.value = null;
  dlg.value = { id: null, title: '', all_day: allDay, start: allDay ? day : `${day}T${t0}`, end: allDay ? day : `${day}T${pad(Math.min(Number(t0.slice(0, 2)) + 1, 23))}:00`, location: '', category: '', description: '' };
}
function openEvent(e: CalEvent) {
  dlgEvent.value = e;
  dlg.value = { id: e.id, title: e.title, all_day: e.all_day, start: e.all_day ? e.start_date! : e.starts_at!.slice(0, 16), end: e.all_day ? e.end_date! : e.ends_at!.slice(0, 16), location: e.location ?? '', category: e.category ?? '', description: e.description ?? '' };
}
function toggleAllDay() {
  const d = dlg.value!;
  if (d.all_day) { d.start = d.start.slice(0, 10); d.end = d.end.slice(0, 10) || d.start; } else { d.start = `${d.start.slice(0, 10)}T09:00`; d.end = `${d.end.slice(0, 10) || d.start.slice(0, 10)}T10:00`; }
}
async function save() {
  const d = dlg.value;
  if (!d || saving.value || !d.title.trim() || !canManage.value) return;
  saving.value = true;
  const body: Record<string, unknown> = { title: d.title.trim(), all_day: d.all_day, location: d.location, category: d.category, description: d.description };
  if (d.all_day) { body.start_date = d.start.slice(0, 10); body.end_date = d.end.slice(0, 10); } else { body.starts_at = d.start; body.ends_at = d.end; }
  try {
    if (d.id) await api.updateEvent(d.id, body); else await api.createEvent(body);
    toast(t(d.id ? 'cal.saved' : 'cal.created')); dlg.value = null; load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { saving.value = false; }
}
async function remove() {
  const d = dlg.value;
  if (!d?.id || !window.confirm(t('cal.confirm_delete'))) return;
  try { await api.deleteEvent(d.id); toast(t('cal.deleted')); dlg.value = null; load(); }
  catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
async function sync() {
  try { await api.syncCalendar(); toast(t('cal.sync_started')); window.setTimeout(load, 6000); }
  catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
const openItem = (it: Item) => { if (it.ev) openEvent(it.ev); else router.push(`/issues/${it.issue!.id}`); };

watch(() => route.query, () => {
  if (s('new')) { const { new: _n, ...rest } = route.query; router.replace({ path: route.path, query: rest }); if (store.meta?.features?.calendar_add) openNew(); return; }
  searchText.value = s('q'); load();
}, { immediate: true });
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (dlg.value && e.key === 'Escape') { dlg.value = null; return; }
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey) return;
  if (e.key === '/') { e.preventDefault(); searchBox.value?.focus(); }
  else if (e.key === 't') go({ month: today.slice(0, 7) });
}
onMounted(() => { window.addEventListener('keydown', onKey); mq.addEventListener('change', onMq); });
onUnmounted(() => { window.removeEventListener('keydown', onKey); mq.removeEventListener('change', onMq); });
const anyFilter = computed(() => !!(s('q') || category.value || mine.value));
const timeRange = (e: CalEvent) => (e.all_day ? t('cal.all_day') : `${e.starts_at!.slice(11, 16)} – ${e.ends_at!.slice(11, 16)}`);
</script>

<template>
  <section class="list-view cal">
    <div class="page-head"><h1>{{ t('nav.calendar') }}</h1><span class="muted">{{ monthTitle }}</span></div>

    <div class="list-toolbar">
      <div class="fbar" role="search">
        <div class="seg" role="group">
          <button class="seg-btn" :aria-label="'‹'" @click="shift(-1)"><ChevronLeft :size="15" /></button>
          <button class="seg-btn" @click="go({ month: today.slice(0, 7) })">{{ t('cal.today') }}</button>
          <button class="seg-btn" :aria-label="'›'" @click="shift(1)"><ChevronRight :size="15" /></button>
        </div>
        <div class="seg" role="group">
          <button class="seg-btn" :class="{ on: view === 'month' }" :aria-pressed="view === 'month'" @click="go({ view: '' })">{{ t('cal.month') }}</button>
          <button class="seg-btn" :class="{ on: view === 'list' }" :aria-pressed="view === 'list'" @click="go({ view: 'list' })">{{ t('cal.list') }}</button>
        </div>
        <label class="fsearch"><Search :size="15" class="text-muted" aria-hidden="true" />
          <input ref="searchBox" type="search" :value="searchText" :placeholder="t('cal.search') + '  ( / )'" :aria-label="t('cal.search')" @input="searchText = ($event.target as HTMLInputElement).value; onSearch()">
        </label>
        <select v-if="data?.categories.length" class="tb-select-plain" :value="category" :aria-label="t('cal.category')" @change="go({ category: ($event.target as HTMLSelectElement).value })">
          <option value="">{{ t('cal.all_categories') }}</option><option v-for="c in data.categories" :key="c.name" :value="c.name">{{ c.name }}</option>
        </select>
        <button class="seg-btn pill-toggle" :class="{ on: mine }" :aria-pressed="mine" @click="go({ mine: mine ? '' : '1' })">{{ t('cal.mine') }}</button>
        <button v-if="anyFilter" class="link-btn" @click="go({ q: '', category: '', mine: '' })">{{ t('filter.reset') }}</button>
        <span class="spacer" />
        <button v-if="data?.google.admin && data.google.enabled" class="btn flex items-center gap-1" @click="sync"><RefreshCw :size="14" /> {{ t('cal.sync') }}</button>
      </div>
    </div>

    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
    <p v-if="data && !data.can_manage" class="muted small">{{ t('cal.read_only') }}</p>

    <div v-if="view === 'month'" class="cal-grid" :class="{ busy: loading }" role="grid" :aria-label="monthTitle">
      <div class="cal-head" role="row"><span v-for="w in weekdays" :key="w" role="columnheader">{{ w }}</span></div>
      <div v-for="(w, wi) in weeks" :key="wi" class="cal-week" role="row">
        <div v-for="d in w" :key="d" class="cal-day" :class="{ other: d.slice(0, 7) !== month, today: d === today, picked: mobile && d === dayPick }" role="gridcell" @click.self="onDay(d)">
          <button class="cal-num" :class="{ today: d === today }" :disabled="!mobile && !canManage" :aria-label="dayLabel(d)" @click.stop="mobile ? onDay(d) : openNew(d)">{{ Number(d.slice(8)) }}</button>
          <button v-for="it in shown(d)" :key="it.key + d" class="cal-chip" :class="{ issue: it.kind === 'issue', timed: !!it.time }" :style="{ '--c': it.color }" :title="it.label" @click.stop="mobile ? onDay(d) : openItem(it)">
            <span v-if="it.time" class="cal-time">{{ it.time }}</span>{{ it.label }}
          </button>
          <button v-if="(byDay.get(d)?.length ?? 0) > 3 && !expanded.has(d)" class="cal-more" @click="expanded = new Set(expanded).add(d)">{{ t('cal.more', { count: (byDay.get(d)?.length ?? 0) - 3 }) }}</button>
        </div>
      </div>
    </div>

    <section v-if="view === 'month' && mobile && dayPick" class="cal-list-day cal-daypanel">
      <h2 :class="{ today: dayPick === today }">{{ dayLabel(dayPick) }}</h2>
      <p v-if="!(byDay.get(dayPick)?.length)" class="muted small">{{ t('cal.empty') }}</p>
      <button v-for="it in byDay.get(dayPick)" :key="it.key" class="cal-row" :style="{ '--c': it.color }" @click="openItem(it)">
        <span class="cal-dot" /><span class="cal-row-time">{{ it.ev ? timeRange(it.ev) : t('cal.issue') }}</span>
        <span class="cal-row-title">{{ it.label }}</span>
      </button>
      <button v-if="canManage" class="btn primary" @click="openNew(dayPick)">{{ t('cal.new') }}</button>
    </section>

    <div v-if="view === 'list'" class="cal-list" :class="{ busy: loading }">
      <p v-if="data && !listDays.length" class="muted empty">{{ t('cal.empty') }}</p>
      <section v-for="d in listDays" :key="d" class="cal-list-day">
        <h2 :class="{ today: d === today }">{{ dayLabel(d) }}</h2>
        <button v-for="it in byDay.get(d)" :key="it.key" class="cal-row" :style="{ '--c': it.color }" @click="openItem(it)">
          <span class="cal-dot" />
          <span class="cal-row-time">{{ it.ev ? timeRange(it.ev) : t('cal.issue') }}</span>
          <span class="cal-row-title">{{ it.label }}</span>
          <span class="muted small">{{ it.ev?.location || it.issue?.project }}</span>
          <CalendarDays v-if="it.ev?.google" :size="14" class="text-muted" :title="t('cal.google')" />
        </button>
      </section>
    </div>

    <div v-if="dlg" class="overlay" @mousedown.self="dlg = null">
      <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="cal-title">
        <h2 id="cal-title">{{ dlg.id ? (canManage ? t('cal.edit') : dlg.title) : t('cal.new') }}</h2>
        <form @submit.prevent="save">
          <label>{{ t('cal.title') }}<input v-model="dlg.title" required autofocus :disabled="!canManage"></label>
          <label class="check"><input v-model="dlg.all_day" type="checkbox" :disabled="!canManage" @change="toggleAllDay"> {{ t('cal.all_day') }}</label>
          <div class="row2">
            <label>{{ t('cal.start') }}<input v-model="dlg.start" required :type="dlg.all_day ? 'date' : 'datetime-local'" :disabled="!canManage"></label>
            <label>{{ t('cal.end') }}<input v-model="dlg.end" required :type="dlg.all_day ? 'date' : 'datetime-local'" :min="dlg.start" :disabled="!canManage"></label>
          </div>
          <label>{{ t('cal.location') }}<input v-model="dlg.location" :disabled="!canManage"></label>
          <label v-if="data?.categories.length">{{ t('cal.category') }}
            <select v-model="dlg.category" :disabled="!canManage"><option value="">{{ t('cal.no_category') }}</option><option v-for="c in data.categories" :key="c.name" :value="c.name">{{ c.name }}</option></select>
          </label>
          <label>{{ t('cal.description') }}<textarea v-model="dlg.description" rows="4" :disabled="!canManage" /></label>
          <p v-if="dlgEvent?.project || dlgEvent?.contact" class="muted small">
            <template v-if="dlgEvent.project">{{ t('cal.project') }}: {{ dlgEvent.project.name }}</template>
            <template v-if="dlgEvent.contact"> · <router-link :to="`/contacts/${dlgEvent.contact.id}`">{{ dlgEvent.contact.name }} <ExternalLink :size="12" class="inline" /></router-link></template>
          </p>
          <p v-if="dlgEvent?.google" class="muted small">{{ t('cal.google') }}</p>
          <div class="dialog-actions">
            <button v-if="dlg.id && canManage" type="button" class="btn flex items-center gap-1 mr-auto danger-text" @click="remove"><Trash2 :size="14" /> {{ t('cal.delete') }}</button>
            <button type="button" class="btn" @click="dlg = null">{{ t('create.cancel') }}</button>
            <button v-if="canManage" type="submit" class="btn primary" :disabled="saving || !dlg.title.trim()">{{ t('cal.save') }}</button>
          </div>
        </form>
      </div>
    </div>
  </section>
</template>

<style>
.cal-grid { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
.cal-head, .cal-week { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); }
.cal-head span { padding: 6px 8px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--muted); border-bottom: 1px solid var(--border); }
.cal-day { min-height: 112px; padding: 4px; border-right: 1px solid var(--border); border-bottom: 1px solid var(--border); display: flex; flex-direction: column; gap: 2px; cursor: default; }
.cal-day:nth-child(7n) { border-right: 0; }
.cal-week:last-child .cal-day { border-bottom: 0; }
.cal-day.other { background: var(--bg); }
.cal-day.other .cal-num { color: var(--muted); }
.cal-num { align-self: flex-start; background: none; border: 0; font: inherit; font-size: 0.8rem; width: 24px; height: 24px; border-radius: 50%; color: var(--fg); cursor: pointer; }
.cal-num:hover:not(:disabled) { background: var(--hover); }
.cal-num.today { background: var(--accent); color: var(--accent-fg); font-weight: 700; }
.cal-chip { display: block; width: 100%; text-align: left; font: inherit; font-size: 0.78rem; line-height: 1.3; padding: 1px 6px; border: 0; border-radius: 4px; cursor: pointer; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; background: var(--c); color: #fff; }
.cal-chip.timed { background: color-mix(in srgb, var(--c) 14%, var(--surface)); color: var(--fg); box-shadow: inset 3px 0 0 var(--c); }
.cal-chip.issue { background: color-mix(in srgb, var(--c) 18%, var(--surface)); color: var(--fg); border: 1px dashed var(--c); }
.cal-chip:hover { filter: brightness(1.08); text-decoration: underline; }
.cal-time { font-weight: 600; margin-right: 4px; opacity: 0.8; }
.cal-more { background: none; border: 0; font: inherit; font-size: 0.75rem; color: var(--muted); text-align: left; padding: 0 6px; cursor: pointer; }
.cal-more:hover { color: var(--accent); }
.cal-list-day h2 { font-size: 0.85rem; margin: 18px 0 6px; color: var(--muted); }
.cal-list-day h2.today { color: var(--accent); }
.cal-row { display: grid; grid-template-columns: 10px 130px minmax(0, 1fr) auto auto; gap: 10px; align-items: center; width: 100%; text-align: left; font: inherit; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 8px 12px; margin-bottom: 6px; cursor: pointer; color: var(--fg); }
.cal-row:hover { background: var(--hover); }
.cal-dot { width: 10px; height: 10px; border-radius: 50%; background: var(--c); }
.cal-row-time { font-variant-numeric: tabular-nums; color: var(--muted); }
.cal-row-title { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pill-toggle { border: 1px solid var(--border); border-radius: 6px; background: var(--surface); padding: 6px 12px; }
.pill-toggle.on { background: var(--accent); color: var(--accent-fg); }
.danger-text { color: var(--danger); }
.mr-auto { margin-right: auto; }
.cal .busy { opacity: 0.6; }
@media (max-width: 720px) {
  .cal-day { min-height: 58px; padding: 2px; }
  .cal-day.picked { background: var(--accent-soft); }
  .cal-chip { font-size: 0; height: 5px; padding: 0; margin: 1px 2px; border-radius: 3px; border: 0; box-shadow: none; background: var(--c); }
  .cal-chip.timed, .cal-chip.issue { background: var(--c); border: 0; }
  .cal-more { display: none; }
  .cal-daypanel { margin-top: 14px; }
  .cal-row { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 10px; }
  .cal-row-title { flex-basis: 100%; white-space: normal; }
  .cal-row .muted { flex-basis: 100%; overflow-wrap: anywhere; }
}
</style>
