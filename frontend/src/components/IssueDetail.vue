<script setup lang="ts">
import { Lock, Paperclip } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import AttachmentPicker from './AttachmentPicker.vue';
import InlineCell from './InlineCell.vue';
import IssueEditDialog from './IssueEditDialog.vue';
import Avatar from './ui/Avatar.vue';
import PriorityIcon from './ui/PriorityIcon.vue';
import StatusBadge from './ui/StatusBadge.vue';
import { locale, t } from '../i18n';
import { toast } from '../lib/toast';
import type { IssueDetail, IssueRow, Upload } from '../types';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'updated', row: IssueRow): void }>();
const config = readConfig();

const issue = ref<IssueDetail | null>(null);
const loading = ref(false);
const error = ref('');
const comment = ref('');
const privateNote = ref(false);
const sending = ref(false);
const editing = ref(false);
const uploads = ref<Upload[]>([]);
const picker = ref<InstanceType<typeof AttachmentPicker> | null>(null);

let seq = 0;
async function load(showSpinner = true) {
  const mine = ++seq;
  if (showSpinner) { loading.value = true; issue.value = null; }
  error.value = '';
  try {
    const res = await api.issue(props.id);
    if (mine === seq) issue.value = res.issue;
  } catch (e) {
    if (mine === seq) error.value = (e as ApiError).status === 404 ? t('detail.not_found') : (e as Error).message;
  } finally { if (mine === seq) loading.value = false; }
}
watch(() => props.id, () => { comment.value = ''; uploads.value = []; privateNote.value = false; load(); }, { immediate: true });

async function patch(fields: Record<string, unknown>, okMessage = true) {
  try {
    const res = await api.updateIssue(props.id, fields);
    emit('updated', res.issue);
    await load(false);
    if (okMessage) toast(t('edit.saved'));
    return true;
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); return false; }
}
async function sendComment() {
  if ((!comment.value.trim() && !uploads.value.length) || sending.value || picker.value?.busy) return;
  sending.value = true;
  const body: Record<string, unknown> = { notes: comment.value, private_notes: privateNote.value };
  if (uploads.value.length) body.uploads = uploads.value.map((u) => ({ token: u.token, filename: u.filename, content_type: u.content_type }));
  const ok = await patch(body);
  sending.value = false;
  if (ok) { comment.value = ''; privateNote.value = false; uploads.value = []; }
}

// Workflow-aware option lists for the inline fields
const loadStatuses = async () => issue.value!.allowed_statuses;
async function loadOpt(what: 'assignees' | 'priorities') {
  const o = await api.issueOptions(props.id);
  return what === 'assignees' ? o.assignees : o.priorities;
}
const fmt = (s: string) => new Date(s).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' });
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '');
const size = (n: number) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const attUrl = (a: { id: number; filename: string }) => `${config.root}/attachments/download/${a.id}/${encodeURIComponent(a.filename)}`;
const classic = computed(() => `${config.root}/issues/${props.id}`);
const canEdit = computed(() => !!issue.value?.permissions.edit);
</script>

<template>
  <aside class="detail" aria-label="Issue">
    <header class="detail-head">
      <button class="icon-btn" :aria-label="t('detail.close')" :title="t('detail.close') + ' (Esc)'" @click="emit('close')">✕</button>
      <span class="muted">#{{ id }}</span>
      <span class="spacer" />
      <a :href="classic" class="muted small">{{ t('detail.classic') }}</a>
    </header>

    <p v-if="loading" class="muted pad">{{ t('detail.loading') }}</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>

    <div v-else-if="issue" class="detail-body">
      <p class="muted small">{{ issue.tracker.name }} · {{ issue.project.name }}</p>
      <h2>{{ issue.subject }} <Lock v-if="issue.is_private" :size="16" class="inline text-muted" aria-label="private" /></h2>

      <dl class="fields">
        <dt>{{ t('col.status') }}</dt>
        <dd><InlineCell kind="select" :editable="canEdit" :label="issue.status.name" :value="issue.status.id"
                        :load-options="loadStatuses" @save="(v) => patch({ status_id: v })"><StatusBadge :status="issue.status" /></InlineCell></dd>
        <dt>{{ t('col.priority') }}</dt>
        <dd><InlineCell kind="select" :editable="canEdit" :label="issue.priority.name" :value="issue.priority.id"
                        :load-options="() => loadOpt('priorities')" @save="(v) => patch({ priority_id: v })"><PriorityIcon :priority="issue.priority" /></InlineCell></dd>
        <dt>{{ t('col.assigned_to') }}</dt>
        <dd><InlineCell kind="select" :editable="canEdit" allow-empty :label="issue.assigned_to?.name ?? ''" :value="issue.assigned_to?.id ?? null"
                        :load-options="() => loadOpt('assignees')" @save="(v) => patch({ assigned_to_id: v })">
          <span v-if="issue.assigned_to" class="inline-flex items-center gap-2"><Avatar :name="issue.assigned_to.name" :size="20" />{{ issue.assigned_to.name }}</span><span v-else class="muted">—</span></InlineCell></dd>
        <dt>{{ t('col.due_date') }}</dt>
        <dd><InlineCell kind="date" :editable="canEdit" :label="fmtDate(issue.due_date)" :value="issue.due_date" @save="(v) => patch({ due_date: v })" /></dd>
        <dt>{{ t('col.start_date') }}</dt><dd>{{ fmtDate(issue.start_date) || '—' }}</dd>
        <dt>{{ t('col.done_ratio') }}</dt><dd><progress :value="issue.done_ratio" max="100" /> {{ issue.done_ratio }}%</dd>
        <dt>{{ t('detail.author') }}</dt><dd>{{ issue.author?.name }}</dd>
        <dt>{{ t('detail.created') }}</dt><dd>{{ fmt(issue.created_on) }}</dd>
        <template v-if="issue.fixed_version"><dt>{{ t('detail.version') }}</dt><dd>{{ issue.fixed_version.name }}</dd></template>
        <template v-if="issue.category"><dt>{{ t('detail.category') }}</dt><dd>{{ issue.category.name }}</dd></template>
        <template v-if="issue.estimated_hours"><dt>{{ t('detail.estimated') }}</dt><dd>{{ issue.estimated_hours }} h</dd></template>
        <template v-for="cf in issue.custom_fields" :key="cf.id"><dt>{{ cf.name }}</dt><dd>{{ cf.value }}</dd></template>
      </dl>
      <p v-if="canEdit" class="small"><button class="btn" @click="editing = true">✎ {{ t('edit.all') }}</button></p>

      <h3>{{ t('detail.description') }}</h3>
      <!-- server-rendered by Redmine's own (sanitizing) text formatter -->
      <div v-if="issue.description_html" class="wiki" v-html="issue.description_html" />
      <p v-else class="muted">{{ t('detail.no_description') }}</p>

      <template v-if="issue.attachments.length">
        <h3>{{ t('detail.attachments') }}</h3>
        <ul class="attachments">
          <li v-for="a in issue.attachments" :key="a.id" class="flex items-center gap-2"><Paperclip :size="14" class="text-muted" /> <a :href="attUrl(a)">{{ a.filename }}</a> <span class="muted small">{{ size(a.filesize) }} · {{ a.author?.name }}</span></li>
        </ul>
      </template>

      <h3>{{ t('detail.history') }}</h3>
      <p v-if="!issue.journals.length" class="muted">{{ t('detail.no_history') }}</p>
      <ol class="journal">
        <li v-for="j in issue.journals" :key="j.id" :class="{ private: j.private_notes }">
          <div class="j-head"><Avatar v-if="j.user" :name="j.user.name" :size="20" /><strong>{{ j.user?.name }}</strong> <span class="muted small">{{ fmt(j.created_on) }}</span>
            <span v-if="j.private_notes" class="pill pill-closed">{{ t('detail.private') }}</span></div>
          <ul v-if="j.details.length" class="j-details"><li v-for="(d, i) in j.details" :key="i">{{ d.text }}</li></ul>
          <div v-if="j.notes_html" class="wiki" v-html="j.notes_html" />
        </li>
      </ol>

      <form v-if="issue.permissions.comment" class="comment-form" @submit.prevent="sendComment">
        <label for="mui-comment"><strong>{{ t('detail.comment') }}</strong></label>
        <textarea id="mui-comment" v-model="comment" rows="4" :placeholder="t('detail.comment.placeholder')"
                  @keydown.ctrl.enter.prevent="sendComment" @keydown.meta.enter.prevent="sendComment" />
        <AttachmentPicker ref="picker" v-model="uploads" />
        <div class="comment-actions">
          <label v-if="issue.permissions.private_notes" class="inline"><input v-model="privateNote" type="checkbox"> {{ t('detail.comment.private') }}</label>
          <span class="spacer" />
          <button class="btn primary" type="submit" :disabled="(!comment.trim() && !uploads.length) || sending">{{ t('detail.comment.send') }}</button>
        </div>
      </form>
    </div>
    <IssueEditDialog v-if="editing" :id="id" @close="editing = false" @saved="(row) => { editing = false; emit('updated', row); load(false); }" />
  </aside>
</template>
