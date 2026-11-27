<script setup lang="ts">
import { ref, watch } from 'vue';
import { api } from '../../api/client';
import { t } from '../../i18n';
import { ui } from '../../lib/ui';
import type { IssueRow } from '../../types';
import IssueRows from './IssueRows.vue';

// A ticket list widget: any list request (a preset or a saved view), the first `limit` rows.
const props = defineProps<{ params: Record<string, string | number | undefined> }>();
const emit = defineEmits<{ total: [n: number] }>();
const rows = ref<IssueRow[] | null>(null);
const error = ref('');

async function load() {
  try {
    const r = await api.issues(props.params);
    rows.value = r.issues; error.value = ''; emit('total', r.total);
  } catch (e) { error.value = (e as Error).message; }
}
watch(() => [JSON.stringify(props.params), ui.refresh], load, { immediate: true });
</script>

<template>
  <p v-if="error" class="error px-4 py-3" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
  <p v-else-if="!rows" class="muted px-4 py-5 text-[0.9rem]">…</p>
  <IssueRows v-else :rows="rows" />
</template>
