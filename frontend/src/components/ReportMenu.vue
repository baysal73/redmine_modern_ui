<script setup lang="ts">
// Reports come from the Redmine Reporter plugin: we only list the templates the user may use and open the plugin's own
// preview/download page, so templates, prompts, e-mail sending and permissions stay exactly as in the classic UI.
import { ref } from 'vue';
import { ChevronDown, FileText } from 'lucide-vue-next';
import { api, readConfig } from '../api/client';
import { t } from '../i18n';
import type { ReportTemplates } from '../types';

const props = defineProps<{ issueIds: number[]; projectId?: string; single?: boolean; compact?: boolean }>();
const config = readConfig();
const open = ref(false);
const data = ref<ReportTemplates | null>(null);
const loading = ref(false);
let loadedFor = '';

async function toggle() {
  open.value = !open.value;
  const key = `${props.single ? props.issueIds[0] : ''}|${props.projectId ?? ''}`;
  if (open.value && loadedFor !== key) {
    loading.value = true;
    try { data.value = await api.reportTemplates(props.single ? { issue_id: props.issueIds[0] } : { project_id: props.projectId }); loadedFor = key; }
    catch { data.value = { available: false, can_preview: false, can_generate: false, templates: [] }; }
    finally { loading.value = false; }
  }
}
function url(id: number): string {
  const q = new URLSearchParams();
  props.issueIds.forEach((i) => q.append('issue_ids[]', String(i)));
  q.append('report_template[ids][]', String(id));
  return `${config.root}/issues_report_templates/${data.value?.can_preview ? 'preview' : 'create'}?${q}`;
}
function close(e: MouseEvent) { if (!(e.target as HTMLElement).closest('.report-wrap')) open.value = false; }
document.addEventListener('click', close);
import { onUnmounted } from 'vue';
onUnmounted(() => document.removeEventListener('click', close));
</script>

<template>
  <div class="report-wrap col-menu-wrap">
    <button v-if="!compact" class="btn tb-btn" aria-haspopup="true" :aria-expanded="open" :title="t('report.hint')" @click.stop="toggle">
      <FileText :size="14" /> {{ t('report.title') }} <ChevronDown :size="13" />
    </button>
    <button v-else class="muted small pdf-link link-like" aria-haspopup="true" :aria-expanded="open" :title="t('report.hint')" @click.stop="toggle">
      <FileText :size="13" /> {{ t('report.title') }}
    </button>
    <div v-if="open" class="col-menu report-menu" role="menu" @click.stop>
      <p v-if="loading" class="muted small px-2 py-1">…</p>
      <p v-else-if="!data?.available" class="muted small px-2 py-1">{{ t('report.unavailable') }}</p>
      <p v-else-if="!data.templates.length" class="muted small px-2 py-1">{{ t('report.none') }}</p>
      <template v-else>
        <p v-if="issueIds.length > 1" class="muted small px-2 py-1">{{ t('report.for_n', { n: issueIds.length }) }}</p>
        <a v-for="tpl in data.templates" :key="tpl.id" class="report-item" role="menuitem" :href="url(tpl.id)" target="_blank" rel="noopener" :title="tpl.description">{{ tpl.name }}</a>
      </template>
    </div>
  </div>
</template>
