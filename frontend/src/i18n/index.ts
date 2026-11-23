import { readConfig } from '../api/client';
import de from './de';
import en from './en';
import tr from './tr';

// To add a language: copy en.ts to xx.ts, translate, and register it here.
const catalogs: Record<string, Record<string, string>> = { en, de, tr };
const lang = (readConfig().lang || 'en').toLowerCase();
const messages = catalogs[lang] ?? catalogs[lang.split('-')[0]] ?? en;

export function t(key: string, vars: Record<string, string | number> = {}): string {
  const text = messages[key] ?? en[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ''));
}
export const locale = catalogs[lang] ? lang : (catalogs[lang.split('-')[0]] ? lang.split('-')[0] : 'en');
