<script setup lang="ts">
// The user's own saved filters for a list screen (private Redmine queries). Applying a view restores the screen's state.
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { Bookmark, ChevronDown, Trash2 } from 'lucide-vue-next';
import { useRouter } from 'vue-router';
import { api } from '../api/client';
import { t } from '../i18n';
import { toast } from '../lib/toast';
import type { SavedQuery } from '../types';

const props = defineProps<{ module: string; path: string; current: Record<string, string> }>();
const router = useRouter();
const views = ref<SavedQuery[]>([]);
const canSave = ref(true);
const open = ref(false);
const name = ref('');
const root = ref<HTMLElement | null>(null);

const IGNORE = ['page', 'new'];
const clean = (q: Record<string, unknown>) => Object.fromEntries(Object.entries(q).filter(([k, v]) => !IGNORE.includes(k) && v !== '' && v != null).map(([k, v]) => [k, String(v)]));
const key = (q: Record<string, unknown>) => JSON.stringify(Object.entries(clean(q)).sort());
const currentName = computed(() => views.value.find((v) => key(v.state) === key(props.current))?.name ?? '');

onMounted(async () => {
  try { const r = await api.listQueries(props.module); views.value = r.queries; canSave.value = r.can_save; } catch { /* the list works without saved views */ }
  document.addEventListener('click', onDoc);
});
onUnmounted(() => document.removeEventListener('click', onDoc));
function onDoc(e: MouseEvent) { if (root.value && !root.value.contains(e.target as Node)) open.value = false; }

async function save() {
  const n = name.value.trim(); if (!n) return;
  try {
    const same = views.value.find((v) => v.name === n);
    if (same) { await api.deleteListQuery(props.module, same.id); views.value = views.value.filter((v) => v.id !== same.id); }
    const state = clean(props.current);
    const r = await api.saveListQuery(props.module, n, { filters: state.filters ?? '', state: JSON.stringify(state) });
    views.value = [...views.value, r.query].sort((a, b) => a.name.localeCompare(b.name));
    name.value = ''; toast(t('views.saved', { name: n }));
  } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
async function remove(v: SavedQuery) {
  try { await api.deleteListQuery(props.module, v.id); views.value = views.value.filter((x) => x.id !== v.id); }
  catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
function apply(v: SavedQuery) { router.push({ path: props.path, query: clean(v.state) }); open.value = false; }
</script>

<template>
  <div ref="root" class="col-menu-wrap">
    <button class="btn tb-btn" aria-haspopup="true" :aria-expanded="open" @click.stop="open = !open"><Bookmark :size="14" /> {{ currentName || t('views.title') }} <ChevronDown :size="13" /></button>
    <div v-if="open" class="col-menu views-menu" role="menu" @click.stop>
      <p v-if="!views.length" class="muted small px-2 py-1">{{ t('views.empty') }}</p>
      <div v-for="v in views" :key="v.id" class="view-row">
        <button class="view-name" :class="{ on: v.name === currentName }" @click="apply(v)">{{ v.name }}</button>
        <button class="icon-btn view-del" :aria-label="t('views.delete', { name: v.name })" @click="remove(v)"><Trash2 :size="13" /></button>
      </div>
      <p v-if="!canSave" class="muted small px-2">{{ t('views.cant_save') }}</p>
      <form v-else class="view-save" @submit.prevent="save">
        <input v-model="name" :placeholder="t('views.name_ph')" :aria-label="t('views.name_ph')" maxlength="60">
        <button class="btn primary" :disabled="!name.trim()">{{ t('views.save') }}</button>
      </form>
      <p class="muted small px-2">{{ t('views.local_hint') }}</p>
    </div>
  </div>
</template>
