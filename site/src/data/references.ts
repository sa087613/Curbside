export type EvidenceType = 'Government data' | 'Research institute' | 'Peer-reviewed study' | 'Preprint' | 'Company description';
export interface Reference {
  id: string; title: string; authors: string; year: number | string; publication: string; url: string;
  evidenceType: EvidenceType; supportedClaim: string; limitation: string;
  setting?: string; measured?: string;
}

export const REFERENCES: Reference[] = [
  { id: 'R1', title: 'Speeding', authors: 'National Highway Traffic Safety Administration', year: 'n.d. (2024 data)', publication: 'NHTSA', url: 'https://www.nhtsa.gov/risky-driving/speeding', evidenceType: 'Government data',
    supportedClaim: 'In 2024, speeding was a contributing factor in 29% of U.S. traffic fatalities; 11,288 people died in speeding-related crashes.', limitation: 'A contributing factor is not necessarily the sole cause.' },
  { id: 'R2', title: 'Teenagers', authors: 'Insurance Institute for Highway Safety', year: 'n.d. (2022 mileage data)', publication: 'IIHS', url: 'https://www.iihs.org/research-areas/teenagers', evidenceType: 'Research institute',
    supportedClaim: 'Drivers ages 16–19 have a fatal crash rate per mile about three times that of drivers 20 and older.', limitation: 'Specific to these age groups, fatal crashes, and a per-mile denominator.' },
  { id: 'R3', title: 'Measuring Risky Driving Behavior Using an mHealth Smartphone App: Development and Evaluation of gForce', authors: 'Freidlin, R. Z., Dave, A. D., Espey, B. G., et al.', year: 2018, publication: 'JMIR mHealth and uHealth, 6(4), e69', url: 'https://mhealth.jmir.org/2018/4/e69/', evidenceType: 'Peer-reviewed study',
    setting: 'Mounted smartphones compared with an in-vehicle data-acquisition system', measured: 'Elevated acceleration (g-force) events',
    supportedClaim: 'Mounted smartphone measurements of elevated acceleration events correlated with a vehicle data-acquisition system under the study’s conditions.', limitation: 'Phone mounting and road features (potholes, speed bumps) affected measurements. Does not validate a universal driving score.' },
  { id: 'R4', title: 'Smartphone-based hard-braking event detection at scale for road safety services', authors: 'Liu, L., Racz, D., Vaillancourt, K., et al.', year: 2023, publication: 'Transportation Research Part C, 146, 103949 (author preprint)', url: 'https://arxiv.org/abs/2202.01934', evidenceType: 'Peer-reviewed study',
    setting: 'Large-scale smartphone navigation data', measured: 'Hard-braking events vs. aggregated crash data',
    supportedClaim: 'A smartphone hard-braking model was developed; aggregated events were associated with crash data (PR-AUC 0.83).', limitation: 'PR-AUC 0.83 is not “83% accuracy.” Aggregate correlation does not establish individual fault or validate a simple threshold prototype.' },
  { id: 'R5', title: 'Analysis of harsh braking and harsh acceleration occurrence via explainable imbalanced machine learning using high-resolution smartphone telematics and traffic data', authors: 'Ziakopoulos, A.', year: 2024, publication: 'Accident Analysis & Prevention, 207, 107743', url: 'https://pubmed.ncbi.nlm.nih.gov/39121576/', evidenceType: 'Peer-reviewed study',
    setting: '314 drivers on an Athens urban arterial', measured: 'Harsh braking / acceleration vs. speed, traffic flow, exposure',
    supportedClaim: 'Harsh-event occurrence was related to speed, traffic flow, and exposure variables — context shapes harsh events.', limitation: 'Predicting harsh events is different from predicting crashes or assigning fault.' },
  { id: 'R6', title: 'Personalized driving safety: Using telematics to reduce risky driving behaviour among young drivers', authors: 'Meuleners, L., Fraser, M., Stevenson, M., Roberts, P.', year: 2023, publication: 'Journal of Safety Research, 86, 164–173', url: 'https://pubmed.ncbi.nlm.nih.gov/37718043/', evidenceType: 'Peer-reviewed study',
    setting: 'Western Australian provisional drivers, ages 17–20, 11 weeks', measured: 'Overall, braking, acceleration, and speed scores',
    supportedClaim: 'No statistically significant intervention-vs-control differences in overall, braking, acceleration, or speed scores.', limitation: 'Favorable trends should not be read as demonstrated effectiveness.' },
  { id: 'R7', title: 'The effect of Real-Time feedback and incentives on speeding behaviors using Telematics: A randomized controlled trial', authors: 'Malekpour, M.-R., Ghamari, S.-H., Ghasemi, E., et al.', year: 2023, publication: 'Accident Analysis & Prevention, 191, 107216', url: 'https://pubmed.ncbi.nlm.nih.gov/37429155/', evidenceType: 'Peer-reviewed study',
    setting: 'RCT, 397 male taxi drivers', measured: 'Share of distance >10% above the speed limit',
    supportedClaim: 'Financial-incentive groups reduced the share of distance driven more than 10% over the limit vs. control.', limitation: 'Adult male taxi drivers with money incentives. Does not establish teen outcomes, crash reduction, or effects from badges.' },
  { id: 'R8', title: 'In-Vehicle Feedback With or Without Parent Communication Training and Teenage Driving Behaviors: A Randomized Clinical Trial', authors: 'Yang, J., Zhang, Y., Alshaikh, E., et al.', year: 2026, publication: 'JAMA Network Open, 9(4), e268631', url: 'https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2848141', evidenceType: 'Peer-reviewed study',
    setting: '240 Ohio parent–teen dyads; teen had a prior moving violation', measured: 'Risky-event incidence',
    supportedClaim: 'Feedback plus parent communication training reduced risky-event incidence vs. control (adjusted IRR 0.68; 97.5% CI 0.51–0.90).', limitation: 'Feedback alone did not significantly reduce overall risky events. Not evidence of fewer crashes, or that Curbside works.' },
  { id: 'R9', title: 'Snapshot Frequently Asked Questions', authors: 'Progressive', year: 'n.d.', publication: 'Progressive.com', url: 'https://www.progressive.com/auto/discounts/snapshot/snapshot-faq/', evidenceType: 'Company description',
    supportedClaim: 'An established insurer program uses driving information in its own pricing.', limitation: 'Rates can increase; availability and rules vary. A third-party score is not automatically accepted.' },
  { id: 'R10', title: 'Drive Safe & Save', authors: 'State Farm', year: 'n.d.', publication: 'StateFarm.com', url: 'https://www.statefarm.com/insurance/auto/discounts/drive-safe-save', evidenceType: 'Company description',
    supportedClaim: 'Insurer-operated smartphone/beacon telematics programs exist.', limitation: 'Savings depend on eligibility, driving data, and program rules.' },
  { id: 'R11', title: 'Introducing the Driving Insights dashboard', authors: 'Uber', year: '2026 (Apr 10)', publication: 'Uber Blog', url: 'https://www.uber.com/us/en/blog/driving-insights-dashboard/', evidenceType: 'Company description',
    supportedClaim: 'Uber describes phone-based insights on speeding, braking, acceleration, turning, and phone handling.', limitation: 'A company product description — not independent evidence of effectiveness or a public integration API.' },
  { id: 'R12', title: 'Feedback and insights hub', authors: 'Lyft', year: 'n.d.', publication: 'Lyft Help', url: 'https://help.lyft.com/hc/en-us/all/articles/9622529073-Feedback-and-insights-hub', evidenceType: 'Company description',
    supportedClaim: 'Lyft offers driving feedback, including Smooth Cruiser features in supported regions.', limitation: 'Availability varies by region.' },
];
export const ref = (id: string) => REFERENCES.find((r) => r.id === id)!;
