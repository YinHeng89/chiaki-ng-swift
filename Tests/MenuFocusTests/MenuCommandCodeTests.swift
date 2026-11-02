import MenuFocus
import Testing

struct MenuCommandCodeTests {
    private func completions(_ commands: [MenuCommand], code: MenuCommandCode = .konami) -> Int {
        var code = code
        return commands.filter { code.advance($0) }.count
    }

    @Test func theKonamiDirectionsCompleteTheCode() {
        #expect(completions([.up, .up, .down, .down, .left, .right, .left, .right]) == 1)
    }

    @Test func anExtraLeadingUpStillCompletesTheCode() {
        #expect(completions([.up, .up, .up, .down, .down, .left, .right, .left, .right]) == 1)
    }

    @Test func aWrongCommandStartsTheCodeOver() {
        #expect(completions([.up, .up, .down, .confirm, .down, .left, .right, .left, .right]) == 0)
        #expect(completions([.up, .up, .down, .left, .up, .up, .down, .down, .left, .right, .left, .right]) ==
            1)
    }

    @Test func theCodeStartsOverAfterCompleting() {
        let konami: [MenuCommand] = [.up, .up, .down, .down, .left, .right, .left, .right]
        var code = MenuCommandCode.konami
        #expect(konami.filter { code.advance($0) }.count == 1)
        #expect(code.entered == 0)
        #expect(completions(konami + konami) == 2)
    }

    @Test func aRepeatedLastStepDoesNotCompleteTwice() {
        #expect(completions([.up, .up, .down, .down, .left, .right, .left, .right, .right]) == 1)
    }
}
