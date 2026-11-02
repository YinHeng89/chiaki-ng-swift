import ChiakiModels
import Foundation
import SwiftUI

/// An operation progress report paired with the time it arrived, so elapsed time since the report can be
/// shown.
public struct TimedProgress: Equatable, Sendable {
    /// The progress report.
    public let progress: OperationProgress
    /// When the report was received.
    public let receivedAt: Date

    /// Pairs a progress report with its arrival time.
    /// - Parameters:
    ///   - progress: The progress report.
    ///   - receivedAt: When the report was received.
    public init(_ progress: OperationProgress, at receivedAt: Date) {
        self.progress = progress
        self.receivedAt = receivedAt
    }

    /// Formats the report for display, including how long ago it was received.
    /// - Parameter now: The current time; earlier times are clamped to zero elapsed.
    public func text(at now: Date) -> OperationProgressText {
        OperationProgressText(progress, sinceReport: .seconds(max(0, now.timeIntervalSince(receivedAt))))
    }
}

/// Shows a progress title and detail lines, refreshing every second so elapsed time stays current.
struct OperationProgressView: View {
    /// The progress report to show.
    let progress: TimedProgress

    var body: some View {
        TimelineView(.periodic(from: progress.receivedAt, by: 1)) { context in
            let text = progress.text(at: context.date)
            VStack(spacing: 4) {
                Text(text.title)
                    .font(.callout.weight(.medium))
                ForEach(text.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("operation-progress")
        }
    }
}
