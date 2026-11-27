<script setup lang="ts">
// "More filters": every filter Redmine's own issue query offers (standard attributes and custom fields), each with the
// operators Redmine allows for it. The chosen filters travel as JSON [{ field, op, values }] in the list state.
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { ListFilter, X } from 'lucide-vue-next';
import { api } from '../api/client';
import { t } from '../i18n';
import type { AdvFilter, FilterDef } from '../types';

const props = withDefaults(defineProps<{ filters: string; project?: string; module?: string }>(), { project: '', module: 'issues' });
const emit = defineEmits<{ (e: 'change', json: string): void }>();

type Opt = { label: string; value: string };
const NO_VALUE = ['!*', '*', 'nd', 't', 'ld', 'nw', 'w', 'lw', 'l2w', 'nm', 'm', 'lm', 'y', 'o', 'c', '*o', '!o'];
const DAYS = ['<t+', '>t+', '><t+', 't+', '>t-', '<t-', '><t-', 't-'];
const LIST_TYPES = ['list', 'list_optional', 'list_status', 'list_with_history', 'list_optional_with_history', 'list_subprojects', 'company'];
const DATE_TYPES = ['date', 'date_past'];
const NUMBER_TYPES = ['integer', 'float', 'hour'];

const defs = ref<FilterDef[]>([]);
const remote = ref<Record<string, Opt[]>>({});
const root = ref<HTMLElement | null>(null);
const picking = ref(false);
const search = ref('');
const optSearch = ref('');
const editing = ref<number | null>(null);
const draft = ref<AdvFilter | null>(null);

async function loadDefs() {
  try { defs.value = (await api.listFilters(props.module, props.project || undefined)).filters; } catch { defs.value = []; }
}
onMounted(loadDefs);
watch(() => props.project, loadDefs);

function parse(json: string): AdvFilter[] {
  try {
    const v = JSON.parse(json || '[]');
    return Array.isArray(v) ? v.filter((x) => x && typeof x.field === 'string' && typeof x.op === 'string').map((x) => ({ field: x.field, op: x.op, values: Array.isArray(x.values) ? x.values.map(String) : [] })) : [];
  } catch { return []; }
}
const adv = computed(() => parse(props.filters));
const items = computed(() => (draft.value && editing.value === adv.value.length ? [...adv.value, draft.value] : adv.value));

const def = (name: string) => defs.value.find((d) => d.name === name);
const labelOf = (name: string) => def(name)?.label ?? name;
const opLabel = (name: string, op: string) => def(name)?.operators.find((o) => o.id === op)?.label ?? op;

type Kind = 'none' | 'range' | 'days' | 'list' | 'date' | 'number' | 'text';
function kindOf(name: string, op: string): Kind {
  const d = def(name);
  if (NO_VALUE.includes(op)) return 'none';
  if (DAYS.includes(op)) return 'days';
  if (!d) return 'text';
  if (op === '><') return DATE_TYPES.includes(d.type) ? 'range' : NUMBER_TYPES.includes(d.type) ? 'range' : 'text';
  if (op === '=p' || op === '=!p' || op === '!p') return 'text';
  if (d.values || (d.remote && LIST_TYPES.includes(d.type))) return 'list';
  if (DATE_TYPES.includes(d.type)) return 'date';
  if (NUMBER_TYPES.includes(d.type)) return 'number';
  return 'text';
}
const rangeType = (name: string) => (DATE_TYPES.includes(def(name)?.type ?? '') ? 'date' : 'number');

function optionsOf(name: string): Opt[] {
  return def(name)?.values ?? remote.value[name] ?? [];
}
async function ensureValues(name: string) {
  const d = def(name);
  if (!d || d.values || remote.value[name] || !d.remote || !LIST_TYPES.includes(d.type)) return;
  try { remote.value = { ...remote.value, [name]: (await api.listFilterValues(props.module, name, props.project || undefined)).values }; } catch { remote.value = { ...remote.value, [name]: [] }; }
}

function summary(f: AdvFilter): string {
  const k = kindOf(f.field, f.op);
  const op = opLabel(f.field, f.op);
  if (k === 'none') return op;
  let v: string;
  if (k === 'list') {
    const all = optionsOf(f.field);
    const names = f.values.map((x) => all.find((o) => o.value === x)?.label ?? x);
    v = names.length > 2 ? t('filter.n_selected', { n: names.length }) : names.join(', ');
  } else if (k === 'range') v = f.values.filter(Boolean).join(' – ');
  else v = f.values.filter(Boolean).join(', ');
  return v ? `${op} ${v}` : '';
}

function commit(list: AdvFilter[]) { emit('change', list.length ? JSON.stringify(list) : ''); }
function close() { picking.value = false; editing.value = null; draft.value = null; search.value = ''; optSearch.value = ''; }

function pick(d: FilterDef) {
  const i = adv.value.findIndex((f) => f.field === d.name);
  picking.value = false; search.value = '';
  if (i >= 0) { edit(i); return; }
  draft.value = { field: d.name, op: d.operators[0]?.id ?? '=', values: [] };
  editing.value = adv.value.length;
  void ensureValues(d.name);
}
function edit(i: number) {
  if (editing.value === i) { close(); return; }
  draft.value = { ...adv.value[i], values: [...adv.value[i].values] };
  editing.value = i; picking.value = false; optSearch.value = '';
  void ensureValues(adv.value[i].field);
}
function setOp(op: string) {
  const d = draft.value; if (!d) return;
  const before = kindOf(d.field, d.op); d.op = op;
  if (before !== kindOf(d.field, op)) d.values = [];
}
function toggleValue(v: string) {
  const d = draft.value; if (!d) return;
  d.values = d.values.includes(v) ? d.values.filter((x) => x !== v) : [...d.values, v];
}
const setVal = (i: number, v: string) => { const d = draft.value; if (d) { const a = [...d.values]; a[i] = v; d.values = a; } };
const complete = computed(() => {
  const d = draft.value; if (!d) return false;
  const k = kindOf(d.field, d.op);
  if (k === 'none') return true;
  if (k === 'range') return !!d.values[0] && !!d.values[1];
  return d.values.filter((x) => x !== '').length > 0;
});
function apply() {
  const d = draft.value; if (!d || !complete.value) return;
  const clean: AdvFilter = { field: d.field, op: d.op, values: kindOf(d.field, d.op) === 'none' ? [] : d.values.filter((x, i) => x !== '' || kindOf(d.field, d.op) === 'range' && i < 2) };
  const list = [...adv.value];
  const idx = editing.value ?? list.length;
  if (idx < list.length) list[idx] = clean; else list.push(clean);
  close(); commit(list);
}
function remove(i: number) { const list = adv.value.filter((_, x) => x !== i); close(); commit(list); }

const matches = computed(() => {
  const q = search.value.trim().toLowerCase();
  const used = new Set(adv.value.map((f) => f.field));
  return defs.value.filter((d) => !used.has(d.name) && (!q || d.label.toLowerCase().includes(q)));
});
const visibleOptions = (name: string) => {
  const q = optSearch.value.trim().toLowerCase();
  return optionsOf(name).filter((o) => !q || o.label.toLowerCase().includes(q));
};

async function togglePicker() { const next = !picking.value; close(); picking.value = next; if (next) { await nextTick(); root.value?.querySelector<HTMLInputElement>('.adv-find')?.focus(); } }
function onDocClick(e: MouseEvent) { if (root.value && !root.value.contains(e.target as Node)) close(); }
function onKey(e: KeyboardEvent) { if (e.key === 'Escape' && (picking.value || editing.value !== null)) { close(); e.stopPropagation(); } }
onMounted(() => { document.addEventListener('click', onDocClick); document.addEventListener('keydown', onKey, true); });
onUnmounted(() => { document.removeEventListener('click', onDocClick); document.removeEventListener('keydown', onKey, true); });
</script>

<template>
  <span ref="root" class="adv">
    <div v-for="(f, i) in items" :key="f.field" class="chip-wrap">
      <span class="fchip" :class="{ on: editing === i }">
        <button class="fchip-main" aria-haspopup="true" :aria-expanded="editing === i" @click.stop="i < adv.length ? edit(i) : close()">
          <span class="fchip-name">{{ labelOf(f.field) }}</span><span class="fchip-val">{{ summary(f) || '…' }}</span>
        </button>
        <button v-if="i < adv.length" class="fchip-x" :aria-label="t('filter.remove', { name: labelOf(f.field) })" @click.stop="remove(i)"><X :size="13" /></button>
      </span>

      <div v-if="editing === i && draft" class="fpop adv-pop" role="dialog" :aria-label="labelOf(f.field)" @click.stop>
        <select class="adv-op" :value="draft.op" :aria-label="t('filter.operator')" @change="setOp(($event.target as HTMLSelectElement).value)">
          <option v-for="o in def(draft.field)?.operators" :key="o.id" :value="o.id">{{ o.label }}</option>
        </select>
        <template v-if="kindOf(draft.field, draft.op) === 'range'">
          <div class="adv-range">
            <input :type="rangeType(draft.field)" :value="draft.values[0] ?? ''" :aria-label="t('filter.from')" @input="setVal(0, ($event.target as HTMLInputElement).value)">
            <span class="muted">–</span>
            <input :type="rangeType(draft.field)" :value="draft.values[1] ?? ''" :aria-label="t('filter.to')" @input="setVal(1, ($event.target as HTMLInputElement).value)">
          </div>
        </template>
        <template v-else-if="kindOf(draft.field, draft.op) === 'days'">
          <label class="adv-days"><input type="number" min="0" step="1" :value="draft.values[0] ?? ''" @input="setVal(0, ($event.target as HTMLInputElement).value)"> {{ t('filter.days') }}</label>
        </template>
        <template v-else-if="kindOf(draft.field, draft.op) === 'list'">
          <input v-if="optionsOf(draft.field).length > 10" v-model="optSearch" class="fpop-search" type="search" :placeholder="t('filter.find')" :aria-label="t('filter.find')">
          <p v-if="!optionsOf(draft.field).length" class="muted small adv-note">{{ t('filter.loading') }}</p>
          <div class="adv-list">
            <label v-for="o in visibleOptions(draft.field)" :key="o.value" class="fopt"><input type="checkbox" :checked="draft.values.includes(o.value)" @change="toggleValue(o.value)"> {{ o.label }}</label>
          </div>
        </template>
        <template v-else-if="kindOf(draft.field, draft.op) !== 'none'">
          <input class="adv-text" :type="kindOf(draft.field, draft.op) === 'date' ? 'date' : kindOf(draft.field, draft.op) === 'number' ? 'number' : 'text'" step="any"
                 :value="draft.values[0] ?? ''" :aria-label="labelOf(draft.field)" @input="setVal(0, ($event.target as HTMLInputElement).value)" @keydown.enter.prevent="apply">
        </template>
        <button class="btn primary adv-apply" :disabled="!complete" @click="apply">{{ t('filter.apply') }}</button>
      </div>
    </div>

    <div class="chip-wrap">
      <button class="fadd" :aria-expanded="picking" aria-haspopup="true" @click.stop="togglePicker"><ListFilter :size="14" /> {{ t('filter.more') }}</button>
      <div v-if="picking" class="fpop adv-pop" role="menu" @click.stop>
        <input v-model="search" class="fpop-search adv-find" type="search" :placeholder="t('filter.find')" :aria-label="t('filter.find')">
        <div class="adv-list">
          <button v-for="d in matches" :key="d.name" class="fopt btn-like" role="menuitem" @click.stop="pick(d)">{{ d.label }}</button>
          <p v-if="!matches.length" class="muted small adv-note">{{ t('filter.none_found') }}</p>
        </div>
      </div>
    </div>
  </span>
</template>

<style>
.adv { display: contents; }
.adv-pop { display: flex; flex-direction: column; gap: 6px; min-width: 260px; max-width: min(380px, 86vw); }
.adv-list { display: flex; flex-direction: column; max-height: 240px; overflow-y: auto; }
.adv-op, .adv-text, .adv-range input, .adv-days input { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; }
.adv-range { display: flex; gap: 6px; align-items: center; }
.adv-range input { flex: 1; min-width: 0; }
.adv-days { display: flex; gap: 8px; align-items: center; }
.adv-days input { width: 90px; }
.adv-note { padding: 4px 8px; }
.adv-apply { align-self: flex-end; }
</style>
