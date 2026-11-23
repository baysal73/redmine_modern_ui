<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { api } from '../api/client';
import IssueDetail from '../components/IssueDetail.vue';
import { locale, t } from '../i18n';
import { stateFromQuery, stateToQuery, type ListState } from '../lib/listQuery';
import { toast } from '../lib/toast';
import type { Board, BoardCard, IssueRow, Meta } from '../types';

const route = useRoute();
const router = useRouter();
const meta = ref<Meta | null>(null);
const board = ref<Board | null>(null);
const loading = ref(true);
const error = ref('');
const searchText = ref('');
const hideClosed = ref(safeGet('modern_ui_board_hide_closed') === '1');
function safeGet(k: string): string | null { try { return localStorage.getItem(k); } catch { return null; } }

const state = computed<ListState>(() => stateFromQuery(route.query as Record<string, string>));
const selectedId = computed(() => (route.params.id ? Number(route.params.id) : null));
function go(patch: Partial<ListState>) { router.push({ name: 'board', params: {}, query: stateToQuery({ ...state.value, ...patch }) }); }
function openIssue(id: number | null) { router.push({ name: 'board', params: { id: id ?? undefined }, query: route.query }); }

let seq = 0;
async function load() {
  const mine = ++seq;
  loading.value = true; error.value = '';
  try {
    const s = state.value;
    const res = await api.board({ project_id: s.project, tracker_id: s.tracker, priority_id: s.priority, assigned_to_id: s.assignee, q: s.q });
    if (mine === seq) board.value = res;
  } catch (e) { if (mine === seq) error.value = (e as Error).message; }
  finally { if (mine === seq) loading.value = false; }
}
watch(() => route.query, () => { searchText.value = state.value.q; load(); }, { immediate: true });
let timer: number | undefined;
function onSearch() { window.clearTimeout(timer); timer = window.setTimeout(() => go({ q: searchText.value.trim() }), 300); }
function toggleHideClosed() { hideClosed.value = !hideClosed.value; try { localStorage.setItem('modern_ui_board_hide_closed', hideClosed.value ? '1' : '0'); } catch { /* ignore */ } }

const columns = computed(() => (board.value?.columns ?? []).filter((c) => !(hideClosed.value && c.status.is_closed)));
const hidden = computed(() => (board.value ? board.value.columns.reduce((n, c) => n + Math.max(c.total - c.issues.length, 0), 0) : 0));

// ---- drag & drop (HTML5) with workflow-aware drop targets ----
const dragging = ref<BoardCard | null>(null);
const overColumn = ref<number | null>(null);
function canDrop(statusId: number): boolean { return !!dragging.value && dragging.value.status.id !== statusId && dragging.value.allowed_status_ids.includes(statusId); }
function onDragStart(e: DragEvent, card: BoardCard) {
  dragging.value = card;
  e.dataTransfer?.setData('text/plain', String(card.id));
  if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
}
function onDragEnd() { dragging.value = null; overColumn.value = null; }
function onDragOver(e: DragEvent, statusId: number) {
  if (!canDrop(statusId)) return; // no preventDefault => drop is refused by the browser
  e.preventDefault();
  overColumn.value = statusId;
}
function onDrop(e: DragEvent, statusId: number) {
  e.preventDefault();
  const card = dragging.value;
  onDragEnd();
  if (card && card.allowed_status_ids.includes(statusId)) move(card, statusId);
}

async function move(card: BoardCard, statusId: number) {
  if (card.status.id === statusId) return;
  if (!card.allowed_status_ids.includes(statusId)) { toast(t('board.not_allowed'), 'error'); return; }
  const b = board.value!;
  const from = b.columns.find((c) => c.status.id === card.status.id)!;
  const to = b.columns.find((c) => c.status.id === statusId)!;
  // optimistic update
  from.issues = from.issues.filter((i) => i.id !== card.id); from.total--;
  const moved: BoardCard = { ...card, status: to.status };
  to.issues.unshift(moved); to.total++;
  try {
    const res = await api.updateIssue(card.id, { status_id: statusId });
    const i = to.issues.findIndex((x) => x.id === card.id);
    if (i >= 0) to.issues[i] = { ...res.issue, allowed_status_ids: moved.allowed_status_ids };
    toast(t('edit.saved'));
    load(); // refresh allowed transitions (they depend on the new status)
  } catch (e) {
    to.issues = to.issues.filter((x) => x.id !== card.id); to.total--;
    from.issues.unshift(card); from.total++;
    toast(t('edit.failed', { message: (e as Error).message }), 'error');
  }
}
function onSelectMove(card: BoardCard, ev: Event) {
  const sel = ev.target as HTMLSelectElement;
  const id = Number(sel.value); sel.value = '';
  if (id) move(card, id);
}
function onDetailUpdated(row: IssueRow) {
  for (const c of board.value?.columns ?? []) { const i = c.issues.findIndex((x) => x.id === row.id); if (i >= 0) c.issues[i] = { ...c.issues[i], ...row }; }
  load();
}

const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString(locale, { day: '2-digit', month: 'short' }) : '');
const overdue = (r: IssueRow) => !!r.due_date && !r.status.is_closed && new Date(r.due_date) < new Date(new Date().toDateString());
const initials = (n: string) => n.split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase();
const projectOptions = computed(() => (meta.value?.projects ?? []).map((p) => ({ id: p.identifier, name: p.name })));
function targets(card: BoardCard) { return (board.value?.columns ?? []).filter((c) => card.allowed_status_ids.includes(c.status.id) && c.status.id !== card.status.id); }

function onKey(e: KeyboardEvent) {
  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes((e.target as HTMLElement).tagName);
  if (e.key === 'Escape' && selectedId.value && !typing) openIssue(null);
}
onMounted(async () => { window.addEventListener('keydown', onKey); try { meta.value = await api.meta(); } catch { /* shown by load */ } });
onUnmounted(() => window.removeEventListener('keydown', onKey));
</script>

<template>
  <section class="board-view">
    <div class="filters" role="search">
      <input v-model="searchText" class="search" type="search" :placeholder="t('filter.search')" :aria-label="t('filter.search')" @input="onSearch">
      <select :value="state.project" :aria-label="t('filter.project')" @change="go({ project: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.project') }}</option>
        <option v-for="p in projectOptions" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select>
      <select :value="state.tracker" :aria-label="t('col.tracker')" @change="go({ tracker: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.tracker') }}</option>
        <option v-for="x in meta?.trackers" :key="x.id" :value="String(x.id)">{{ x.name }}</option>
      </select>
      <select :value="state.assignee" :aria-label="t('col.assigned_to')" @change="go({ assignee: ($event.target as HTMLSelectElement).value })">
        <option value="">{{ t('filter.assignee') }}</option>
        <option value="me">{{ t('filter.assignee.me') }}</option>
        <option value="none">{{ t('filter.assignee.none') }}</option>
      </select>
      <span class="spacer" />
      <label class="inline muted"><input type="checkbox" :checked="hideClosed" @change="toggleHideClosed"> {{ t('board.hide_closed') }}</label>
    </div>

    <p v-if="error" class="error" role="alert">{{ t('error.load', { message: error }) }} <button class="link-btn" @click="load">{{ t('retry') }}</button></p>
    <p v-if="hidden" class="muted small">{{ t('board.more', { count: hidden }) }}</p>

    <div class="split" :class="{ open: !!selectedId }">
      <div class="board" :class="{ busy: loading }">
        <section v-for="col in columns" :key="col.status.id" class="column"
                 :class="{ 'drop-ok': dragging && canDrop(col.status.id), 'drop-no': dragging && !canDrop(col.status.id) && dragging.status.id !== col.status.id, over: overColumn === col.status.id }"
                 :aria-label="col.status.name" @dragover="onDragOver($event, col.status.id)" @dragleave="overColumn = null" @drop="onDrop($event, col.status.id)">
          <header><span class="pill" :class="col.status.is_closed ? 'pill-closed' : 'pill-open'">{{ col.status.name }}</span><span class="muted">{{ col.total }}</span></header>
          <div class="cards">
            <article v-for="c in col.issues" :key="c.id" class="card" :class="{ selected: c.id === selectedId, dragging: dragging?.id === c.id }"
                     draggable="true" tabindex="0" @dragstart="onDragStart($event, c)" @dragend="onDragEnd"
                     @click="openIssue(c.id)" @keydown.enter="openIssue(c.id)">
              <div class="card-top"><span class="muted small">#{{ c.id }} · {{ c.tracker.name }}</span>
                <span class="prio" :title="c.priority.name">{{ c.priority.name }}</span></div>
              <div class="card-title">{{ c.subject }}</div>
              <div class="card-meta">
                <span v-if="!state.project" class="muted small">{{ c.project.name }}</span>
                <span v-if="c.due_date" class="small" :class="{ overdue: overdue(c) }">📅 {{ fmtDate(c.due_date) }}</span>
                <span class="spacer" />
                <span v-if="c.assigned_to" class="avatar" :title="c.assigned_to.name">{{ initials(c.assigned_to.name) }}</span>
              </div>
              <select v-if="targets(c).length" class="move-select" :aria-label="t('board.move_to')" @click.stop @change="onSelectMove(c, $event)">
                <option value="">{{ t('board.move_to') }}</option>
                <option v-for="tc in targets(c)" :key="tc.status.id" :value="tc.status.id">{{ tc.status.name }}</option>
              </select>
            </article>
            <p v-if="!col.issues.length" class="muted small empty-col">{{ t('board.empty') }}</p>
          </div>
        </section>
      </div>
      <IssueDetail v-if="selectedId" :id="selectedId" class="split-detail" @close="openIssue(null)" @updated="onDetailUpdated" />
    </div>
  </section>
</template>
