export interface Ref { id: number; name: string }
export interface Status extends Ref { is_closed: boolean }
export interface IssueRow {
  id: number; subject: string;
  project: Ref; tracker: Ref; status: Status; priority: Ref;
  author: Ref | null; assigned_to: Ref | null;
  start_date: string | null; due_date: string | null; done_ratio: number;
  created_on: string; updated_on: string; closed_on: string | null; is_private: boolean;
}
export interface IssueList { issues: IssueRow[]; total: number; page: number; per_page: number; pages: number }
export interface Meta {
  user: { id: number; name: string; admin: boolean; language: string };
  features?: { contacts: boolean; invoices: boolean; invoices_add?: boolean; products?: boolean; products_add?: boolean; calendar?: boolean; calendar_add?: boolean; contacts_add?: boolean; documents?: boolean; documents_add?: boolean };
  statuses: Status[]; trackers: Ref[]; priorities: Ref[]; users: Ref[];
  addable_project_ids: number[];
  classic_menu: { name: string; caption: string; url: string }[];
  projects: { id: number; identifier: string; name: string; parent_id: number | null; trackers: Ref[] }[];
  settings: { per_page_options: number[]; text_formatting: string; attachment_max_size: number };
}
export interface IssueOptions { allowed_statuses: Status[]; assignees: Ref[]; priorities: Ref[]; editable: boolean }
export interface ReportTemplates { available: boolean; can_preview: boolean; can_generate: boolean; templates: { id: number; name: string; description: string }[] }
export interface ContactRow { id: number; name: string; is_company: boolean; company: string; job_title: string; email: string; phone: string; city: string; assigned_to: Ref | null; updated_on: string }
export interface ContactList { contacts: ContactRow[]; total: number; page: number; per_page: number; pages: number }
export interface ContactNote { id: number; author: Ref | null; created_on: string; type_id: number | null; subject: string; content_html: string }
export interface ContactDetail {
  id: number; name: string; is_company: boolean; editable: boolean; can_add_note: boolean; project_id: string | null;
  projects: { id: number; identifier: string; name: string }[];
  values: Record<string, string | number | null | string[]>; address: Record<string, string>;
  assignees: Ref[]; assigned_to: Ref | null; author: Ref | null; created_on: string; updated_on: string; avatar_url: string | null;
  company_contact: Ref | null; employees: { id: number; name: string; job_title: string }[];
  custom_fields: CustomFieldForm[]; background_html: string;
  deals: { id: number; name: string; status: string | null; price: number | null; currency: string | null; project: string | null }[];
  issues: { id: number; subject: string; status: Status; project: string }[]; notes: ContactNote[];
  timeline: { kind: 'note' | 'issue' | 'invoice' | 'event'; id: number; date: string; title: string; meta: string; day?: string; day_only?: boolean }[];
}
export interface ContactOptions { can_add: boolean; projects: { id: number; identifier: string; name: string }[]; custom_fields: { id: number; name: string; values: string[] }[]; assignees: Ref[] }
export interface InvoiceRow {
  id: number; number: string; subject: string; invoice_date: string | null; due_date: string | null; status: Ref; currency: string;
  amount: number; balance: number; remaining: number; overdue: boolean; contact: Ref | null; project: string;
}
export interface InvoiceList { invoices: InvoiceRow[]; total: number; page: number; per_page: number; pages: number; sums: { currency: string; amount: number; open: number }[] }
export interface InvoiceDetail extends InvoiceRow {
  lock: string; assigned_to_id: number | null; project_identifier: string; description: string; order_number: string; paid_date: string | null; discount: number;
  assigned_to: Ref | null; author: Ref | null; contact_visible: boolean; can_edit: boolean; can_delete: boolean; can_send?: boolean; can_pay: boolean;
  subtotal: number; tax_amount: number; discount_amount: number;
  lines: { id: number; description: string; quantity: number; units: string; price: number; tax: number | null; discount: number | null; total: number }[];
  payments: { id: number; date: string | null; amount: number; description: string; can_remove: boolean }[];
}
export interface InvoiceForm { statuses: Ref[]; assignees: Ref[]; finance: { enabled: boolean; accounts: Ref[]; categories: Ref[] } }
export interface InvoiceOptions { statuses: Ref[]; projects: { id: number; identifier: string; name: string }[]; addable_projects: { id: number; identifier: string; name: string }[] }
export interface InvoiceDefaults { number: string; invoice_date: string; currency: string; currencies: string[]; tax: number; statuses: Ref[]; assignees: Ref[]; assigned_to_id: number }
export interface AppConfig { base: string; root: string; lang: string; csrf: string; brand?: { primary: string | null; gold: string | null; grey: string | null; logo: string | null } }

export interface JournalDetail { property: string; name: string; text: string }
export interface Journal {
  id: number; index: number; user: Ref | null; created_on: string; private_notes: boolean;
  notes_html: string; details: JournalDetail[];
}
export interface Attachment { id: number; filename: string; filesize: number; content_type: string | null; author: Ref | null; created_on: string; description: string }
export interface IssueDetail extends IssueRow {
  description_html: string; parent_id: number | null; fixed_version: Ref | null; category: Ref | null; estimated_hours: number | null;
  allowed_statuses: Status[];
  permissions: { edit: boolean; comment: boolean; private_notes: boolean; delete: boolean };
  custom_fields: { id: number; name: string; value: string }[];
  attachments: Attachment[]; journals: Journal[];
}


export interface NewIssueOptions { trackers: Ref[]; priorities: (Ref & { is_default: boolean })[]; assignees: Ref[] }

export interface CustomFieldForm {
  id: number; name: string; format: string; kind: string; multiple: boolean; required: boolean; description: string;
  value: string | string[]; options: { label: string; value: string }[];
  file?: { id: number; filename: string; filesize: number; content_type: string; url: string } | null;
}
export interface IssueForm {
  project_id: string;
  values: Record<string, string | number | boolean | null>;
  editable: string[]; required: string[]; description_as_text: boolean;
  options: { statuses: Status[]; priorities: Ref[]; assignees: Ref[]; categories: Ref[]; versions: Ref[] };
  custom_fields: CustomFieldForm[];
}

export interface Home {
  today: string; overdue: IssueRow[]; due_soon: IssueRow[]; undated: IssueRow[]; recent: IssueRow[];
  counts: { overdue: number; due_soon: number; undated: number; assigned_open: number };
}

// One widget on the start page; the layout is stored per user on the server
export type WidgetType = 'stats' | 'overdue' | 'due_soon' | 'undated' | 'assigned' | 'reported' | 'watched' | 'recent' | 'query' | 'cal_day' | 'cal_week';
export type WidgetSize = 's' | 'm' | 'l' | 'full';
export interface HomeWidget { id: string; type: WidgetType; size: WidgetSize; limit?: number; query_id?: number }

export interface Upload { token: string; filename: string; filesize: number; content_type?: string }

export interface ProductRow { id: number; code: string; name: string; status: Ref; category: string | null; price: number | null; currency: string; project: string; bundle: boolean; image_url: string | null; updated_at: string }
export interface ProductList { products: ProductRow[]; total: number; page: number; per_page: number; pages: number }
export interface ProductDetail extends ProductRow {
  project_identifier: string; description: string; category_id: number | null; tag_list: string[]; created_at: string; author: Ref | null;
  can_edit: boolean; can_delete: boolean; used: boolean; bundle_items: { id: number; name: string; quantity: number }[];
}
export interface ProductOptions { can_add: boolean; projects: { id: number; identifier: string; name: string }[]; categories: Ref[]; statuses: Ref[]; currencies: string[]; default_currency: string; default_status_id: number }

export interface CalEvent {
  id: number; title: string; description: string | null; location: string | null; all_day: boolean; category: string | null;
  start_date?: string; end_date?: string; starts_at?: string; ends_at?: string; color: string; google: boolean;
  project: { id: number; name: string } | null; contact: { id: number; name: string } | null; project_id: number | null;
}
export interface CalIssue { id: number; subject: string; tracker: string; status: string; project: string; start_date: string | null; due_date: string | null; assigned_to: string | null; color: string }
export interface CalendarData {
  from: string; to: string; can_manage: boolean; time_zone: string; google: { enabled: boolean; admin: boolean };
  categories: { name: string; color: string }[]; events: CalEvent[]; issues: CalIssue[];
}

export interface BulkResult { done: number; failed: { id: number; name: string; error: string }[] }

export interface DocFolder { id: number; title: string; description: string; locked: boolean; updated_at: string | null; author: string | null; files: number; folders: number }
export interface DocFile { id: number; name: string; title: string; size: number; version: string; updated_at: string | null; author: string | null; locked: boolean; download_url: string; view_url: string; classic_url: string; description?: string; comment?: string }
export interface DocRevision { id: number; name: string; version: string; size: number; author: string | null; created_at: string | null; comment: string; description: string; download_url: string }
export interface DocFileDetail extends DocFile { path: { id: number; title: string }[]; project: { id: number; identifier: string; name: string }; revisions: DocRevision[]; can_delete: boolean }
export interface DocList {
  project: { id: number; identifier: string; name: string };
  folder: { id: number; title: string; parent_id: number | null } | null;
  path: { id: number; title: string }[];
  folders: DocFolder[]; files: DocFile[]; truncated: boolean;
  can: { upload: boolean; folder: boolean; delete_file: boolean; delete_folder: boolean };
}
export interface DocUploadResult { done: number; files: { id: number; name: string }[]; failed: { name: string; error: string }[] }

export interface FilterDef {
  name: string; label: string; type: string; remote: boolean;
  operators: { id: string; label: string }[]; values: { label: string; value: string }[] | null;
}
export interface AdvFilter { field: string; op: string; values: string[] }
export interface SavedQuery { id: number; name: string; project: string | null; state: Record<string, string> }
