// Filter/sort/page state <-> URL query string (so views are shareable links).
export interface ListState {
  project: string; status: string; tracker: string; priority: string; assignee: string;
  q: string; sort: string; page: number;
}
export const defaultState: ListState = {
  project: '', status: 'open', tracker: '', priority: '', assignee: '', q: '', sort: 'updated_on:desc', page: 1,
};
type Q = Record<string, string | (string | null)[] | null | undefined>;
const one = (v: Q[string]): string => (Array.isArray(v) ? (v[0] ?? '') : (v ?? '')) as string;

export function stateFromQuery(query: Q): ListState {
  return {
    project: one(query.project), status: one(query.status) || defaultState.status,
    tracker: one(query.tracker), priority: one(query.priority), assignee: one(query.assignee),
    q: one(query.q), sort: one(query.sort) || defaultState.sort,
    page: Math.max(parseInt(one(query.page), 10) || 1, 1),
  };
}

// Only non-default values go into the URL.
export function stateToQuery(s: ListState): Record<string, string> {
  const out: Record<string, string> = {};
  (Object.keys(defaultState) as (keyof ListState)[]).forEach((k) => {
    if (String(s[k]) !== String(defaultState[k]) && String(s[k]) !== '') out[k] = String(s[k]);
  });
  return out;
}

export function toApiParams(s: ListState, perPage: number) {
  return {
    project_id: s.project, status: s.status, tracker_id: s.tracker, priority_id: s.priority,
    assigned_to_id: s.assignee, q: s.q, sort: s.sort, page: s.page, per_page: perPage,
  };
}

// Click on a column: same column toggles direction, new column starts ascending.
export function nextSort(current: string, column: string): string {
  const [col, dir] = current.split(':');
  if (col === column) return `${column}:${dir === 'asc' ? 'desc' : 'asc'}`;
  return `${column}:asc`;
}
