import { useState } from 'react';
import { Navigation, scrollToChapter } from './components/Navigation';
import { Route, MarkerGlyph } from './components/Route';
import { DrivingDemo } from './components/DrivingDemo';
import { ResearchSection } from './components/ResearchSection';
import { Cite } from './components/Cite';
import { REFERENCES } from './data/references';

function Chapter({ id, n, label, dark, children }: { id: string; n: number; label: string; dark?: boolean; children: React.ReactNode }) {
  return (
    <section id={id} className={`chapter${dark ? ' dark' : ''}`} aria-labelledby={`${id}-h`}>
      <div className="wrap">
        <p className="eyebrow"><span className="num">{String(n).padStart(2, '0')}</span>{label}</p>
        {children}
      </div>
    </section>
  );
}

// Fictional teen progress — invented fixture.
const TEEN_TRIPS = [71, 74, 70, 78, 82, 85];
const SHARE_FIELDS = [
  ['score', 'Weekly score and tier', true], ['counts', 'Event counts by type', true],
  ['quality', 'Data-quality summary', true], ['notes', 'My context notes', false], ['route', 'Route or locations', false],
] as const;

export default function App() {
  const [share, setShare] = useState<Record<string, boolean>>(Object.fromEntries(SHARE_FIELDS.map(([k, , v]) => [k, v])));
  const [flagged, setFlagged] = useState(false);
  const tx = (i: number) => 20 + i * 52, ty = (v: number) => 120 - (v - 60) * 3.2;

  return (
    <>
      <Navigation />
      <main id="main" tabIndex={-1}>
        {/* 01 HERO */}
        <section id="hero" className="chapter hero" aria-labelledby="hero-h">
          <div className="wrap hero-grid">
            <div>
              <p className="eyebrow"><span className="num">01</span>Driving safety, made understandable</p>
              <h1 id="hero-h" className="display">Good driving.<br /><span className="accent">Made visible.</span></h1>
              <p className="lead">CURBSIDE turns driving patterns into a clear score, useful feedback, and a path toward better habits.</p>
              <div className="cta-row">
                <button className="btn filled" onClick={() => scrollToChapter('demo')}>Explore the demo</button>
                <button className="btn outlined" onClick={() => scrollToChapter('research')}>See the research</button>
              </div>
            </div>
            <figure className="hero-visual card">
              <span className="chip warn corner">Illustrative demo</span>
              <Route className="draw" title="Stylized route with one braking event marker"
                markers={[{ at: 0.47, kind: 'braking', label: 'Hard brake' }]} />
              <div className="hero-score"><span className="mono big">88</span><span className="label">Trip score</span></div>
              <figcaption className="hero-coach">
                <MarkerGlyph kind="braking" /> <span><strong>One hard stop on Oak St.</strong> A bigger gap behind the car ahead makes most stops gentler.</span>
              </figcaption>
            </figure>
          </div>
        </section>

        {/* 02 PROBLEM */}
        <Chapter id="problem" n={2} label="The problem">
          <h2 id="problem-h" className="headline">Every trip leaves clues.</h2>
          <p className="lead narrow">Speeding and abrupt maneuvers can reveal patterns worth reviewing — but after a drive, it’s hard to remember exactly when and where they happened.</p>
          <div className="stats-row">
            <div className="stat">
              <p className="stat-num">29%</p>
              <p>of U.S. traffic fatalities in <strong>2024</strong> had speeding as a <strong>contributing factor</strong> — 11,288 people died in speeding-related crashes. <Cite id="R1" /></p>
              <p className="muted small">Contributing factor ≠ sole cause.</p>
            </div>
            <div className="stat">
              <p className="stat-num">~3×</p>
              <p>the <strong>fatal crash rate per mile</strong> for drivers ages <strong>16–19</strong> vs. drivers 20 and older (2022 mileage data). <Cite id="R2" /></p>
              <p className="muted small">Fatal crashes only; per-mile denominator.</p>
            </div>
          </div>
        </Chapter>

        {/* 03 IDEA */}
        <Chapter id="idea" n={3} label="The idea" dark>
          <h2 id="idea-h" className="headline">Turn a trip into something you can learn from.</h2>
          <ol className="flow">
            <li><span className="flow-n mono">1</span><h3>Observe</h3><p>Collect GPS and motion signals with permission, on the phone.</p></li>
            <li><span className="flow-n mono">2</span><h3>Understand</h3><p>Identify events, account for data quality, and explain the score.</p></li>
            <li><span className="flow-n mono">3</span><h3>Improve</h3><p>One focused post-trip suggestion, and progress over time.</p></li>
          </ol>
          <div className="built">
            <p className="label"><span className="chip good">Built</span> A native iOS prototype (SwiftUI) already records drives</p>
            <p className="muted narrow">Our iPhone app detects hard brakes, fast starts, and sharp turns from on-device motion + GPS, scores each drive, and pins events on a map with a 5-second replay. Scoring runs on the phone. The web demo below is separate and uses simulated data.</p>
            <div className="shots" role="list">
              {[['01-home', 'App home with Curbside Score gauge'], ['03-drive-complete-top', 'Drive Complete: score ring and event map'], ['04-drive-complete-coaching', 'Coaching card and points breakdown'], ['05-score-tiers-history', 'Score tiers and 6-week history'], ['07-family', 'Family leaderboard'], ['08-privacy', 'Privacy: data stays on device']].map(([f, alt]) => (
                <figure key={f} role="listitem"><img src={`screens/${f}.png`} alt={alt} loading="lazy" width="390" height="844" /><figcaption>{alt}</figcaption></figure>
              ))}
            </div>
          </div>
        </Chapter>

        {/* 04 SIGNALS */}
        <Chapter id="signals" n={4} label="What the app notices">
          <h2 id="signals-h" className="headline">Signals, not verdicts.</h2>
          <p className="lead narrow">A single event never means reckless driving or fault. Each signal has an innocent explanation, so feedback stays specific and humble.</p>
          <div className="signals">
            {([
              ['braking', 'Hard braking', 'A sudden deceleration may be worth reviewing.', 'It can be the correct response to an unexpected hazard.', '“Three firm stops on Main St — try a longer following gap.”'],
              ['acceleration', 'Rapid acceleration', 'Repeated abrupt launches suggest room for smoother driving.', 'Merging onto a fast road may require it.', '“Roll on over 2–3 seconds from lights.”'],
              ['overspeed', 'Sustained speeding', 'Sustained speed above a verified posted limit is useful to flag.', 'Needs accurate location, map matching, and current speed-limit data.', '“4 min above 45 on Route 9 — mostly downhill.”'],
              ['cornering', 'Sharp cornering', 'Lateral motion can identify sharp turns.', 'Phone position, road geometry, and vehicle behavior affect it.', '“Your left turns are quicker than your right.”'],
            ] as const).map(([k, t, ind, alt, fb]) => (
              <article key={k} className={`signal card ev-${k}`}>
                <h3><MarkerGlyph kind={k} /> {t}</h3>
                <dl><dt>Could indicate</dt><dd>{ind}</dd><dt>Could also be</dt><dd>{alt}</dd><dt>Useful feedback</dt><dd className="quote">{fb}</dd></dl>
              </article>
            ))}
          </div>
          <p className="muted small">Speed-limit matching is planned; the iOS prototype does not yet detect speeding.</p>
        </Chapter>

        {/* 05 DEMO */}
        <Chapter id="demo" n={5} label="Interactive demo" dark>
          <h2 id="demo-h" className="headline">See what goes into the score.</h2>
          <p className="lead narrow">Switch scenarios, tap events, and exclude a simulated event to see the calculation change. Everything runs in your browser on bundled data — no location permission.</p>
          <DrivingDemo />
        </Chapter>

        {/* 06 TEENS */}
        <Chapter id="teens" n={6} label="Teen drivers & families">
          <h2 id="teens-h" className="headline">Build confidence, one trip at a time.</h2>
          <div className="split">
            <div>
              <p className="lead">A score becomes more useful when it explains what changed — and gives you one thing to work on next.</p>
              <ul className="checks">
                <li><strong>Personal improvement.</strong> Compared with your own past trips first.</li>
                <li><strong>Specific feedback.</strong> “Harsh launches dropped from 4 to 1 per 10 mi.”</li>
                <li><strong>Constructive conversations.</strong> Parents see summaries — never routes or locations.</li>
                <li><strong>Optional sharing.</strong> The teen consents, and can stop sharing.</li>
                <li><strong>Future rewards.</strong> Family goals today; partner rewards are mock data.</li>
              </ul>
              <p className="muted small">Research note: feedback <em>plus</em> parent communication training reduced risky events in a teen trial; feedback alone did not significantly. <Cite id="R8" /></p>
            </div>
            <figure className="card teen-card">
              <p className="label">Maya’s last 6 trips · fictional</p>
              <svg viewBox="0 0 300 140" role="img" aria-label={`Fictional teen trip scores rising from ${TEEN_TRIPS[0]} to ${TEEN_TRIPS.at(-1)} over six trips`}>
                <line x1="0" x2="300" y1={ty(80)} y2={ty(80)} className="limit" /><text x="296" y={ty(80) - 5} textAnchor="end" className="axis">family goal 80</text>
                <path d={TEEN_TRIPS.map((v, i) => `${i ? 'L' : 'M'}${tx(i)} ${ty(v)}`).join(' ')} className="trace" />
                {TEEN_TRIPS.map((v, i) => <g key={i}><circle cx={tx(i)} cy={ty(v)} r="5" className="dot" /><text x={tx(i)} y={ty(v) - 10} textAnchor="middle" className="axis">{v}</text></g>)}
              </svg>
              <figcaption><strong>What changed:</strong> fewer hard launches since trip 3. <strong>Next:</strong> smoother stops at lights.</figcaption>
            </figure>
          </div>
          <aside className="card opportunity">
            <p className="label"><span className="chip tonal">Future opportunity</span></p>
            <p className="big-text">Eligible drivers could share approved driving summaries with participating insurers.</p>
            <p className="muted">Insurance discounts would require insurer partnerships and eligibility rules. This prototype does not determine premiums or guarantee savings. Insurer programs already exist and can raise rates as well as lower them. <Cite id="R9" /> <Cite id="R10" /></p>
          </aside>
        </Chapter>

        {/* 07 RIDESHARE */}
        <Chapter id="rideshare" n={7} label="Rideshare">
          <h2 id="rideshare-h" className="headline">A clearer picture of the ride.</h2>
          <div className="split">
            <div>
              <p className="lead">An opt-in trip report a driver controls: understandable evidence, and sharing on their terms.</p>
              <p className="muted">Uber and Lyft already offer driving insights and feedback <Cite id="R11" /> <Cite id="R12" />. CURBSIDE’s hypothesis is a portable, self-explaining report the driver chooses to share. No platform integration exists.</p>
            </div>
            <article className="card report" aria-label="Sample rideshare trip report, simulated">
              <header className="report-head"><span className="label">Trip report · simulated</span><span className="mono">18.4 mi · 41 min</span></header>
              <ul className="report-events">
                <li><MarkerGlyph kind="braking" /> Hard braking · 6:12 PM <span className="chip status pending">{flagged ? 'Flagged for review' : 'Accepted'}</span></li>
                <li><MarkerGlyph kind="acceleration" /> Rapid acceleration · 6:20 PM</li>
              </ul>
              <p className="small"><strong>Coverage:</strong> GPS good for 96% of trip; 2 min in a tunnel unscored.</p>
              <p className="small"><strong>Context note:</strong> “Cyclist swerved into lane at 6:12.”</p>
              <p className="small muted"><strong>Private explanation:</strong> score 86 — braking −9, acceleration −5. Only you see this.</p>
              <button className="btn tonal small" onClick={() => setFlagged((f) => !f)} aria-pressed={flagged}>{flagged ? 'Undo flag' : 'Flag braking event for review'}</button>
              <fieldset className="share">
                <legend className="label">Share preview — you choose</legend>
                {SHARE_FIELDS.map(([k, label]) => (
                  <label key={k} className="switch-row"><input type="checkbox" role="switch" checked={share[k]} onChange={(e) => setShare({ ...share, [k]: e.target.checked })} /><span>{label}</span></label>
                ))}
                <p className="small muted" aria-live="polite">Sharing {SHARE_FIELDS.filter(([k]) => share[k]).length} of {SHARE_FIELDS.length} items. Nothing ranks or lists identifiable drivers.</p>
              </fieldset>
            </article>
          </div>
        </Chapter>

        {/* 08 RESEARCH */}
        <Chapter id="research" n={8} label="Research" dark>
          <h2 id="research-h" className="headline">Promising technology. Evidence that deserves context.</h2>
          <ResearchSection />
        </Chapter>

        {/* 09 TRUST */}
        <Chapter id="trust" n={9} label="Trust & context">
          <h2 id="trust-h" className="headline">A useful score should explain itself.</h2>
          <p className="muted narrow">Design commitments. Where the iOS prototype already does something, we say so.</p>
          <div className="principles">
            <article><h3>Context matters</h3><p>An emergency stop and repeated avoidable abrupt braking shouldn’t automatically get the same interpretation. <Cite id="R5" /></p></article>
            <article><h3>Uncertainty stays visible</h3><p>Poor GPS, ambiguous driver identity, or incomplete data should reduce confidence or prevent scoring.</p><p className="small"><span className="chip good">Built</span> The app suppresses events while the phone is being handled, and requires a GPS speed change to confirm brakes.</p></article>
            <article><h3>Sharing is a choice</h3><p>Collecting a trip is separate from sharing its report.</p><p className="small"><span className="chip good">Built</span> Teens consent before a score syncs; routes and raw motion stay on the phone.</p></article>
            <article><h3>Improvement is personal</h3><p>Compare a driver with their own prior trips before any comparison across drivers.</p></article>
          </div>
        </Chapter>

        {/* 10 LANDSCAPE */}
        <Chapter id="landscape" n={10} label="Existing products">
          <h2 id="landscape-h" className="headline">The category exists. The experience can improve.</h2>
          <div className="table-wrap">
            <table>
              <caption className="sr-only">Comparison of existing telematics products and the Curbside concept</caption>
              <thead><tr><th scope="col">Who</th><th scope="col">What exists</th><th scope="col">Note</th></tr></thead>
              <tbody>
                <tr><th scope="row">Insurer telematics</th><td>Programs link their own driving data to policy pricing (e.g., Snapshot, Drive Safe & Save). <Cite id="R9" /> <Cite id="R10" /></td><td>Rules and eligibility vary; rates can rise.</td></tr>
                <tr><th scope="row">Rideshare platforms</th><td>Platform-specific insights on speeding, braking, acceleration, and more. <Cite id="R11" /> <Cite id="R12" /></td><td>Availability varies; platform-specific.</td></tr>
                <tr className="us"><th scope="row">CURBSIDE concept</th><td>Transparent explanations, context review, personal coaching, voluntary sharing across use cases.</td><td><span className="chip warn">Hypotheses to test</span></td></tr>
              </tbody>
            </table>
          </div>
        </Chapter>

        {/* 11 ROADMAP */}
        <Chapter id="roadmap" n={11} label="Roadmap" dark>
          <h2 id="roadmap-h" className="headline">From a compelling demo to a trustworthy tool.</h2>
          <ol className="roadmap">
            <li className="stage now"><p className="label"><span className="chip good">Now · built</span> Hackathon prototype</p>
              <ul><li>iOS app: on-device recording, brake / launch / turn detection, per-drive score</li><li>5-second event replay, 0–100 Curbside Score with tiers</li><li>Family consent, parent dashboard, leaderboard (score + tier only)</li><li>Parent goals + mock partner rewards</li><li>This site: synthetic trips, transparent calculation, event review</li></ul></li>
            <li className="stage"><p className="label"><span className="chip tonal">Next · planned</span> Mobile measurement pilot</p>
              <ul><li>Phone placement & orientation handling at scale</li><li>Driver / passenger distinction</li><li>Speed-limit data integration</li><li>Comparison against reference measurements</li><li>Data-quality and battery testing</li></ul></li>
            <li className="stage"><p className="label"><span className="chip tonal">Later · planned</span> Evaluated deployment</p>
              <ul><li>Consent-based real-world pilot</li><li>False-positive analysis</li><li>Performance across devices, vehicles, roads</li><li>Behavioral outcome evaluation</li><li>Independent review of the scoring</li><li>Insurer or platform partnerships where appropriate</li></ul></li>
          </ol>
        </Chapter>

        {/* 12 CLOSE */}
        <section id="close" className="chapter close" aria-labelledby="close-h">
          <div className="wrap">
            <p className="eyebrow"><span className="num">12</span>Closing</p>
            <h2 id="close-h" className="display">Better habits start with <span className="accent">better feedback.</span></h2>
            <p className="lead">CURBSIDE makes driving patterns easier to see, understand, and improve.</p>
            <div className="cta-row">
              <button className="btn filled" onClick={() => scrollToChapter('demo')}>Try the demo</button>
              <button className="btn outlined" onClick={() => scrollToChapter('research')}>Explore the evidence</button>
              <a className="btn text" href="https://github.com/sa087613/Curbside" target="_blank" rel="noreferrer">GitHub</a>
            </div>
            <Route title="Closing route motif" className="close-route" />
            <h3 className="label" id="refs">Bibliography</h3>
            <ol className="biblio">
              {REFERENCES.map((r) => (
                <li key={r.id} id={`ref-${r.id}`}><span className="mono">{r.id}</span> {r.authors} ({r.year}). <a href={r.url} target="_blank" rel="noreferrer">{r.title}</a>. <em>{r.publication}</em>. <span className="muted">[{r.evidenceType}] Limitation: {r.limitation}</span></li>
              ))}
            </ol>
            <p className="disclosure small"><strong>Prototype disclosure.</strong> The web demo uses simulated trips and an illustrative scoring model whose thresholds and weights are prototype choices, not validated constants. Scores are not a validated measure of safety, fault, or insurability. No insurer or rideshare partnership exists; partner rewards in the app are mock data.</p>
          </div>
        </section>
      </main>
    </>
  );
}
