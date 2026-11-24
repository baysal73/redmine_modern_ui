<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { Building2, Mail, Phone } from 'lucide-vue-next';
import { ApiError, api, readConfig } from '../api/client';
import { locale, t } from '../i18n';
import { hasContent } from '../lib/ckeditor';
import { toast } from '../lib/toast';
import { offerUndo } from '../lib/undo';
import type { ContactDetail, CustomFieldForm } from '../types';
import EditableField from './EditableField.vue';
import RichText from './RichText.vue';
import Avatar from './ui/Avatar.vue';

const props = defineProps<{ id: number }>();
const emit = defineEmits<{ (e: 'close'): void; (e: 'updated'): void }>();
const config = readConfig();

const c = ref<ContactDetail | null>(null);
const loading = ref(false);
const error = ref('');
const note = ref('');
const noteType = ref('');
const sending = ref(false);

let seq = 0;
async function load(spinner = true) {
  const mine = ++seq;
  if (spinner) { loading.value = true; c.value = null; }
  error.value = '';
  try { const r = await api.contact(props.id); if (mine === seq) c.value = r.contact; }
  catch (e) { if (mine === seq) error.value = (e as ApiError).status === 404 ? t('ct.not_found') : (e as Error).message; }
  finally { if (mine === seq) loading.value = false; }
}
watch(() => props.id, () => { note.value = ''; noteType.value = ''; load(); }, { immediate: true });

const str = (k: string) => String(c.value?.values[k] ?? '');
const fmt = (s: string) => new Date(s).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' });
const fmtDate = (s: string | null | undefined) => (s ? new Date(s).toLocaleDateString(locale) : '');
const link = (u: string) => (/^https?:\/\//i.test(u) ? u : `http://${u}`);

// Change a contact field; the old value is read back from the loaded contact so the change can be undone
async function patch(fields: Record<string, unknown>) {
  const cur = c.value; if (!cur) return;
  const undo: Record<string, unknown> = {};
  for (const k of Object.keys(fields)) {
    if (k === 'address') undo.address = Object.fromEntries(Object.keys(fields.address as object).map((f) => [f, cur.address[f] ?? '']));
    else if (k === 'custom_field_values') {
      const o: Record<string, unknown> = {};
      for (const id of Object.keys(fields[k] as object)) { const f = cur.custom_fields.find((x) => String(x.id) === id); const v = f?.value; o[id] = Array.isArray(v) && !v.length ? [''] : (v ?? ''); }
      undo[k] = o;
    } else undo[k] = k === 'tag_list' ? (cur.values.tag_list as string[]).join(', ') : cur.values[k] ?? '';
  }
  try {
    const r = await api.updateContact(props.id, fields);
    c.value = r.contact; emit('updated');
    offerUndo(t('edit.saved'), async () => { const b = await api.updateContact(props.id, undo); c.value = b.contact; emit('updated'); });
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); await load(false); }
}
const field = (k: string, v: unknown) => patch({ [k]: v });
const saveAddr = (k: string, v: unknown) => patch({ address: { [k]: v ?? '' } });
const saveCf = (f: CustomFieldForm, v: unknown) => patch({ custom_field_values: { [f.id]: Array.isArray(v) && !v.length ? [''] : (v ?? '') } });
const opts = (list: { id: number; name: string }[] = []) => list.map((o) => ({ value: String(o.id), label: o.name }));
const visOpts = computed(() => ['0', '1', '2'].map((v) => ({ value: v, label: t('ct.vis.' + v) })));

const noteTypes = ['', '0', '1', '2'];
async function sendNote() {
  if (!hasContent(note.value) || sending.value) return;
  sending.value = true;
  try { await api.addContactNote(props.id, { content: note.value, type_id: noteType.value }); note.value = ''; noteType.value = ''; toast(t('ct.note.saved')); await load(false); }
  catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { sending.value = false; }
}
const classic = computed(() => `${config.root}/contacts/${props.id}`);
const cfKind = (f: CustomFieldForm) => (f.kind === 'select' ? (f.multiple ? 'multi' : 'select') : f.kind === 'text' ? 'textarea' : f.kind === 'int' || f.kind === 'float' ? 'number' : f.kind === 'date' ? 'date' : 'text');
const cfText = (f: CustomFieldForm) => { const v = Array.isArray(f.value) ? f.value : [f.value]; return v.filter(Boolean).join(', '); };
const ed = computed(() => !!c.value?.editable);
</script>

<template>
  <aside class="detail" aria-label="Contact">
    <header class="detail-head">
      <button class="icon-btn" :aria-label="t('detail.close')" :title="t('detail.close') + ' (Esc)'" @click="emit('close')">✕</button>
      <span class="muted">#{{ id }}</span>
      <span class="spacer" />
      <a :href="classic" class="muted small">{{ t('detail.classic') }}</a>
    </header>
    <p v-if="loading" class="muted pad">{{ t('detail.loading') }}</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>

    <div v-else-if="c" class="detail-body">
      <div class="ct-title">
        <img v-if="c.avatar_url" :src="c.avatar_url" alt="" class="ct-avatar">
        <Building2 v-else-if="c.is_company" :size="36" class="text-muted" aria-hidden="true" />
        <Avatar v-else :name="c.name" :size="40" />
        <div>
          <h2>{{ c.name }}</h2>
          <p class="muted small">{{ c.is_company ? t('ct.kind.company') : t('ct.kind.person') }}<template v-if="c.projects.length"> · {{ c.projects.map((p) => p.name).join(', ') }}</template></p>
        </div>
      </div>
      <p v-if="c.company_contact" class="small"><Building2 :size="13" class="inline" /> <a href="#" @click.prevent="$router.push('/contacts/' + c.company_contact.id)">{{ c.company_contact.name }}</a></p>

      <dl class="fields">
        <dt>{{ c.is_company ? t('ct.company_name') : t('ct.first_name') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.first_name')" :model-value="str('first_name')" @save="(v) => field('first_name', v)">{{ str('first_name') || '—' }}</EditableField></dd>
        <template v-if="!c.is_company">
          <dt>{{ t('ct.last_name') }}</dt>
          <dd><EditableField kind="text" :editable="ed" :label="t('ct.last_name')" :model-value="str('last_name')" allow-empty @save="(v) => field('last_name', v)">{{ str('last_name') || '—' }}</EditableField></dd>
          <dt>{{ t('ct.company') }}</dt>
          <dd><EditableField kind="text" :editable="ed" :label="t('ct.company')" :model-value="str('company')" allow-empty @save="(v) => field('company', v)">{{ str('company') || '—' }}</EditableField></dd>
          <dt>{{ t('ct.job_title') }}</dt>
          <dd><EditableField kind="text" :editable="ed" :label="t('ct.job_title')" :model-value="str('job_title')" allow-empty @save="(v) => field('job_title', v)">{{ str('job_title') || '—' }}</EditableField></dd>
        </template>
        <dt>{{ t('ct.email') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.email')" :model-value="str('email')" allow-empty @save="(v) => field('email', v)">
          <span v-if="str('email')"><Mail :size="13" class="inline text-muted" /> <template v-for="(m, i) in str('email').split(/, */)" :key="m"><a :href="'mailto:' + m">{{ m }}</a><template v-if="i < str('email').split(/, */).length - 1">, </template></template></span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('ct.phone') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.phone')" :model-value="str('phone')" allow-empty @save="(v) => field('phone', v)">
          <span v-if="str('phone')"><Phone :size="13" class="inline text-muted" /> <template v-for="(p, i) in str('phone').split(/, */)" :key="p"><a :href="'tel:' + p.replace(/\s/g, '')">{{ p }}</a><template v-if="i < str('phone').split(/, */).length - 1">, </template></template></span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('ct.website') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.website')" :model-value="str('website')" allow-empty @save="(v) => field('website', v)">
          <a v-if="str('website')" :href="link(str('website'))" target="_blank" rel="noopener noreferrer">{{ str('website') }}</a><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('ct.street') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.street')" :model-value="c.address.street1" allow-empty @save="(v) => saveAddr('street1', v)">{{ c.address.street1 || '—' }}</EditableField></dd>
        <dt>{{ t('ct.postcode') }} / {{ t('ct.city') }}</dt>
        <dd class="flex gap-2">
          <EditableField kind="text" :editable="ed" :label="t('ct.postcode')" :model-value="c.address.postcode" allow-empty @save="(v) => saveAddr('postcode', v)">{{ c.address.postcode || '—' }}</EditableField>
          <EditableField kind="text" :editable="ed" :label="t('ct.city')" :model-value="c.address.city" allow-empty @save="(v) => saveAddr('city', v)">{{ c.address.city || '—' }}</EditableField>
        </dd>
        <dt>{{ t('ct.country') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.country')" :model-value="c.address.country_code" allow-empty @save="(v) => saveAddr('country_code', String(v).toUpperCase().slice(0, 2))">{{ c.address.country_code || '—' }}</EditableField></dd>
        <template v-if="!c.is_company">
          <dt>{{ t('ct.birthday') }}</dt>
          <dd><EditableField kind="date" :editable="ed" :label="t('ct.birthday')" :model-value="str('birthday')" allow-empty @save="(v) => field('birthday', v || null)">{{ fmtDate(str('birthday')) || '—' }}</EditableField></dd>
        </template>
        <dt>{{ t('col.assigned_to') }}</dt>
        <dd><EditableField kind="select" allow-empty :editable="ed" :label="t('col.assigned_to')" :model-value="String(c.values.assigned_to_id ?? '')" :options="opts(c.assignees)" @save="(v) => field('assigned_to_id', v === '' ? null : Number(v))">
          <span v-if="c.assigned_to" class="inline-flex items-center gap-2"><Avatar :name="c.assigned_to.name" :size="20" />{{ c.assigned_to.name }}</span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('ct.tags') }}</dt>
        <dd><EditableField kind="text" :editable="ed" :label="t('ct.tags')" :model-value="(c.values.tag_list as string[]).join(', ')" allow-empty @save="(v) => field('tag_list', v)">
          <span v-if="(c.values.tag_list as string[]).length" class="tags"><span v-for="g in (c.values.tag_list as string[])" :key="g" class="tag">{{ g }}</span></span><span v-else class="muted">—</span></EditableField></dd>
        <dt>{{ t('ct.visibility') }}</dt>
        <dd><EditableField kind="select" :editable="ed" :label="t('ct.visibility')" :model-value="String(c.values.visibility)" :options="visOpts" @save="(v) => field('visibility', Number(v))">{{ t('ct.vis.' + c.values.visibility) }}</EditableField></dd>
        <template v-for="f in c.custom_fields" :key="f.id">
          <dt>{{ f.name }}</dt>
          <dd><EditableField :kind="cfKind(f)" allow-empty :editable="ed" :label="f.name" :step="f.kind === 'int' ? '1' : 'any'" :options="f.options" :model-value="f.value" @save="(v) => saveCf(f, v)">
            <template v-if="cfText(f)"><a v-if="f.kind === 'link'" :href="link(cfText(f))" target="_blank" rel="noopener noreferrer">{{ cfText(f) }}</a><span v-else>{{ f.kind === 'select' ? cfText(f) : cfText(f) }}</span></template><span v-else class="muted">—</span>
          </EditableField></dd>
        </template>
        <dt>{{ t('detail.created') }}</dt><dd>{{ fmt(c.created_on) }}<template v-if="c.author"> · {{ c.author.name }}</template></dd>
      </dl>

      <template v-if="c.employees.length">
        <h3>{{ t('ct.employees') }}</h3>
        <ul class="ct-list"><li v-for="e in c.employees" :key="e.id"><a href="#" @click.prevent="$router.push('/contacts/' + e.id)">{{ e.name }}</a> <span class="muted small">{{ e.job_title }}</span></li></ul>
      </template>
      <template v-if="c.deals.length">
        <h3>{{ t('ct.deals') }}</h3>
        <ul class="ct-list"><li v-for="d in c.deals" :key="d.id"><a :href="`${config.root}/deals/${d.id}`">{{ d.name }}</a> <span class="muted small">{{ d.status }}<template v-if="d.price"> · {{ d.price }} {{ d.currency }}</template></span></li></ul>
      </template>
      <template v-if="c.issues.length">
        <h3>{{ t('ct.issues') }}</h3>
        <ul class="ct-list"><li v-for="i in c.issues" :key="i.id"><a href="#" @click.prevent="$router.push('/issues/' + i.id)">#{{ i.id }} {{ i.subject }}</a> <span class="muted small">{{ i.status.name }} · {{ i.project }}</span></li></ul>
      </template>

      <h3>{{ t('ct.notes') }}</h3>
      <form v-if="c.can_add_note" class="comment-form" @submit.prevent="sendNote">
        <RichText v-model="note" :project="c.project_id" :rows="3" :height="120" :placeholder="t('ct.note.placeholder')" :label="t('ct.notes')" @submit="sendNote" />
        <div class="comment-actions">
          <select v-model="noteType" :aria-label="t('ct.note.type')"><option v-for="n in noteTypes" :key="n" :value="n">{{ t('ct.note.type.' + (n || 'none')) }}</option></select>
          <span class="spacer" />
          <button class="btn primary" type="submit" :disabled="!hasContent(note) || sending">{{ t('detail.comment.send') }}</button>
        </div>
      </form>
      <p v-if="!c.notes.length" class="muted">{{ t('ct.note.none') }}</p>
      <ol class="journal">
        <li v-for="n in c.notes" :key="n.id">
          <div class="j-head"><Avatar v-if="n.author" :name="n.author.name" :size="20" /><strong>{{ n.author?.name }}</strong> <span class="muted small">{{ fmt(n.created_on) }}</span>
            <span v-if="n.type_id !== null" class="pill">{{ t('ct.note.type.' + n.type_id) }}</span></div>
          <p v-if="n.subject" class="small"><strong>{{ n.subject }}</strong></p>
          <div class="wiki" v-html="n.content_html" />
        </li>
      </ol>
    </div>
  </aside>
</template>

<style>
.ct-title { display: flex; gap: 12px; align-items: center; margin-bottom: 8px; }
.ct-title h2 { margin: 0; }
.ct-avatar { width: 40px; height: 40px; border-radius: 50%; object-fit: cover; }
.ct-list { margin: 0; padding-left: 18px; display: grid; gap: 3px; }
.tags { display: inline-flex; flex-wrap: wrap; gap: 4px; }
.tag { background: var(--hover); border-radius: 999px; padding: 1px 9px; font-size: 0.85em; }
</style>
