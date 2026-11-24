import { reactive } from 'vue';
export interface ToastAction { label: string; run: () => void }
export const toasts = reactive<{ id: number; text: string; kind: 'ok' | 'error'; action?: ToastAction }[]>([]);
let next = 1;
export function toast(text: string, kind: 'ok' | 'error' = 'ok', action?: ToastAction) {
  const id = next++;
  toasts.push({ id, text, kind, action });
  setTimeout(() => dismiss(id), kind === 'error' ? 6000 : action ? 8000 : 2000);
}
export function dismiss(id: number) { const i = toasts.findIndex((t) => t.id === id); if (i >= 0) toasts.splice(i, 1); }
