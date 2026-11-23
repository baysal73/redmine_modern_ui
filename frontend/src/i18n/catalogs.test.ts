import { describe, expect, it } from 'vitest';
import de from './de';
import en from './en';
import tr from './tr';

describe('translation catalogs', () => {
  for (const [name, cat] of [['de', de], ['tr', tr]] as const) {
    it(`${name} only contains keys that exist in en`, () => {
      expect(Object.keys(cat).filter((k) => !(k in en))).toEqual([]);
    });
    it(`${name} keeps the same placeholders as en`, () => {
      const ph = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort().join();
      for (const [k, v] of Object.entries(cat)) expect(ph(v), `${name}:${k}`).toBe(ph(en[k]));
    });
    it(`${name} translates at least 90% of the keys`, () => {
      expect(Object.keys(cat).length / Object.keys(en).length).toBeGreaterThan(0.9);
    });
  }
});
