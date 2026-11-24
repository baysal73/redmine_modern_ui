<script setup lang="ts">
// Pick, drop or paste files; each one is uploaded right away and kept as a token until the issue is saved.
import { Paperclip, X } from 'lucide-vue-next';
import { computed, ref } from 'vue';
import { api } from '../api/client';
import { t } from '../i18n';
import { store } from '../lib/store';
import { toast } from '../lib/toast';
import type { Upload } from '../types';

const model = defineModel<Upload[]>({ required: true });
const busy = ref(0);
const over = ref(false);
const input = ref<HTMLInputElement | null>(null);
const maxSize = computed(() => store.meta?.settings.attachment_max_size ?? 0);
const size = (n: number) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);

async function add(files: FileList | File[] | null) {
  for (const f of Array.from(files ?? [])) {
    if (maxSize.value && f.size > maxSize.value) { toast(t('attach.too_big', { name: f.name, max: size(maxSize.value) }), 'error'); continue; }
    busy.value++;
    try { model.value = [...model.value, await api.upload(f)]; }
    catch (e) { toast(t('attach.failed', { name: f.name, message: (e as Error).message }), 'error'); }
    finally { busy.value--; }
  }
  if (input.value) input.value.value = '';
}
const remove = (token: string) => { model.value = model.value.filter((u) => u.token !== token); };
const onDrop = (e: DragEvent) => { over.value = false; add(e.dataTransfer?.files ?? null); };
const onPaste = (e: ClipboardEvent) => { const files = e.clipboardData?.files; if (files?.length) { e.preventDefault(); add(files); } };
defineExpose({ busy });
</script>

<template>
  <div class="attach" :class="{ over }" @dragover.prevent="over = true" @dragleave="over = false" @drop.prevent="onDrop" @paste="onPaste">
    <button type="button" class="link-btn attach-btn" @click="input?.click()"><Paperclip :size="14" /> {{ t('attach.add') }}</button>
    <span class="muted small">{{ t('attach.hint') }}</span>
    <input ref="input" type="file" multiple hidden @change="add(($event.target as HTMLInputElement).files)">
    <ul v-if="model.length || busy" class="attach-list">
      <li v-for="u in model" :key="u.token"><Paperclip :size="12" /> {{ u.filename }} <span class="muted small">{{ size(u.filesize) }}</span>
        <button type="button" class="icon-btn attach-x" :aria-label="t('attach.remove', { name: u.filename })" @click="remove(u.token)"><X :size="12" /></button></li>
      <li v-if="busy" class="muted small">{{ t('attach.uploading') }}</li>
    </ul>
  </div>
</template>

<style>
.attach { border: 1px dashed var(--border); border-radius: 8px; padding: 6px 10px; }
.attach.over { border-color: var(--accent); background: var(--pill-open); }
.attach-btn { display: inline-flex; gap: 4px; align-items: center; }
.attach-list { list-style: none; margin: 6px 0 0; padding: 0; display: grid; gap: 2px; }
.attach-list li { display: flex; align-items: center; gap: 6px; }
.attach-x { border: 0; background: none; padding: 2px 4px; color: var(--muted); }
</style>
