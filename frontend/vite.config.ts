import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// Redmine 7 serves plugin assets through Propshaft, which renames files with a content hash.
// Relative imports between chunks would break, so the build MUST be a single JS and a single CSS file.
export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: '../assets',
    emptyOutDir: false,
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000, // inline images/fonts into the CSS/JS
    chunkSizeWarningLimit: 800,
    rollupOptions: {
      input: 'src/main.ts',
      output: {
        format: 'es',
        inlineDynamicImports: true,
        entryFileNames: 'javascripts/app.js',
        assetFileNames: (info) => (info.name?.endsWith('.css') ? 'stylesheets/app.css' : 'stylesheets/[name][extname]'),
      },
    },
  },
  test: { environment: 'node' },
});
