import type { DriveEvent } from '../lib/scoring';
// All values are invented demonstration fixtures.
export interface Scenario { id: string; label: string; miles: number; trips: number; routeTrip: string; events: DriveEvent[] }

const ev = (id: string, tripId: string, type: DriveEvent['type'], time: string, severity: DriveEvent['severity'], note: string, at: number, extra: Partial<DriveEvent> = {}): DriveEvent =>
  ({ id, tripId, type, time, severity, quality: 'good', review: 'accepted', note, at, ...extra });

export const TOGGLE_EVENT_ID = 'mx-b1';

export const SCENARIOS: Scenario[] = [
  { id: 'smooth', label: 'Smooth week', miles: 120, trips: 6, routeTrip: 'T-104', events: [
    ev('sm-b1', 'T-104', 'braking', 'Tue 7:42 AM', 'low', 'Gentle-but-firm stop at a school crosswalk.', 0.32),
    ev('sm-a1', 'T-104', 'acceleration', 'Tue 7:51 AM', 'low', 'Brisk merge onto the arterial.', 0.58),
    ev('sm-s1', 'T-106', 'overspeed', 'Thu 5:10 PM', 'low', '30 s above a 45 mph limit, map-matched.', 0.75, { minutes: 0.5 }),
    ev('sm-c1', 'T-104', 'cornering', 'Tue 7:55 AM', 'low', 'Tight on-ramp. Context only.', 0.82),
  ] },
  { id: 'mixed', label: 'Mixed week', miles: 86, trips: 5, routeTrip: 'T-212', events: [
    ev(TOGGLE_EVENT_ID, 'T-212', 'braking', 'Mon 4:18 PM', 'medium', 'Car ahead stopped suddenly — possibly a correct hazard response.', 0.28, { quality: 'fair' }),
    ev('mx-b2', 'T-212', 'braking', 'Mon 4:31 PM', 'low', 'Late stop at a yellow light.', 0.55),
    ev('mx-b3', 'T-214', 'braking', 'Wed 8:02 AM', 'low', 'Short gap in slow traffic.', 0.4),
    ev('mx-a1', 'T-212', 'acceleration', 'Mon 4:20 PM', 'medium', 'Quick launch from a stop.', 0.33),
    ev('mx-s1', 'T-215', 'overspeed', 'Fri 6:40 PM', 'medium', '2.2 min above a 55 mph limit.', 0.7, { minutes: 2.2 }),
    ev('mx-s2', 'T-212', 'overspeed', 'Mon 4:40 PM', 'low', '1 min above a 35 mph limit.', 0.78, { minutes: 1 }),
    ev('mx-c1', 'T-212', 'cornering', 'Mon 4:44 PM', 'medium', 'Sharp right turn. Awaiting review; context only.', 0.88, { review: 'pending', quality: 'fair' }),
  ] },
  { id: 'attention', label: 'Needs attention', miles: 60, trips: 4, routeTrip: 'T-330', events: [
    ev('na-b1', 'T-330', 'braking', 'Sat 11:05 PM', 'high', 'Very abrupt stop at a red light.', 0.22),
    ev('na-b2', 'T-330', 'braking', 'Sat 11:14 PM', 'high', 'Abrupt stop behind a turning car.', 0.48),
    ev('na-b3', 'T-331', 'braking', 'Sun 1:20 PM', 'medium', 'Close following on the arterial.', 0.6),
    ev('na-a1', 'T-330', 'acceleration', 'Sat 11:06 PM', 'high', 'Hard launch from a light.', 0.25),
    ev('na-a2', 'T-331', 'acceleration', 'Sun 1:12 PM', 'medium', 'Quick pass.', 0.36),
    ev('na-a3', 'T-332', 'acceleration', 'Sun 6:02 PM', 'low', 'Brisk start.', 0.5),
    ev('na-s1', 'T-330', 'overspeed', 'Sat 11:22 PM', 'high', '7.5 min above a 50 mph limit.', 0.7, { minutes: 7.5 }),
    ev('na-s2', 'T-332', 'overspeed', 'Sun 6:15 PM', 'medium', '4.5 min above a 40 mph limit.', 0.8, { minutes: 4.5 }),
    ev('na-c1', 'T-330', 'cornering', 'Sat 11:30 PM', 'high', 'Fast left turn. Context only.', 0.9),
  ] },
  { id: 'insufficient', label: 'Insufficient data', miles: 6, trips: 1, routeTrip: 'T-401', events: [] },
];
