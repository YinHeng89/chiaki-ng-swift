import DesignSystem
import MenuFocus
import SwiftUI

/// A search field floating over a dimmed screen, focused on appearance and dismissed by Done, submit or a tap
/// outside, while what it searches keeps filtering underneath as the text changes.
struct SearchOverlay: View {
    /// The field's placeholder.
    let prompt: String
    /// The text searched for.
    @Binding var query: String
    /// The overlay's accessibility identifier.
    let identifier: String
    /// Dismisses the overlay.
    let done: () -> Void
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var editing: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Dimming.strong.color
                .contentShape(.rect)
                .onTapGesture(perform: done)
            field
                .padding(.horizontal, 28 + layout.sideInset)
                .padding(.top, 18 + layout.topChromeInset)
        }
        .onAppear {
            editing = true
        }
        .accessibilityIdentifier(identifier)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            SwiftUI.TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .menuFocusBinding($editing)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(done)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button("Done", action: done)
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .font(.system(size: 17))
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 52)
        .glassEffect(AppGlass.control, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1)
        }
    }
}
