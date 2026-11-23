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
  statuses: Status[]; trackers: Ref[]; priorities: Ref[];
  projects: { id: number; identifier: string; name: string; parent_id: number | null; trackers: Ref[] }[];
  settings: { per_page_options: number[]; text_formatting: string };
}
export interface IssueOptions { allowed_statuses: Status[]; assignees: Ref[]; priorities: Ref[]; editable: boolean }
export interface AppConfig { base: string; root: string; lang: string; csrf: string }
