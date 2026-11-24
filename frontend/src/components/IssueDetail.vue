<script setup lang="ts">
import { Lock, Paperclip } from 'lucide-vue-next';
import { computed, ref, watch } from 'vue';
import { ApiError, api, readConfig } from '../api/client';
import AttachmentPicker from './AttachmentPicker.vue';
import EditableField from './EditableField.vue';
import RichText from './RichText.vue';
import Avatar from './ui/Avatar.vue';
import PriorityIcon from './ui/PriorityIcon.vue';
import StatusBadge from './ui/StatusBadge.vue';
import { locale, t } from '../i18n';
import { hasContent } from '../lib/ckeditor';
import { toast } from '../lib/toast';
import type { CustomFieldForm, IssueDetail, IssueForm, IssueRow, Upload } from '../types';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'updated', row: IssueRow): void }>();
const config = readConfig();

const issue = ref<IssueDetail | null>(null);
const form = ref<IssueForm | null>(null);
const loading = ref(false);
const error = ref('');
const comment = ref('');
const privateNote = ref(false);
const sending = ref(false);
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
    if (mine === seq) await loadForm(mine, res.issue.permissions.edit);
  } catch (e) {
    if (mine === seq) error.value = (e as ApiError).status === 404 ? t('detail.not_found') : (e as Error).message;
  } finally { if (mine === seq) loading.value = false; }
}
// What the current user may edit, with the choices (workflow aware); only fetched when editing is allowed at all
async function loadForm(mine: number, allowed: boolean) {
  if (!allowed) { form.value = null; return; }
  try { const f = await api.issueForm(props.id); if (mine === seq) form.value = f; } catch { if (mine === seq) form.value = null; }
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
  if ((!hasContent(comment.value) && !uploads.value.length) || sending.value || picker.value?.busy) return;
  sending.value = true;
  const body: Record<string, unknown> = { notes: comment.value, private_notes: privateNote.value };
  if (uploads.value.length) body.uploads = uploads.value.map((u) => ({ token: u.token, filename: u.filename, content_type: u.content_type }));
  const ok = await patch(body);
  sending.value = false;
  if (ok) { comment.value = ''; privateNote.value = false; uploads.value = []; }
}

const fmt = (s: string) => new Date(s).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' });
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale) : '');
const size = (n: number) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const attUrl = (a: { id: number; filename: string }) => `${config.root}/attachments/download/${a.id}/${encodeURIComponent(a.filename)}`;
const can = (f: string) => !!form.value?.editable.includes(f);
const opts = (list: { id: number; name: string }[] = []) => list.map((o) => ({ value: String(o.id), label: o.name }));
const toId = (v: unknown) => (v === '' || v === null || v === undefined ? null : Number(v));
const doneOptions = Array.from({ length: 11 }, (_, i) => ({ value: String(i * 10), label: `${i * 10} %` }));
const cfLabel = (c: CustomFieldForm) => {
  const vals = Array.isArray(c.value) ? c.value : [c.value];
  const text = c.kind === 'select' ? vals.filter(Boolean).map((v) => c.options.find((o) => o.value === v)?.label ?? v).join(', ') : vals.join(', ');
  return text;
};
const editableCfIds = computed(() => new Set(form.value?.custom_fields.map((c) => c.id) ?? []));
const readOnlyCfs = computed(() => (issue.value?.custom_fields ?? []).filter((c) => !editableCfIds.value.has(c.id)));
const field = (name: string, v: unknown) => patch({ [name]: v });
const saveCf = (c: CustomFieldForm, v: unknown) => patch({ custom_field_values: { [c.id]: Array.isArray(v) && !v.length ? [''] : (v ?? '') } });
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
      <EditableField kind="text" :editable="can('subject')" :label="t('col.subject')" :model-value="issue.subject" @save="(v) => field('subject', v)">
        <h2>{{ issue.subject }} <Lock v-if="issue.is_private" :size="16" class="inline text-muted" aria-label="private" /></h2>
      </EditableField>

      <dl class="fields">
        <dt>{{ t('col.status') }}</dt>
        <dd><EditableField kind="select" :editable="canEdit && can('status_id')" :label="t('col.status')" :model-value="String(issue.status.id)"
                           :options="opts(form?.options.statuses ?? issue.allowed_statuses)" @save="(v) => field('status_id', toId(v))"><StatusBadge :status="issue.status" /></EditableField></dd>
        <dt>{{ t('col.priority') }}</dt>
        <dd><EditableField kind="select" :editable="canEdit && can('priority_id')" :label="t('col.priority')" :model-value="String(issue.priority.id)"
                           :options="opts(form?.options.priorities)" @save="(v) => field('priority_id', toId(v))"><PriorityIcon :priority="issue.priority" /></EditableField></dd>
        <dt>{{ t('col.assigned_to') }}</dt>
        <dd><EditableField kind="select" allow-empty :editable="canEdit && can('assigned_to_id')" :label="t('col.assigned_to')" :model-value="String(issue.assigned_to?.id ?? '')"
                           :options="opts(form?.options.assignees)" @save="(v) => field('assigned_to_id', toId(v))">
          <span v-if="issue.assigned_to" class="inline-flex items-center gap-2"><Avatar :name="issue.assigned_to.name" :size="20" />{{ issue.assigned_to.name }}</span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('col.start_date') }}</dt>
        <dd><EditableField kind="date" :editable="can('start_date')" :label="t('col.start_date')" :model-value="issue.start_date ?? ''" @save="(v) => field('start_date', v || null)">{{ fmtDate(issue.start_date) || '—' }}</EditableField></dd>
        <dt>{{ t('col.due_date') }}</dt>
        <dd><EditableField kind="date" :editable="can('due_date')" :label="t('col.due_date')" :model-value="issue.due_date ?? ''" @save="(v) => field('due_date', v || null)">{{ fmtDate(issue.due_date) || '—' }}</EditableField></dd>
        <dt>{{ t('col.done_ratio') }}</dt>
        <dd><EditableField kind="select" :editable="can('done_ratio')" :label="t('col.done_ratio')" :model-value="String(issue.done_ratio)" :options="doneOptions" @save="(v) => field('done_ratio', toId(v))"><progress :value="issue.done_ratio" max="100" /> {{ issue.done_ratio }}%</EditableField></dd>
        <template v-if="can('estimated_hours') || issue.estimated_hours"><dt>{{ t('detail.estimated') }}</dt>
          <dd><EditableField kind="number" step="0.25" :editable="can('estimated_hours')" :label="t('detail.estimated')" :model-value="String(issue.estimated_hours ?? '')" @save="(v) => field('estimated_hours', toId(v))">{{ issue.estimated_hours ? issue.estimated_hours + ' h' : '—' }}</EditableField></dd></template>
        <template v-if="can('category_id') || issue.category"><dt>{{ t('detail.category') }}</dt>
          <dd><EditableField kind="select" allow-empty :editable="can('category_id')" :label="t('detail.category')" :model-value="String(issue.category?.id ?? '')" :options="opts(form?.options.categories)" @save="(v) => field('category_id', toId(v))">{{ issue.category?.name ?? '—' }}</EditableField></dd></template>
        <template v-if="can('fixed_version_id') || issue.fixed_version"><dt>{{ t('detail.version') }}</dt>
          <dd><EditableField kind="select" allow-empty :editable="can('fixed_version_id')" :label="t('detail.version')" :model-value="String(issue.fixed_version?.id ?? '')" :options="opts(form?.options.versions)" @save="(v) => field('fixed_version_id', toId(v))">{{ issue.fixed_version?.name ?? '—' }}</EditableField></dd></template>
        <template v-for="c in form?.custom_fields ?? []" :key="c.id">
          <dt>{{ c.name }}</dt>
          <dd>
            <EditableField :kind="c.kind === 'select' ? (c.multiple ? 'multi' : 'select') : c.kind === 'text' ? 'textarea' : c.kind === 'int' || c.kind === 'float' ? 'number' : c.kind === 'date' ? 'date' : 'text'"
                           allow-empty editable :label="c.name" :step="c.kind === 'int' ? '1' : 'any'" :options="c.options" :model-value="c.value" @save="(v) => saveCf(c, v)">
              <span v-if="cfLabel(c)" class="cf-val">{{ cfLabel(c) }}</span><span v-else class="muted">—</span>
            </EditableField>
          </dd>
        </template>
        <template v-for="c in readOnlyCfs" :key="'ro' + c.id"><dt>{{ c.name }}</dt><dd>{{ c.value }}</dd></template>
        <template v-if="!form"><template v-for="c in issue.custom_fields" :key="'v' + c.id"><dt>{{ c.name }}</dt><dd>{{ c.value }}</dd></template></template>
        <dt>{{ t('detail.author') }}</dt><dd>{{ issue.author?.name }}</dd>
        <dt>{{ t('detail.created') }}</dt><dd>{{ fmt(issue.created_on) }}</dd>
        <template v-if="can('is_private')"><dt>{{ t('edit.private') }}</dt>
          <dd><EditableField kind="check" editable :label="t('edit.private')" :model-value="issue.is_private" @save="(v) => field('is_private', v)">{{ issue.is_private ? t('detail.private') : '—' }}</EditableField></dd></template>
      </dl>

      <h3>{{ t('detail.description') }}</h3>
      <EditableField kind="rich" :editable="can('description')" :label="t('detail.description')" :project="form?.project_id" :model-value="form?.values.description as string ?? ''" @save="(v) => field('description', v)">
        <!-- server-rendered by Redmine's own (sanitizing) text formatter -->
        <div v-if="issue.description_html" class="wiki" v-html="issue.description_html" />
        <p v-else class="muted">{{ canEdit ? t('detail.add_description') : t('detail.no_description') }}</p>
      </EditableField>

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
        <RichText v-model="comment" :project="issue.project.id" :rows="4" :height="140" :placeholder="t('detail.comment.placeholder')"
                  :label="t('detail.comment')" @submit="sendComment" />
        <AttachmentPicker ref="picker" v-model="uploads" />
        <div class="comment-actions">
          <label v-if="issue.permissions.private_notes" class="inline"><input v-model="privateNote" type="checkbox"> {{ t('detail.comment.private') }}</label>
          <span class="spacer" />
          <button class="btn primary" type="submit" :disabled="(!hasContent(comment) && !uploads.length) || sending">{{ t('detail.comment.send') }}</button>
        </div>
      </form>
    </div>
  </aside>
</template>
