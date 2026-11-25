import type { AppConfig } from '../types';

// Company colours from the plugin settings. They only set CSS variables; styles.css decides where they are used.
export function applyBrand(config: AppConfig): void {
  const b = config.brand;
  if (!b) return;
  const root = document.documentElement.style;
  if (b.primary) root.setProperty('--brand-primary', b.primary);
  if (b.gold) root.setProperty('--brand-gold', b.gold);
  if (b.grey) {
    root.setProperty('--brand-grey', b.grey);
    root.setProperty('--brand-border', `color-mix(in srgb, ${b.grey} 32%, #ffffff)`);
  }
}

export function logoUrl(config: AppConfig): string | null {
  return config.brand?.logo ? `${config.base}/api/logo?v=${config.brand.logo}` : null;
}
