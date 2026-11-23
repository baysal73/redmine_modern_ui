// Accessible modal behaviour: focus first control, trap Tab, close on Esc, restore focus afterwards.
export function trapFocus(root: HTMLElement, onClose: () => void): () => void {
  const previous = document.activeElement as HTMLElement | null;
  const focusable = () => Array.from(root.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'));
  focusable()[0]?.focus();
  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'Escape') { e.stopPropagation(); onClose(); return; }
    if (e.key !== 'Tab') return;
    const items = focusable(); if (!items.length) return;
    const first = items[0]; const last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  };
  root.addEventListener('keydown', onKey);
  return () => { root.removeEventListener('keydown', onKey); previous?.focus?.(); };
}
