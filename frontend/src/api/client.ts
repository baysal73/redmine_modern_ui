import type { AppConfig, Board, IssueForm, NewIssueOptions, IssueDetail, IssueList, IssueOptions, IssueRow, Meta } from '../types';

export function readConfig(): AppConfig {
  const el = document.getElementById('app');
  return JSON.parse(el?.dataset.config ?? '{}') as AppConfig;
}
const config = readConfig();

export class ApiError extends Error {
  constructor(public status: number, message: string, public data: any = null) { super(message); }
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? config.csrf;
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method ?? 'GET').toUpperCase();
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (method !== 'GET') { headers['Content-Type'] = 'application/json'; headers['X-CSRF-Token'] = csrfToken(); }
  const res = await fetch(`${config.base}/api/${path}`, { credentials: 'same-origin', ...init, headers });
  if (res.status === 401) { window.location.href = `${config.root}/login?back_url=${encodeURIComponent(window.location.href)}`; throw new ApiError(401, 'login'); }
  let body: any = null;
  try { body = await res.json(); } catch { /* non-JSON error page */ }
  if (!res.ok) throw new ApiError(res.status, body?.error ?? `HTTP ${res.status}`, body);
  return body as T;
}

export function toQuery(params: Record<string, string | number | undefined | null>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== '') q.set(k, String(v));
  const s = q.toString();
  return s ? `?${s}` : '';
}

export const api = {
  meta: () => request<Meta>('meta'),
  issues: (params: Record<string, string | number | undefined>) => request<IssueList>(`issues${toQuery(params)}`),
  board: (params: Record<string, string | number | undefined>) => request<Board>(`issues/board${toQuery(params)}`),
  newIssueOptions: (projectId: number) => request<NewIssueOptions>(`projects/${projectId}/new_issue_options`),
  createIssue: (issue: Record<string, unknown>) => request<{ issue: IssueRow }>('issues', { method: 'POST', body: JSON.stringify({ issue }) }),
  issue: (id: number) => request<{ issue: IssueDetail }>(`issues/${id}`),
  issueForm: (id: number) => request<IssueForm>(`issues/${id}/form`),
  issueOptions: (id: number) => request<IssueOptions>(`issues/${id}/options`),
  updateIssue: (id: number, issue: Record<string, unknown>) =>
    request<{ issue: IssueRow }>(`issues/${id}`, { method: 'PATCH', body: JSON.stringify({ issue }) }),
};
