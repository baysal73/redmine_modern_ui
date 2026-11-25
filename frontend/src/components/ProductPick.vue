<script setup lang="ts">
// Search box that lists active products (also without typing) and hands the chosen one to the parent.
import { Package } from 'lucide-vue-next';
import { onUnmounted, ref } from 'vue';
import { api } from '../api/client';
import { t } from '../i18n';
import { money } from '../lib/money';
import type { ProductRow } from '../types';

const emit = defineEmits<{ (e: 'pick', p: ProductRow): void }>();
const q = ref('');
const hits = ref<ProductRow[]>([]);
const open = ref(false);
const loading = ref(false);
let timer: number | undefined;
let seq = 0;

async function search() {
  const mine = ++seq; loading.value = true;
  try { const r = await api.products({ q: q.value.trim(), status: 1, per_page: 10 }); if (mine === seq) hits.value = r.products; }
  catch { if (mine === seq) hits.value = []; }
  finally { if (mine === seq) loading.value = false; }
}
function onInput() { window.clearTimeout(timer); timer = window.setTimeout(search, 200); }
function onFocus() { open.value = true; search(); }
function onBlur() { window.setTimeout(() => { open.value = false; }, 150); }
function pick(p: ProductRow) { emit('pick', p); q.value = ''; open.value = false; }
onUnmounted(() => window.clearTimeout(timer));
</script>

<template>
  <div class="pp">
    <input v-model="q" type="search" autocomplete="off" :placeholder="t('inv.add_product')" :aria-label="t('inv.add_product')" @focus="onFocus" @click="open || onFocus()" @blur="onBlur" @input="onInput">
    <ul v-if="open" class="pp-list" role="listbox">
      <li v-for="p in hits" :key="p.id" role="option">
        <button type="button" @mousedown.prevent="pick(p)">
          <Package :size="14" class="text-muted" aria-hidden="true" />
          <span class="pp-name">{{ p.name }}<span v-if="p.code" class="muted small"> · {{ p.code }}</span></span>
          <span v-if="p.price !== null" class="muted">{{ money(p.price, p.currency) }}</span>
        </button>
      </li>
      <li v-if="!hits.length" class="muted small pp-empty">{{ loading ? t('loading') : t('pr.empty') }}</li>
    </ul>
  </div>
</template>

<style>
.pp { position: relative; display: inline-block; }
.pp input { font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; min-width: 240px; }
.pp-list { position: absolute; top: 100%; left: 0; z-index: 6; min-width: 340px; max-height: 300px; overflow: auto; list-style: none; margin: 2px 0 0; padding: 4px; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; box-shadow: 0 6px 20px rgba(0,0,0,.15); }
.pp-list button { all: unset; box-sizing: border-box; display: flex; gap: 8px; align-items: center; width: 100%; padding: 6px 8px; border-radius: 6px; cursor: pointer; color: var(--fg); }
.pp-list button:hover { background: var(--hover, rgba(127,127,127,.15)); }
.pp-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pp-empty { padding: 6px 8px; }
</style>
