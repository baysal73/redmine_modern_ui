<script setup lang="ts">
import { readConfig } from './api/client';
import { t } from './i18n';
import { toggleTheme } from './lib/theme';
import { toasts } from './lib/toast';

const config = readConfig();
const classicUrl = `${config.root}/my/page`;
</script>

<template>
  <header class="topbar">
    <router-link class="brand" to="/issues">{{ t('app.title') }}</router-link>
    <nav aria-label="Main">
      <router-link to="/issues">{{ t('nav.issues') }}</router-link>
    </nav>
    <span class="spacer" />
    <button class="icon-btn" :title="t('nav.theme')" :aria-label="t('nav.theme')" @click="toggleTheme">◐</button>
    <a class="classic-link" :href="classicUrl">{{ t('nav.classic') }}</a>
  </header>
  <main><router-view /></main>
  <div class="toasts" aria-live="polite">
    <div v-for="x in toasts" :key="x.id" class="toast" :class="x.kind" role="status">{{ x.text }}</div>
  </div>
</template>
