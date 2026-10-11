# Curbside

A native iOS driving coach for teen drivers and their families (SwiftUI, iOS 17+). The phone's GPS and
motion sensors record each drive, score it out of 100, pin every hard brake / fast start / sharp turn on a
map, and tell the driver the one habit to fix.

**How it differs from Life360:** a 5-second replay of every hard brake and turn, a credit-score-style
long-term score, a family leaderboard, and rewards for safe driving.

## Product rules

### Two scores
- **Drive score (0–100), per drive.** Points are deducted per event, weighted by type and severity, and
  normalized by distance. Weights are in `ScoringConfig` (in `CurbsideConfig.swift`).
- **Curbside Score (0–100), long term.** A slow-moving weighted rolling average of recent drive scores
  (recent drives count more, older ones decay).
  - Four tiers: **Bronze 0–59, Silver 60–79, Gold 80–89, Platinum 90–100**.
  - (Before the redesign it was 300–850 with five tiers. Only the output scale and tiers changed; the
    formula stayed the same.)
  - Missing days doesn't hurt it: it decays by drive count, not calendar time.
  - Consistent good driving raises it gradually.
  - One bad drive dents it a little; a pattern of bad drives drops it more.
  - Shown as a half gauge colored by tier, "+N this week", a tier bar, a 6-week history chart, "what's
    moving your score" factors, and "what's changing" (hard brakes and harsh launches per 10 mi, recent
    drives vs the ones before).

### Family
- Parent and teen accounts. A parent creates a family and invites teens with a code.
- Parent dashboard: each teen's Curbside Score, tier, weekly change, and event counts. **No route maps or
  locations.**
- Family leaderboard ranks everyone by Curbside Score, including parents (they can drive too). Each row has
  an avatar initial, role, tier badge, score, and weekly change, and "You" is highlighted. A Family goal
  card sits below it ("Everyone above 80 · 3 of 4 there").
- **Teens must consent to sharing**, and the app must show clearly what parents can see.

### Privacy (design screen 08)
- Scoring runs on the phone. **Only the score and tier sync.** Raw motion data and location history (routes,
  event locations) never leave the phone.
- A Privacy screen shows "Raw motion data · On device", "Location history · On device", and two toggles:
  "Share score with family" (the consent/sharing switch) and "Partner offers".

### Rewards
- Parents set goals tied to the Curbside Score (e.g. "80+ for 4 weeks → $20 / later curfew / custom").
- Partner rewards (Sephora, Taco Bell, etc.) unlock by score tier. **There are no real partnerships.**
  Use mock data behind a protocol so a real backend can replace it later, and **no real brand logos**.
- The Rewards tab (screen 06) has tier chips, the current-tier offer card with "Show at checkout" and a QR
  code, and a locked next-tier card with a progress bar and "N points to go". Parent rewards are on this
  tab too.

### Drives
- Drives start automatically: `CMMotionActivityManager` (automotive activity) plus location detect driving
  and start/stop recording. The manual Start Drive button stays.
- Driving screen (screen 02): a dark map with a yellow route line, plus a bottom glass card showing "Drive
  detected", the trip name, big MPH, and a coral End drive button. Nothing else.
- Drive Complete (screens 03–04): a 270° score ring, "Great drive · N points lost", four tiles, the event
  map, a coaching card, the points breakdown, a speed chart with event marks, and "This drive moved your
  score from X to Y". Tapping an event opens the 5-second replay.

### Safety (non-negotiable)
- **No interactive UI or notifications during a drive.** The driving screen shows only the map, trip name,
  speed, and End drive.
- **No live event popups.** The demo video shows "Hard brake" / "Sharp turn" popups during the drive. Never
  build them. Events appear only after the drive ends.
- Every alert or prompt goes through `PromptGate` (`Curbside/App/PromptGate.swift`), which holds prompts
  until the drive ends. Never call `.alert` / `.sheet` / notifications for app prompts directly.

## Design system

The reference is in `design/`: screenshots `01`–`08`, plus `curbside-demo-video.html`, whose JS has the exact
colors, copy, and layout values.
- **Every color, font, spacing value, and the glass card style lives in one file,
  `Curbside/Support/DesignSystem.swift`.** Views never hard-code a color or font.
- The app is dark only.
  - Background: #0D0D0F, with a faint yellow glow top-left, a faint ice-blue glow bottom-right, and a
    topographic line texture at about 7% opacity.
  - Glass cards: white at 7% fill, a 1.5 pt white border at 13%, and a 28 pt corner radius (24 pt for
    tiles).
- Colors:
  - Accent yellow #FFC400: primary buttons, the selected tab pill, the score ring, routes, highlights.
  - Coral #FF5A4E: End drive and hard-brake markers.
  - Green #4ADE80: gains.
  - Muted text: white at 62%.
- Tier colors: Bronze #CD7F32, Silver #C0C7D1, Gold #FFC400, Platinum #F2F6FF. A tier color always appears
  with its name.
- Type:
  - Numbers are big, heavy, and SF Rounded.
  - Labels are small, uppercase, and letter-spaced (about 0.14 em).
  - Body text uses SF Pro.
- A floating 5-tab bar (Drive, Trends, History, Family, Rewards). The selected tab is a yellow pill.
- After each redesign phase, screenshot the changed screens in the Simulator, compare them with the matching
  `design/` screenshot, and fix the differences.

## Architecture

```
Curbside/                 iOS app target (SwiftUI, @Observable, SwiftData, Swift 6 strict concurrency)
  App/                    entry point, RootView, PromptGate
  Recording/              LocationService, MotionService, DriveRecorder, RecordingView
  Drives/                 Drive (@Model), home, history, summary, event replay, debug views
  Score/                  gauge, score card, "what's moving your score", Trends tab
  Family/                 FamilyBackend (Firebase + demo), FamilyStore, sign-in, consent, leaderboard, parent dashboard
  Rewards/                Rewards tab, parent reward cards and the new-reward form, partner catalog, RewardsCenter, celebration
  Support/                DesignSystem (colors, fonts, spacing, glass cards), formatting, shared UI helpers
CurbsideCore/             local Swift package: pure Swift, no UIKit / CoreLocation / SwiftUI
  Sources/CurbsideCore/
    CurbsideConfig.swift  ← ALL tunable thresholds and weights live here
    Detection/            EventDetector, AxisEstimator, GPSTrack
    Scoring/              DriveScore (0–100) and CurbsideScoreReport (0–100, tiers, history, trend, factors)
    Replay/               EventClip: the 5 s before each event, rebuilt from stored data
    Family/               SharedDrive/SharedStanding (what leaves the phone), leaderboard, invite codes, disclosure
    Rewards/              ParentReward + RewardEvaluator, TierUnlock, CelebrationQueue, PartnerRewardsProvider + mock
    Export/               DriveLog (debug JSON format), DriveMetrics
  Sources/replay/         `replay` CLI: runs an exported drive through the real detection + scoring code
  Tests/                  Swift Testing suites; SyntheticDrive builds physically consistent fake drives
firebase/                 firestore.rules + emulator tests (npm test)
site/                     presentation website (Vite + React + TS, M3 styling); see site/README.md
project.yml               XcodeGen spec, the source of truth for Curbside.xcodeproj
```

Rules already in place:
- **All thresholds and weights go in `CurbsideConfig.swift`.** No magic numbers in detection or scoring code.
- **Detection and scoring logic lives in `CurbsideCore` as pure Swift with unit tests.** The app only feeds
  it sensor samples and displays its results. The live app and the replay tool run the same code.
- **Tune on real drives with the replay tool**, not by guessing.
- Detection details:
  - Events use gravity-free acceleration projected onto a forward axis learned from GPS speed changes.
  - Hard brakes and fast starts must be confirmed by a GPS speed change.
  - Phone handling suppresses events.
- Raw drive logs are JSON files in `Documents/Drives` (visible in the Files app). SwiftData stores the
  summary, the events, and a 1 Hz route.
- Event replay keeps no extra buffer. `EventClipBuilder` re-runs the raw log through `EventDetector` to
  recover the exact brake/cornering signal around each event. If the raw log is missing, it falls back to
  the stored 1 Hz route and estimates braking from GPS speed changes, with no cornering force.
- The Curbside Score is never stored. `CurbsideScoreReport.compute` is a pure function of all scored
  drives, so tuning `CurbsideScoreConfig` re-scores everything. The formula in plain words:
  - It's a recency-weighted average of drive scores. Each older drive counts 0.95× the next newer one,
    decaying by drive count, never by time.
  - Each drive is weighted by distance (5 mi = 1 drive, clamped to 0.4–2).
  - New drivers start with 8 virtual drives scoring 80.
  - The average is mapped to 0–100 through `scaleAnchors`, which set how hard each tier is to reach.
- App navigation: a floating tab bar with Drive (home), Trends, History, Family, and Rewards. A saved drive
  opens Drive Complete on the Drive tab.
- Chart colors:
  - Score lines are yellow.
  - The habit series use a validated categorical palette (blue / orange / aqua), with dark-mode values.
  - Tier and severity colors always appear with a text label.
- Rewards:
  - Parents set a goal (reach N+, or hold N+ for W weeks) and a prize. The prize is money, a privilege, or
    something custom.
  - Progress is computed on the teen's phone (`RewardEvaluator`, from score history) and is only published
    while the teen is sharing.
  - Rules: only parents create, edit, or delete rewards; only the teen writes `progress`.
  - A hold streak keeps running between drives, because the score only changes when you drive.
- Partner catalog:
  - `PartnerRewardsProvider` with `MockPartnerRewardsProvider`. The partners are fictional placeholders,
    use SF Symbols, and are marked as samples.
  - A test fails if a real brand name shows up in the mock data. Swap the provider to go live.
- Celebrations: a parent reward earned, or a new tier reached for the first time.
  - They're detected only when a drive is saved, by comparing just before vs just after the drive.
  - They're shown only through `RewardsCenter`/`CelebrationQueue`, which refuses while recording or saving.
  - Never show a celebration at any other time.
- Units are mph only.
- Gotcha: never assign to a property inside its own `didSet` on an `@Observable` class. The macro turns it
  into a computed property and it recurses until it crashes.
- Backend: Firebase (Auth with Sign in with Apple, plus Firestore), project `curbside-3fb59`. It was
  chosen over CloudKit for invite codes, the cross-user leaderboard, and possible Android/web parents.
  - All access goes through the `FamilyBackend` protocol. `FirebaseFamilyBackend` is the real one;
    `DemoFamilyBackend` is an in-memory demo family ("Preview with a demo family"). `FamilyStore` holds the
    setup phase, members, and syncing.
  - `Curbside/GoogleService-Info.plist` is gitignored and copied into the app by a build script only when
    it exists. Without it the app builds and Family runs in demo mode only.
  - Privacy is enforced in `firebase/firestore.rules` and tested in the emulator, not just in the app:
    - Nothing about a member is stored unless they're sharing.
    - Drives are readable only by their owner and the family's parents.
    - Teens see the member list and scores, but never other members' drives.
  - What leaves the phone is exactly what's in `CurbsideCore/Family/SharedData.swift`. A test fails if it
    gains a field that `SharingDisclosure` (the consent screen) doesn't list.
  - Raw logs, speeds, g-forces, replays, routes, and event locations never leave the phone. (Redesign
    phase R5 removes the route and coordinate uploads that phase 5 added.)
  - Only drives recorded after the user consents are uploaded.
  - Uploads happen silently after a drive is saved, never with UI.
  - When the rules change, re-test them and paste them into Firebase console › Firestore › Rules.

## Commands

```sh
xcodegen generate                         # after adding/removing files or editing project.yml
cd CurbsideCore && swift test             # core unit tests (fast, no simulator)
cd CurbsideCore && swift run replay drive.json --verbose [--csv signal.csv] [--config cfg.json]
cd CurbsideCore && swift run replay --dump-config > cfg.json
cd firebase && JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="$JAVA_HOME/bin:$PATH" npm test   # Firestore rules (emulator)
xcodebuild -project Curbside.xcodeproj -scheme Curbside -destination 'generic/platform=iOS Simulator' build
```

Bundle ID `com.sophaban.curbside`, team `A3ZZHU4YHF`. The Simulator has no motion sensors, so test
detection on a real phone.

## Phases

Work one phase at a time. After each phase, tell the user what to test on a real drive, commit with a
clear message, and stop until they've tested.

1. ✅ Drive recording, event detection, debug export, and replay harness
2. ✅ Drive score + post-drive summary (score, event map color-coded by severity, the one habit to fix,
   speed chart)
3. ✅ 5-second event replay: tap an event to watch a car marker, a speed readout, and a brake-force indicator
   over the 5 s leading up to it
4. ✅ Curbside Score (pure module + tests), trends, and history
5. ✅ Accounts, families, parent dashboard, leaderboard, and teen consent
6. ✅ Rewards: parent goals plus a mock partner catalog behind a protocol

### Redesign (matches `design/`)
- R1. Design system, floating tab bar, and the Curbside Score rescaled to 0–100 with four tiers (with
  tests)
- R2. Home and Drive Complete
- R3. Driving screen and automatic drive detection
- R4. Rewards and Family
- R5. Privacy screen and the sync/rules changes (score and tier only, no routes)
