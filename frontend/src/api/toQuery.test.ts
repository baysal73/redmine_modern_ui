import { describe, expect, it } from 'vitest';

// client.ts reads the DOM at import time, so provide a minimal document first.
describe('toQuery', () => {
  it('skips empty values and encodes the rest', async () => {
    (globalThis as any).document = { getElementById: () => ({ dataset: { config: '{"base":"/app","root":""}' } }), querySelector: () => null };
    const { toQuery } = await import('./client');
    expect(toQuery({ a: 1, b: '', c: undefined, d: 'x y' })).toBe('?a=1&d=x+y');
    expect(toQuery({})).toBe('');
  });
});
