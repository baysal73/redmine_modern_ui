<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api, readConfig } from '../api/client';
import AttachmentPicker from './AttachmentPicker.vue';
import { loadMeta, store } from '../lib/store';
import { t } from '../i18n';
import { trapFocus } from '../lib/dialog';
import { toast } from '../lib/toast';
import { ui } from '../lib/ui';
import type { NewIssueOptions, Upload } from '../types';

const route = useRoute();
const router = useRouter();
const config = readConfig();
const root = ref<HTMLElement | null>(null);
const meta = computed(() => store.meta);
const opts = ref<NewIssueOptions | null>(null);
const projectId = ref<number | ''>('');
const trackerId = ref<number | ''>('');
const subject = ref('');
const assignee = ref<number | ''>('');
const description = ref('');
const priorityId = ref<number | ''>('');
const dueDate = ref('');
const more = ref(false);
const uploads = ref<Upload[]>([]);
const picker = ref<InstanceType<typeof AttachmentPicker> | null>(null);
const busy = ref(false);
const error = ref('');
const classicUrl = ref('');
let release: (() => void) | null = null;

const projects = computed(() => (meta.value?.projects ?? []).filter((p) => meta.value!.addable_project_ids.includes(p.id)));
const noProjects = computed(() => !!meta.value && projects.value.length === 0);

function lastProject(): number | '' {
  const stored = Number((() => { try { return localStorage.getItem('modern_ui_last_project'); } catch { return null; } })());
  const fromFilter = (meta.value?.projects ?? []).find((p) => p.identifier === route.query.project)?.id;
  const wanted = fromFilter ?? stored;
  return projects.value.some((p) => p.id === wanted) ? (wanted as number) : (projects.value[0]?.id ?? '');
}
async function loadOptions() {
  opts.value = null; error.value = '';
  if (!projectId.value) return;
  try {
    opts.value = await api.newIssueOptions(projectId.value);
    if (!opts.value.trackers.some((x) => x.id === trackerId.value)) trackerId.value = opts.value.trackers[0]?.id ?? '';
    if (!opts.value.assignees.some((x) => x.id === assignee.value)) assignee.value = '';
    priorityId.value = opts.value.priorities.find((p) => p.is_default)?.id ?? '';
  } catch (e) { error.value = (e as Error).message; }
}
watch(projectId, loadOptions);

async function submit() {
  if (!subject.value.trim() || !projectId.value || busy.value || picker.value?.busy) return;
  busy.value = true; error.value = ''; classicUrl.value = '';
  try {
    const res = await api.createIssue({
      project_id: projectId.value, tracker_id: trackerId.value, subject: subject.value.trim(),
      assigned_to_id: assignee.value || null, description: description.value || null,
      priority_id: priorityId.value || null, due_date: dueDate.value || null,
      uploads: uploads.value.map((u) => ({ token: u.token, filename: u.filename, content_type: u.content_type })),
    });
    try { localStorage.setItem('modern_ui_last_project', String(projectId.value)); } catch { /* ignore */ }
    toast(t('create.created', { id: res.issue.id }));
    ui.quickCreate = false; ui.refresh++;
    router.push({ name: 'issues', params: { id: res.issue.id }, query: route.query });
  } catch (e) {
    error.value = (e as Error).message;
    classicUrl.value = (e as ApiError).data?.classic_url ?? '';
  } finally { busy.value = false; }
}
const close = () => { ui.quickCreate = false; };

onMounted(async () => {
  try { await loadMeta(); } catch (e) { error.value = (e as Error).message; return; }
  projectId.value = lastProject();
  release = trapFocus(root.value!, close);
});
onUnmounted(() => release?.());
void config;
</script>

<template>
  <div class="overlay" @mousedown.self="close">
    <div ref="root" class="dialog" role="dialog" aria-modal="true" aria-labelledby="qc-title">
      <h2 id="qc-title">{{ t('create.title') }}</h2>
      <p v-if="noProjects" class="muted">{{ t('create.no_projects') }}</p>
      <form v-else @submit.prevent="submit">
        <label>{{ t('col.project') }}
          <select v-model="projectId"><option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option></select>
        </label>
        <div class="row2">
          <label>{{ t('col.tracker') }}
            <select v-model="trackerId"><option v-for="x in opts?.trackers" :key="x.id" :value="x.id">{{ x.name }}</option></select>
          </label>
          <label>{{ t('col.assigned_to') }}
            <select v-model="assignee"><option value="">{{ t('unassigned') }}</option><option v-for="u in opts?.assignees" :key="u.id" :value="u.id">{{ u.name }}</option></select>
          </label>
        </div>
        <label>{{ t('col.subject') }}
          <input v-model="subject" type="text" required maxlength="255" autocomplete="off" :placeholder="t('create.subject_ph')">
        </label>
        <button type="button" class="link-btn" :aria-expanded="more" @click="more = !more">{{ more ? '▾' : '▸' }} {{ t('create.more') }}</button>
        <template v-if="more">
          <label>{{ t('detail.description') }}<textarea v-model="description" rows="4" /></label>
          <AttachmentPicker ref="picker" v-model="uploads" />
          <div class="row2">
            <label>{{ t('col.priority') }}
              <select v-model="priorityId"><option v-for="p in opts?.priorities" :key="p.id" :value="p.id">{{ p.name }}</option></select>
            </label>
            <label>{{ t('col.due_date') }}<input v-model="dueDate" type="date"></label>
          </div>
        </template>
        <p v-if="error" class="error-text" role="alert">{{ error }}
          <a v-if="classicUrl" :href="classicUrl">{{ t('create.classic') }}</a></p>
        <div class="dialog-actions">
          <button type="button" class="btn" @click="close">{{ t('create.cancel') }}</button>
          <button type="submit" class="btn primary" :disabled="busy || !subject.trim()">{{ t('create.submit') }}</button>
        </div>
      </form>
    </div>
  </div>
</template>
