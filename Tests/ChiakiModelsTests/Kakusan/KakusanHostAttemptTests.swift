@testable import ChiakiModels
import Foundation
import Testing

private enum Expect: Equatable, Sendable, CustomStringConvertible {
    case accept(String)
    case ignore
    case reject

    var description: String {
        switch self {
        case .accept(let state):
            "accept \(state)"
        case .ignore:
            "ignore"
        case .reject:
            "reject"
        }
    }
}

private let attemptID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let inviteOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let replyOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
private let approvalOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
private let codeOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!
private let staleOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
private let guestID = KakusanGuestID(Data(repeating: 1, count: 16))!
private let block = KakusanBlock(pasted: "RCP1:aW52aXRhdGlvbg")!
private let invitation = KakusanInvitation(
    block: block,
    expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
)
private let ownCode = KakusanCode("4821")!
private let firstGrant = KakusanSeatGrant(seat: 3, generation: 1)
private let peer = KakusanIdentity(
    publicKey: KakusanPublicKey(Data(repeating: 2, count: 32))!,
    fingerprint: KakusanFingerprint(Data(repeating: 3, count: 32))!
)

private func change(_ state: KakusanSessionState, error: KakusanError? = nil) -> KakusanHostInput {
    let reason: KakusanReason? = state == .closing
        ? .user
        : nil
    return .state(KakusanStateChange(state: state, error: error, reason: reason, byPeer: true))
}

private func seated(_ state: KakusanSessionState, pad: UInt8? = 2) -> KakusanHostInput {
    .state(KakusanStateChange(
        state: state,
        byPeer: true,
        seat: firstGrant.seat,
        generation: firstGrant.generation,
        consoleSeat: pad
    ))
}

private func reserved(pad: UInt8 = 2) -> KakusanHostInput {
    .state(KakusanStateChange(
        state: .admitting,
        byPeer: true,
        seat: firstGrant.seat,
        generation: firstGrant.generation,
        reservedSeat: pad
    ))
}

private let builders: [(String, [KakusanHostInput])] = {
    let preparedGuest: [KakusanHostInput] = [.invitation(.invited(inviteOp, guestID))]
    let invited = preparedGuest + [.invitation(.ready(invitation))]
    let importing = invited + [.reply(.submit(replyOp))]
    let connecting = importing + [.reply(.imported(replyOp))]
    let sending = connecting + [.approval(.request(approvalOp))]
    let granted = sending + [.approval(.result(approvalOp, nil))]
    let verifying = granted + [.code(.ready(ownCode))]
    let submitting = verifying + [.code(.submit(codeOp))]
    let submitted = submitting + [.code(.result(codeOp, nil))]
    let admitting = submitted + [change(.admitting)]
    let console = admitting + [.seat(.joinRequested)]
    let held = console + [reserved()]
    let joined = held + [.seat(.consoleJoined(pad: 2))]
    let readying = joined + [seated(.readyWait)]
    let active = readying + [seated(.active)]
    let closing = active + [change(.closing)]
    return [
        ("P", []), ("Pg", preparedGuest), ("I", invited), ("Ii", importing),
        ("Ir", importing + [.reply(.rejected(replyOp, .invalidBlock))]),
        ("C", connecting), ("Cs", sending), ("Cg", granted), ("V(g,a)", verifying),
        ("V(g,s)", submitting), ("V(g,d)", submitted), ("A", admitting), ("Ac", console),
        ("Ah", held), ("Aj", joined), ("R", readying), ("Act", active), ("Cl", closing),
        ("E:closed(user,true)", closing + [change(.closed)])
    ]
}()

private func build(_ inputs: [KakusanHostInput]) -> KakusanHostAttempt {
    var attempt = KakusanHostAttempt(id: attemptID, operation: inviteOp)
    for input in inputs {
        #expect(attempt.apply(input) == .accepted, "builder input \(input) was not accepted")
    }
    return attempt
}

private struct HostCase: Sendable {
    let name: String
    let input: KakusanHostInput
    let expected: @Sendable (String) -> Expect

    init(_ name: String, _ input: KakusanHostInput, _ expected: @escaping @Sendable (String) -> Expect) {
        self.name = name
        self.input = input
        self.expected = expected
    }
}

extension KakusanHostAttempt {
    fileprivate var tag: String {
        switch phase {
        case .preparing:
            return guest == nil
                ? "P"
                : "Pg"
        case .invitation(_, .awaiting):
            return "I"
        case .invitation(_, .importing):
            return "Ii"
        case .invitation(_, .rejected):
            return "Ir"
        case .connecting(let approval):
            return "C" + approvalTag(approval).replacingOccurrences(of: "p", with: "")
        case let .verifying(approval, verification):
            return "V(\(approvalTag(approval)),\(entryTag(verification.entry)))"
        case .admitting(.awaitingSeat):
            return "A"
        case .admitting(.awaitingConsole):
            return "Ac"
        case .admitting(.reserved):
            return "Ah"
        case .admitting(.consoleJoined):
            return "Aj"
        case .readying:
            return "R"
        case .active:
            return "Act"
        case .closing:
            return "Cl"
        case .ended(let outcome):
            return "E:\(outcomeTag(outcome))"
        }
    }
}

private func approvalTag(_ approval: KakusanApproval) -> String {
    switch approval {
    case .pending:
        "p"
    case .sending:
        "s"
    case .granted:
        "g"
    }
}

private func entryTag(_ entry: KakusanCodeEntry) -> String {
    switch entry {
    case .awaiting:
        "a"
    case .submitting:
        "s"
    case .submitted:
        "d"
    }
}

private func outcomeTag(_ outcome: KakusanAttemptOutcome) -> String {
    switch outcome {
    case .cancelled:
        "cancelled"
    case .left:
        "left"
    case .failed(let error):
        "failed(\(error.rawValue))"
    case let .closed(reason, byPeer):
        "closed(\(reason.rawValue),\(byPeer))"
    }
}

private let preInvitation = ["P", "Pg"]
private let inviting = ["I", "Ii", "Ir"]
private let connectingStates = ["C", "Cs", "Cg"]
private let verifyingStates = ["V(g,a)", "V(g,s)", "V(g,d)"]
private let admittingStates = ["A", "Ac", "Ah", "Aj"]
private let live = preInvitation + inviting + connectingStates + verifyingStates + admittingStates + [
    "R",
    "Act",
    "Cl"
]

private func table(
    _ fallback: Expect,
    _ rules: [String: Expect] = [:],
    ended: Expect = .ignore
) -> @Sendable (String) -> Expect {
    { state in
        if state.hasPrefix("E:") {
            return ended
        }
        return rules[state] ?? fallback
    }
}

private func all(_ states: [String], _ expect: Expect) -> [String: Expect] {
    Dictionary(uniqueKeysWithValues: states.map { ($0, expect) })
}

private let inputs: [HostCase] = [
    HostCase("invited", .invitation(.invited(inviteOp, guestID)), table(.ignore, ["P": .accept("Pg")])),
    HostCase("invited stale", .invitation(.invited(staleOp, guestID)), table(.ignore)),
    HostCase(
        "invite failed",
        .invitation(.failed(inviteOp, .internal)),
        table(.ignore, all(preInvitation, .accept("E:failed(internal)")))
    ),
    HostCase(
        "invitation ready",
        .invitation(.ready(invitation)),
        table(.ignore, ["P": .reject, "Pg": .accept("I")])
    ),
    HostCase("expired", .invitation(.expired), table(.ignore, all(inviting, .accept("E:failed(expired)")))),
    HostCase(
        "submit reply",
        .reply(.submit(replyOp)),
        table(.reject, ["I": .accept("Ii"), "Ir": .accept("Ii")])
    ),
    HostCase("reply imported", .reply(.imported(replyOp)), table(.ignore, ["Ii": .accept("C")])),
    HostCase(
        "reply imported elsewhere",
        .reply(.imported(nil)),
        table(.ignore, ["I": .accept("C"), "Ir": .accept("C")])
    ),
    HostCase("reply redirected", .reply(.redirected(replyOp)), table(.ignore, ["Ii": .accept("I")])),
    HostCase(
        "reply rejected",
        .reply(.rejected(replyOp, .invalidBlock)),
        table(.ignore, ["Ii": .accept("Ir")])
    ),
    HostCase("reply bound", .reply(.bound(peer)), { state in
        if state.hasPrefix("E:") {
            return .ignore
        }
        return preInvitation.contains(state)
            ? .reject
            : .accept(state)
    }),
    HostCase("approval request", .approval(.request(approvalOp)), table(.reject, ["C": .accept("Cs")])),
    HostCase("approval granted", .approval(.result(approvalOp, nil)), table(.ignore, ["Cs": .accept("Cg")])),
    HostCase(
        "approval failed",
        .approval(.result(approvalOp, .noCapacity)),
        table(.ignore, ["Cs": .accept("E:failed(noCapacity)")])
    ),
    HostCase("code ready", .code(.ready(ownCode)), table(.ignore, all(preInvitation, .reject)
            .merging(all(inviting, .accept("V(p,a)"))) { $1 }
            .merging(["C": .accept("V(p,a)"), "Cs": .accept("V(s,a)"), "Cg": .accept("V(g,a)")]) { $1 })),
    HostCase("submit code", .code(.submit(codeOp)), table(.reject, ["V(g,a)": .accept("V(g,s)")])),
    HostCase("code accepted", .code(.result(codeOp, nil)), table(.ignore, ["V(g,s)": .accept("V(g,d)")])),
    HostCase(
        "code wrong",
        .code(.result(codeOp, .pairingFailed)),
        table(.ignore, ["V(g,s)": .accept("E:failed(pairingFailed)")])
    ),
    HostCase(
        "state waiting",
        change(.waiting),
        table(.reject, all(preInvitation + inviting + ["Cl"], .ignore))
    ),
    HostCase("state connecting", change(.connecting), table(.reject, all(inviting, .accept("C"))
            .merging(all(connectingStates + ["Cl"], .ignore)) { $1 })),
    HostCase("state verifying", change(.verifying), table(.reject, all(inviting, .accept("V(p,a)"))
            .merging(["C": .accept("V(p,a)"), "Cs": .accept("V(s,a)"), "Cg": .accept("V(g,a)")]) { $1 }
            .merging(all(verifyingStates + ["Cl"], .ignore)) { $1 })),
    HostCase(
        "state admitting",
        change(.admitting),
        table(.reject, all(inviting + connectingStates + verifyingStates, .accept("A"))
            .merging(all(admittingStates + ["Cl"], .ignore)) { $1 })
    ),
    HostCase(
        "state admitting with a reserved seat",
        reserved(),
        table(.reject, all(inviting + connectingStates + verifyingStates, .accept("A"))
            .merging(["A": .accept("Ah"), "Ac": .accept("Ah"), "Ah": .ignore, "Aj": .ignore, "Cl": .ignore]) {
                $1
            })
    ),
    HostCase(
        "state admitting with another reserved seat",
        reserved(pad: 3),
        table(.reject, all(inviting + connectingStates + verifyingStates, .accept("A"))
            .merging(all(["A", "Ac", "Ah"], .accept("Ah"))) { $1 }
            .merging(["Aj": .ignore, "Cl": .ignore]) { $1 })
    ),
    HostCase(
        "state ready wait",
        seated(.readyWait),
        table(.reject, ["Ac": .accept("R"), "Ah": .accept("R"), "Aj": .accept("R"), "R": .ignore,
                        "Cl": .ignore])
    ),
    HostCase(
        "state ready wait without the seat",
        change(.readyWait),
        table(.reject, ["R": .ignore, "Cl": .ignore])
    ),
    HostCase(
        "state active",
        seated(.active),
        table(.reject, ["Ac": .accept("Act"), "Ah": .accept("Act"), "Aj": .accept("Act"),
                        "R": .accept("Act"), "Act": .ignore, "Cl": .ignore])
    ),
    HostCase(
        "state active without the seat",
        change(.active),
        table(.reject, ["R": .accept("Act"), "Act": .ignore, "Cl": .ignore])
    ),
    HostCase(
        "state active on another seat",
        seated(.active, pad: 3),
        table(.reject, all(["Ac", "Ah", "Aj", "R", "Act"], .accept("Act")).merging(["Cl": .ignore]) { $1 })
    ),
    HostCase("state closing", change(.closing), table(.accept("Cl"), ["Cl": .ignore])),
    HostCase("state closed", change(.closed, error: .noPath), table(.accept("E:failed(noPath)"))),
    HostCase(
        "join requested",
        .seat(.joinRequested),
        table(.reject, all(connectingStates + verifyingStates + ["A"], .accept("Ac"))
            .merging(["Ac": .ignore, "Ah": .ignore, "Cl": .ignore]) { $1 })
    ),
    HostCase(
        "console joined",
        .seat(.consoleJoined(pad: 2)),
        table(.reject, all(["A", "Aj", "R", "Act", "Cl"], .ignore)
            .merging(["Ac": .accept("Aj"), "Ah": .accept("Aj")]) { $1 })
    ),
    HostCase(
        "console joined on another seat",
        .seat(.consoleJoined(pad: 3)),
        table(.reject, ["A": .ignore, "Ac": .accept("Aj"), "Ah": .accept("Aj"), "Aj": .accept("Aj"),
                        "R": .accept("R"),
                        "Act": .accept("Act"), "Cl": .ignore])
    ),
    HostCase(
        "console join failed",
        .seat(.consoleJoinFailed),
        table(.reject, all(["A", "Ah", "Aj", "R", "Act", "Cl"], .ignore)
            .merging(["Ac": .accept("A")]) { $1 })
    ),
    HostCase(
        "console left",
        .seat(.consoleLeft(pad: 2)),
        table(.reject, all(["A", "Ac", "Ah", "Cl"], .ignore)
            .merging(all(["Aj", "R", "Act"], .accept("Cl"))) { $1 })
    ),
    HostCase(
        "console left another seat",
        .seat(.consoleLeft(pad: 3)),
        table(.reject, all(admittingStates + ["R", "Act", "Cl"], .ignore))
    ),
    HostCase("cancel", .cancel, table(.accept("E:cancelled"))),
    HostCase("hosting ended", .hostingEnded, table(.accept("E:closed(source,false)")))
]

@Test func hostAttemptBuildersReachEveryPhase() {
    for (name, steps) in builders {
        #expect(build(steps).tag == name)
    }
    #expect(Set(builders.map(\.0)).isSuperset(of: live))
}

@Test(arguments: inputs.indices)
func hostAttemptHandlesInputInEveryState(_ index: Int) {
    let entry = inputs[index]
    let (inputName, input, expected) = (entry.name, entry.input, entry.expected)
    for (stateName, steps) in builders {
        let before = build(steps)
        var attempt = before
        let transition = attempt.apply(input)
        let expectation = expected(stateName)
        switch expectation {
        case .accept(let next):
            #expect(transition == .accepted, "\(inputName) in \(stateName) expected \(expectation)")
            #expect(attempt.tag == next, "\(inputName) in \(stateName) reached \(attempt.tag)")
        case .ignore:
            #expect(transition == .ignored, "\(inputName) in \(stateName) expected ignore, got \(transition)")
            #expect(attempt == before, "\(inputName) in \(stateName) changed state while ignored")
        case .reject:
            #expect(
                transition == .rejected,
                "\(inputName) in \(stateName) expected reject, got \(transition)"
            )
            #expect(attempt == before, "\(inputName) in \(stateName) changed state while rejected")
        }
    }
}

@Test func hostAttemptRejectsConflictingIdentityAndCodes() {
    var attempt = build(builders[0].1)
    #expect(attempt.apply(.invitation(.invited(inviteOp, guestID))) == .accepted)
    #expect(attempt
        .apply(.invitation(.invited(inviteOp, KakusanGuestID(Data(repeating: 9, count: 16))!))) ==
        .rejected)
    var bound = build(builders.first { $0.0 == "C" }!.1)
    #expect(bound.apply(.reply(.bound(peer))) == .accepted)
    #expect(bound.milestone == .bound)
    let other = KakusanIdentity(
        publicKey: KakusanPublicKey(Data(repeating: 7, count: 32))!,
        fingerprint: peer.fingerprint
    )
    #expect(bound.apply(.reply(.bound(other))) == .rejected)
    #expect(bound.peer == peer)
    var verifying = build(builders.first { $0.0 == "V(g,a)" }!.1)
    #expect(verifying.apply(.code(.ready(KakusanCode("0000")!))) == .rejected)
}

@Test func hostAttemptTracksSeatAndMilestones() {
    let active = build(builders.first { $0.0 == "Act" }!.1)
    #expect(active.seat == firstGrant)
    #expect(active.pad == 2)
    #expect(active.milestone == .seated)
    let admitted = build(builders.first { $0.0 == "A" }!.1)
    #expect(admitted.milestone == .verified)
    #expect(admitted.seat == nil)
    #expect(admitted.pad == nil)
    #expect(!admitted.seatRequested)
    let asked = build(builders.first { $0.0 == "Ac" }!.1)
    #expect(asked.seat == nil)
    #expect(asked.pad == nil)
    #expect(asked.seatRequested)
    var held = build(builders.first { $0.0 == "Ah" }!.1)
    #expect(held.phase == .admitting(.reserved(firstGrant, pad: 2)))
    #expect(held.seat == firstGrant)
    #expect(held.reservedPad == 2)
    #expect(held.pad == nil)
    #expect(held.seatRequested)
    #expect(held.milestone == .verified)
    #expect(held.apply(reserved(pad: 3)) == .accepted)
    #expect(held.reservedPad == 3)
    #expect(held.apply(change(.closed, error: .sourceJoinFailed)) == .accepted)
    #expect(held.reservedPad == nil)
    #expect(held.seat == nil)
    #expect(!held.seatRequested)
    var joined = build(builders.first { $0.0 == "Aj" }!.1)
    #expect(joined.reservedPad == nil)
    #expect(joined.seat == nil)
    #expect(joined.pad == 2)
    #expect(joined.apply(seated(.readyWait, pad: 3)) == .accepted)
    #expect(joined.seat == firstGrant)
    #expect(joined.pad == 3)
    #expect(joined.apply(.seat(.consoleLeft(pad: 3))) == .accepted)
    #expect(joined.phase == .closing(.closed(.source, byPeer: false)))
    #expect(!joined.seatRequested)
    var unreported = build(builders.first { $0.0 == "Ac" }!.1)
    #expect(unreported.apply(seated(.active, pad: nil)) == .rejected)
    #expect(unreported.apply(seated(.active, pad: 1)) == .accepted)
    #expect(unreported.phase == .active(firstGrant, pad: 1))
    #expect(build(builders.first { $0.0 == "Cs" }!.1).approval == .sending(approvalOp))
    #expect(build(builders.first { $0.0 == "I" }!.1).outcome == nil)
}
