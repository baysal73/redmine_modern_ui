<script setup lang="ts">
// Pick several values from a long list without losing the others: chips for what is chosen, a searchable
// checklist to add or remove. Replaces the native <select multiple> (Ctrl + click).
import { Plus, X } from 'lucide-vue-next';
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
import { t } from '../i18n';

interface Opt { label: string; value: string }
const props = defineProps<{ modelValue: string[]; options: Opt[]; autoOpen?: boolean; label?: string }>();
const emit = defineEmits<{ (e: 'update:modelValue', v: string[]): void; (e: 'close'): void }>();

const open = ref(false);
const q = ref('');
const root = ref<HTMLElement | null>(null);
const search = ref<HTMLInputElement | null>(null);

const labelOf = (v: string) => props.options.find((o) => o.value === v)?.label ?? v;
const chosen = computed(() => new Set(props.modelValue));
const filtered = computed(() => {
  const needle = q.value.trim().toLowerCase();
  return props.options.filter((o) => !needle || o.label.toLowerCase().includes(needle));
});
function toggle(v: string) {
  emit('update:modelValue', chosen.value.has(v) ? props.modelValue.filter((x) => x !== v) : [...props.modelValue, v]);
}
function openList() { open.value = true; nextTick(() => search.value?.focus()); }
function closeList() { open.value = false; q.value = ''; emit('close'); }
function onDown(e: MouseEvent) { if (root.value && !root.value.contains(e.target as Node) && (open.value || props.autoOpen)) closeList(); }
function onKey(e: KeyboardEvent) { if (e.key === 'Escape' && open.value) { e.stopPropagation(); closeList(); } }
onMounted(() => {
  document.addEventListener('mousedown', onDown, true);
  if (props.autoOpen) openList();
});
onUnmounted(() => document.removeEventListener('mousedown', onDown, true));
</script>

<template>
  <div ref="root" class="mpick" @keydown="onKey">
    <ul class="mpick-chips" :aria-label="label">
      <li v-for="v in modelValue" :key="v" class="mpick-chip">
        {{ labelOf(v) }}
        <button type="button" :aria-label="t('picker.remove', { name: labelOf(v) })" @click="toggle(v)"><X :size="12" /></button>
      </li>
      <li><button type="button" class="mpick-add" :aria-expanded="open" @click="open ? closeList() : openList()"><Plus :size="13" /> {{ t('picker.add') }}</button></li>
    </ul>
    <div v-if="open" class="mpick-pop" role="listbox" aria-multiselectable="true">
      <input ref="search" v-model="q" type="search" class="mpick-search" :placeholder="t('picker.search')" :aria-label="t('picker.search')" @keydown.enter.prevent>
      <div class="mpick-list">
        <label v-for="o in filtered" :key="o.value" class="mpick-opt" :class="{ on: chosen.has(o.value) }">
          <input type="checkbox" :checked="chosen.has(o.value)" @change="toggle(o.value)"> {{ o.label }}
        </label>
        <p v-if="!filtered.length" class="muted small mpick-none">{{ t('picker.none') }}</p>
      </div>
      <div class="mpick-foot"><span class="muted small">{{ t('picker.count', { n: modelValue.length }) }}</span>
        <button v-if="modelValue.length" type="button" class="link-btn" @click="emit('update:modelValue', [])">{{ t('picker.clear') }}</button></div>
    </div>
  </div>
</template>

<style>
.mpick { position: relative; }
.mpick-chips { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.mpick-chip { display: inline-flex; align-items: center; gap: 4px; background: var(--pill-open); color: var(--pill-open-fg); border-radius: 999px; padding: 2px 4px 2px 10px; font-size: 0.85rem; }
.mpick-chip button { display: inline-flex; background: none; border: 0; color: inherit; cursor: pointer; padding: 2px; border-radius: 50%; }
.mpick-chip button:hover { background: rgb(0 0 0 / 0.12); }
.mpick-add { display: inline-flex; align-items: center; gap: 3px; font: inherit; font-size: 0.85rem; color: var(--muted); background: none; border: 1px dashed var(--border); border-radius: 999px; padding: 2px 10px; cursor: pointer; }
.mpick-add:hover { color: var(--fg); border-color: var(--accent); }
.mpick-pop { position: absolute; z-index: 40; top: calc(100% + 6px); left: 0; min-width: 260px; max-width: 92vw; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; box-shadow: 0 10px 30px rgb(0 0 0 / 0.2); padding: 8px; }
.mpick-search { width: 100%; font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; margin-bottom: 6px; box-sizing: border-box; }
.mpick-list { max-height: 240px; overflow-y: auto; display: grid; gap: 1px; }
.mpick-opt { display: flex; gap: 8px; align-items: center; padding: 5px 8px; border-radius: 6px; cursor: pointer; }
.mpick-opt:hover { background: var(--hover); }
.mpick-opt.on { font-weight: 600; }
.mpick-none { padding: 6px 8px; }
.mpick-foot { display: flex; justify-content: space-between; align-items: center; border-top: 1px solid var(--border); margin-top: 6px; padding-top: 4px; }
</style>
