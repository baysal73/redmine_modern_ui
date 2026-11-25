import { reactive } from 'vue';

// Tiny shared UI state: which dialogs are open, and a counter views watch to reload after changes.
export const ui = reactive({ quickCreate: false, help: false, palette: false, refresh: 0 });
