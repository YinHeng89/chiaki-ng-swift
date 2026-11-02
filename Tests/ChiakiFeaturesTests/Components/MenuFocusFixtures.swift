import ChiakiClients
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Synchronization
import Testing
@testable import ChiakiFeatures
import MenuFocus

@MainActor final class GridFocusProbe {
    var focus: String?
}

struct ColumnsFixture: View {
    let probe: GridFocusProbe
    @MenuFocusState private var focus: String?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(spacing: 20) {
                ForEach(1...4, id: \.self) { index in
                    FocusButton("Left \(index)") {}
                        .buttonStyle(.plain)
                        .menuFocused($focus, equals: "left\(index)")
                }
            }
            VStack(spacing: 20) {
                ForEach(1...3, id: \.self) { index in
                    FocusButton("Right \(index)") {}
                        .buttonStyle(.plain)
                        .menuFocused($focus, equals: "right\(index)")
                }
            }
        }
        .padding(40)
        .task {
            await Task.yield()
            focus = "right1"
        }
        .onChange(of: focus) { _, value in
            probe.focus = value
        }
    }
}

struct TextNavigationFixture: View {
    @MenuFocusState private var focused: Bool
    @State private var value = ""

    var body: some View {
        VStack {
            FocusButton("Before") {}
            TextField("Entry", text: $value)
                .menuFocusBinding($focused)
            FocusButton("After") {}
        }
        .onAppear {
            focused = true
        }
    }
}

struct TextEntryFixture: View {
    var valueChanged: (String) -> Void = { _ in }
    @MenuFocusState private var focused: Bool
    @State private var value = ""

    var body: some View {
        TextField("Entry", text: $value)
            .menuFocusBinding($focused)
            .controllerKeyboard(title: "Entry", text: $value, isFocused: focused)
            .onChange(of: value) { _, updated in
                valueChanged(updated)
            }
            .onAppear {
                focused = true
            }
    }
}

@MainActor final class FocusProbe {
    var focus: Int?
    var activations = [Int]()
    var highlighted = Set<Int>()
}

struct FocusHighlightLabel: View {
    let index: Int
    let probe: FocusProbe
    @Environment(\.menuItemFocused) private var highlighted

    var body: some View {
        Text("Action \(index)")
            .onChange(of: highlighted, initial: true) { _, value in
                if value {
                    probe.highlighted.insert(index)
                } else {
                    probe.highlighted.remove(index)
                }
            }
    }
}

struct FocusFixture: View {
    let probe: FocusProbe
    @MenuFocusState private var focused: Int?

    var body: some View {
        VStack {
            ForEach(0..<3) { index in
                FocusButton {
                    probe.activations.append(index)
                } label: {
                    FocusHighlightLabel(index: index, probe: probe)
                }
                .buttonStyle(.plain)
                .menuFocused($focused, equals: index)
                .disabled(index == 1)
            }
        }
        .onChange(of: focused) { _, value in
            probe.focus = value
        }
    }
}

struct ControlsFocusFixture: View {
    let probe: FocusProbe
    @MenuFocusState private var focused: Int?
    @State private var enabled = false
    @State private var value = 0.5
    @State private var selection = 0
    @State private var text = ""

    var body: some View {
        VStack {
            FocusButton("Action") {}
                .menuFocusBinding($focused, equals: 0)
            Toggle("Enabled", isOn: $enabled)
                .menuFocusBinding($focused, equals: 1)
            Slider(value: $value)
                .menuFocusBinding($focused, equals: 2)
            Picker("Choice", selection: $selection) {
                Text("First").tag(0)
                Text("Second").tag(1)
            }
            .menuFocusBinding($focused, equals: 3)
            TextField("Text", text: $text)
                .menuFocusBinding($focused, equals: 4)
            FocusButton("Tab") {}
                .menuFocusBinding($focused, equals: 5)
                .focusable(false)
        }
        .onChange(of: focused) { _, value in
            probe.focus = value
        }
    }
}

extension CatalogClient {
    static let clearing: @Sendable (UUID, ProductID) -> AsyncStream<CloudLaunchClearanceEvent> = { _, _ in
        AsyncStream { continuation in
            continuation.yield(.finished(.success(.cleared(nil))))
            continuation.finish()
        }
    }

    static let unanswered: @Sendable (UUID, CloudGame) async -> CloudStoreCheck = { _, _ in
        try? await Task.sleep(for: .seconds(60))
        return CloudStoreCheck(card: .checking)
    }
}
