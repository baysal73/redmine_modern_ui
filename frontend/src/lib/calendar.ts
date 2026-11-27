// Date helpers and day buckets shared by the calendar screen and the calendar widgets on the start page.
// Dates are plain YYYY-MM-DD strings; the server already delivers event times in the user's time zone.
import type { CalendarData, CalEvent, CalIssue } from '../types';

export const pad = (n: number) => String(n).padStart(2, '0');
export const iso = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
export const parse = (s: string) => { const [y, m, d] = s.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
export const addDays = (s: string, n: number) => { const d = parse(s); d.setUTCDate(d.getUTCDate() + n); return iso(d); };
export const todayIso = () => { const n = new Date(); return `${n.getFullYear()}-${pad(n.getMonth() + 1)}-${pad(n.getDate())}`; };
// Monday of the week that contains the day
export const weekStart = (s: string) => addDays(s, -((parse(s).getUTCDay() + 6) % 7));

export interface CalItem { key: string; kind: 'event' | 'issue'; label: string; time: string; color: string; ev?: CalEvent; issue?: CalIssue; first: string; last: string }

export function evRange(e: CalEvent): [string, string] {
  if (e.all_day) return [e.start_date!, e.end_date!];
  const first = e.starts_at!.slice(0, 10);
  let last = e.ends_at!.slice(0, 10);
  if (last > first && e.ends_at!.slice(11, 16) === '00:00') last = addDays(last, -1);
  return [first, last < first ? first : last];
}

export function calItems(data: CalendarData | null): CalItem[] {
  const out: CalItem[] = [];
  for (const e of data?.events ?? []) { const [first, last] = evRange(e); out.push({ key: 'e' + e.id, kind: 'event', label: e.title, time: e.all_day ? '' : e.starts_at!.slice(11, 16), color: e.color, ev: e, first, last }); }
  for (const i of data?.issues ?? []) { const first = i.start_date ?? i.due_date!; const last = i.due_date ?? first; out.push({ key: 'i' + i.id, kind: 'issue', label: `#${i.id} ${i.subject}`, time: '', color: i.color, issue: i, first, last: last < first ? first : last }); }
  return out;
}

// Items per day between from and to (inclusive); all-day entries first, then by start time
export function byDay(items: CalItem[], from: string, to: string): Map<string, CalItem[]> {
  const m = new Map<string, CalItem[]>();
  for (const it of items) for (let d = it.first < from ? from : it.first; d <= it.last && d <= to; d = addDays(d, 1)) { if (!m.has(d)) m.set(d, []); m.get(d)!.push(it); }
  for (const list of m.values()) list.sort((a, b) => Number(!!b.ev?.all_day) - Number(!!a.ev?.all_day) || a.time.localeCompare(b.time));
  return m;
}
