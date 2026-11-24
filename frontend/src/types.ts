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
  statuses: Status[]; trackers: Ref[]; priorities: Ref[]; users: Ref[];
  addable_project_ids: number[];
  classic_menu: { name: string; caption: string; url: string }[];
  projects: { id: number; identifier: string; name: string; parent_id: number | null; trackers: Ref[] }[];
  settings: { per_page_options: number[]; text_formatting: string; attachment_max_size: number };
}
export interface IssueOptions { allowed_statuses: Status[]; assignees: Ref[]; priorities: Ref[]; editable: boolean }
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
