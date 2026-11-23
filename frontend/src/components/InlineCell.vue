<script setup lang="ts">
// Click-to-edit cell. kind="select" loads its options lazily (workflow-aware) when opened.
import { nextTick, ref } from 'vue';
import { t } from '../i18n';

interface Opt { id: number | string; name: string }
const props = defineProps<{
  kind: 'select' | 'date';
  label: string;               // text shown when not editing
  value: string | number | null;
  loadOptions?: () => Promise<Opt[]>;
  allowEmpty?: boolean;        // select: offer "unassigned"
  editable: boolean;
  badge?: string;              // optional css class for the display text
}>();
const emit = defineEmits<{ (e: 'save', value: string | number | null): void }>();

const editing = ref(false);
const opts = ref<Opt[]>([]);
const busy = ref(false);
const field = ref<HTMLElement | null>(null);

async function open() {
  if (!props.editable || editing.value) return;
  busy.value = true;
  try {
    if (props.kind === 'select' && props.loadOptions) opts.value = await props.loadOptions();
    editing.value = true;
    await nextTick();
    field.value?.focus();
  } catch { /* the caller shows the error toast */ } finally { busy.value = false; }
}
function commit(v: string) {
  editing.value = false;
  const val = props.kind === 'select' ? (v === '' ? null : Number(v)) : (v || null);
  if (String(val ?? '') !== String(props.value ?? '')) emit('save', val);
}
</script>

<template>
  <span v-if="!editing" class="cell" :class="{ editable }" :tabindex="editable ? 0 : -1" role="button"
        :aria-label="label" @click="open" @keydown.enter.prevent="open" @keydown.space.prevent="open">
    <span :class="badge">{{ label || '—' }}</span>
  </span>
  <select v-else-if="kind === 'select'" ref="field" class="cell-input" :value="value ?? ''"
          @change="commit(($event.target as HTMLSelectElement).value)" @blur="editing = false" @keydown.esc="editing = false">
    <option v-if="allowEmpty" value="">{{ t('unassigned') }}</option>
    <option v-for="o in opts" :key="o.id" :value="o.id">{{ o.name }}</option>
  </select>
  <input v-else ref="field" class="cell-input" type="date" :value="value ?? ''"
         @change="commit(($event.target as HTMLInputElement).value)" @blur="editing = false" @keydown.esc="editing = false">
</template>
