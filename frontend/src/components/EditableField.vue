<script setup lang="ts">
// A value that turns into an editor when clicked and saves when you click away (Enter saves, Esc cancels).
// Checkboxes save immediately. Values are strings (string[] for multi select, boolean for checkboxes).
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { Pencil } from 'lucide-vue-next';
import { t } from '../i18n';
import MultiPicker from './MultiPicker.vue';
import RichText from './RichText.vue';

type Kind = 'text' | 'textarea' | 'number' | 'date' | 'select' | 'multi' | 'check' | 'rich';
type Val = string | string[] | boolean | null;
interface Opt { label: string; value: string }
const props = withDefaults(defineProps<{
  kind: Kind; modelValue: Val; editable?: boolean; options?: Opt[]; allowEmpty?: boolean; label: string;
  step?: string; project?: string | number | null; placeholder?: string;
}>(), { editable: true, options: () => [], allowEmpty: false, step: 'any', project: null, placeholder: '' });
const emit = defineEmits<{ (e: 'save', v: Val): void }>();

const editing = ref(false);
const draft = ref<Val>(null);
const field = ref<HTMLElement | null>(null);
const wrap = ref<HTMLElement | null>(null);
const rich = ref<InstanceType<typeof RichText> | null>(null);

function open(e?: Event) {
  if (!props.editable || editing.value) return;
  if ((e?.target as HTMLElement | null)?.closest('a, button')) return; // links inside values keep working
  const sel = window.getSelection();
  if (sel && !sel.isCollapsed && (e?.currentTarget as HTMLElement | null)?.contains(sel.anchorNode)) return; // selecting text to copy it
  draft.value = Array.isArray(props.modelValue) ? [...props.modelValue] : props.modelValue;
  editing.value = true;
  nextTick(() => field.value?.focus?.());
}
function cancel() { editing.value = false; }
function commit() {
  if (!editing.value) return;
  editing.value = false;
  const a = JSON.stringify(draft.value ?? ''); const b = JSON.stringify(props.modelValue ?? '');
  if (a !== b) emit('save', draft.value);
}
// The rich editor may never get focus (so it never blurs): clicking anywhere outside also ends editing
function onDocDown(e: MouseEvent) {
  if (!editing.value || props.kind !== 'rich') return;
  const target = e.target as HTMLElement;
  if (wrap.value?.contains(target) || target.closest('.cke_reset_all, .cke_dialog_background_cover, .cke')) return;
  rich.value?.flush();
  commit();
}
watch(editing, (on) => { if (on) document.addEventListener('mousedown', onDocDown, true); else document.removeEventListener('mousedown', onDocDown, true); });
onBeforeUnmount(() => document.removeEventListener('mousedown', onDocDown, true));
function toggleCheck(v: boolean) { emit('save', v); }
</script>

<template>
  <label v-if="kind === 'check'" class="ef-check">
    <input type="checkbox" :checked="!!modelValue" :disabled="!editable" @change="toggleCheck(($event.target as HTMLInputElement).checked)"> <slot>{{ label }}</slot>
  </label>

  <div v-else-if="!editing" class="ef" :class="{ editable }" :tabindex="editable ? 0 : -1" :role="editable ? 'button' : undefined"
       :aria-label="editable ? t('edit.field', { name: label }) : undefined" @click="open" @keydown.enter.self.prevent="open">
    <slot />
    <Pencil v-if="editable" :size="12" class="ef-pencil" aria-hidden="true" />
  </div>

  <div v-else ref="wrap" class="ef-edit" @keydown.esc.stop="cancel">
    <select v-if="kind === 'select'" ref="field" v-model="draft as string" class="cell-input" :aria-label="label" @change="commit" @blur="commit">
      <option v-if="allowEmpty" value="">{{ t('edit.none') }}</option>
      <option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option>
    </select>
    <MultiPicker v-else-if="kind === 'multi'" v-model="draft as string[]" :options="options" :label="label" auto-open @close="commit" />
    <textarea v-else-if="kind === 'textarea'" ref="field" v-model="draft as string" class="cell-input ef-area" rows="3" :aria-label="label"
              @blur="commit" @keydown.ctrl.enter.prevent="commit" @keydown.meta.enter.prevent="commit" />
    <RichText v-else-if="kind === 'rich'" ref="rich" v-model="draft as string" autofocus :project="project" :rows="8" :height="240" :label="label" @blur="commit" @submit="commit" />
    <input v-else ref="field" v-model="draft as string" class="cell-input" :type="kind" :step="kind === 'number' ? step : undefined"
           :aria-label="label" :placeholder="placeholder" @blur="commit" @change="kind === 'date' && commit()" @keydown.enter.prevent="commit">
  </div>
</template>

<style>
.ef { position: relative; display: block; border-radius: 6px; padding: 2px 6px; margin: -2px -6px; min-height: 1.4em; border: 1px solid transparent; }
.ef.editable { cursor: text; }
.ef.editable:hover, .ef.editable:focus-visible { border-color: var(--border); background: var(--surface); }
.ef-pencil { position: absolute; right: 6px; top: 6px; color: var(--muted); opacity: 0; }
.ef.editable:hover .ef-pencil { opacity: 1; }
.ef-edit { display: block; }
.ef-edit .cell-input, .ef-area { width: 100%; box-sizing: border-box; }
.ef-check { display: inline-flex; align-items: center; gap: 8px; }
</style>
