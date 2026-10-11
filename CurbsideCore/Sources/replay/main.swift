import CurbsideCore
import Foundation

// Replays an exported drive through the real detection code.
//
//   swift run replay drive.json [--config cfg.json] [--log-config] [--csv signal.csv] [--verbose]
//   swift run replay --dump-config > cfg.json

let usage = """
usage: replay <drive.json> [options]
       replay --dump-config

options:
  --config <file>   use thresholds from a JSON config (start from --dump-config)
  --log-config      use the config the app recorded with, instead of the current defaults
  --csv <file>      write the processed signal (speed, longitudinal/lateral g) per sample
  --verbose         list every rejected candidate and detector note
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var inputPath: String?
var configPath: String?
var csvPath: String?
var useLogConfig = false
var verbose = false

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--dump-config":
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try e.encode(DetectionConfig.default), as: UTF8.self))
        exit(0)
    case "--config":
        guard !args.isEmpty else { fail(usage) }
        configPath = args.removeFirst()
    case "--csv":
        guard !args.isEmpty else { fail(usage) }
        csvPath = args.removeFirst()
    case "--log-config": useLogConfig = true
    case "--verbose", "-v": verbose = true
    case "--help", "-h": print(usage); exit(0)
    default:
        if a.hasPrefix("-") || inputPath != nil { fail(usage) }
        inputPath = a
    }
}

guard let inputPath else { fail(usage) }

let log: DriveLog
do {
    log = try DriveLog.decode(Data(contentsOf: URL(fileURLWithPath: inputPath)))
} catch {
    fail("Couldn't read \(inputPath): \(error)")
}

var config = DetectionConfig.default
if let configPath {
    do {
        config = try JSONDecoder().decode(DetectionConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    } catch {
        fail("Couldn't read config \(configPath): \(error)")
    }
} else if useLogConfig {
    guard let c = log.config else { fail("This export has no readable config") }
    config = c
}

var csvLines: [String] = []
if csvPath != nil { csvLines.append("t,speed_mph,longitudinal_g,lateral_g,gyro_lateral_g,axis_calibrated,handling") }
let tap: ((SignalFrame) -> Void)? = csvPath == nil ? nil : { f in
    csvLines.append(String(format: "%.3f,%@,%.4f,%.4f,%.4f,%d,%d", f.t,
                           f.speed.map { String(format: "%.2f", Units.mph(fromMps: $0)) } ?? "",
                           f.longitudinalG, f.lateralG, f.gyroLateralG, f.axisCalibrated ? 1 : 0, f.handling ? 1 : 0))
}

let result = log.detect(config: config, signalTap: tap)
let duration = log.endDate.timeIntervalSince(log.startDate)
let metrics = DriveMetrics.compute(locations: log.locations, duration: duration)

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func mph(_ mps: Double) -> String { String(format: "%.0f", Units.mph(fromMps: mps)) }
func clock(_ t: Double) -> String { String(format: "%2d:%02d", Int(t) / 60, Int(t) % 60) }

let df = DateFormatter()
df.dateStyle = .medium
df.timeStyle = .short
let motionRate = log.motion.count > 1 ? Double(log.motion.count - 1) / (log.motion.last!.t - log.motion.first!.t) : 0

print("Drive \(df.string(from: log.startDate))  ·  \(log.deviceModel)  ·  app \(log.appVersion)")
print(String(format: "  %@ min  ·  %.2f mi  ·  max %@ mph", clock(duration), metrics.distanceMiles, mph(metrics.maxSpeedMps)))
print(String(format: "  %d motion samples (%.1f Hz)  ·  %d GPS fixes", log.motion.count, motionRate, log.locations.count))
print(String(format: "  forward axis calibrated for %.0f%% of the drive", result.calibratedFraction * 100))
print("")

print("Events (\(result.events.count)):")
for e in result.events {
    let where_ = e.latitude.map { String(format: "%.5f,%.5f", $0, e.longitude ?? 0) } ?? "-"
    print("  \(clock(e.startTime))  \(pad(e.kind.displayName, 11)) \(pad(e.severity.displayName, 9))"
          + String(format: "peak %.2fg  %4.1fs  ", e.peakG, e.endTime - e.startTime)
          + "\(mph(e.speedBefore))→\(mph(e.speedAfter)) mph  \(where_)\(e.usedCalibratedAxis ? "" : "  [fallback axis]")")
}
if result.events.isEmpty { print("  none") }
print("")

if let score = DriveScore.compute(events: result.events, distanceMeters: metrics.distanceMeters) {
    print("Drive score: \(score.rounded) / 100")
    for d in score.deductions {
        print("  \(pad(d.kind.displayName, 11)) ×\(d.count)  " + String(format: "−%.1f pts", d.points))
    }
    if let habit = score.habitToFix {
        print("  Habit to fix: \(habit.kind.displayName.lowercased()) (cost \(Int(habit.points.rounded())) points)")
    }
} else {
    print(String(format: "Drive score: not scored (%.2f mi is under the %.1f mi minimum)",
                 metrics.distanceMiles, ScoringConfig.default.minScoredMiles))
}
print("")

let byReason = Dictionary(grouping: result.rejected, by: { $0.reason.key })
print("Rejected candidates (\(result.rejected.count)): "
      + byReason.sorted { $0.value.count > $1.value.count }.map { "\($0.key) ×\($0.value.count)" }.joined(separator: ", "))
if verbose {
    for r in result.rejected where !(r.reason.key == "too short") {
        print("  \(clock(r.startTime))  \(pad(r.kind.displayName, 11)) " + String(format: "peak %.2fg  ", r.peakG) + r.reason.description)
    }
    print("")
    print("Detector notes:")
    for n in result.notes { print("  \(clock(n.t))  \(n.message)") }
}

if let live = log.liveEvents {
    print("")
    let liveSig = live.map { "\($0.kind)@\(Int($0.startTime))" }.sorted()
    let replaySig = result.events.map { "\($0.kind)@\(Int($0.startTime))" }.sorted()
    if liveSig == replaySig {
        print("Matches what the app found live (\(live.count) events).")
    } else {
        print("Differs from the app's live result: app found \(live.count), replay found \(result.events.count)."
              + (configPath != nil || !useLogConfig ? " (Expected if thresholds changed.)" : ""))
    }
}

if let csvPath {
    do {
        try csvLines.joined(separator: "\n").write(toFile: csvPath, atomically: true, encoding: .utf8)
        print("Wrote \(csvLines.count - 1) samples to \(csvPath)")
    } catch {
        fail("Couldn't write \(csvPath): \(error)")
    }
}
