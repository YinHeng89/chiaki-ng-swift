import ChiakiModels
import Foundation
import Testing

@Test func consoleKeyboardOpensWithTheConsoleText() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    #expect(keyboard.send(.remoteOpened(id, "Hello")).isEmpty)
    #expect(keyboard.session?.id == id)
    #expect(keyboard.session?.text == "Hello")
}

@Test func consoleKeyboardSendsEditsAndIgnoresTheirEchoes() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, ""))
    #expect(keyboard.send(.edited(id, "a")) == [.setText("a")])
    #expect(keyboard.send(.edited(id, "ab")) == [.setText("ab")])
    #expect(keyboard.send(.edited(id, "ab")).isEmpty)
    keyboard.send(.remoteTextChanged("a"))
    #expect(keyboard.session?.text == "ab")
    keyboard.send(.remoteTextChanged("ab"))
    #expect(keyboard.session?.text == "ab")
}

@Test func consoleKeyboardAdoptsTextTheConsoleChanged() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, ""))
    keyboard.send(.edited(id, "abcdef"))
    keyboard.send(.remoteTextChanged("abc"))
    #expect(keyboard.session?.text == "abc")
    keyboard.send(.remoteTextChanged("xyz"))
    #expect(keyboard.session?.text == "xyz")
}

@Test func consoleKeyboardAcceptSendsTheFinalText() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, "user"))
    keyboard.send(.edited(id, "user1"))
    #expect(keyboard.send(.accepted(id)) == [.accept("user1")])
    #expect(keyboard.phase == .closed)
}

@Test func consoleKeyboardRejectCloses() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, "user"))
    #expect(keyboard.send(.rejected(id)) == [.reject])
    #expect(keyboard.phase == .closed)
}

@Test func consoleKeyboardRemoteCloseAndStreamEndCloseWithoutCommands() {
    var keyboard = ConsoleKeyboard()
    let first = UUID()
    keyboard.send(.remoteOpened(first, ""))
    #expect(keyboard.send(.remoteClosed).isEmpty)
    #expect(keyboard.phase == .closed)
    keyboard.send(.remoteOpened(UUID(), ""))
    #expect(keyboard.send(.streamEnded).isEmpty)
    #expect(keyboard.phase == .closed)
}

@Test func consoleKeyboardIgnoresStaleOverlayCallbacks() {
    var keyboard = ConsoleKeyboard()
    let stale = UUID()
    let current = UUID()
    keyboard.send(.remoteOpened(stale, ""))
    keyboard.send(.remoteOpened(current, "new"))
    #expect(keyboard.send(.edited(stale, "x")).isEmpty)
    #expect(keyboard.send(.accepted(stale)).isEmpty)
    #expect(keyboard.send(.rejected(stale)).isEmpty)
    #expect(keyboard.session?.id == current)
    #expect(keyboard.session?.text == "new")
    keyboard.send(.rejected(current))
    #expect(keyboard.send(.accepted(current)).isEmpty)
    #expect(keyboard.send(.edited(current, "late")).isEmpty)
    #expect(keyboard.send(.remoteTextChanged("late")).isEmpty)
    #expect(keyboard.phase == .closed)
}

@Test func consoleKeyboardBoundsUnconfirmedEdits() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, ""))
    for count in 1...(ConsoleKeyboard.unconfirmedLimit + 10) {
        keyboard.send(.edited(id, String(repeating: "a", count: count)))
    }
    keyboard.send(.remoteTextChanged("a"))
    #expect(keyboard.session?.text == "a")
}

@Test func consoleKeyboardLimitsTextToWhatTheBridgeAccepts() {
    var keyboard = ConsoleKeyboard()
    let id = UUID()
    keyboard.send(.remoteOpened(id, ""))
    let long = String(repeating: "é", count: ConsoleKeyboard.textByteLimit)
    let commands = keyboard.send(.edited(id, long))
    let sent = keyboard.session?.text ?? ""
    #expect(sent.utf8.count <= ConsoleKeyboard.textByteLimit)
    #expect(sent.count == ConsoleKeyboard.textByteLimit / 2)
    #expect(commands == [.setText(sent)])
    #expect(keyboard.send(.accepted(id)) == [.accept(sent)])
}
