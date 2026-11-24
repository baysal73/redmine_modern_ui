// Loads the CKEditor that Redmine's redmine_ckeditor plugin ships, on demand (it is large and only needed when
// someone writes text). The server tells us whether it is active (api/editor); otherwise callers use a textarea.
import { api } from '../api/client';

export interface EditorConfig {
  kind: 'plain' | 'ckeditor';
  basepath?: string; script?: string;
  plugins?: { name: string; path: string }[];
  options?: Record<string, unknown>;
  mentions?: unknown[];
}
/* eslint-disable @typescript-eslint/no-explicit-any */
type CK = any;

const configs = new Map<string, Promise<EditorConfig>>();
let scriptLoaded: Promise<CK> | null = null;

export function editorConfig(projectId?: string | number | null): Promise<EditorConfig> {
  const key = String(projectId ?? '');
  if (!configs.has(key)) {
    const p = api.editor(projectId ?? undefined);
    p.catch(() => configs.delete(key)); // retry next time
    configs.set(key, p);
  }
  return configs.get(key)!;
}

function loadScript(cfg: EditorConfig): Promise<CK> {
  const w = window as any;
  if (w.CKEDITOR?.replace) return Promise.resolve(w.CKEDITOR);
  if (!scriptLoaded) {
    w.CKEDITOR_BASEPATH = cfg.basepath;
    scriptLoaded = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = cfg.script!;
      s.onload = () => {
        (cfg.plugins ?? []).forEach((p) => w.CKEDITOR.plugins.addExternal(p.name, p.path));
        resolve(w.CKEDITOR);
      };
      s.onerror = () => { scriptLoaded = null; reject(new Error('CKEditor could not be loaded')); };
      document.head.appendChild(s);
    });
  }
  return scriptLoaded;
}

// Returns the CKEditor global, or null when the plain textarea should be used.
export async function loadCkeditor(projectId?: string | number | null): Promise<{ ck: CK; options: Record<string, unknown> } | null> {
  const cfg = await editorConfig(projectId);
  if (cfg.kind !== 'ckeditor') return null;
  (window as any).CKEditor = { ...((window as any).CKEditor ?? {}), mentionsConfig: cfg.mentions ?? [] };
  const ck = await loadScript(cfg);
  return { ck, options: cfg.options ?? {} };
}

// "<p>&nbsp;</p>" or only tags/whitespace counts as empty (images and embeds count as content)
export function hasContent(html: string): boolean {
  if (/<(img|iframe|table|hr)\b/i.test(html)) return true;
  return html.replace(/<[^>]*>|&nbsp;|\s/g, '') !== '';
}
