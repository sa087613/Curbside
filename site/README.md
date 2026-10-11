# CURBSIDE — presentation site

Hackathon presentation website for Curbside (the iOS app lives in the repo root). React + TypeScript + Vite, plain CSS styled with Material 3 tokens seeded from the app's black/yellow palette.

```sh
cd site
npm install
npm run dev      # local dev server
npm test         # scoring unit tests (Vitest)
npm run build    # production build → site/dist (static, relative paths)
```

**Deploy:** any static host. Vercel/Netlify: root directory `site`, build `npm run build`, output `dist`.

## Built vs. simulated vs. planned
- **Built (iOS app, repo root):** on-device drive recording, hard brake / fast start / sharp turn detection, per-drive score, 5-second event replay, 0–100 Curbside Score with tiers, family consent + leaderboard (score and tier only), parent goals, mock partner rewards.
- **Simulated (this site):** the interactive demo runs an *illustrative* formula (`src/lib/scoring.ts`) over invented fixtures (`src/data/scenarios.ts`). It is not the app's scoring model and is not validated.
- **Planned:** speed-limit matching, driver/passenger distinction, reference-measurement validation, pilots, partnerships.

Sources live in one registry: `src/data/references.ts`.

## 3-minute presentation script
Press **Present** (top right); use ← → or the on-screen buttons, Esc to exit.
1. **Problem (02):** Speeding contributed to 29% of 2024 U.S. traffic deaths; teens 16–19 crash fatally ~3× more per mile. After a drive, you can't remember where things went wrong.
2. **Feedback loop (03):** Observe → Understand → Improve. Show the real iOS screenshots — this already records and scores drives on the phone.
3. **Demo (05):** Mixed week = 88. Tap the medium brake, toggle "Exclude this simulated event" → 91; distance unchanged. Switch to Needs attention (54) and Insufficient data (no score). Point at the coaching card.
4. **Evidence (08):** Phones can measure motion (R3, R4); context matters (R5). Feedback + parent training cut risky events (IRR 0.68, R8) — but feedback alone didn't, and another teen trial was null (R6).
5. **What we built (11 "Now"):** native iOS app + this transparent demo.
6. **Next:** measurement pilot against reference data, false-positive analysis, then an evaluated deployment.
