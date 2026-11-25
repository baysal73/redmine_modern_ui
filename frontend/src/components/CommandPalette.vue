<script setup lang="ts">
// Ctrl/⌘ + K: one search over issues, contacts, invoices and projects, plus quick navigation.
import { Building2, CalendarCheck, FolderKanban, ListChecks, Package, Receipt, Users, CalendarDays } from 'lucide-vue-next';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { api, readConfig } from '../api/client';
import { t } from '../i18n';
import { trapFocus } from '../lib/dialog';
import { store } from '../lib/store';
import { ui } from '../lib/ui';

interface Item { key: string; group: string; label: string; hint: string; icon: unknown; run: () => void }
const router = useRouter();
const config = readConfig();
const root = ref<HTMLElement | null>(null);
const input = ref<HTMLInputElement | null>(null);
const query = ref('');
const found = ref<Item[]>([]);
const busy = ref(false);
const active = ref(0);
let release: (() => void) | null = null;
const close = () => { ui.palette = false; };
const go = (path: string) => () => { close(); router.push(path); };

const features = computed(() => store.meta?.features);
const nav = computed<Item[]>(() => [
  { key: 'n-home', group: 'palette.go', label: t('nav.home'), hint: 'g h', icon: CalendarCheck, run: go('/home') },
  { key: 'n-issues', group: 'palette.go', label: t('nav.issues'), hint: 'g i', icon: ListChecks, run: go('/issues') },
  ...(features.value?.contacts ? [{ key: 'n-contacts', group: 'palette.go', label: t('nav.contacts'), hint: 'g k', icon: Users, run: go('/contacts') }] : []),
  ...(features.value?.invoices ? [{ key: 'n-invoices', group: 'palette.go', label: t('nav.invoices'), hint: 'g r', icon: Receipt, run: go('/invoices') }] : []),
  ...(features.value?.calendar ? [{ key: 'n-calendar', group: 'palette.go', label: t('nav.calendar'), hint: 'g c', icon: CalendarDays, run: go('/calendar') }] : []),
  ...(features.value?.products ? [{ key: 'n-products', group: 'palette.go', label: t('nav.products'), hint: 'g p', icon: Package, run: go('/products') }] : []),
  { key: 'n-new', group: 'palette.go', label: t('create.button'), hint: 'c', icon: ListChecks, run: () => { close(); ui.quickCreate = true; } },
]);
const projectHits = computed<Item[]>(() => {
  const q = query.value.trim().toLowerCase();
  if (q.length < 2) return [];
  return (store.meta?.projects ?? []).filter((p) => p.name.toLowerCase().includes(q) || p.identifier.includes(q)).slice(0, 5)
    .map((p) => ({ key: 'p' + p.id, group: 'palette.projects', label: p.name, hint: p.identifier, icon: FolderKanban, run: () => { window.location.href = `${config.root}/projects/${p.identifier}`; } }));
});
const items = computed<Item[]>(() => {
  const q = query.value.trim().toLowerCase();
  if (q.length < 2) return nav.value.filter((n) => !q || n.label.toLowerCase().includes(q));
  return [...found.value, ...projectHits.value];
});
const grouped = computed(() => {
  const out: { group: string; items: { item: Item; index: number }[] }[] = [];
  items.value.forEach((item, index) => {
    let g = out.find((x) => x.group === item.group);
    if (!g) { g = { group: item.group, items: [] }; out.push(g); }
    g.items.push({ item, index });
  });
  return out;
});

let seq = 0; let timer: number | undefined;
watch(query, (v) => {
  active.value = 0;
  window.clearTimeout(timer);
  const q = v.trim();
  if (q.length < 2) { found.value = []; busy.value = false; return; }
  busy.value = true;
  timer = window.setTimeout(() => search(q), 200);
});
async function search(q: string) {
  const mine = ++seq;
  const num = /^#?(\d+)$/.exec(q);
  const jobs = await Promise.allSettled([
    api.issues({ q, status: 'all', per_page: 6, sort: 'updated_on:desc' }),
    features.value?.contacts ? api.contacts({ q, per_page: 5, sort: 'updated_on:desc' }) : Promise.resolve(null),
    features.value?.invoices ? api.invoices({ q, status: 'all', per_page: 5 }) : Promise.resolve(null),
    features.value?.products ? api.products({ q, per_page: 5 }) : Promise.resolve(null),
  ]);
  if (mine !== seq) return;
  const out: Item[] = [];
  if (num) out.push({ key: 'i-open', group: 'palette.issues', label: `#${num[1]}`, hint: t('palette.open_id'), icon: ListChecks, run: go(`/issues/${num[1]}`) });
  const [iss, con, inv, prod] = jobs.map((j) => (j.status === 'fulfilled' ? j.value : null)) as any[];
  for (const i of iss?.issues ?? []) out.push({ key: 'i' + i.id, group: 'palette.issues', label: `#${i.id} ${i.subject}`, hint: `${i.project.name} · ${i.status.name}`, icon: ListChecks, run: go(`/issues/${i.id}`) });
  for (const c of con?.contacts ?? []) out.push({ key: 'c' + c.id, group: 'palette.contacts', label: c.name, hint: c.company || c.email, icon: c.is_company ? Building2 : Users, run: go(`/contacts/${c.id}`) });
  for (const v of inv?.invoices ?? []) out.push({ key: 'v' + v.id, group: 'palette.invoices', label: v.number, hint: `${v.contact?.name ?? ''} · ${v.status.name}`, icon: Receipt, run: go(`/invoices/${v.id}`) });
  for (const x of prod?.products ?? []) out.push({ key: 'p' + x.id, group: 'palette.products', label: x.name, hint: [x.code, x.category].filter(Boolean).join(' · '), icon: Package, run: go(`/products/${x.id}`) });
  found.value = out; busy.value = false;
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'ArrowDown') { e.preventDefault(); active.value = Math.min(active.value + 1, items.value.length - 1); scrollActive(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); active.value = Math.max(active.value - 1, 0); scrollActive(); }
  else if (e.key === 'Enter') { e.preventDefault(); items.value[active.value]?.run(); }
}
function scrollActive() { requestAnimationFrame(() => root.value?.querySelector('.pal-item.on')?.scrollIntoView({ block: 'nearest' })); }
onMounted(() => { release = trapFocus(root.value!, close); input.value?.focus(); });
onUnmounted(() => { release?.(); window.clearTimeout(timer); seq++; });
</script>

<template>
  <div class="overlay pal-overlay" @mousedown.self="close">
    <div ref="root" class="dialog pal" role="dialog" aria-modal="true" :aria-label="t('palette.title')">
      <input ref="input" v-model="query" class="pal-input" type="search" :placeholder="t('palette.placeholder')" :aria-label="t('palette.placeholder')"
             role="combobox" aria-expanded="true" aria-controls="pal-list" @keydown="onKey">
      <div id="pal-list" class="pal-list" role="listbox">
        <p v-if="busy" class="muted small px-2 py-1">…</p>
        <p v-else-if="query.trim().length >= 2 && !items.length" class="muted small px-2 py-1">{{ t('palette.none') }}</p>
        <template v-for="g in grouped" :key="g.group">
          <p class="pal-group">{{ t(g.group) }}</p>
          <button v-for="x in g.items" :key="x.item.key" class="pal-item" :class="{ on: x.index === active }" role="option" :aria-selected="x.index === active"
                  @mousemove="active = x.index" @click="x.item.run()">
            <component :is="x.item.icon" :size="15" aria-hidden="true" /><span class="pal-label">{{ x.item.label }}</span><span class="muted small pal-hint">{{ x.item.hint }}</span>
          </button>
        </template>
      </div>
    </div>
  </div>
</template>

<style>
.pal-overlay { align-items: flex-start; padding-top: 12vh; }
.pal { width: min(620px, 94vw); padding: 0; overflow: hidden; }
.pal-input { width: 100%; font: inherit; font-size: 1.05rem; color: var(--fg); background: transparent; border: 0; border-bottom: 1px solid var(--border); padding: 14px 16px; outline: 0; }
.pal-list { max-height: 55vh; overflow-y: auto; padding: 6px; }
.pal-group { margin: 8px 8px 2px; font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--muted); }
.pal-item { display: flex; align-items: center; gap: 10px; width: 100%; text-align: left; font: inherit; color: var(--fg); background: none; border: 0; border-radius: 8px; padding: 8px 10px; cursor: pointer; }
.pal-item.on { background: var(--hover); }
.pal-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pal-hint { white-space: nowrap; max-width: 45%; overflow: hidden; text-overflow: ellipsis; }
</style>
