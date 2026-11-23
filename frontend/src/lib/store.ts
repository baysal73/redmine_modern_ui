import { reactive } from 'vue';
import { api } from '../api/client';
import type { Meta } from '../types';

// Reference data (statuses, trackers, projects, menu…) is loaded once and shared by all views.
export const store = reactive<{ meta: Meta | null; loading: Promise<Meta> | null }>({ meta: null, loading: null });

export function loadMeta(force = false): Promise<Meta> {
  if (!force && store.meta) return Promise.resolve(store.meta);
  if (!store.loading) {
    store.loading = api.meta().then((m) => { store.meta = m; return m; }).finally(() => { store.loading = null; });
  }
  return store.loading;
}
