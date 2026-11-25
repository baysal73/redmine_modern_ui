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
  features?: { contacts: boolean; invoices: boolean; invoices_add?: boolean };
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
  custom_fields: CustomFieldForm[];
  deals: { id: number; name: string; status: string | null; price: number | null; currency: string | null; project: string | null }[];
  issues: { id: number; subject: string; status: Status; project: string }[]; notes: ContactNote[];
}
export interface ContactOptions { can_add: boolean; projects: { id: number; identifier: string; name: string }[]; custom_fields: { id: number; name: string; values: string[] }[]; assignees: Ref[] }
export interface InvoiceRow {
  id: number; number: string; subject: string; invoice_date: string | null; due_date: string | null; status: Ref; currency: string;
  amount: number; balance: number; remaining: number; overdue: boolean; contact: Ref | null; project: string;
}
export interface InvoiceList { invoices: InvoiceRow[]; total: number; page: number; per_page: number; pages: number; sums: { currency: string; amount: number; open: number }[] }
export interface InvoiceDetail extends InvoiceRow {
  lock: string; assigned_to_id: number | null; project_identifier: string; description: string; order_number: string; paid_date: string | null; discount: number;
  assigned_to: Ref | null; author: Ref | null; contact_visible: boolean; can_edit: boolean; can_delete: boolean; can_pay: boolean;
  subtotal: number; tax_amount: number; discount_amount: number;
  lines: { id: number; description: string; quantity: number; units: string; price: number; tax: number | null; discount: number | null; total: number }[];
  payments: { id: number; date: string | null; amount: number; description: string; can_remove: boolean }[];
}
export interface InvoiceForm { statuses: Ref[]; assignees: Ref[]; finance: { enabled: boolean; accounts: Ref[]; categories: Ref[] } }
export interface InvoiceOptions { statuses: Ref[]; projects: { id: number; identifier: string; name: string }[]; addable_projects: { id: number; identifier: string; name: string }[] }
export interface InvoiceDefaults { number: string; invoice_date: string; currency: string; currencies: string[]; tax: number; statuses: Ref[]; assignees: Ref[]; assigned_to_id: number }
export interface AppConfig { base: string; root: string; lang: string; csrf: string }

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

export interface Upload { token: string; filename: string; filesize: number; content_type?: string }
