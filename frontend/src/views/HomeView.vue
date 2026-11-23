<script setup lang="ts">
import { AlertTriangle, CalendarClock, ChevronRight, Clock, Inbox } from 'lucide-vue-next';
import { computed, onMounted, ref, watch } from 'vue';
import { api } from '../api/client';
import Avatar from '../components/ui/Avatar.vue';
import PriorityIcon from '../components/ui/PriorityIcon.vue';
import StatusBadge from '../components/ui/StatusBadge.vue';
import { locale, t } from '../i18n';
import { loadMeta, store } from '../lib/store';
import { ui } from '../lib/ui';
import type { Home, IssueRow } from '../types';

const home = ref<Home | null>(null);
const error = ref('');
async function load() {
  try { home.value = await api.home(); error.value = ''; } catch (e) { error.value = (e as Error).message; }
}
onMounted(() => { loadMeta().catch(() => {}); load(); });
watch(() => ui.refresh, load);

const hour = new Date().getHours();
const greeting = computed(() => t(hour < 11 ? 'home.greeting_morning' : hour < 18 ? 'home.greeting_day' : 'home.greeting_evening'));
const firstName = computed(() => (store.meta?.user.name ?? '').split(' ')[0]);
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale, { weekday: 'short', day: '2-digit', month: 'short' }) : '');
const todayLong = computed(() => new Date().toLocaleDateString(locale, { weekday: 'long', day: 'numeric', month: 'long' }));

const sections = computed(() => !home.value ? [] : [
  { key: 'overdue', title: t('home.overdue'), icon: AlertTriangle, tone: 'text-danger', rows: home.value.overdue, total: home.value.counts.overdue, link: { assignee: 'me', due: 'overdue' } },
  { key: 'soon', title: t('home.due_soon'), icon: CalendarClock, tone: 'text-warn', rows: home.value.due_soon, total: home.value.counts.due_soon, link: { assignee: 'me', due: 'week' } },
  { key: 'undated', title: t('home.undated'), icon: Inbox, tone: 'text-muted', rows: home.value.undated, total: home.value.counts.undated, link: { assignee: 'me', due: 'none' } },
]);
const rowOverdue = (r: IssueRow) => !!r.due_date && !r.status.is_closed && new Date(r.due_date) < new Date(new Date().toDateString());
</script>

<template>
  <section class="mx-auto max-w-5xl">
    <header class="mb-5">
      <h1 class="text-2xl font-semibold tracking-tight">{{ greeting }}<span v-if="firstName">, {{ firstName }}</span></h1>
      <p class="muted mt-1">{{ todayLong }} · {{ t('home.subtitle') }}</p>
    </header>

    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>

    <div v-if="home" class="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
      <router-link v-for="c in [
        { n: home.counts.overdue, l: t('home.overdue'), q: { assignee: 'me', due: 'overdue' }, tone: home.counts.overdue ? 'text-danger' : '' },
        { n: home.counts.due_soon, l: t('filter.due.week'), q: { assignee: 'me', due: 'week' }, tone: '' },
        { n: home.counts.undated, l: t('home.undated'), q: { assignee: 'me', due: 'none' }, tone: '' },
        { n: home.counts.assigned_open, l: t('home.assigned_open'), q: { assignee: 'me' }, tone: 'text-accent' },
      ]" :key="c.l" :to="{ path: '/issues', query: c.q }" class="card-surface block p-4 no-underline transition hover:border-accent">
        <div class="text-3xl font-semibold tabular-nums" :class="c.tone">{{ c.n }}</div>
        <div class="muted mt-1 text-[0.85rem]">{{ c.l }}</div>
      </router-link>
    </div>

    <div class="grid gap-5 lg:grid-cols-2">
      <template v-for="s in sections" :key="s.key">
        <section v-if="s.rows.length || home" class="card-surface overflow-hidden">
          <h2 class="flex items-center gap-2 border-b border-line px-4 py-3 text-[0.95rem] font-semibold">
            <component :is="s.icon" :size="16" :class="s.tone" /> {{ s.title }}
            <span class="muted ml-1 font-normal">{{ s.total }}</span>
            <router-link v-if="s.total > s.rows.length" :to="{ path: '/issues', query: s.link }" class="ml-auto text-[0.82rem] font-normal">{{ t('home.show_all') }} <ChevronRight :size="13" class="inline" /></router-link>
          </h2>
          <p v-if="!s.rows.length" class="muted px-4 py-5 text-[0.9rem]">{{ t('home.nothing') }}</p>
          <ul v-else>
            <li v-for="r in s.rows" :key="r.id" class="border-b border-line last:border-0">
              <router-link :to="`/issues/${r.id}`" class="home-row">
                <StatusBadge :status="r.status" plain />
                <span class="min-w-0 flex-1"><span class="block truncate font-medium text-fg">{{ r.subject }}</span>
                  <span class="muted block truncate text-[0.8rem]">#{{ r.id }} · {{ r.project.name }}</span></span>
                <PriorityIcon :priority="r.priority" :label="false" />
                <span v-if="r.due_date" class="whitespace-nowrap text-[0.82rem]" :class="rowOverdue(r) ? 'font-semibold text-danger' : 'muted'">{{ fmtDate(r.due_date) }}</span>
              </router-link>
            </li>
          </ul>
        </section>
      </template>

      <section v-if="home" class="card-surface overflow-hidden lg:col-span-2">
        <h2 class="flex items-center gap-2 border-b border-line px-4 py-3 text-[0.95rem] font-semibold"><Clock :size="16" class="text-muted" /> {{ t('home.recent') }}</h2>
        <ul>
          <li v-for="r in home.recent" :key="r.id" class="border-b border-line last:border-0">
            <router-link :to="`/issues/${r.id}`" class="home-row">
              <StatusBadge :status="r.status" plain />
              <span class="min-w-0 flex-1"><span class="block truncate font-medium text-fg">{{ r.subject }}</span>
                <span class="muted block truncate text-[0.8rem]">#{{ r.id }} · {{ r.project.name }}</span></span>
              <Avatar v-if="r.assigned_to" :name="r.assigned_to.name" :size="22" />
              <span class="muted whitespace-nowrap text-[0.8rem]">{{ new Date(r.updated_on).toLocaleString(locale, { dateStyle: 'short', timeStyle: 'short' }) }}</span>
            </router-link>
          </li>
        </ul>
      </section>
    </div>
  </section>
</template>
