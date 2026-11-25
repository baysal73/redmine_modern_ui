<script setup lang="ts">
import { ChevronRight, Download, File as FileIcon, FileText, Folder, FolderPlus, Lock, Pencil, Search, Trash2, Upload, X } from 'lucide-vue-next';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ApiError, api, readConfig } from '../api/client';
import { t } from '../i18n';
import { store } from '../lib/store';
import { toast } from '../lib/toast';
import { offerUndo } from '../lib/undo';
import type { DocFileDetail, DocFolder, DocList } from '../types';

const route = useRoute();
const router = useRouter();
const config = readConfig();
const locale = (config.lang || 'en').toLowerCase();
const projects = ref<{ id: number; identifier: string; name: string }[]>([]);
const data = ref<DocList | null>(null);
const loading = ref(false);
const error = ref('');
const filter = ref('');
const dragging = ref(false);
const busyText = ref('');
const picker = ref<HTMLInputElement | null>(null);
const detail = ref<DocFileDetail | null>(null);
const dialog = ref<{ mode: 'new' | 'rename'; id?: number; title: string } | null>(null);
const LAST = 'mui-docs-project';

const projectId = computed(() => String(route.query.project ?? ''));
const folderId = computed(() => (route.query.folder ? Number(route.query.folder) : null));
const size = (n: number) => (n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale, { day: 'numeric', month: 'short', year: '2-digit' }) : '');
const fmtDateTime = (s: string | null) => (s ? new Date(s).toLocaleString(locale, { dateStyle: 'short', timeStyle: 'short' }) : '');

const files = computed(() => {
  const q = filter.value.trim().toLowerCase();
  return (data.value?.files ?? []).filter((f) => !q || f.name.toLowerCase().includes(q) || f.title.toLowerCase().includes(q));
});
const folders = computed(() => {
  const q = filter.value.trim().toLowerCase();
  return (data.value?.folders ?? []).filter((f) => !q || f.title.toLowerCase().includes(q));
});

function go(project: string | number, folder?: number | null) {
  const query: Record<string, string> = { project: String(project) };
  if (folder) query.folder = String(folder);
  router.push({ path: '/documents', query });
}

let seq = 0;
async function load() {
  if (!projectId.value) return;
  const mine = ++seq; loading.value = true; error.value = '';
  try {
    const r = await api.documents(projectId.value, folderId.value ?? undefined);
    if (mine === seq) data.value = r;
  } catch (e) { if (mine === seq) { error.value = (e as ApiError).message; data.value = null; } }
  finally { if (mine === seq) loading.value = false; }
}

onMounted(async () => {
  try { projects.value = (await api.documentProjects()).projects; } catch (e) { error.value = (e as ApiError).message; return; }
  if (!projectId.value && projects.value.length) {
    let last = ''; try { last = localStorage.getItem(LAST) ?? ''; } catch { /* storage unavailable */ }
    const pick = projects.value.find((p) => String(p.id) === last) ?? projects.value[0];
    router.replace({ path: '/documents', query: { project: String(pick.id) } });
  }
});
watch(() => [route.query.project, route.query.folder], () => {
  filter.value = ''; detail.value = null;
  if (projectId.value) { try { localStorage.setItem(LAST, projectId.value); } catch { /* storage unavailable */ } }
  load();
}, { immediate: true });

async function sendFiles(list: File[]) {
  if (!list.length || !data.value?.can.upload) return;
  const max = store.meta?.settings.attachment_max_size ?? 0;
  const tokens: string[] = [];
  let done = 0;
  for (const f of list) {
    busyText.value = t('doc.uploading', { done, total: list.length });
    if (max && f.size > max) { toast(t('attach.too_big', { name: f.name, max: size(max) }), 'error'); continue; }
    try { tokens.push((await api.upload(f)).token); } catch (e) { toast(t('edit.failed', { message: `${f.name}: ${(e as Error).message}` }), 'error'); }
    done += 1;
  }
  try {
    if (tokens.length) {
      const r = await api.uploadDocuments(projectId.value, folderId.value, tokens);
      if (r.done) toast(t('doc.uploaded', { n: r.done }));
      if (r.failed.length) toast(t('doc.upload_failed', { reason: `${r.failed[0].name}: ${r.failed[0].error}` }), 'error');
    }
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
  finally { busyText.value = ''; await load(); }
}
function onPick(e: Event) {
  const el = e.target as HTMLInputElement;
  sendFiles([...(el.files ?? [])]);
  el.value = '';
}
function onDrop(e: DragEvent) {
  dragging.value = false;
  if (e.dataTransfer?.files?.length) sendFiles([...e.dataTransfer.files]);
}

async function openFile(id: number) {
  try { detail.value = (await api.documentFile(id)).file; } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
async function removeFile(id: number, name: string) {
  try {
    await api.deleteDocument(id);
    detail.value = null;
    offerUndo(t('doc.deleted', { name }), async () => { await api.restoreDocument(id); await load(); });
    await load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
async function removeFolder(f: DocFolder) {
  try {
    await api.deleteFolder(f.id);
    offerUndo(t('doc.deleted', { name: f.title }), async () => { await api.restoreFolder(f.id); await load(); });
    await load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
async function saveDialog() {
  const d = dialog.value;
  if (!d || !d.title.trim()) return;
  try {
    if (d.mode === 'new') { const r = await api.createFolder(projectId.value, folderId.value, d.title.trim()); toast(t('doc.created', { name: r.folder.title })); }
    else if (d.id) await api.renameFolder(d.id, d.title.trim());
    dialog.value = null;
    await load();
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
</script>

<template>
  <section class="list-view docs">
    <div class="page-head"><h1>{{ t('nav.documents') }}</h1>
      <span v-if="data" class="muted">{{ t('doc.items', { files: data.files.length, folders: data.folders.length }) }}</span>
    </div>

    <p v-if="!projects.length && !error && !loading" class="muted empty">{{ t('doc.no_projects') }}</p>

    <div v-if="projects.length" class="list-toolbar">
      <div class="fbar" role="search">
        <select class="tb-select-plain" :value="projectId" :aria-label="t('doc.project')" @change="go(($event.target as HTMLSelectElement).value)">
          <option v-for="p in projects" :key="p.id" :value="String(p.id)">{{ p.name }}</option>
        </select>
        <label class="fsearch"><Search :size="15" class="text-muted" aria-hidden="true" />
          <input v-model="filter" type="search" :placeholder="t('doc.search')" :aria-label="t('doc.search')">
        </label>
        <span class="spacer" />
        <button v-if="data?.can.folder" class="btn" @click="dialog = { mode: 'new', title: '' }"><FolderPlus :size="15" aria-hidden="true" /> {{ t('doc.new_folder') }}</button>
        <button v-if="data?.can.upload" class="btn primary" :disabled="!!busyText" @click="picker?.click()"><Upload :size="15" aria-hidden="true" /> {{ busyText || t('doc.upload') }}</button>
        <input ref="picker" type="file" multiple hidden @change="onPick">
      </div>
    </div>

    <nav v-if="data" class="doc-crumbs" :aria-label="t('doc.name')">
      <button class="link-btn" @click="go(projectId)">{{ data.project.name }}</button>
      <template v-for="p in data.path" :key="p.id"><ChevronRight :size="14" class="text-muted" aria-hidden="true" /><button class="link-btn" @click="go(projectId, p.id)">{{ p.title }}</button></template>
    </nav>

    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>

    <div class="table-wrap doc-drop" :class="{ busy: loading, dragging }"
         @dragover.prevent="data?.can.upload && (dragging = true)" @dragleave.prevent="dragging = false" @drop.prevent="onDrop">
      <table v-if="data" class="m-docs">
        <thead><tr>
          <th>{{ t('doc.name') }}</th><th class="num">{{ t('doc.size') }}</th><th>{{ t('doc.version') }}</th><th>{{ t('doc.modified') }}</th><th>{{ t('doc.author') }}</th><th class="doc-actions" />
        </tr></thead>
        <tbody>
          <tr v-for="f in folders" :key="'d' + f.id" @click="go(projectId, f.id)">
            <td><span class="inline-flex items-center gap-2"><Folder :size="18" class="doc-folder" aria-hidden="true" /><a class="subject" href="#" @click.prevent>{{ f.title }}</a><Lock v-if="f.locked" :size="13" class="text-muted" :aria-label="t('doc.locked')" /></span></td>
            <td class="num muted"><span class="doc-count">{{ t('doc.items', { files: f.files, folders: f.folders }) }}</span></td><td /><td>{{ fmtDate(f.updated_at) }}</td><td>{{ f.author }}</td>
            <td class="doc-actions" @click.stop>
              <button v-if="data.can.folder" class="icon-btn" :aria-label="t('doc.rename')" @click="dialog = { mode: 'rename', id: f.id, title: f.title }"><Pencil :size="14" /></button>
              <button v-if="data.can.delete_folder" class="icon-btn" :aria-label="t('doc.delete')" @click="removeFolder(f)"><Trash2 :size="14" /></button>
            </td>
          </tr>
          <tr v-for="f in files" :key="'f' + f.id" @click="openFile(f.id)">
            <td><span class="inline-flex items-center gap-2"><FileText v-if="/\.(pdf|docx?|txt|odt|xlsx?)$/i.test(f.name)" :size="18" class="text-muted" aria-hidden="true" /><FileIcon v-else :size="18" class="text-muted" aria-hidden="true" /><a class="subject" href="#" @click.prevent>{{ f.title || f.name }}</a><Lock v-if="f.locked" :size="13" class="text-muted" :aria-label="t('doc.locked')" /></span>
              <span v-if="f.title && f.title !== f.name" class="muted small block">{{ f.name }}</span></td>
            <td class="num">{{ size(f.size) }}</td><td>{{ f.version }}</td><td>{{ fmtDate(f.updated_at) }}</td><td>{{ f.author }}</td>
            <td class="doc-actions" @click.stop>
              <a class="icon-btn" :href="f.download_url" :aria-label="t('doc.download')"><Download :size="14" /></a>
              <button v-if="data.can.delete_file" class="icon-btn" :aria-label="t('doc.delete')" @click="removeFile(f.id, f.title || f.name)"><Trash2 :size="14" /></button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="loading && !data" class="muted">{{ t('loading') }}</p>
      <p v-else-if="data && !files.length && !folders.length" class="muted empty">{{ filter ? t('pr.empty') : t('doc.empty') }}</p>
      <p v-if="data?.truncated" class="muted small">{{ t('doc.truncated', { n: 500 }) }}</p>
      <p v-if="data?.can.upload" class="muted small doc-hint">{{ t('doc.drop') }} · {{ t('doc.same_name_hint') }}</p>
    </div>

    <div v-if="detail" class="overlay" @mousedown.self="detail = null">
      <div class="dialog doc-dialog" role="dialog" aria-modal="true" :aria-label="detail.name">
        <div class="flex items-start gap-2"><h2 class="grow">{{ detail.title || detail.name }}</h2><button class="icon-btn" :aria-label="t('detail.close')" @click="detail = null"><X :size="16" /></button></div>
        <p class="muted small">{{ detail.name }} · {{ size(detail.size) }} · {{ t('doc.version') }} {{ detail.version }}</p>
        <p v-if="detail.description">{{ detail.description }}</p>
        <p class="flex gap-2">
          <a class="btn primary" :href="detail.view_url" target="_blank" rel="noopener">{{ t('doc.open') }}</a>
          <a class="btn" :href="detail.download_url"><Download :size="14" aria-hidden="true" /> {{ t('doc.download') }}</a>
          <button v-if="detail.can_delete" class="btn danger-text" @click="removeFile(detail.id, detail.title || detail.name)"><Trash2 :size="14" aria-hidden="true" /> {{ t('doc.delete') }}</button>
        </p>
        <h3>{{ t('doc.versions') }}</h3>
        <ul class="doc-revs">
          <li v-for="r in detail.revisions" :key="r.id"><a :href="r.download_url"><strong>{{ r.version }}</strong> {{ r.name }}</a>
            <span class="muted small"> · {{ size(r.size) }} · {{ r.author }} · {{ fmtDateTime(r.created_at) }}</span>
            <span v-if="r.comment" class="muted small block">{{ r.comment }}</span></li>
        </ul>
      </div>
    </div>

    <div v-if="dialog" class="overlay" @mousedown.self="dialog = null">
      <form class="dialog" role="dialog" aria-modal="true" :aria-label="dialog.mode === 'new' ? t('doc.new_folder') : t('doc.rename')" @submit.prevent="saveDialog">
        <h2>{{ dialog.mode === 'new' ? t('doc.new_folder') : t('doc.rename') }}</h2>
        <input v-model="dialog.title" required maxlength="255" :placeholder="t('doc.folder_name')" :aria-label="t('doc.folder_name')" autofocus>
        <div class="dialog-actions"><button class="btn" type="button" @click="dialog = null">{{ t('create.cancel') }}</button><button class="btn primary" type="submit" :disabled="!dialog.title.trim()">{{ dialog.mode === 'new' ? t('doc.create') : t('doc.save') }}</button></div>
      </form>
    </div>
  </section>
</template>

<style>
.docs .doc-crumbs { display: flex; align-items: center; flex-wrap: wrap; gap: 2px; margin: 4px 0 10px; }
.docs .doc-folder { color: var(--brand-gold, #a39872); }
.docs .doc-actions { width: 1%; white-space: nowrap; text-align: right; }
.docs .doc-actions .icon-btn { display: inline-flex; }
.docs tbody tr { cursor: pointer; }
.docs .doc-drop.dragging { outline: 2px dashed var(--accent); outline-offset: -4px; }
.docs .doc-hint { padding: 10px 4px; }
.docs .doc-dialog { width: min(640px, 94vw); }
.docs .doc-revs { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
@media (max-width: 760px) {
  .docs .m-docs th:nth-child(3), .docs .m-docs td:nth-child(3), .docs .m-docs th:nth-child(4), .docs .m-docs td:nth-child(4), .docs .m-docs th:nth-child(5), .docs .m-docs td:nth-child(5) { display: none; }
  .docs .doc-count { display: none; }
  .docs .m-docs td:first-child { white-space: normal; word-break: break-word; }
}
</style>
