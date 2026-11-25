// Amounts with the invoice's own currency; unknown currency codes fall back to "1,234.50 XYZ".
import { locale } from '../i18n';

export function money(value: number, currency: string): string {
  try { return new Intl.NumberFormat(locale, { style: 'currency', currency: currency || 'EUR' }).format(value); }
  catch { return `${new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)} ${currency}`; }
}
