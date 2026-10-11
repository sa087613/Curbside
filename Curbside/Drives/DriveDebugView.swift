import CurbsideCore
import SwiftUI

/// Phase 1 drive detail: stats, detected events, and the debug export.
/// (Phase 2 replaces the top of this with the scored summary and map.)
struct DriveDetailView: View {
    let drive: Drive

    var body: some View {
        let events = drive.events
        let rejected = drive.rejected
        List {
            Section {
                LabeledContent("Started", value: drive.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Format.duration(drive.duration))
                LabeledContent("Distance", value: Format.miles(drive.distanceMeters))
                LabeledContent("Top speed", value: Format.mph(drive.maxSpeedMps))
            }

            Section("Events") {
                if events.isEmpty {
                    Text("No hard brakes, fast starts, or sharp turns.")
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    EventRow(event: event)
                }
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
        .navigationTitle(drive.startDate.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EventRow: View {
    let event: DrivingEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.title3)
                .foregroundStyle(event.severity.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.kind.displayName) · \(event.severity.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text("at \(Format.clock(event.startTime)) · \(event.peakG, format: .number.precision(.fractionLength(2)))g · \(Format.mph(event.speedBefore)) → \(Format.mph(event.speedAfter))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
