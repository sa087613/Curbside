import { ref } from '../data/references';

const GROUPS = [
  { title: 'Measurement', lead: 'Smartphones can detect useful motion signals — under tested conditions.', ids: ['R3', 'R4', 'R5'] },
  { title: 'Behavior change', lead: 'Some interventions improve measured behavior. Effects depend on the intervention and population.', ids: ['R6', 'R7', 'R8'] },
];
const RESULT_TONE: Record<string, string> = { R6: 'Null result', R7: 'Positive (incentives)', R8: 'Positive (feedback + parent training)', R3: 'Feasibility', R4: 'Aggregate association', R5: 'Context matters' };

export function ResearchSection() {
  return (
    <div className="research">
      {GROUPS.map((g, gi) => (
        <div key={g.title} className="research-group">
          <p className="label"><span className="num">{gi + 1}</span> {g.title}</p>
          <p className="lead">{g.lead}</p>
          {g.ids.map((id) => {
            const r = ref(id);
            return (
              <details key={id} className="study">
                <summary>
                  <span className="study-id mono">{id}</span>
                  <span className="study-title">{r.authors.split(',')[0]} et al. ({r.year})<small>{r.setting}</small></span>
                  <span className={`chip ${id === 'R6' ? 'warn' : 'tonal'}`}>{RESULT_TONE[id]}</span>
                </summary>
                <dl className="study-body">
                  <dt>Population / setting</dt><dd>{r.setting}</dd>
                  <dt>Measured</dt><dd>{r.measured}</dd>
                  <dt>Main result</dt><dd>{r.supportedClaim}</dd>
                  <dt>Limitation</dt><dd>{r.limitation}</dd>
                  <dt>Source</dt><dd><a href={r.url} target="_blank" rel="noreferrer">{r.title} — {r.publication}</a></dd>
                </dl>
              </details>
            );
          })}
        </div>
      ))}
      <div className="research-group limits">
        <p className="label"><span className="num">3</span> Limits</p>
        <p className="lead">A score alone does not establish crash prevention, fault, or insurance eligibility.</p>
        <ul className="plain">
          <li>Aggregate hard-braking associations (R4) say nothing about an individual driver’s fault.</li>
          <li>Harsh events depend on traffic and speed context (R5) — predicting them is not predicting crashes.</li>
          <li>Feedback alone did not significantly reduce risky events among teens with a prior violation; feedback plus parent training did (R8). Another teen trial found no significant differences (R6).</li>
          <li>Incentive results came from adult taxi drivers paid money (R7), not teens earning badges.</li>
        </ul>
      </div>
    </div>
  );
}
