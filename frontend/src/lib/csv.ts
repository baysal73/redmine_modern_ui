// Downloads rows as CSV (semicolon-separated with a BOM, so Excel in German locales opens it with the right columns and umlauts).
export function downloadCsv(filename: string, header: string[], rows: (string | number | null | undefined)[][]): void {
  const cell = (v: string | number | null | undefined) => { const s = v == null ? '' : String(v); return /[";\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const text = [header, ...rows].map((r) => r.map(cell).join(';')).join('\r\n');
  const url = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
