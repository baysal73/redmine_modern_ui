<script setup lang="ts">
import { Circle, CircleCheck, CircleDot, CircleDotDashed } from 'lucide-vue-next';
import { computed } from 'vue';
import { store } from '../../lib/store';
import type { Status } from '../../types';

const props = defineProps<{ status: Status; plain?: boolean }>();
// Icon by position of the status among the open ones: first = not started, last = almost done
const kind = computed(() => {
  if (props.status.is_closed) return 'done';
  const open = (store.meta?.statuses ?? []).filter((s) => !s.is_closed);
  const i = open.findIndex((s) => s.id === props.status.id);
  if (i <= 0) return 'todo';
  return i >= open.length - 1 && open.length > 2 ? 'review' : 'doing';
});
const icon = computed(() => ({ todo: Circle, doing: CircleDot, review: CircleDotDashed, done: CircleCheck })[kind.value]);
const tone = computed(() => ({
  todo: 'text-muted', doing: 'text-accent', review: 'text-warn', done: 'text-ok',
})[kind.value]);
</script>

<template>
  <span class="inline-flex items-center gap-1.5 whitespace-nowrap text-[0.85rem]" :class="plain ? '' : 'rounded-full bg-hover px-2 py-0.5'">
    <component :is="icon" :size="14" :stroke-width="2.2" class="shrink-0" :class="tone" aria-hidden="true" />
    <span>{{ status.name }}</span>
  </span>
</template>
