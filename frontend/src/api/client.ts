import type { InvoiceDefaults, InvoiceForm, InvoiceDetail, InvoiceList, InvoiceOptions, ContactDetail, ContactList, ContactNote, ContactOptions, AppConfig, ReportTemplates, Home, IssueForm, NewIssueOptions, IssueDetail, IssueList, IssueOptions, IssueRow, Meta, Upload } from '../types';

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

// Multipart upload (no JSON content type); returns the token to send with the issue.
async function uploadFile(file: File): Promise<Upload> {
  const body = new FormData();
  body.append('file', file, file.name);
  const res = await fetch(`${config.base}/api/uploads`, { method: 'POST', credentials: 'same-origin', headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken() }, body });
  let data: any = null;
  try { data = await res.json(); } catch { /* non-JSON error page */ }
  if (res.status === 401) { window.location.href = `${config.root}/login?back_url=${encodeURIComponent(window.location.href)}`; throw new ApiError(401, 'login'); }
  if (!res.ok) throw new ApiError(res.status, data?.error ?? `HTTP ${res.status}`, data);
  return data.upload as Upload;
}

export const api = {
  editor: (projectId?: string | number) => request<import('../lib/ckeditor').EditorConfig>(`editor${toQuery({ project_id: projectId })}`),
  upload: uploadFile,
  reportTemplates: (params: Record<string, string | number | undefined>) => request<ReportTemplates>(`report_templates${toQuery(params)}`),
  contacts: (params: Record<string, string | number | undefined>) => request<ContactList>(`contacts${toQuery(params)}`),
  contactOptions: () => request<ContactOptions>('contacts/options'),
  contact: (id: number) => request<{ contact: ContactDetail }>(`contacts/${id}`),
  updateContact: (id: number, contact: Record<string, unknown>) => request<{ contact: ContactDetail }>(`contacts/${id}`, { method: 'PATCH', body: JSON.stringify({ contact }) }),
  createContact: (contact: Record<string, unknown>) => request<{ contact: ContactDetail }>('contacts', { method: 'POST', body: JSON.stringify({ contact }) }),
  addContactNote: (id: number, note: Record<string, unknown>) => request<{ note: ContactNote }>(`contacts/${id}/notes`, { method: 'POST', body: JSON.stringify({ note }) }),
  invoices: (params: Record<string, string | number | undefined>) => request<InvoiceList>(`invoices${toQuery(params)}`),
  invoiceOptions: () => request<InvoiceOptions>('invoices/options'),
  invoiceDefaults: (projectId: number) => request<InvoiceDefaults>(`invoices/new${toQuery({ project_id: projectId })}`),
  createInvoice: (invoice: Record<string, unknown>) => request<{ invoice: InvoiceDetail }>('invoices', { method: 'POST', body: JSON.stringify({ invoice }) }),
  invoiceForm: (id: number) => request<InvoiceForm>(`invoices/${id}/form`),
  updateInvoice: (id: number, invoice: Record<string, unknown>) => request<{ invoice: InvoiceDetail }>(`invoices/${id}`, { method: 'PATCH', body: JSON.stringify({ invoice }) }),
  addInvoicePayment: (id: number, payment: Record<string, unknown>) => request<{ invoice: InvoiceDetail }>(`invoices/${id}/payments`, { method: 'POST', body: JSON.stringify({ payment }) }),
  removeInvoicePayment: (id: number, paymentId: number, lock: string) => request<{ invoice: InvoiceDetail }>(`invoices/${id}/payments/${paymentId}${toQuery({ lock })}`, { method: 'DELETE' }),
  invoice: (id: number) => request<{ invoice: InvoiceDetail }>(`invoices/${id}`),
  home: () => request<Home>('home'),
  meta: () => request<Meta>('meta'),
  issues: (params: Record<string, string | number | undefined>) => request<IssueList>(`issues${toQuery(params)}`),
  newIssueOptions: (projectId: number) => request<NewIssueOptions>(`projects/${projectId}/new_issue_options`),
  createIssue: (issue: Record<string, unknown>) => request<{ issue: IssueRow }>('issues', { method: 'POST', body: JSON.stringify({ issue }) }),
  issue: (id: number) => request<{ issue: IssueDetail }>(`issues/${id}`),
  issueForm: (id: number) => request<IssueForm>(`issues/${id}/form`),
  issueOptions: (id: number) => request<IssueOptions>(`issues/${id}/options`),
  bulkUpdate: (ids: number[], issue: Record<string, unknown>) =>
    request<{ updated: IssueRow[]; failed: { id: number; error: string }[] }>('issues/bulk', { method: 'POST', body: JSON.stringify({ ids, issue }) }),
  updateIssue: (id: number, issue: Record<string, unknown>) =>
    request<{ issue: IssueRow }>(`issues/${id}`, { method: 'PATCH', body: JSON.stringify({ issue }) }),
};
