// Illustrative scoring model for the presentation demo. Thresholds and weights are prototype
// choices, not validated constants. Pure functions only: no UI state.

export type EventType = 'braking' | 'acceleration' | 'overspeed' | 'cornering';
export type Severity = 'low' | 'medium' | 'high';
export type ReviewStatus = 'accepted' | 'pending' | 'excluded';

export interface DriveEvent {
  id: string;
  tripId: string;
  type: EventType;
  time: string;
  severity: Severity;
  quality: 'good' | 'fair' | 'poor';
  review: ReviewStatus;
  note: string;
  /** Overspeed only: confirmed minutes above a verified posted limit. */
  minutes?: number;
  /** Position along the selected trip's route, 0–1 (for the route marker). */
  at: number;
}

export interface ScoreInput { miles: number; trips: number; events: DriveEvent[] }

export const SEVERITY_WEIGHT: Record<Severity, number> = { low: 0.5, medium: 1, high: 1.5 };
export const MIN_MILES = 20;
export const MIN_TRIPS = 3;
export const CAPS = { braking: 24, acceleration: 16, speeding: 40 } as const;
export const FACTORS = { braking: 3, acceleration: 2, speeding: 0.8 } as const;

export interface ScoreResult {
  score: number | null;
  eligible: boolean;
  reason?: string;
  units: { braking: number; acceleration: number; overspeedMinutes: number };
  penalties: { braking: number; acceleration: number; speeding: number };
  counted: DriveEvent[];
}

const finiteNonNeg = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n) && n >= 0;
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

/** True when an event is counted: accepted, scoring type, valid fields. Cornering is context only. */
export function isCounted(e: DriveEvent): boolean {
  if (e.review !== 'accepted' || e.type === 'cornering') return false;
  if (e.type === 'overspeed') return finiteNonNeg(e.minutes);
  return e.severity in SEVERITY_WEIGHT;
}

export function computeScore(input: ScoreInput): ScoreResult {
  const seen = new Set<string>();
  const counted = input.events.filter((e) => {
    if (seen.has(e.id)) return false; // duplicate IDs never count twice
    seen.add(e.id);
    return isCounted(e);
  });
  const sum = (t: EventType) => counted.filter((e) => e.type === t).reduce((s, e) => s + SEVERITY_WEIGHT[e.severity], 0);
  const units = {
    braking: sum('braking'),
    acceleration: sum('acceleration'),
    overspeedMinutes: counted.filter((e) => e.type === 'overspeed').reduce((s, e) => s + (e.minutes ?? 0), 0),
  };
  const zero = { braking: 0, acceleration: 0, speeding: 0 };

  if (!finiteNonNeg(input.miles) || !finiteNonNeg(input.trips) || !Number.isInteger(input.trips)) {
    return { score: null, eligible: false, reason: 'Invalid trip data — the score was not calculated.', units, penalties: zero, counted };
  }
  if (input.miles < MIN_MILES || input.trips < MIN_TRIPS) {
    return { score: null, eligible: false, reason: `More data needed: at least ${MIN_MILES} eligible miles across ${MIN_TRIPS} usable trips.`, units, penalties: zero, counted };
  }
  const M = input.miles; // ≥ 20 here, so never zero
  const penalties = {
    braking: Math.min(CAPS.braking, ((100 * units.braking) / M) * FACTORS.braking),
    acceleration: Math.min(CAPS.acceleration, ((100 * units.acceleration) / M) * FACTORS.acceleration),
    speeding: Math.min(CAPS.speeding, ((100 * units.overspeedMinutes) / M) * FACTORS.speeding),
  };
  const score = Math.round(clamp(100 - penalties.braking - penalties.acceleration - penalties.speeding, 0, 100));
  return { score, eligible: true, units, penalties, counted };
}

export type Persona = 'teen' | 'rideshare';

/** One focused, rule-based suggestion. Persona changes wording, never the score. */
export function coaching(r: ScoreResult, persona: Persona): { title: string; body: string } {
  if (!r.eligible) return { title: 'Keep driving to unlock a score', body: `${r.reason} A score from too little driving would mostly be noise.` };
  const p = r.penalties;
  const top = (Object.keys(p) as (keyof typeof p)[]).reduce((a, b) => (p[b] > p[a] ? b : a));
  if (p[top] < 3) return {
    title: 'Consistent and smooth',
    body: persona === 'teen'
      ? 'Few flagged moments across these trips. Keep the same following distance and steady speed — this is a pattern, not a guarantee of zero risk.'
      : 'Rides were smooth with few flagged moments. A consistent pattern like this is worth keeping; it is not a guarantee of zero risk.',
  };
  if (top === 'speeding') return {
    title: 'Review the sustained overspeed stretches',
    body: `Overspeed time cost the most (−${p.speeding.toFixed(1)}). Look at where speed stayed above the posted limit for more than a moment${persona === 'rideshare' ? ' — often on highway merges between pickups' : ''}.`,
  };
  if (top === 'braking') return {
    title: 'Look further ahead',
    body: `Hard braking cost the most (−${p.braking.toFixed(1)}). Some braking is the right response to hazards — but a bigger following gap and earlier lift-off make most stops gentler.`,
  };
  return { title: 'Ease into the throttle', body: `Rapid starts cost the most (−${p.acceleration.toFixed(1)}). Rolling on over two or three seconds is smoother${persona === 'rideshare' ? ' for passengers' : ''} and easier on the car.` };
}
