<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import RichText from './RichText.vue';
import { t } from '../i18n';
import { trapFocus } from '../lib/dialog';
import { toast } from '../lib/toast';
import type { IssueForm, IssueRow } from '../types';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'saved', row: IssueRow): void }>();
const config = readConfig();

const root = ref<HTMLElement | null>(null);
const form = ref<IssueForm | null>(null);
const values = ref<Record<string, string | number | boolean | null>>({});
const original = ref('');
const cfValues = ref<Record<number, string | string[]>>({});
const cfOriginal = ref('');
const error = ref('');
const busy = ref(false);
let release: (() => void) | null = null;

const can = (f: string) => !!form.value?.editable.includes(f);
const req = (f: string) => !!form.value?.required.includes(f);
const classicEdit = `${config.root}/issues/${props.id}/edit`;
const showDescription = computed(() => can('description'));
const hasAnyField = computed(() => (form.value?.editable.length ?? 0) > 0 || (form.value?.custom_fields.length ?? 0) > 0);

onMounted(async () => {
  try {
    const f = await api.issueForm(props.id);
    form.value = f;
    values.value = { ...f.values };
    original.value = JSON.stringify(values.value);
    cfValues.value = Object.fromEntries(f.custom_fields.map((c) => [c.id, c.multiple ? [...(c.value as string[])] : c.value]));
    cfOriginal.value = JSON.stringify(cfValues.value);
  } catch (e) { error.value = (e as Error).message; }
  release = trapFocus(root.value!, () => emit('close'));
});
onUnmounted(() => release?.());

const num = (v: unknown) => (v === '' || v === null || v === undefined ? null : Number(v));
async function save() {
  if (!form.value || busy.value) return;
  busy.value = true; error.value = '';
  const issue: Record<string, unknown> = {};
  const orig = JSON.parse(original.value) as Record<string, unknown>;
  for (const f of form.value.editable) {
    if (f === 'notes' || f === 'private_notes') continue;
    if (f === 'description' && !showDescription.value) continue;
    if (JSON.stringify(values.value[f] ?? null) !== JSON.stringify(orig[f] ?? null)) {
      const raw = values.value[f];
      issue[f] = ['status_id', 'priority_id', 'assigned_to_id', 'category_id', 'fixed_version_id', 'done_ratio', 'estimated_hours'].includes(f) ? num(raw) : (raw === '' ? null : raw);
    }
  }
  const cfOrig = JSON.parse(cfOriginal.value) as Record<string, unknown>;
  const changed: Record<string, unknown> = {};
  for (const [id, v] of Object.entries(cfValues.value)) if (JSON.stringify(v) !== JSON.stringify(cfOrig[id])) changed[id] = v;
  if (Object.keys(changed).length) issue.custom_field_values = changed;
  if (!Object.keys(issue).length) { emit('close'); busy.value = false; return; }
  try {
    const res = await api.updateIssue(props.id, issue);
    toast(t('edit.saved'));
    emit('saved', res.issue);
  } catch (e) { error.value = (e as ApiError).message; } finally { busy.value = false; }
}

</script>

<template>
  <div class="overlay" @mousedown.self="emit('close')">
    <div ref="root" class="dialog wide" role="dialog" aria-modal="true" aria-labelledby="ed-title">
      <h2 id="ed-title">{{ t('edit.title') }} #{{ id }}</h2>
      <p v-if="!form && !error" class="muted">{{ t('loading') }}</p>
      <p v-else-if="form && !hasAnyField" class="muted">{{ t('edit.no_permission') }}</p>
      <form v-else-if="form" @submit.prevent="save">
        <label v-if="can('subject')">{{ t('col.subject') }}<input v-model="values.subject" type="text" maxlength="255" required></label>
        <div v-if="showDescription" class="full"><label>{{ t('detail.description') }}</label>
          <RichText v-model="(values.description as string)" :project="form.project_id" :rows="6" :height="220" :label="t('detail.description')" /></div>

        <div class="grid2">
          <label v-if="can('status_id')">{{ t('col.status') }}
            <select v-model="values.status_id"><option v-for="s in form.options.statuses" :key="s.id" :value="s.id">{{ s.name }}</option></select></label>
          <label v-if="can('priority_id')">{{ t('col.priority') }}
            <select v-model="values.priority_id"><option v-for="p in form.options.priorities" :key="p.id" :value="p.id">{{ p.name }}</option></select></label>
          <label v-if="can('assigned_to_id')">{{ t('col.assigned_to') }}
            <select v-model="values.assigned_to_id"><option :value="null">{{ t('unassigned') }}</option><option v-for="u in form.options.assignees" :key="u.id" :value="u.id">{{ u.name }}</option></select></label>
          <label v-if="can('category_id') && form.options.categories.length">{{ t('edit.category') }}
            <select v-model="values.category_id"><option :value="null">{{ t('edit.none') }}</option><option v-for="c in form.options.categories" :key="c.id" :value="c.id">{{ c.name }}</option></select></label>
          <label v-if="can('fixed_version_id') && form.options.versions.length">{{ t('edit.version') }}
            <select v-model="values.fixed_version_id"><option :value="null">{{ t('edit.none') }}</option><option v-for="v in form.options.versions" :key="v.id" :value="v.id">{{ v.name }}</option></select></label>
          <label v-if="can('start_date')">{{ t('col.start_date') }}<input v-model="values.start_date" type="date"></label>
          <label v-if="can('due_date')">{{ t('col.due_date') }}<input v-model="values.due_date" type="date"></label>
          <label v-if="can('done_ratio')">{{ t('col.done_ratio') }}
            <select v-model="values.done_ratio"><option v-for="n in 11" :key="n" :value="(n - 1) * 10">{{ (n - 1) * 10 }} %</option></select></label>
          <label v-if="can('estimated_hours')">{{ t('edit.estimated') }}<input v-model="values.estimated_hours" type="number" min="0" step="0.25"></label>
        </div>
        <label v-if="can('is_private')" class="check"><input v-model="values.is_private" type="checkbox"> {{ t('edit.private') }}</label>

        <template v-if="form.custom_fields.length">
          <h3>{{ t('edit.custom') }}</h3>
          <div class="grid2">
            <label v-for="c in form.custom_fields" :key="c.id" :class="{ full: c.kind === 'text' }" :title="c.description">
              {{ c.name }}<span v-if="c.required"> *</span>
              <select v-if="c.kind === 'select' && c.multiple" v-model="cfValues[c.id]" multiple size="4">
                <option v-for="o in c.options" :key="o.value" :value="o.value">{{ o.label }}</option></select>
              <select v-else-if="c.kind === 'select'" v-model="cfValues[c.id]">
                <option value="">{{ t('edit.none') }}</option><option v-for="o in c.options" :key="o.value" :value="o.value">{{ o.label }}</option></select>
              <textarea v-else-if="c.kind === 'text'" v-model="(cfValues[c.id] as string)" rows="3" />
              <input v-else-if="c.kind === 'date'" v-model="(cfValues[c.id] as string)" type="date">
              <input v-else-if="c.kind === 'int' || c.kind === 'float'" v-model="(cfValues[c.id] as string)" type="number" :step="c.kind === 'int' ? 1 : 'any'">
              <input v-else v-model="(cfValues[c.id] as string)" type="text">
              <span v-if="c.multiple && c.kind === 'select'" class="muted small">Ctrl / ⌘ + click</span>
              
            </label>
          </div>
        </template>

        <p v-if="error" class="error-text" role="alert">{{ error }}</p>
        <div class="dialog-actions">
          <a class="muted small" :href="classicEdit" style="margin-right:auto">{{ t('detail.classic') }}</a>
          <button type="button" class="btn" @click="emit('close')">{{ t('edit.cancel') }}</button>
          <button type="submit" class="btn primary" :disabled="busy">{{ t('edit.save') }}</button>
        </div>
      </form>
      <p v-if="error && !form" class="error-text" role="alert">{{ error }}</p>
    </div>
  </div>
</template>
