import { computed, ref } from 'vue';

// Row selection for the list views (checkbox column + bulk bar).
export function useSelection(ids: () => number[]) {
  const selected = ref<Set<number>>(new Set());
  const allSelected = computed(() => ids().length > 0 && ids().every((id) => selected.value.has(id)));
  function toggle(id: number) { const n = new Set(selected.value); if (n.has(id)) n.delete(id); else n.add(id); selected.value = n; }
  function toggleAll() { selected.value = allSelected.value ? new Set() : new Set(ids()); }
  function set(list: number[]) { selected.value = new Set(list); }
  function clear() { selected.value = new Set(); }
  return { selected, allSelected, toggle, toggleAll, set, clear, count: computed(() => selected.value.size) };
}
