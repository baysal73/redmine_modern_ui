<script setup lang="ts">
import { CalendarCheck, ExternalLink, Keyboard, ListChecks, Menu, Moon, Plus, SquareKanban, Sun, X } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { readConfig } from './api/client';
import QuickCreate from './components/QuickCreate.vue';
import ShortcutHelp from './components/ShortcutHelp.vue';
import Avatar from './components/ui/Avatar.vue';
import { t } from './i18n';
import { loadMeta, store } from './lib/store';
import { toggleTheme } from './lib/theme';
import { toasts } from './lib/toast';
import { ui } from './lib/ui';

const config = readConfig();
const router = useRouter();
const route = useRoute();
const navOpen = ref(false);
const dark = ref(document.documentElement.dataset.theme === 'dark');
const classicUrl = `${config.root}/my/page`;
const user = computed(() => store.meta?.user);

const nav = [
  { to: '/home', label: 'nav.home', icon: CalendarCheck },
  { to: '/issues', label: 'nav.issues', icon: ListChecks },
  { to: '/board', label: 'nav.board', icon: SquareKanban },
];
const isActive = (to: string) => route.path === to || route.path.startsWith(to + '/');
function flipTheme() { toggleTheme(); dark.value = document.documentElement.dataset.theme === 'dark'; }
watch(() => route.fullPath, () => { navOpen.value = false; });

// Global shortcuts (ignored while typing or when a dialog is open)
let chord = false; let chordTimer: number | undefined;
function onKey(e: KeyboardEvent) {
  const el = e.target as HTMLElement;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.isContentEditable || e.ctrlKey || e.metaKey || e.altKey) return;
  if (ui.quickCreate || ui.help) return;
  if (chord) {
    chord = false; window.clearTimeout(chordTimer);
    if (e.key === 'i') router.push('/issues'); else if (e.key === 'b') router.push('/board'); else if (e.key === 'h') router.push('/home');
    return;
  }
  if (e.key === 'c') { e.preventDefault(); ui.quickCreate = true; }
  else if (e.key === '?') { e.preventDefault(); ui.help = true; }
  else if (e.key === 'g') { chord = true; chordTimer = window.setTimeout(() => { chord = false; }, 1200); }
}
onMounted(() => { window.addEventListener('keydown', onKey); loadMeta().catch(() => {}); });
onUnmounted(() => window.removeEventListener('keydown', onKey));
</script>

<template>
  <a class="skip-link" href="#main">{{ t('a11y.skip') }}</a>
  <div class="shell">
    <button class="mobile-menu icon-btn" :aria-label="t('nav.menu')" @click="navOpen = true"><Menu :size="18" /></button>
    <div v-if="navOpen" class="scrim" @click="navOpen = false" />
    <aside class="sidebar" :class="{ open: navOpen }" :aria-label="t('nav.menu')">
      <div class="flex items-center justify-between px-3 pb-3 pt-1">
        <router-link to="/home" class="brand">{{ t('app.title') }}</router-link>
        <button class="icon-btn md:hidden" :aria-label="t('detail.close')" @click="navOpen = false"><X :size="16" /></button>
      </div>
      <button class="btn primary mx-2 mb-3 flex items-center justify-center gap-2" @click="ui.quickCreate = true">
        <Plus :size="16" /> {{ t('create.button') }} <kbd class="ml-auto">c</kbd>
      </button>
      <nav class="flex flex-col gap-0.5 px-2" aria-label="Main">
        <router-link v-for="n in nav" :key="n.to" :to="n.to" class="nav-item" :class="{ active: isActive(n.to) }">
          <component :is="n.icon" :size="17" aria-hidden="true" /> {{ t(n.label) }}
        </router-link>
      </nav>
      <div v-if="store.meta?.classic_menu?.length" class="mt-5 px-2">
        <p class="nav-heading">{{ t('nav.more') }}</p>
        <nav class="flex flex-col gap-0.5" :aria-label="t('nav.more')">
          <a v-for="m in store.meta.classic_menu" :key="m.name" :href="m.url" class="nav-item muted-item">
            <ExternalLink :size="15" aria-hidden="true" /> {{ m.caption }}
          </a>
        </nav>
      </div>
      <div class="mt-auto flex flex-col gap-1 border-t border-line px-2 pt-3">
        <button class="nav-item" @click="ui.help = true"><Keyboard :size="17" /> {{ t('nav.help') }} <kbd class="ml-auto">?</kbd></button>
        <button class="nav-item" @click="flipTheme"><component :is="dark ? Sun : Moon" :size="17" /> {{ t('nav.theme') }}</button>
        <a class="nav-item" :href="classicUrl"><ExternalLink :size="17" /> {{ t('nav.classic') }}</a>
        <div v-if="user" class="mt-1 flex items-center gap-2 px-2 py-1.5 text-[0.85rem]">
          <Avatar :name="user.name" :size="26" /> <span class="truncate">{{ user.name }}</span>
        </div>
      </div>
    </aside>
    <main id="main" tabindex="-1"><router-view /></main>
  </div>
  <QuickCreate v-if="ui.quickCreate" />
  <ShortcutHelp v-if="ui.help" />
  <div class="toasts" aria-live="polite">
    <div v-for="x in toasts" :key="x.id" class="toast" :class="x.kind" role="status">{{ x.text }}</div>
  </div>
</template>
