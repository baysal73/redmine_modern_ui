<script setup lang="ts">
import { t } from '../i18n';
defineProps<{ count: number }>();
defineEmits<{ (e: 'clear'): void }>();
</script>

<template>
  <div v-if="count" class="bulkbar" role="region" :aria-label="t('bulk.title')">
    <strong>{{ t('bulk.selected', { n: count }) }}</strong>
    <slot />
    <button class="link-btn" @click="$emit('clear')">{{ t('bulk.clear') }}</button>
  </div>
</template>
