<script setup lang="ts">
import { ChevronLeft, ChevronRight, Plus } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { api } from '../../api/client';
import { locale, t } from '../../i18n';
import { addDays, byDay, calItems, type CalItem, parse, todayIso, weekStart } from '../../lib/calendar';
import { store } from '../../lib/store';
import { ui } from '../../lib/ui';
import type { CalendarData } from '../../types';

// Calendar on the start page: one day (agenda) or one week (seven columns; a day list when the widget is narrow).
const props = defineProps<{ mode: 'day' | 'week' }>();
const router = useRouter();
const today = todayIso();
const anchor = ref(props.mode === 'week' ? weekStart(today) : today);
const from = computed(() => anchor.value);
const to = computed(() => (props.mode === 'week' ? addDays(anchor.value, 6) : anchor.value));
const days = computed(() => { const out: string[] = []; for (let d = from.value; d <= to.value; d = addDays(d, 1)) out.push(d); return out; });
const data = ref<CalendarData | null>(null);
const error = ref('');

let seq = 0;
async function load() {
  const mine = ++seq;
  try {
    const r = await api.calendar({ from: from.value, to: to.value });
    if (mine === seq) { data.value = r; error.value = ''; }
  } catch (e) { if (mine === seq) error.value = (e as Error).message; }
}
watch(() => [from.value, ui.refresh], load, { immediate: true });

const buckets = computed(() => byDay(calItems(data.value), from.value, to.value));
const step = (n: number) => { anchor.value = addDays(anchor.value, n * (props.mode === 'week' ? 7 : 1)); };
const goToday = () => { anchor.value = props.mode === 'week' ? weekStart(today) : today; };
const isNow = computed(() => (props.mode === 'week' ? anchor.value === weekStart(today) : anchor.value === today));

const fmt = (d: string, o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat(locale, { ...o, timeZone: 'UTC' }).format(parse(d));
const title = computed(() => (props.mode === 'day'
  ? fmt(anchor.value, { weekday: 'long', day: 'numeric', month: 'long' })
  : `${fmt(from.value, { day: 'numeric', month: 'short' })} – ${fmt(to.value, { day: 'numeric', month: 'short', year: 'numeric' })}`));
const timeRange = (it: CalItem) => (it.ev ? (it.ev.all_day ? t('cal.all_day') : `${it.ev.starts_at!.slice(11, 16)} – ${it.ev.ends_at!.slice(11, 16)}`) : t('cal.issue'));

function open(it: CalItem, day: string) {
  if (it.ev) router.push({ path: '/calendar', query: { month: day.slice(0, 7), event: String(it.ev.id) } });
  else router.push(`/issues/${it.issue!.id}`);
}
const canAdd = computed(() => !!store.meta?.features?.calendar_add && !!data.value?.can_manage);
</script>

<template>
  <div class="calw" :class="mode">
    <div class="calw-bar">
      <button class="calw-nav" :aria-label="'‹'" @click="step(-1)"><ChevronLeft :size="15" /></button>
      <button class="calw-today" :disabled="isNow" @click="goToday">{{ t('cal.today') }}</button>
      <button class="calw-nav" :aria-label="'›'" @click="step(1)"><ChevronRight :size="15" /></button>
      <span class="calw-title">{{ title }}</span>
      <router-link v-if="canAdd" class="calw-nav ml-auto" :to="{ path: '/calendar', query: { new: '1' } }" :title="t('cal.new')" :aria-label="t('cal.new')"><Plus :size="15" /></router-link>
    </div>
    <p v-if="error" class="error px-4 py-3" role="alert">{{ t('error.load', { message: error }) }}</p>

    <template v-else-if="mode === 'day'">
      <p v-if="data && !buckets.get(anchor)?.length" class="muted px-4 py-5 text-[0.9rem]">{{ t('cal.empty') }}</p>
      <ul v-else>
        <li v-for="it in buckets.get(anchor)" :key="it.key" class="border-b border-line last:border-0">
          <button class="calw-row" :style="{ '--c': it.color }" @click="open(it, anchor)">
            <span class="calw-dot" :class="{ issue: it.kind === 'issue' }" />
            <span class="calw-time">{{ timeRange(it) }}</span>
            <span class="calw-label">{{ it.label }}<small v-if="it.ev?.location" class="muted"> · {{ it.ev.location }}</small></span>
          </button>
        </li>
      </ul>
    </template>

    <div v-else class="calw-week">
      <div v-for="d in days" :key="d" class="calw-day" :class="{ today: d === today, empty: !buckets.get(d)?.length }">
        <div class="calw-dhead"><span>{{ fmt(d, { weekday: 'short' }) }}</span><b>{{ Number(d.slice(8)) }}</b></div>
        <div class="calw-items">
          <button v-for="it in buckets.get(d)" :key="it.key" class="calw-chip" :class="{ issue: it.kind === 'issue', timed: !!it.time }" :style="{ '--c': it.color }" :title="it.label" @click="open(it, d)">
            <span v-if="it.time" class="calw-ctime">{{ it.time }}</span>{{ it.label }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style>
.calw-bar { display: flex; align-items: center; gap: 4px; padding: 8px 12px; border-bottom: 1px solid var(--border); }
.calw-bar .calw-nav { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border: 1px solid var(--border); border-radius: 6px; background: var(--surface); color: var(--fg); cursor: pointer; }
.calw-bar .calw-nav:hover { background: var(--hover); text-decoration: none; }
.calw-today { font: inherit; font-size: 0.8rem; height: 28px; padding: 0 10px; border: 1px solid var(--border); border-radius: 6px; background: var(--surface); color: var(--fg); cursor: pointer; }
.calw-today:disabled { opacity: 0.5; cursor: default; }
.calw-title { margin-left: 8px; font-size: 0.85rem; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.calw .ml-auto { margin-left: auto; }
.calw-row { display: flex; align-items: baseline; gap: 10px; width: 100%; padding: 9px 16px; border: 0; background: none; font: inherit; color: var(--fg); text-align: left; cursor: pointer; }
.calw-row:hover { background: var(--hover); }
.calw-dot { flex: none; width: 9px; height: 9px; border-radius: 50%; background: var(--c); align-self: center; }
.calw-dot.issue { background: transparent; border: 2px dashed var(--c); width: 7px; height: 7px; }
.calw-time { flex: none; min-width: 96px; font-size: 0.82rem; color: var(--muted); font-variant-numeric: tabular-nums; }
.calw-label { min-width: 0; font-weight: 500; overflow-wrap: anywhere; }
.calw-week { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); }
.calw-day { min-height: 120px; padding: 6px; border-right: 1px solid var(--border); }
.calw-items { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.calw-day:last-child { border-right: 0; }
.calw-dhead { display: flex; align-items: baseline; gap: 6px; font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.03em; margin-bottom: 2px; }
.calw-dhead b { font-size: 0.95rem; color: var(--fg); text-transform: none; }
.calw-day.today .calw-dhead b { color: var(--accent-fg); background: var(--accent); border-radius: 50%; min-width: 24px; height: 24px; display: inline-flex; align-items: center; justify-content: center; }
.calw-chip { display: block; width: 100%; text-align: left; font: inherit; font-size: 0.76rem; line-height: 1.3; padding: 2px 6px; border: 0; border-radius: 4px; cursor: pointer; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; background: var(--c); color: #fff; }
.calw-chip.timed { background: color-mix(in srgb, var(--c) 14%, var(--surface)); color: var(--fg); box-shadow: inset 3px 0 0 var(--c); }
.calw-chip.issue { background: color-mix(in srgb, var(--c) 18%, var(--surface)); color: var(--fg); border: 1px dashed var(--c); }
.calw-chip:hover { filter: brightness(1.08); text-decoration: underline; }
.calw-ctime { font-weight: 600; margin-right: 4px; opacity: 0.8; }
/* narrow widget (one third / half, or a phone): the week becomes a list of days */
.calw { container-type: inline-size; }
@container (max-width: 620px) {
  .calw-week { display: block; }
  .calw-day { min-height: 0; border-right: 0; border-bottom: 1px solid var(--border); display: flex; gap: 8px; padding: 6px 12px; }
  .calw-day:last-child { border-bottom: 0; }
  .calw-day.empty { opacity: 0.55; }
  .calw-dhead { flex: 0 0 64px; margin: 0; }
  .calw-items { flex: 1; }
  .calw-chip { white-space: normal; }
}
</style>
