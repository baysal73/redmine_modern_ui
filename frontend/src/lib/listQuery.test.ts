import { describe, expect, it } from 'vitest';
import { defaultState, nextSort, stateFromQuery, stateToQuery, toApiParams, splitIds, joinIds } from './listQuery';

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
  it('puts the group column first in the sort', () => {
    expect(toApiParams({ ...defaultState, group: 'status', sort: 'due_date:asc' }, 25).sort).toBe('status:asc,due_date:asc');
    expect(toApiParams({ ...defaultState, group: 'status', sort: 'status:desc,id:asc' }, 25).sort).toBe('status:asc,id:asc');
    expect(toApiParams(defaultState, 25).sort).toBe('updated_on:desc');
  });
  it('rejects unknown group columns', () => {
    expect(stateFromQuery({ group: 'author_id; drop' }).group).toBe('');
  });
  it('splits and joins multi values', () => {
    expect(splitIds('1, 2,,3')).toEqual(['1', '2', '3']);
    expect(joinIds(['1', '2'])).toBe('1,2');
  });
  it('toggles sort', () => {
    expect(nextSort('id:asc', 'id')).toBe('id:desc');
    expect(nextSort('id:desc', 'id')).toBe('id:asc');
    expect(nextSort('id:desc', 'subject')).toBe('subject:asc');
  });
});
