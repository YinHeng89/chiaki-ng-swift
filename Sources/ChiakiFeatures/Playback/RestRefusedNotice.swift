import SwiftUI
import DesignSystem

/// An orange glass capsule warning that the console refused to enter rest mode and is still on, announced to
/// VoiceOver when it appears.
public struct RestRefusedNotice: View {
    /// Creates a rest refused notice.
    public init() {
    }

    private static let message = "Your console didn’t go into rest mode. It’s still on."

    public var body: some View {
        Label(Self.message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(AppGlass.control.tint(.orange.opacity(0.25)), in: .capsule)
            .onAppear {
                AccessibilityNotification.Announcement(Self.message).post()
            }
    }
}
