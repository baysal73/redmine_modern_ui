// One level of "undo" for the last saved change: a button in the toast, and Ctrl/⌘ + Z outside text fields.
import { t } from '../i18n';
import { toast } from './toast';

let pending: (() => Promise<void>) | null = null;

export async function undoLast() {
  const fn = pending;
  pending = null;
  if (!fn) return;
  try { await fn(); toast(t('undo.done')); } catch (e) { toast(t('edit.failed', { message: (e as Error).message }), 'error'); }
}
export function offerUndo(message: string, revert: () => Promise<void>) {
  pending = revert;
  toast(message, 'ok', { label: t('undo'), run: undoLast });
}
export const hasUndo = () => pending !== null;
