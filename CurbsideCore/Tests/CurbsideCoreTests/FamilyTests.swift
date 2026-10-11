import CurbsideCore
import Foundation
import Testing

@Suite("Family")
struct FamilyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Privacy: what's shared is exactly what's disclosed

    /// All keys (recursively) in the JSON encoding of a value.
    private func keys(of value: some Encodable) throws -> Set<String> {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        var out = Set<String>()
        func walk(_ any: Any) {
            if let dict = any as? [String: Any] {
                for (k, v) in dict { out.insert(k); walk(v) }
            } else if let array = any as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return out
    }

    private func sampleDrive() -> SharedDrive {
        let event = DrivingEvent(kind: .hardBrake, severity: .hard, startTime: 61.3, endTime: 63, peakTime: 62, peakG: 0.44,
                                 speedBefore: 15, speedAfter: 4, latitude: 33.123456789, longitude: -84.987654321,
                                 usedCalibratedAxis: true)
        let route = (0..<500).map { i in
            RoutePoint(t: Double(i), latitude: 33 + Double(i) * 1e-4, longitude: -84 + sin(Double(i) / 20) * 1e-3, speed: 12)
        }
        let score = DriveScore.compute(events: [event], distanceMeters: 8_000)
        return SharedDrive.make(id: UUID(), startDate: now, durationSeconds: 612.4, distanceMeters: 8_000,
                                score: score, events: [event], route: route)
    }

    @Test(arguments: FamilyRole.allCases)
    func everySharedFieldIsDisclosed(role: FamilyRole) throws {
        let disclosed = SharingDisclosure.forRole(role).disclosedFields
        let standing = SharedStanding(score: 712, trendDelta: 5, weekly: .empty, updatedAt: now)
        var uploaded = try keys(of: sampleDrive()).union(keys(of: standing))
        if role == .teen {
            // Teens also publish progress on rewards their parents set.
            let progress = RewardProgress(currentScore: 712, streakStart: now, earnedAt: now, updatedAt: now)
            uploaded.formUnion(try keys(of: ["progress": progress]))
        }
        #expect(uploaded.subtracting(disclosed).isEmpty, "Shared but not disclosed: \(uploaded.subtracting(disclosed))")
    }

    @Test func sharedDriveCarriesNoSpeedsOrForces() throws {
        let k = try keys(of: sampleDrive())
        for forbidden in ["speed", "speedBefore", "speedAfter", "peakG", "maxSpeedMps", "motion", "t"] {
            #expect(!k.contains(forbidden))
        }
    }

    @Test func sharedDriveIsCompactAndRounded() throws {
        let d = sampleDrive()
        #expect(d.route.count <= FamilyConfig.default.sharedRouteMaxPoints)
        #expect(d.route.first == SharedPoint(lat: 33, lon: -84))
        #expect(d.events.first?.lat == 33.12346)
        #expect(d.events.first?.lon == -84.98765)
        #expect(d.events.first?.offsetSeconds == 61)
        #expect(d.durationSeconds == 612)
        #expect(d.miles == 4.97)
        #expect(d.score != nil)
    }

    // MARK: Route simplification

    @Test func simplifierKeepsEndpointsAndShapeWithinTolerance() {
        // A straight line with a 50 m detour in the middle.
        var points = (0...100).map { SharedPoint(lat: 33 + Double($0) * 1e-4, lon: -84) }
        points[50].lon = -84 + 50 / (111_320 * cos(33 * Double.pi / 180))
        let s = RouteSimplifier.simplify(points, toleranceMeters: 5, maxPoints: 300)
        #expect(s.first == points.first && s.last == points.last)
        #expect(s.contains(points[50]))
        #expect(s.count < 10)
    }

    @Test func simplifierHonorsMaxPoints() {
        let zigzag = (0..<2000).map { SharedPoint(lat: 33 + Double($0) * 1e-5, lon: -84 + ($0 % 2 == 0 ? 0 : 3e-4)) }
        let s = RouteSimplifier.simplify(zigzag, toleranceMeters: 1, maxPoints: 120)
        #expect(s.count <= 120)
        #expect(s.first == zigzag.first && s.last == zigzag.last)
    }

    // MARK: Weekly summary

    @Test func weeklySummaryCountsOnlyTheLastSevenDays() {
        func drive(daysAgo: Double, score: Int?, events: [DrivingEventKind]) -> SharedDrive {
            SharedDrive(id: UUID().uuidString, startDate: now.addingTimeInterval(-daysAgo * 86_400), durationSeconds: 600,
                        miles: 4, score: score,
                        events: events.map { SharedEvent(kind: $0, severity: .moderate, offsetSeconds: 0, lat: nil, lon: nil) },
                        route: [])
        }
        let w = WeeklySummary.compute(drives: [
            drive(daysAgo: 1, score: 90, events: [.hardBrake]),
            drive(daysAgo: 3, score: 81, events: [.hardBrake, .sharpTurn]),
            drive(daysAgo: 6.9, score: nil, events: []),
            drive(daysAgo: 8, score: 40, events: [.harshAcceleration]),
        ], now: now)
        #expect(w.drives == 3)
        #expect(w.miles == 12)
        #expect(w.averageScore == 86)
        #expect(w.hardBrakes == 2 && w.sharpTurns == 1 && w.fastStarts == 0)
        #expect(WeeklySummary.compute(drives: [], now: now) == .empty)
    }

    // MARK: Leaderboard

    private func member(_ name: String, _ role: FamilyRole, _ score: Int?, me: Bool = false) -> MemberStanding {
        MemberStanding(id: name, displayName: name, role: role,
                       standing: score.map { SharedStanding(score: $0, trendDelta: 0, weekly: .empty, updatedAt: now) }, isMe: me)
    }

    @Test func leaderboardRanksByScoreWithParentsIncluded() {
        let ranked = Leaderboard.rank([
            member("Sam", .teen, 702), member("Alex", .parent, 755), member("Riley", .teen, 781, me: true),
        ])
        #expect(ranked.map(\.member.displayName) == ["Riley", "Alex", "Sam"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func tiesShareARankAndNonSharersGoLast() {
        let ranked = Leaderboard.rank([
            member("Zoe", .teen, nil), member("Bea", .teen, 740), member("Al", .parent, 740),
            member("Cy", .teen, 690), member("Ann", .parent, nil),
        ])
        #expect(ranked.map(\.member.displayName) == ["Al", "Bea", "Cy", "Ann", "Zoe"])
        #expect(ranked.map(\.rank) == [1, 1, 3, nil, nil])
    }

    // MARK: Invite codes

    @Test func inviteCodesAvoidLookAlikes() {
        var rng = SeededRNG(seed: 9)
        for _ in 0..<500 {
            let code = InviteCode.generate(using: &rng)
            #expect(code.count == 8)
            #expect(!code.contains { "0O1IL".contains($0) })
        }
    }

    @Test func inviteCodeNormalization() {
        #expect(InviteCode.normalize(" abcd-efgh ") == "ABCDEFGH")
        #expect(InviteCode.normalize("ABCD EFGH") == "ABCDEFGH")
        #expect(InviteCode.normalize("ABCD-EFG") == nil)
        #expect(InviteCode.normalize("ABCD-EFG0") == nil)
        #expect(InviteCode.display("ABCDEFGH") == "ABCD-EFGH")
    }
}
