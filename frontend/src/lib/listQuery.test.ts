import { describe, expect, it } from 'vitest';
import { defaultState, nextSort, stateFromQuery, stateToQuery, toApiParams } from './listQuery';

describe('listQuery', () => {
  it('round-trips non-default values only', () => {
    const s = { ...defaultState, status: 'all', q: 'banner', page: 3 };
    expect(stateToQuery(s)).toEqual({ status: 'all', q: 'banner', page: '3' });
    expect(stateFromQuery(stateToQuery(s))).toEqual(s);
  });
  it('uses defaults for an empty query', () => {
    expect(stateFromQuery({})).toEqual(defaultState);
    expect(stateToQuery(defaultState)).toEqual({});
  });
  it('ignores invalid page numbers', () => {
    expect(stateFromQuery({ page: 'abc' }).page).toBe(1);
    expect(stateFromQuery({ page: '-4' }).page).toBe(1);
  });
  it('maps to API params', () => {
    expect(toApiParams({ ...defaultState, assignee: 'none' }, 25).assigned_to_id).toBe('none');
  });
  it('toggles sort', () => {
    expect(nextSort('id:asc', 'id')).toBe('id:desc');
    expect(nextSort('id:desc', 'id')).toBe('id:asc');
    expect(nextSort('id:desc', 'subject')).toBe('subject:asc');
  });
});
