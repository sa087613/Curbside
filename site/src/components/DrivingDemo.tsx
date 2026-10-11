import { useMemo, useState } from 'react';
import { SCENARIOS, TOGGLE_EVENT_ID } from '../data/scenarios';
import { computeScore, coaching, isCounted, SEVERITY_WEIGHT, CAPS, type DriveEvent, type Persona } from '../lib/scoring';
import { Route, MarkerGlyph } from './Route';

const TYPE_LABEL: Record<DriveEvent['type'], string> = { braking: 'Hard braking', acceleration: 'Rapid acceleration', overspeed: 'Sustained overspeed', cornering: 'Sharp cornering' };
const LIMIT = 45;

/** Deterministic synthetic speed trace for the selected trip, shaped by its events. */
function speedTrace(events: DriveEvent[]) {
  const n = 80;
  return Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1);
    let v = 34 + 8 * Math.sin(t * 9) + 4 * Math.sin(t * 23);
    if (t < 0.06) v *= t / 0.06; if (t > 0.94) v *= (1 - t) / 0.06;
    for (const e of events) {
      const d = Math.abs(t - e.at);
      if (e.type === 'overspeed' && d < 0.07) v = Math.max(v, LIMIT + 4 + (e.minutes ?? 1) * 1.2 - d * 60);
      if (e.type === 'braking' && d < 0.04) v *= 0.35 + d * 14;
    }
    return Math.max(0, v);
  });
}

export function DrivingDemo() {
  const [scenarioId, setScenarioId] = useState('mixed');
  const [persona, setPersona] = useState<Persona>('teen');
  const [excluded, setExcluded] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(TOGGLE_EVENT_ID);

  const scenario = SCENARIOS.find((s) => s.id === scenarioId)!;
  const events = useMemo(() => scenario.events.map((e) => (e.id === TOGGLE_EVENT_ID && excluded ? { ...e, review: 'excluded' as const } : e)), [scenario, excluded]);
  const result = useMemo(() => computeScore({ miles: scenario.miles, trips: scenario.trips, events }), [scenario, events]);
  const tip = coaching(result, persona);
  const tripEvents = events.filter((e) => e.tripId === scenario.routeTrip);
  const trace = useMemo(() => speedTrace(tripEvents), [tripEvents]);
  const selected = events.find((e) => e.id === selectedId) ?? null;
  const quality = !result.eligible ? 'Not enough data' : events.some((e) => e.quality !== 'good') ? 'Good · 1 event fair GPS' : 'Good';

  const pick = (id: string) => { setScenarioId(id); setSelectedId(SCENARIOS.find((s) => s.id === id)!.events[0]?.id ?? null); };
  const reset = () => { setScenarioId('mixed'); setPersona('teen'); setExcluded(false); setSelectedId(TOGGLE_EVENT_ID); };

  const max = Math.max(60, ...trace);
  const W = 600, H = 150;
  const x = (i: number) => (i / (trace.length - 1)) * W;
  const y = (v: number) => H - 14 - (v / max) * (H - 28);
  const line = trace.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(' ');
  const peak = Math.round(Math.max(...trace));
  const ring = result.score ?? 0;

  return (
    <div className="demo">
      <div className="demo-controls">
        <div className="segmented" role="radiogroup" aria-label="Scenario">
          {SCENARIOS.map((s) => (
            <button key={s.id} role="radio" aria-checked={s.id === scenarioId} onClick={() => pick(s.id)}>{s.label}</button>
          ))}
        </div>
        <div className="segmented small" role="radiogroup" aria-label="Viewing as">
          {(['teen', 'rideshare'] as const).map((p) => (
            <button key={p} role="radio" aria-checked={p === persona} onClick={() => setPersona(p)}>{p === 'teen' ? 'Teen driver' : 'Rideshare driver'}</button>
          ))}
        </div>
        <button className="btn outlined small" onClick={reset}>Reset demo</button>
      </div>
      <p className="sim-label"><span className="chip warn">Simulated trips · Illustrative scoring model</span></p>

      <div className="demo-grid">
        <section className="card score-card" aria-labelledby="score-h">
          <h3 id="score-h" className="label">Weekly score</h3>
          <div className="ring" style={{ ['--p' as string]: ring }} aria-hidden="true">
            <svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="52" className="ring-track" /><circle cx="60" cy="60" r="52" className="ring-fill" pathLength={100} /></svg>
            <span className="ring-num">{result.score ?? '—'}</span>
          </div>
          <p className="sr-only" aria-live="polite">{result.score == null ? 'More data needed, no score.' : `Score ${result.score} out of 100.`}</p>
          <p className="score-sub">{result.score == null ? 'More data needed' : 'out of 100 · illustrative'}</p>
          <dl className="stats">
            <div><dt>Eligible miles</dt><dd className="mono">{scenario.miles}</dd></div>
            <div><dt>Usable trips</dt><dd className="mono">{scenario.trips}</dd></div>
            <div><dt>Data quality</dt><dd>{quality}</dd></div>
          </dl>
        </section>

        <section className="card route-card" aria-labelledby="route-h">
          <h3 id="route-h" className="label">Selected trip {scenario.routeTrip} · route illustration</h3>
          {scenario.events.length ? (
            <Route title={`Stylized route for trip ${scenario.routeTrip} with ${tripEvents.length} event markers`} progress={selected?.tripId === scenario.routeTrip ? selected.at : undefined}
              markers={tripEvents.map((e) => ({ at: e.at, kind: e.type, label: TYPE_LABEL[e.type], active: e.id === selectedId, pending: e.review !== 'accepted', onClick: () => setSelectedId(e.id) }))} />
          ) : <p className="empty">One 6-mile trip recorded. No route summary until there is enough data.</p>}
          {scenario.events.length > 0 && <>
            <h4 className="label">Speed timeline (mph)</h4>
            <svg className="speed" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`Synthetic speed trace for trip ${scenario.routeTrip}: peak ${peak} mph against a ${LIMIT} mph posted limit, with ${tripEvents.length} event marks.`}>
              <line x1="0" x2={W} y1={y(LIMIT)} y2={y(LIMIT)} className="limit" />
              <text x={W - 4} y={y(LIMIT) - 6} textAnchor="end" className="axis">limit {LIMIT}</text>
              <path d={line} className="trace" />
              {tripEvents.map((e) => (
                <line key={e.id} x1={e.at * W} x2={e.at * W} y1={8} y2={H - 8} className={`ev-mark ev-${e.type}${e.id === selectedId ? ' is-active' : ''}`} />
              ))}
            </svg>
          </>}
        </section>

        <section className="card events-card" aria-labelledby="events-h">
          <h3 id="events-h" className="label">Events ({events.length})</h3>
          {events.length === 0 && <p className="empty">No events — and too little driving to say much.</p>}
          <ul className="event-list">
            {events.map((e) => (
              <li key={e.id}>
                <button className={`event-row${e.id === selectedId ? ' is-active' : ''} status-${e.review}`} aria-pressed={e.id === selectedId} onClick={() => setSelectedId(e.id)}>
                  <MarkerGlyph kind={e.type} />
                  <span className="ev-name">{TYPE_LABEL[e.type]}<small>{e.time} · {e.tripId}</small></span>
                  <span className={`chip status ${e.review}`}>{e.review === 'pending' ? 'Awaiting review' : e.review === 'excluded' ? 'Excluded' : isCounted(e) ? 'Counted' : 'Context only'}</span>
                </button>
              </li>
            ))}
          </ul>
          {selected && (
            <div className="event-detail" aria-live="polite">
              <p><strong>{TYPE_LABEL[selected.type]}</strong> · {selected.severity} severity{selected.type === 'overspeed' ? ` · ${selected.minutes} min` : ` · weight ${SEVERITY_WEIGHT[selected.severity]}`}</p>
              <p className="muted">{selected.note}</p>
              <dl className="mini"><dt>ID</dt><dd className="mono">{selected.id}</dd><dt>GPS quality</dt><dd>{selected.quality}</dd><dt>In calculation</dt><dd>{isCounted(selected) ? 'Yes' : 'No'}</dd></dl>
              {selected.type === 'cornering' && <p className="muted small">Cornering is shown for context and excluded from this initial formula.</p>}
              {selected.id === TOGGLE_EVENT_ID && (
                <label className="switch-row">
                  <input type="checkbox" role="switch" checked={excluded} onChange={(e) => setExcluded(e.target.checked)} />
                  <span>Exclude this simulated event</span>
                </label>
              )}
            </div>
          )}
          {scenarioId === 'mixed' && <p className="muted small">In production, event review would need defined rules and an audit trail — a driver could not simply erase an unfavorable event. Excluding never changes distance.</p>}
        </section>

        <section className="card breakdown-card" aria-labelledby="bd-h">
          <h3 id="bd-h" className="label">Score breakdown</h3>
          <ul className="bars">
            {([['braking', 'Braking', `${result.units.braking} severity units`], ['acceleration', 'Acceleration', `${result.units.acceleration} severity units`], ['speeding', 'Overspeed', `${result.units.overspeedMinutes} min`]] as const).map(([k, label, u]) => (
              <li key={k}>
                <div className="bar-head"><span>{label} <small className="muted">{u}</small></span><span className="mono">−{result.penalties[k].toFixed(1)} <small className="muted">/ {CAPS[k]}</small></span></div>
                <div className="bar"><span style={{ width: `${(result.penalties[k] / CAPS[k]) * 100}%` }} className={`fill-${k}`} /></div>
              </li>
            ))}
          </ul>
          <div className="coach">
            <p className="label">One thing to work on</p>
            <p className="coach-title">{tip.title}</p>
            <p>{tip.body}</p>
          </div>
          <details className="explain">
            <summary>How this score is calculated</summary>
            <pre className="mono formula">{`M = eligible miles
braking   = min(24, 100 × B / M × 3)
accel     = min(16, 100 × A / M × 2)
overspeed = min(40, 100 × S / M × 0.8)
score = round(clamp(100 − penalties, 0, 100))
No score if M < 20 or trips < 3`}</pre>
            <p className="small">Severity weights: low 0.5 · medium 1 · high 1.5. Events are normalized by distance so a long week isn’t penalized for being long. Normalization does not account for road conditions, congestion, vehicle differences, or measurement quality. These weights are prototype choices, not validated constants.</p>
          </details>
        </section>
      </div>
    </div>
  );
}
