import { describe, it, expect } from 'vitest';
import { computeScore, type DriveEvent } from './scoring';
import { SCENARIOS, TOGGLE_EVENT_ID } from '../data/scenarios';

const byId = (id: string) => SCENARIOS.find((s) => s.id === id)!;
const score = (id: string) => computeScore(byId(id)).score;

describe('illustrative scoring', () => {
  it('matches expected scenario scores', () => {
    expect(score('smooth')).toBe(98);
    expect(score('mixed')).toBe(88);
    expect(score('attention')).toBe(54);
  });
  it('returns null when data is insufficient', () => {
    const r = computeScore(byId('insufficient'));
    expect(r.score).toBeNull();
    expect(r.reason).toMatch(/More data needed/);
  });
  it('excluding the medium brake moves mixed from 88 to 91 without changing distance', () => {
    const s = byId('mixed');
    const events = s.events.map((e) => (e.id === TOGGLE_EVENT_ID ? { ...e, review: 'excluded' as const } : e));
    expect(computeScore({ ...s, events }).score).toBe(91);
    expect(s.miles).toBe(86);
  });
  it('counts duplicate IDs once', () => {
    const s = byId('mixed');
    const dup = s.events.find((e) => e.id === 'mx-b2')!;
    expect(computeScore({ ...s, events: [...s.events, dup, dup] }).score).toBe(88);
  });
  it('rejects invalid inputs without NaN', () => {
    for (const miles of [-5, NaN, Infinity]) {
      const r = computeScore({ miles, trips: 5, events: [] });
      expect(r.score).toBeNull();
    }
    const bad: DriveEvent = { id: 'x', tripId: 't', type: 'overspeed', time: '', severity: 'low', quality: 'good', review: 'accepted', note: '', at: 0, minutes: -3 };
    expect(computeScore({ miles: 100, trips: 5, events: [bad] }).score).toBe(100);
  });
  it('handles zero distance safely', () => {
    const r = computeScore({ miles: 0, trips: 4, events: byId('attention').events });
    expect(r.score).toBeNull();
    expect(Object.values(r.penalties).every(Number.isFinite)).toBe(true);
  });
});
