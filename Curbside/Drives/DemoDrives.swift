import CurbsideCore
import Foundation
import SwiftData

/// Hard-coded sample drives for showing the app (e.g. to judges) without driving.
/// They have a 1 Hz route and events but no raw log, so replays use the route fallback.
/// Demo drives are recognised by their log file name and are never uploaded (uploads only
/// happen when the recorder saves a real drive).
enum DemoDrives {
    static let filePrefix = "demo-"

    static func isDemo(_ drive: Drive) -> Bool { drive.logFileName.hasPrefix(filePrefix) }

    /// A planned drive: when, which route, and what happened.
    private struct Plan {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let route: Int
        let events: [(DrivingEventKind, EventSeverity, Double)]   // kind, severity, fraction of the way through
    }

    // Oldest first: a few rough drives early on, getting smoother.
    private static let plans: [Plan] = [
        Plan(daysAgo: 38, hour: 16, minute: 10, route: 0, events: [(.hardBrake, .hard, 0.3), (.harshAcceleration, .moderate, 0.55), (.sharpTurn, .hard, 0.8)]),
        Plan(daysAgo: 35, hour: 7, minute: 40, route: 1, events: [(.hardBrake, .severe, 0.45), (.hardBrake, .moderate, 0.7)]),
        Plan(daysAgo: 31, hour: 18, minute: 5, route: 2, events: [(.harshAcceleration, .hard, 0.2), (.sharpTurn, .moderate, 0.6)]),
        Plan(daysAgo: 27, hour: 15, minute: 30, route: 0, events: [(.hardBrake, .moderate, 0.5)]),
        Plan(daysAgo: 24, hour: 7, minute: 45, route: 1, events: [(.hardBrake, .hard, 0.35), (.sharpTurn, .moderate, 0.75)]),
        Plan(daysAgo: 20, hour: 17, minute: 20, route: 2, events: []),
        Plan(daysAgo: 16, hour: 12, minute: 15, route: 0, events: [(.harshAcceleration, .moderate, 0.25)]),
        Plan(daysAgo: 12, hour: 7, minute: 35, route: 1, events: []),
        Plan(daysAgo: 9, hour: 19, minute: 0, route: 2, events: [(.hardBrake, .moderate, 0.6)]),
        Plan(daysAgo: 5, hour: 16, minute: 45, route: 0, events: []),
        Plan(daysAgo: 2, hour: 7, minute: 50, route: 1, events: []),
        Plan(daysAgo: 0, hour: 16, minute: 49, route: 2, events: [(.hardBrake, .hard, 0.4)]),
    ]

    /// Waypoints (lat, lon) for three Midtown Atlanta loops.
    private static let routes: [[(Double, Double)]] = [
        [(33.7756, -84.3963), (33.7756, -84.3880), (33.7812, -84.3862), (33.7869, -84.3833), (33.7905, -84.3870), (33.7898, -84.3961), (33.7840, -84.4010)],
        [(33.7712, -84.3920), (33.7712, -84.3800), (33.7650, -84.3790), (33.7590, -84.3795), (33.7540, -84.3860), (33.7560, -84.3940), (33.7630, -84.3965)],
        [(33.7800, -84.4060), (33.7870, -84.4065), (33.7935, -84.4010), (33.7990, -84.3925), (33.8030, -84.3860), (33.7975, -84.3800), (33.7900, -84.3790)],
    ]

    static func load(into context: ModelContext, now: Date = .now) {
        removeAll(from: context)
        let calendar = Calendar.current
        for (index, plan) in plans.enumerated() {
            let day = calendar.date(byAdding: .day, value: -plan.daysAgo, to: calendar.startOfDay(for: now))!
            var start = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day)!
            if start > now { start = now.addingTimeInterval(-40 * 60) }
            context.insert(makeDrive(plan, index: index, start: start))
        }
        try? context.save()
    }

    static func removeAll(from context: ModelContext) {
        let prefix = filePrefix
        try? context.delete(model: Drive.self, where: #Predicate { $0.logFileName.starts(with: prefix) })
        try? context.save()
    }

    private static func makeDrive(_ plan: Plan, index: Int, start: Date) -> Drive {
        // 1 Hz route along the waypoints at a cruising speed that wobbles like real traffic.
        let waypoints = routes[plan.route]
        var route: [RoutePoint] = []
        var t = 0.0, distance = 0.0
        for leg in 0..<(waypoints.count - 1) {
            let (a, b) = (waypoints[leg], waypoints[leg + 1])
            let legMeters = meters(a, b)
            var covered = 0.0
            while covered < legMeters {
                let cruise = 11.0 + 3.0 * sin(t / 23) + 1.5 * sin(t / 7)   // ~25 mph
                let ramp = min(1, t / 15)                                     // pull away from the start
                let speed = max(1.5, cruise * ramp)
                let f = covered / legMeters
                route.append(RoutePoint(t: t, latitude: a.0 + (b.0 - a.0) * f, longitude: a.1 + (b.1 - a.1) * f, speed: speed))
                covered += speed; distance += speed; t += 1
            }
        }

        var events: [DrivingEvent] = []
        for (kind, severity, fraction) in plan.events {
            let i = min(route.count - 3, max(2, Int(Double(route.count) * fraction)))
            let peakG: Double = switch severity { case .moderate: 0.33; case .hard: 0.42; case .severe: 0.55 }
            var before = route[i].speed ?? 10, after = before
            switch kind {
            case .hardBrake:
                after = max(1, before - peakG * 9.81 * 2)
                // Show the slowdown on the speed chart and in the replay.
                for j in i...(min(route.count - 1, i + 6)) {
                    let k = Double(j - i) / 6
                    route[j].speed = after + (before - after) * (j == i ? 1 : k * 0.9)
                }
            case .harshAcceleration:
                before = max(1, before - peakG * 9.81 * 2)
                route[i - 1].speed = before
            case .sharpTurn:
                break
            }
            let p = route[i]
            events.append(DrivingEvent(kind: kind, severity: severity, startTime: p.t - 0.8, endTime: p.t + 0.6,
                                       peakTime: p.t, peakG: peakG, speedBefore: before, speedAfter: after,
                                       latitude: p.latitude, longitude: p.longitude, usedCalibratedAxis: true))
        }

        let duration = route.last?.t ?? 0
        let maxSpeed = route.compactMap(\.speed).max() ?? 0
        let samples = Int(duration * 50)
        return Drive(id: UUID(), startDate: start, endDate: start.addingTimeInterval(duration),
                     metrics: DriveMetrics(distanceMeters: distance, durationSeconds: duration, maxSpeedMps: maxSpeed),
                     result: DetectionResult(events: events, calibratedFraction: 1, processedMotionSamples: samples),
                     route: route, motionSampleCount: samples, locationCount: route.count,
                     logFileName: "\(filePrefix)\(index).json")
    }

    private static func meters(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dLat = (b.0 - a.0) * 111_000
        let dLon = (b.1 - a.1) * 111_000 * cos(a.0 * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}
