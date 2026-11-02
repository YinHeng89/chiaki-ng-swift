import ComposableArchitecture
import SwiftUI
import ChiakiModels
import DesignSystem
import PlatformUI
import Foundation

/// The PS5 cloud console's toasts and recording banner, in the stream's top-trailing corner.
///
/// It only displays; it takes no input and never holds focus. Besides the reducer's own timer, the layer
/// expires the shown toast after its time, so a toast still leaves when the effect that timed it was cancelled.
public struct CloudToastLayer: View {
    /// The toasts.
    public let toasts: StoreOf<CloudToastsReducer>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    /// Creates a cloud toast layer.
    ///
    /// - Parameter toasts: The toasts.
    public init(toasts: StoreOf<CloudToastsReducer>) {
        self.toasts = toasts
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let recording = toasts.recording {
                CloudRecordingPill(banner: recording)
                    .transition(transition)
            }
            if let toast = toasts.shown {
                CloudToastCard(notice: toast.notice, thumbnail: toast.thumbnail)
                    .id(toast.id)
                    .transition(transition)
            }
        }
        .padding(.top, 28)
        .padding(.trailing, 28 + layout.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .task(id: toasts.shown?.id) {
            guard let shown = toasts.shown else {
                return
            }
            try? await Task.sleep(for: shown.notice.shownFor + .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            toasts.send(.expired(shown.id))
        }
        .animation(animation, value: toasts.shown)
        .animation(animation, value: toasts.recording == nil)
    }

    private var animation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        return .spring(duration: 0.35)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }
}

/// One PS5 cloud toast: the notice's symbol or the capture's preview, its headline and its lines, announced
/// to VoiceOver as it appears.
private struct CloudToastCard: View {
    /// What the console reported.
    public let notice: CloudSystemNotice
    /// The capture's preview as JPEG data, shown in place of the symbol.
    public var thumbnail: Data?

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.headline)
                    .font(.headline)
                    .lineLimit(2)
                ForEach(Array(notice.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 220, maxWidth: 360, alignment: .leading)
        .glassEffect(AppGlass.notice, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            AccessibilityNotification.Announcement(notice.announcement).post()
        }
    }

    @ViewBuilder private var leading: some View {
        if let thumbnail, let image = PlatformImage(data: thumbnail) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 42)
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint, lineWidth: 2)
                }
                .transition(.opacity)
        } else {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 40, height: 40)
                .background(tint, in: .circle)
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .screenshotSaved:
            "camera.fill"
        case .recordingSaved:
            "video.fill"
        case .screenshotRefused, .recordingRefused:
            "nosign"
        case .recordingPaused:
            "pause.circle.fill"
        case .recordingResumed:
            "record.circle"
        case .recordingLimitReached:
            "timer"
        case .capturesUploading:
            "icloud.and.arrow.up"
        case .trophyEarned:
            "trophy.fill"
        case .trialTimeLeft:
            AppIcon.trial.rawValue
        case .invitation:
            "person.badge.plus"
        case .message:
            "message.fill"
        case .invitationJoinFailed:
            "person.crop.circle.badge.exclamationmark"
        }
    }

    private var symbolColor: Color {
        switch notice.kind {
        case .screenshotRefused, .recordingRefused, .recordingPaused, .recordingLimitReached,
             .capturesUploading, .trophyEarned(.bronze), .trialTimeLeft, .invitationJoinFailed:
            .white
        case .screenshotSaved, .recordingSaved, .recordingResumed, .trophyEarned, .invitation, .message:
            .black.opacity(0.8)
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .trophyEarned(let grade):
            Self.trophyColor(grade)
        case .screenshotRefused, .recordingRefused, .trialTimeLeft, .invitationJoinFailed:
            .orange
        case .recordingPaused, .recordingLimitReached, .capturesUploading:
            Palette.slate
        case .screenshotSaved, .recordingSaved, .recordingResumed, .invitation, .message:
            Palette.accent
        }
    }

    private static func trophyColor(_ grade: CloudSystemNotice.TrophyGrade) -> Color {
        switch grade {
        case .bronze:
            Color(red: 0.80, green: 0.52, blue: 0.30)
        case .silver:
            Color(red: 0.76, green: 0.78, blue: 0.82)
        case .gold:
            Color(red: 0.96, green: 0.77, blue: 0.26)
        case .platinum:
            Color(red: 0.70, green: 0.85, blue: 0.95)
        }
    }
}

/// The PS5 cloud console's recording banner: a pulsing dot, Recording and the clip's length so far.
private struct CloudRecordingPill: View {
    /// The banner.
    public let banner: CloudRecordingBanner

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
            Text("Recording")
                .font(.callout.weight(.semibold))
            if !banner.elapsed.isEmpty {
                Text(banner.elapsed)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(AppGlass.notice, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.elapsed.isEmpty
            ? "Recording"
            : "Recording \(banner.elapsed)")
            .onAppear {
                AccessibilityNotification.Announcement("Recording started").post()
            }
    }
}

/// The PS5 cloud console's notices, shown one at a time as toasts, and its recording banner.
///
/// Toasts show in the order they arrived, each for its notice's time; at most ``queueLimit`` wait, the
/// oldest dropped first. A capture's preview joins the toast of its saved screenshot or clip whichever of
/// the two arrives first.
@Reducer public struct CloudToastsReducer {
    /// One toast.
    public struct Toast: Equatable, Identifiable, Sendable {
        /// The toast's number, in arrival order.
        public let id: Int

        /// What the console reported.
        public let notice: CloudSystemNotice

        /// The capture's preview as JPEG data, once it arrived.
        public var thumbnail: Data?

        /// Creates a toast.
        ///
        /// - Parameters:
        ///   - id: The toast's number, in arrival order.
        ///   - notice: What the console reported.
        ///   - thumbnail: The capture's preview as JPEG data, once it arrived.
        public init(id: Int, notice: CloudSystemNotice, thumbnail: Data? = nil) {
            self.id = id
            self.notice = notice
            self.thumbnail = thumbnail
        }

        /// Whether a capture's preview belongs on this toast: a screenshot's on a saved screenshot, a clip's on
        /// a saved clip, and only while it has none.
        ///
        /// - Parameter capture: The preview.
        /// - Returns: Whether the preview joins this toast.
        public func accepts(_ capture: CloudCaptureThumbnail) -> Bool {
            guard thumbnail == nil else {
                return false
            }
            switch notice.kind {
            case .screenshotSaved:
                return !capture.video
            case .recordingSaved:
                return capture.video
            default:
                return false
            }
        }
    }

    /// Whether a toast shows.
    public enum Phase: Equatable, Sendable {
        /// No toast shows.
        case idle

        /// The toast shows.
        case showing(Toast)
    }

    /// The toasts and the recording banner.
    @ObservableState public struct State: Equatable {
        /// Whether a toast shows.
        public var phase = Phase.idle

        /// The toasts waiting, oldest first.
        public var queued: [Toast] = []

        /// The recording banner, while the console records.
        public var recording: CloudRecordingBanner?

        /// A preview that arrived before its toast.
        public var waitingThumbnail: CloudCaptureThumbnail?

        /// The next toast's number.
        public var nextID = 0

        /// Creates the state with nothing shown.
        public init() {
        }

        /// The toast that shows.
        public var shown: Toast? {
            guard case .showing(let toast) = phase else {
                return nil
            }
            return toast
        }

        /// Whether nothing shows or waits.
        public var isEmpty: Bool {
            phase == .idle && queued.isEmpty && recording == nil
        }
    }

    /// Everything the toasts react to.
    public enum Action: Equatable, Sendable {
        /// The console reported a notice.
        case received(CloudSystemNotice)

        /// The console sent a capture's preview.
        case thumbnail(CloudCaptureThumbnail)

        /// The toast with this number ran out of time.
        case expired(Int)

        /// The recording banner changed, or `nil` once recording stopped.
        case recording(CloudRecordingBanner?)

        /// Clears every toast and the banner, as the stream stops playing.
        case clear
    }

    /// The most toasts that wait.
    public static let queueLimit = 4

    /// The effects the toasts cancel.
    public enum CancelID: Sendable {
        /// The shown toast's timer.
        case expiry
    }

    /// Times each toast.
    @Dependency(\.continuousClock) var clock

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .received(let notice):
                return received(notice, state: &state)
            case .expired(let id):
                guard state.shown?.id == id else {
                    return .none
                }
                guard !state.queued.isEmpty else {
                    state.phase = .idle
                    return .none
                }
                return show(state.queued.removeFirst(), state: &state)
            case .thumbnail(let capture):
                attach(capture, state: &state)
                return .none
            case .recording(let banner):
                state.recording = banner
                return .none
            case .clear:
                state.phase = .idle
                state.queued = []
                state.recording = nil
                state.waitingThumbnail = nil
                return .cancel(id: CancelID.expiry)
            }
        }
    }

    private func received(_ notice: CloudSystemNotice, state: inout State) -> Effect<Action> {
        var toast = Toast(id: state.nextID, notice: notice)
        state.nextID += 1
        if let waiting = state.waitingThumbnail, toast.accepts(waiting) {
            toast.thumbnail = waiting.jpeg
            state.waitingThumbnail = nil
        }
        guard case .idle = state.phase else {
            if state.queued.count >= Self.queueLimit {
                state.queued.removeFirst()
            }
            state.queued.append(toast)
            return .none
        }
        return show(toast, state: &state)
    }

    private func attach(_ capture: CloudCaptureThumbnail, state: inout State) {
        if case .showing(var toast) = state.phase, toast.accepts(capture) {
            toast.thumbnail = capture.jpeg
            state.phase = .showing(toast)
            return
        }
        if let index = state.queued.firstIndex(where: { toast in
            toast.accepts(capture)
        }) {
            state.queued[index].thumbnail = capture.jpeg
            return
        }
        state.waitingThumbnail = capture
    }

    private func show(_ toast: Toast, state: inout State) -> Effect<Action> {
        state.phase = .showing(toast)
        return .run { [clock] send in
            try await clock.sleep(for: toast.notice.shownFor)
            await send(.expired(toast.id))
        }
        .cancellable(id: CancelID.expiry, cancelInFlight: true)
    }
}
