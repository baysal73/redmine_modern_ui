<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { t } from '../i18n';
import { trapFocus } from '../lib/dialog';
import { ui } from '../lib/ui';
import { store } from '../lib/store';

const root = ref<HTMLElement | null>(null);
let release: (() => void) | null = null;
const close = () => { ui.help = false; };
const f = () => store.meta?.features;
const rows = computed<[string, string][]>(() => [
  ['c', 'help.create'], ['/', 'help.search'], ['j / k', 'help.next_prev'], ['Esc', 'help.close'],
  ['g i', 'help.go_issues'],
  ...(f()?.contacts ? [['g k', 'help.go_contacts'] as [string, string]] : []),
  ...(f()?.invoices ? [['g r', 'help.go_invoices'] as [string, string]] : []),
  ...(f()?.products ? [['g p', 'help.go_products'] as [string, string]] : []),
  ...(f()?.calendar ? [['g c', 'help.go_calendar'] as [string, string]] : []),
  ['Ctrl + Enter', 'help.send'], ['Ctrl + K', 'help.palette'], ['Ctrl + Z', 'help.undo'], ['?', 'help.this'],
]);
onMounted(() => { release = trapFocus(root.value!, close); });
onUnmounted(() => release?.());
</script>

<template>
  <div class="overlay" @mousedown.self="close">
    <div ref="root" class="dialog" role="dialog" aria-modal="true" aria-labelledby="sh-title">
      <h2 id="sh-title">{{ t('help.title') }}</h2>
      <dl class="shortcuts"><template v-for="[k, d] in rows" :key="k"><dt><kbd>{{ k }}</kbd></dt><dd>{{ t(d) }}</dd></template></dl>
      <div class="dialog-actions"><button class="btn" @click="close">{{ t('detail.close') }}</button></div>
    </div>
  </div>
</template>
