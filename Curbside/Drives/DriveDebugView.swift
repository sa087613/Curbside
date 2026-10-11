import CurbsideCore
import SwiftUI

/// Sensor/detector diagnostics and the raw JSON export, for tuning.
struct DriveDebugView: View {
    let drive: Drive

    var body: some View {
        let rejected = drive.rejected
        List {
            Section {
                LabeledContent("Started", value: drive.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Format.duration(drive.duration))
                LabeledContent("Distance", value: Format.miles(drive.distanceMeters))
                LabeledContent("Top speed", value: Format.mph(drive.maxSpeedMps))
                LabeledContent("Route points", value: drive.route.count.formatted())
            }

            Section {
                LabeledContent("Motion samples", value: drive.motionSampleCount.formatted())
                LabeledContent("GPS fixes", value: drive.locationCount.formatted())
                LabeledContent("Forward axis calibrated", value: drive.calibratedFraction.formatted(.percent.precision(.fractionLength(0))))
                if drive.motionSampleCount == 0 {
                    Text("No motion data was recorded on this device.")
                        .foregroundStyle(.secondary)
                }
                if FileManager.default.fileExists(atPath: drive.logURL.path) {
                    ShareLink(item: drive.logURL) {
                        Label("Export Raw Data (JSON)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("Raw data file is missing.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Replay on a Mac: swift run replay <file>.json --verbose (from CurbsideCore/). The file is also in Files › On My iPhone › Curbside › Drives.")
            }

            if !rejected.isEmpty {
                Section("Rejected candidates (\(rejected.count))") {
                    ForEach(Array(rejected.enumerated()), id: \.offset) { _, r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Format.clock(r.startTime))  \(r.kind.displayName) · \(r.peakG, format: .number.precision(.fractionLength(2)))g")
                                .font(.subheadline)
                            Text(r.reason.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let notes = drive.notes
            if !notes.isEmpty {
                Section("Detector notes") {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        Text("\(Format.clock(n.t))  \(n.message)")
                            .font(.caption)
                    }
                }
            }
        }
        .glassList()
        .navigationTitle("Debug details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
