<script setup lang="ts">
// Search box + filter chips. Active filters are chips you click to edit; "Add filter" offers the rest.
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
import { ListFilter, Plus, Search, X } from 'lucide-vue-next';
import { t } from '../i18n';
import AdvancedFilters from './AdvancedFilters.vue';
import { joinIds, splitIds, type ListState } from '../lib/listQuery';
import type { Meta } from '../types';

type Key = 'status' | 'project' | 'tracker' | 'priority' | 'assignee' | 'due';
const props = defineProps<{ state: ListState; meta: Meta | null; searchText: string }>();
const emit = defineEmits<{
  (e: 'change', patch: Partial<ListState>): void;
  (e: 'search', text: string): void;
  (e: 'reset'): void;
}>();

const open = ref<Key | 'add' | null>(null);
const userFilter = ref('');
const root = ref<HTMLElement | null>(null);
const searchBox = ref<HTMLInputElement | null>(null);
defineExpose({ focusSearch: () => searchBox.value?.focus() });

const ORDER: Key[] = ['status', 'project', 'tracker', 'priority', 'assignee', 'due'];
const label = (k: Key) => t(`filter.name.${k}`);
const PRESETS = ['open', 'closed', 'all'];

const values = computed<Record<Key, string>>(() => ({
  status: props.state.status, project: props.state.project, tracker: props.state.tracker,
  priority: props.state.priority, assignee: props.state.assignee, due: props.state.due,
}));
// status is always shown (it filters by default); the others only when set
const active = computed(() => ORDER.filter((k) => k === 'status' || values.value[k] !== ''));
const addable = computed(() => ORDER.filter((k) => !active.value.includes(k)));
const anyActive = computed(() => active.value.some((k) => k !== 'status') || props.state.status !== 'open' || props.state.q !== '' || props.state.filters !== '');

const nameOf = (list: { id: number | string; name: string }[] | undefined, id: string) =>
  list?.find((x) => String(x.id) === id)?.name ?? id;

function optionsFor(k: Key): { id: string; name: string }[] {
  const m = props.meta;
  switch (k) {
    case 'status': return (m?.statuses ?? []).map((s) => ({ id: String(s.id), name: s.name }));
    case 'tracker': return (m?.trackers ?? []).map((x) => ({ id: String(x.id), name: x.name }));
    case 'priority': return (m?.priorities ?? []).map((x) => ({ id: String(x.id), name: x.name }));
    case 'assignee': {
      const q = userFilter.value.trim().toLowerCase();
      const users = (m?.users ?? []).filter((u) => !q || u.name.toLowerCase().includes(q)).map((u) => ({ id: String(u.id), name: u.name }));
      return [{ id: 'me', name: t('filter.assignee.me') }, ...users];
    }
    default: return [];
  }
}

function valueText(k: Key): string {
  const v = values.value[k];
  if (k === 'status') {
    if (PRESETS.includes(v)) return t(`filter.status.${v}`);
  }
  if (k === 'due') return v ? t(`filter.due.${v}`) : '';
  if (k === 'project') return props.meta?.projects.find((p) => p.identifier === v)?.name ?? v;
  if (k === 'assignee' && v === 'none') return t('filter.assignee.none');
  const ids = splitIds(v);
  const all = optionsFor(k);
  const names = ids.map((id) => all.find((o) => o.id === id)?.name ?? (k === 'assignee' ? nameOf(props.meta?.users, id) : id));
  return names.length > 2 ? t('filter.n_selected', { n: names.length }) : names.join(', ');
}

function patchFor(k: Key, v: string): Partial<ListState> {
  return { [k]: v } as Partial<ListState>;
}
function isChecked(k: Key, id: string) { return splitIds(values.value[k]).includes(id); }
function toggle(k: Key, id: string) {
  let ids = splitIds(values.value[k]).filter((x) => x !== 'none' && !(k === 'status' && PRESETS.includes(x)));
  ids = ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id];
  if (k === 'status' && !ids.length) { emit('change', { status: 'open' }); return; }
  emit('change', patchFor(k, joinIds(ids)));
}
function setSingle(k: Key, v: string) { emit('change', patchFor(k, v)); open.value = null; }
function clear(k: Key) { emit('change', patchFor(k, k === 'status' ? 'open' : '')); if (open.value === k) open.value = null; }

async function addFilter(k: Key) {
  open.value = k;
  // a filter without a value is not active yet; the popover is what the user wants to see
  await nextTick();
}
function toggleOpen(k: Key | 'add') { open.value = open.value === k ? null : k; userFilter.value = ''; }
function onDocClick(e: MouseEvent) { if (root.value && !root.value.contains(e.target as Node)) open.value = null; }
function onKey(e: KeyboardEvent) { if (e.key === 'Escape' && open.value) { open.value = null; e.stopPropagation(); } }
onMounted(() => { document.addEventListener('click', onDocClick); document.addEventListener('keydown', onKey, true); });
onUnmounted(() => { document.removeEventListener('click', onDocClick); document.removeEventListener('keydown', onKey, true); });

// A just-added filter has no value yet, so it is not in `active`; keep showing its chip while its popover is open.
const shown = computed(() => {
  const k = open.value;
  return k && k !== 'add' && !active.value.includes(k) ? [...active.value, k] : active.value;
});
</script>

<template>
  <div ref="root" class="fbar" role="search">
    <label class="fsearch">
      <Search :size="15" class="text-muted" aria-hidden="true" />
      <input ref="searchBox" type="search" :value="searchText" :placeholder="t('filter.search') + '  ( / )'" :aria-label="t('filter.search')"
             @input="emit('search', ($event.target as HTMLInputElement).value)">
    </label>

    <div v-for="k in shown" :key="k" class="chip-wrap">
      <span class="fchip" :class="{ on: open === k }">
        <button class="fchip-main" :aria-expanded="open === k" aria-haspopup="true" @click.stop="toggleOpen(k)">
          <span class="fchip-name">{{ label(k) }}</span><span class="fchip-val">{{ valueText(k) || '…' }}</span>
        </button>
        <button v-if="k !== 'status' || state.status !== 'open'" class="fchip-x" :aria-label="t('filter.remove', { name: label(k) })" @click.stop="clear(k)"><X :size="13" /></button>
      </span>

      <div v-if="open === k" class="fpop" role="dialog" :aria-label="label(k)">
        <template v-if="k === 'status'">
          <label v-for="p in PRESETS" :key="p" class="fopt"><input type="radio" name="status-preset" :checked="values.status === p" @change="setSingle('status', p)"> {{ t('filter.status.' + p) }}</label>
          <hr>
          <label v-for="o in optionsFor('status')" :key="o.id" class="fopt"><input type="checkbox" :checked="isChecked('status', o.id)" @change="toggle('status', o.id)"> {{ o.name }}</label>
        </template>
        <template v-else-if="k === 'project'">
          <label class="fopt"><input type="radio" name="project" :checked="values.project === ''" @change="setSingle('project', '')"> {{ t('filter.project') }}</label>
          <label v-for="p in meta?.projects" :key="p.id" class="fopt"><input type="radio" name="project" :checked="values.project === p.identifier" @change="setSingle('project', p.identifier)"> {{ p.name }}</label>
        </template>
        <template v-else-if="k === 'due'">
          <label v-for="d in ['overdue', 'week', 'none']" :key="d" class="fopt"><input type="radio" name="due" :checked="values.due === d" @change="setSingle('due', d)"> {{ t('filter.due.' + d) }}</label>
        </template>
        <template v-else>
          <input v-if="k === 'assignee'" v-model="userFilter" class="fpop-search" type="search" :placeholder="t('filter.find_person')" :aria-label="t('filter.find_person')">
          <label v-if="k === 'assignee'" class="fopt"><input type="radio" name="assignee-none" :checked="values.assignee === 'none'" @change="setSingle('assignee', 'none')"> {{ t('filter.assignee.none') }}</label>
          <label v-for="o in optionsFor(k)" :key="o.id" class="fopt"><input type="checkbox" :checked="isChecked(k, o.id)" @change="toggle(k, o.id)"> {{ o.name }}</label>
        </template>
      </div>
    </div>

    <AdvancedFilters :filters="state.filters" :project="state.project" @change="(json) => emit('change', { filters: json })" />

    <div v-if="addable.length" class="chip-wrap">
      <button class="fadd" :aria-expanded="open === 'add'" aria-haspopup="true" @click.stop="toggleOpen('add')"><Plus :size="14" /> {{ t('filter.add') }}</button>
      <div v-if="open === 'add'" class="fpop" role="menu">
        <button v-for="k in addable" :key="k" class="fopt btn-like" role="menuitem" @click.stop="addFilter(k)"><ListFilter :size="14" /> {{ label(k) }}</button>
      </div>
    </div>
    <button v-if="anyActive" class="link-btn" @click="emit('reset')">{{ t('filter.reset') }}</button>
  </div>
</template>

<style>
.fbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.fsearch { display: flex; align-items: center; gap: 6px; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 0 10px; min-width: 220px; flex: 0 1 280px; }
.fsearch:focus-within { border-color: var(--accent); }
.fsearch input { border: 0; outline: 0; background: transparent; font: inherit; color: var(--fg); padding: 7px 0; width: 100%; }
.chip-wrap { position: relative; }
.fchip { display: inline-flex; align-items: stretch; border: 1px solid var(--border); border-radius: 8px; background: var(--surface); overflow: hidden; }
.fchip.on, .fchip:hover { border-color: var(--accent); }
.fchip-main { display: inline-flex; gap: 6px; align-items: center; font: inherit; background: none; border: 0; color: var(--fg); padding: 6px 10px; cursor: pointer; }
.fchip-name { color: var(--muted); }
.fchip-val { font-weight: 600; }
.fchip-x { background: none; border: 0; border-left: 1px solid var(--border); color: var(--muted); padding: 0 7px; cursor: pointer; display: inline-flex; align-items: center; }
.fchip-x:hover { color: var(--danger); background: var(--hover); }
.fadd { display: inline-flex; gap: 4px; align-items: center; font: inherit; color: var(--muted); background: none; border: 1px dashed var(--border); border-radius: 8px; padding: 6px 10px; cursor: pointer; }
.fadd:hover { color: var(--fg); border-color: var(--accent); }
.fpop { position: absolute; z-index: 30; top: calc(100% + 6px); left: 0; min-width: 220px; max-height: 340px; overflow-y: auto; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 6px; box-shadow: 0 10px 30px rgb(0 0 0 / 0.18); display: grid; gap: 1px; }
.fpop hr { border: 0; border-top: 1px solid var(--border); margin: 4px 0; }
.fopt { display: flex; gap: 8px; align-items: center; padding: 5px 8px; border-radius: 6px; cursor: pointer; white-space: nowrap; }
.fopt:hover { background: var(--hover); }
.fopt.btn-like { background: none; border: 0; font: inherit; color: var(--fg); text-align: left; width: 100%; }
.fpop-search { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 5px 8px; margin-bottom: 4px; }
@media (max-width: 720px) { .fsearch { flex-basis: 100%; } .fpop { max-width: 86vw; } }
</style>
