// Filter/sort/page state <-> URL query string (so views are shareable links).
export interface ListState {
  project: string; status: string; tracker: string; priority: string; assignee: string; due: string;
  q: string; sort: string; group: string; page: number;
}
export const defaultState: ListState = {
  project: '', status: 'open', tracker: '', priority: '', assignee: '', due: '', q: '', sort: 'updated_on:desc', group: '', page: 1,
};
export const GROUPS = ['status', 'priority', 'assigned_to', 'project', 'tracker'];
type Q = Record<string, string | (string | null)[] | null | undefined>;
const one = (v: Q[string]): string => (Array.isArray(v) ? (v[0] ?? '') : (v ?? '')) as string;

export function stateFromQuery(query: Q): ListState {
  return {
    project: one(query.project), status: one(query.status) || defaultState.status,
    tracker: one(query.tracker), priority: one(query.priority), assignee: one(query.assignee), due: one(query.due),
    q: one(query.q), sort: one(query.sort) || defaultState.sort,
    group: GROUPS.includes(one(query.group)) ? one(query.group) : '',
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
    assigned_to_id: s.assignee, due: s.due, q: s.q, sort: sortWithGroup(s), page: s.page, per_page: perPage,
  };
}

// Click on a column: same column toggles direction, new column starts ascending.
export function nextSort(current: string, column: string): string {
  const [col, dir] = current.split(':');
  if (col === column) return `${column}:${dir === 'asc' ? 'desc' : 'asc'}`;
  return `${column}:asc`;
}

// Grouping is a sort on the group column first, so every group stays contiguous across pages.
export function sortWithGroup(s: ListState): string {
  if (!s.group) return s.sort;
  const rest = s.sort.split(',').filter((part) => part.split(':')[0] !== s.group);
  return [`${s.group}:asc`, ...rest].join(',');
}

// "1,3" <-> [1, 3]; used by the multi-value filters (status ids, tracker ids, ...).
export const splitIds = (v: string): string[] => v.split(',').map((x) => x.trim()).filter(Boolean);
export const joinIds = (ids: string[]): string => ids.join(',');
