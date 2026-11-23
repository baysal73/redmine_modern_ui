// Light/dark mode: follows the OS until the user picks one (stored in localStorage).
const KEY = 'modern_ui_theme';
function stored(): string | null { try { return localStorage.getItem(KEY); } catch { return null; } }
export function applyTheme() {
  const v = stored();
  if (v) document.documentElement.dataset.theme = v; else delete document.documentElement.dataset.theme;
}
export function toggleTheme() {
  const dark = document.documentElement.dataset.theme
    ? document.documentElement.dataset.theme === 'dark'
    : window.matchMedia('(prefers-color-scheme: dark)').matches;
  try { localStorage.setItem(KEY, dark ? 'light' : 'dark'); } catch { /* private mode */ }
  applyTheme();
}
