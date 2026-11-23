<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { readConfig } from './api/client';
import QuickCreate from './components/QuickCreate.vue';
import ShortcutHelp from './components/ShortcutHelp.vue';
import { ui } from './lib/ui';
import { t } from './i18n';
import { toggleTheme } from './lib/theme';
import { toasts } from './lib/toast';

const config = readConfig();
const classicUrl = `${config.root}/my/page`;
const router = useRouter();

// Global shortcuts (ignored while typing or when a dialog is open)
let chord = false; let chordTimer: number | undefined;
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey || e.altKey) return;
  if (ui.quickCreate || ui.help) return;
  if (chord) {
    chord = false; window.clearTimeout(chordTimer);
    if (e.key === 'i') router.push('/issues'); else if (e.key === 'b') router.push('/board');
    return;
  }
  if (e.key === 'c') { e.preventDefault(); ui.quickCreate = true; }
  else if (e.key === '?') { e.preventDefault(); ui.help = true; }
  else if (e.key === 'g') { chord = true; chordTimer = window.setTimeout(() => { chord = false; }, 1200); }
}
onMounted(() => window.addEventListener('keydown', onKey));
onUnmounted(() => window.removeEventListener('keydown', onKey));
</script>

<template>
  <a class="skip-link" href="#main">{{ t('a11y.skip') }}</a>
  <header class="topbar">
    <router-link class="brand" to="/issues">{{ t('app.title') }}</router-link>
    <nav aria-label="Main">
      <router-link to="/issues">{{ t('nav.issues') }}</router-link>
      <router-link to="/board">{{ t('nav.board') }}</router-link>
    </nav>
    <span class="spacer" />
    <button class="btn primary" @click="ui.quickCreate = true">＋ {{ t('create.button') }}</button>
    <button class="icon-btn" :title="t('help.title') + ' (?)'" :aria-label="t('help.title')" @click="ui.help = true">?</button>
    <button class="icon-btn" :title="t('nav.theme')" :aria-label="t('nav.theme')" @click="toggleTheme">◐</button>
    <a class="classic-link" :href="classicUrl">{{ t('nav.classic') }}</a>
  </header>
  <main id="main" tabindex="-1"><router-view /></main>
  <QuickCreate v-if="ui.quickCreate" />
  <ShortcutHelp v-if="ui.help" />
  <div class="toasts" aria-live="polite">
    <div v-for="x in toasts" :key="x.id" class="toast" :class="x.kind" role="status">{{ x.text }}</div>
  </div>
</template>
