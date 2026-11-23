/** @type {import('tailwindcss').Config} */
// Colours come from CSS variables (src/styles.css) so light/dark mode and the accent colour switch without rebuilding.
export default {
  content: ['./src/**/*.{vue,ts}'],
  corePlugins: { preflight: false }, // the app has its own base styles; keeps the build small and predictable
  theme: {
    extend: {
      colors: {
        bg: 'var(--bg)', surface: 'var(--surface)', fg: 'var(--fg)', muted: 'var(--muted)', line: 'var(--border)',
        accent: 'var(--accent)', 'accent-fg': 'var(--accent-fg)', 'accent-soft': 'var(--accent-soft)', hover: 'var(--hover)',
        danger: 'var(--danger)', ok: 'var(--ok)', warn: 'var(--warn)',
      },
      borderRadius: { card: '12px' },
      boxShadow: { card: '0 1px 2px rgb(16 24 40 / 0.05), 0 1px 3px rgb(16 24 40 / 0.06)', pop: '0 12px 32px rgb(16 24 40 / 0.18)' },
    },
  },
};
