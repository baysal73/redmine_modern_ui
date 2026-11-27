<script setup lang="ts">
import { locale, t } from '../../i18n';
import type { IssueRow } from '../../types';
import Avatar from '../ui/Avatar.vue';
import PriorityIcon from '../ui/PriorityIcon.vue';
import StatusBadge from '../ui/StatusBadge.vue';

// Ticket rows of the start page widgets: status, subject, project, then due date (lists) or last change (recent).
defineProps<{ rows: IssueRow[]; recent?: boolean }>();
const fmtDate = (s: string) => new Date(s).toLocaleDateString(locale, { weekday: 'short', day: '2-digit', month: 'short' });
const overdue = (r: IssueRow) => !!r.due_date && !r.status.is_closed && new Date(r.due_date) < new Date(new Date().toDateString());
</script>

<template>
  <p v-if="!rows.length" class="muted px-4 py-5 text-[0.9rem]">{{ t('home.nothing') }}</p>
  <ul v-else>
    <li v-for="r in rows" :key="r.id" class="border-b border-line last:border-0">
      <router-link :to="`/issues/${r.id}`" class="home-row">
        <StatusBadge :status="r.status" plain />
        <span class="min-w-0 flex-1"><span class="block truncate font-medium text-fg">{{ r.subject }}</span>
          <span class="muted block truncate text-[0.8rem]">#{{ r.id }} · {{ r.project.name }}</span></span>
        <template v-if="recent">
          <Avatar v-if="r.assigned_to" :name="r.assigned_to.name" :size="22" />
          <span class="muted whitespace-nowrap text-[0.8rem]">{{ new Date(r.updated_on).toLocaleString(locale, { dateStyle: 'short', timeStyle: 'short' }) }}</span>
        </template>
        <template v-else>
          <PriorityIcon :priority="r.priority" :label="false" />
          <span v-if="r.due_date" class="whitespace-nowrap text-[0.82rem]" :class="overdue(r) ? 'font-semibold text-danger' : 'muted'">{{ fmtDate(r.due_date) }}</span>
        </template>
      </router-link>
    </li>
  </ul>
</template>
