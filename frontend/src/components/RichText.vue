<script setup lang="ts">
// Text field for descriptions and comments: CKEditor (the one Redmine already uses) when it is active, else a textarea.
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { t } from '../i18n';
import { loadCkeditor } from '../lib/ckeditor';

const props = withDefaults(defineProps<{ modelValue: string; project?: string | number | null; rows?: number; placeholder?: string; label?: string; height?: number }>(), {
  project: null, rows: 4, placeholder: '', label: '', height: 180,
});
const emit = defineEmits<{ (e: 'update:modelValue', v: string): void; (e: 'submit'): void; (e: 'blur'): void }>();

const area = ref<HTMLTextAreaElement | null>(null);
const failed = ref(false);
const loading = ref(true);
let editor: any = null; // eslint-disable-line @typescript-eslint/no-explicit-any
let last = props.modelValue;

function push() {
  if (!editor || !editor.checkDirty()) return; // setData/normalisation alone is not an edit
  last = editor.getSnapshot(); // what the classic form submits as well
  emit('update:modelValue', last);
}

onMounted(async () => {
  try {
    const loaded = await loadCkeditor(props.project);
    if (!loaded || !area.value) { loading.value = false; return; }
    const { ck, options } = loaded;
    ck.config.versionCheck = false;
    editor = ck.replace(area.value, {
      ...options, height: props.height, width: '100%', startupFocus: false,
      resize_enabled: true,
      removePlugins: `${(options.removePlugins as string) ?? ''},elementspath`,
    });
    editor.on('instanceReady', () => { editor.setData(props.modelValue ?? '', { noSnapshot: true, callback: () => { last = editor.getSnapshot(); editor.resetDirty(); } }); loading.value = false; });
    editor.on('change', push);
    editor.on('blur', () => { push(); emit('blur'); });
    editor.addCommand('muiSubmit', { exec: () => { push(); emit('submit'); } });
    editor.setKeystroke(ck.CTRL + 13, 'muiSubmit');
  } catch {
    failed.value = true; loading.value = false; // plain textarea stays usable
  }
});
onBeforeUnmount(() => { try { editor?.destroy(true); } catch { /* ignore */ } editor = null; });

// reset from outside (e.g. comment cleared after sending)
watch(() => props.modelValue, (v) => { if (editor && v !== last) { editor.setData(v ?? '', { callback: () => { last = editor.getSnapshot(); editor.resetDirty(); } }); } });
defineExpose({ focus: () => (editor ? editor.focus() : area.value?.focus()) });
</script>

<template>
  <div class="richtext" :aria-busy="loading">
    <textarea ref="area" :value="modelValue" :rows="rows" :placeholder="placeholder" :aria-label="label || undefined"
              @input="emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)" @blur="!editor && emit('blur')"
              @keydown.ctrl.enter.prevent="emit('submit')" @keydown.meta.enter.prevent="emit('submit')" />
    <p v-if="loading" class="muted small">{{ t('loading') }}</p>
    <p v-if="failed" class="muted small">{{ t('editor.failed') }}</p>
  </div>
</template>

<style>
.richtext { width: 100%; }
.richtext textarea { width: 100%; }
.richtext .cke { border-radius: 6px; }
</style>
