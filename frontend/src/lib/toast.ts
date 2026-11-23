import { reactive } from 'vue';
export const toasts = reactive<{ id: number; text: string; kind: 'ok' | 'error' }[]>([]);
let next = 1;
export function toast(text: string, kind: 'ok' | 'error' = 'ok') {
  const id = next++;
  toasts.push({ id, text, kind });
  setTimeout(() => { const i = toasts.findIndex((t) => t.id === id); if (i >= 0) toasts.splice(i, 1); }, kind === 'error' ? 6000 : 2000);
}
