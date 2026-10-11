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
- **Curbside Score (300–850), long term.** A slow-moving, credit-score-style weighted rolling average of
  recent drive scores (recent drives count more, older ones decay).
  - Missing days doesn't hurt it: it decays by drive count, not calendar time.
  - Consistent good driving raises it gradually.
  - One bad drive dents it a little; a pattern of bad drives drops it more.
  - Shown like a credit score: a gauge, tier labels, a trend arrow, and "what's moving your score" factors.

### Family
- Parent and teen accounts. A parent creates a family and invites teens with a code.
- Parent dashboard: each teen's Curbside Score, a weekly summary, and recent drives with maps.
- Family tree leaderboard ranks everyone by Curbside Score, including parents (they can drive too).
- **Teens must consent to sharing**, and the app must show clearly what parents can see.

### Rewards
- Parents set goals tied to the Curbside Score (e.g. "750+ for 4 weeks → $20 / later curfew / custom").
- Partner rewards (Sephora, Taco Bell, etc.) unlock by score tier. **There are no real partnerships.**
  Use mock data behind a protocol so a real backend can replace it later, and **no real brand logos**.

### Safety (non-negotiable)
- **No interactive UI or notifications during a drive.** The recording screen shows only the speed and a
  Stop button.
- Every alert or prompt goes through `PromptGate` (`Curbside/App/PromptGate.swift`), which holds prompts
  until the drive ends. Never call `.alert` / `.sheet` / notifications for app prompts directly.

## Architecture

```
Curbside/                 iOS app target (SwiftUI, @Observable, SwiftData, Swift 6 strict concurrency)
  App/                    entry point, RootView, PromptGate
  Recording/              LocationService, MotionService, DriveRecorder, RecordingView
  Drives/                 Drive (@Model), drive list, summary, debug views
  Support/                formatting and shared UI helpers
CurbsideCore/             local Swift package: pure Swift, no UIKit / CoreLocation / SwiftUI
  Sources/CurbsideCore/
    CurbsideConfig.swift  ← ALL tunable thresholds and weights live here
    Detection/            EventDetector, AxisEstimator, GPSTrack
    Scoring/              drive score (Curbside Score is added in Phase 4)
    Replay/               EventClip: the 5 s before each event, rebuilt from stored data
    Export/               DriveLog (debug JSON format), DriveMetrics
  Sources/replay/         `replay` CLI: runs an exported drive through the real detection + scoring code
  Tests/                  Swift Testing suites; SyntheticDrive builds physically consistent fake drives
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
- Units are mph only.
- Gotcha: never assign to a property inside its own `didSet` on an `@Observable` class. The macro turns it
  into a computed property and it recurses until it crashes.
- Backend (Phase 5): Firebase (Auth + Firestore) was recommended over CloudKit, for invite codes, a
  cross-user leaderboard, and possible Android/web parents. Confirm with the user before adding it. Raw
  sensor logs never leave the phone; only summaries are shared, and only after the teen consents.

## Commands

```sh
xcodegen generate                         # after adding/removing files or editing project.yml
cd CurbsideCore && swift test             # core unit tests (fast, no simulator)
cd CurbsideCore && swift run replay drive.json --verbose [--csv signal.csv] [--config cfg.json]
cd CurbsideCore && swift run replay --dump-config > cfg.json
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
4. Curbside Score (pure module + tests), trends, and history
5. Accounts, families, parent dashboard, leaderboard, and teen consent
6. Rewards: parent goals plus a mock partner catalog behind a protocol
