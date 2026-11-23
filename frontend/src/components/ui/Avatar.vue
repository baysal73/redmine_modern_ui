<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(defineProps<{ name: string; size?: number }>(), { size: 24 });
const initials = computed(() => props.name.split(/\s+/).filter(Boolean).map((p) => p[0]).slice(0, 2).join('').toUpperCase() || '?');
// stable colour per name
const hue = computed(() => { let h = 0; for (const c of props.name) h = (h * 31 + c.charCodeAt(0)) % 360; return h; });
</script>

<template>
  <span class="inline-flex shrink-0 items-center justify-center rounded-full font-semibold text-white select-none"
        :style="{ width: size + 'px', height: size + 'px', fontSize: Math.round(size * 0.4) + 'px', background: `hsl(${hue} 48% 42%)` }"
        :title="name" aria-hidden="true">{{ initials }}</span>
</template>
