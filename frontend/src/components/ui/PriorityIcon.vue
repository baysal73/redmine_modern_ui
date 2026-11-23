<script setup lang="ts">
import { computed } from 'vue';
import { store } from '../../lib/store';
import type { Ref } from '../../types';

const props = withDefaults(defineProps<{ priority: Ref; label?: boolean }>(), { label: true }); // Vue casts an absent Boolean prop to false, so default it
// 0..3 by position in the priority list (Redmine orders them from low to high)
const level = computed(() => {
  const list = store.meta?.priorities ?? [];
  const i = list.findIndex((p) => p.id === props.priority.id);
  if (i < 0 || list.length < 2) return 1;
  return Math.round((i / (list.length - 1)) * 3);
});
const color = computed(() => ['var(--muted)', 'var(--muted)', 'var(--warn)', 'var(--danger)'][level.value]);
</script>

<template>
  <span class="inline-flex items-center gap-1.5 whitespace-nowrap" :title="priority.name">
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
      <rect v-for="n in 4" :key="n" :x="(n - 1) * 3.6" :y="12 - n * 3" width="2.4" :height="n * 3" rx="0.8"
            :fill="n - 1 <= level ? color : 'currentColor'" :opacity="n - 1 <= level ? 1 : 0.2" />
    </svg>
    <span v-if="label">{{ priority.name }}</span>
  </span>
</template>
