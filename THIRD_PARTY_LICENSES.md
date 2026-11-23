# Third-party software

The built frontend (`assets/javascripts/app.js`) bundles the following runtime libraries. All licenses are
compatible with the GPL-2.0-or-later.

| Package | License |
|---|---|
| vue, @vue/* | MIT |
| vue-router, @vue/devtools-api | MIT |
| @babel/parser, @babel/types, @babel/helper-* (compiler only) | MIT |
| csstype, magic-string, nanoid, postcss, @jridgewell/sourcemap-codec | MIT |
| lucide-vue-next (icons, only the icons in use are bundled) | ISC |
| source-map-js | BSD-3-Clause |
| picocolors | ISC |

Build and test tools (Vite, TypeScript, Vitest, vue-tsc, Tailwind CSS 3 [MIT], PostCSS [MIT], Autoprefixer [MIT]) are only used during development. Tailwind only generates the stylesheet at build time; no Tailwind code is shipped.
