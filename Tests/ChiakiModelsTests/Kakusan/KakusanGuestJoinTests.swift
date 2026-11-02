@testable import ChiakiModels
import Foundation
import Testing

private enum GuestExpect: Equatable, Sendable {
    case accept(String)
    case ignore
    case reject
}

private let session = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
private let otherSession = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let previewOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
private let secondPreviewOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!
private let codeOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!
private let secondCodeOp = UUID(uuidString: "00000000-0000-0000-0000-0000000000B6")!
private let reply = KakusanBlock(pasted: "RCP1:cmVwbHk")!
private let code = KakusanCode("7306")!
private let summary = KakusanInvitationSummary(
    invitation: KakusanBlock(pasted: "RCP1:aW52aXRl")!,
    preview: KakusanInvitationPreview(
        hostHint: KakusanIdentityHint(Data(repeating: 1, count: 8))!,
        claimedHostName: nil,
        capacity: 4,
        expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
    )
)

private func sessionInput(_ event: KakusanGuestInput.Session) -> KakusanGuestInput {
    .session(session, event)
}

private func state(_ value: KakusanSessionState, error: KakusanError? = nil,
                   seat: Int? = nil) -> KakusanGuestInput {
    sessionInput(.state(KakusanStateChange(state: value, error: error, seat: seat)))
}

private let guestBuilders: [(String, [KakusanGuestInput])] = {
    let entering: [KakusanGuestInput] = [.open]
    let previewing = entering + [.preview(.request(previewOp))]
    let previewed = previewing + [.preview(.succeeded(previewOp, summary))]
    let accepted = previewed + [.setDisclosure(true)]
    let preparing = accepted + [.start(session)]
    let waiting = preparing + [sessionInput(.replyReady(reply))]
    let connecting = waiting + [state(.connecting)]
    let verifying = connecting + [sessionInput(.codeReady(code))]
    let submitting = verifying + [sessionInput(.submitCode(codeOp))]
    let submitted = submitting + [sessionInput(.codeResult(codeOp, nil))]
    let admitting = submitted + [state(.admitting)]
    let readying = admitting + [state(.readyWait, seat: 3)]
    let streaming = readying + [state(.active, seat: 3)]
    let framing = streaming + [sessionInput(.streamReady(fps: 60))]
    let playing = framing + [sessionInput(.firstFrame)]
    return [
        ("idle", []), ("En", entering), ("Ee", previewing + [.preview(.failed(previewOp, .invalidBlock))]),
        ("Pv", previewing), ("Pd", previewed), ("Da", accepted), ("Pr", preparing), ("W", waiting),
        ("Co", connecting), ("V(a)", verifying), ("V(s)", submitting), ("V(d)", submitted), ("A", admitting),
        ("R", readying), ("S(as)", streaming), ("S(af)", framing), ("S(p)", playing),
        ("L", playing + [.leave]), ("E:failed(noPath)", playing + [state(.closed, error: .noPath)])
    ]
}()

private func buildJoin(_ inputs: [KakusanGuestInput]) -> KakusanGuestJoin {
    var join = KakusanGuestJoin()
    for input in inputs {
        #expect(join.apply(input) == .accepted, "builder input \(input) was not accepted")
    }
    return join
}

private struct GuestCase: Sendable {
    let name: String
    let input: KakusanGuestInput
    let expected: @Sendable (String) -> GuestExpect

    init(_ name: String, _ input: KakusanGuestInput,
         _ expected: @escaping @Sendable (String) -> GuestExpect) {
        self.name = name
        self.input = input
        self.expected = expected
    }
}

extension KakusanGuestJoin {
    fileprivate var tag: String {
        switch phase {
        case .idle:
            "idle"
        case .entering(let error):
            error == nil
                ? "En"
                : "Ee"
        case .previewing:
            "Pv"
        case .previewed:
            "Pd"
        case .disclosureAccepted:
            "Da"
        case .preparingReply:
            "Pr"
        case .waitingForHost:
            "W"
        case .connecting:
            "Co"
        case .verifying(_, let verification):
            "V(\(verificationTag(verification.entry)))"
        case .admitting:
            "A"
        case .readying:
            "R"
        case .streaming(_, let stream):
            "S(\(videoTag(stream.video)))"
        case .leaving:
            "L"
        case .ended(.failed(let error)):
            "E:failed(\(error.rawValue))"
        case let .ended(.closed(reason, byPeer)):
            "E:closed(\(reason.rawValue),\(byPeer))"
        }
    }
}

private func verificationTag(_ entry: KakusanCodeEntry) -> String {
    switch entry {
    case .awaiting:
        "a"
    case .submitting:
        "s"
    case .submitted:
        "d"
    }
}

private func videoTag(_ video: KakusanGuestVideo) -> String {
    switch video {
    case .awaitingStream:
        "as"
    case .awaitingFrame:
        "af"
    case .playing:
        "p"
    }
}

private let offline = ["idle", "En", "Ee", "Pv", "Pd", "Da"]
private let streams = ["S(as)", "S(af)", "S(p)"]
private let codes = ["V(a)", "V(s)", "V(d)"]
private let sessionPhases = ["Pr", "W", "Co"] + codes + ["A", "R"] + streams

private func rule(
    _ fallback: GuestExpect,
    _ rules: [String: GuestExpect] = [:]
) -> @Sendable (String) -> GuestExpect {
    { stateName in
        rules[stateName] ?? fallback
    }
}

private func each(_ states: [String], _ expect: GuestExpect) -> [String: GuestExpect] {
    Dictionary(uniqueKeysWithValues: states.map { ($0, expect) })
}

private func sessionRule(
    _ fallback: GuestExpect,
    _ rules: [String: GuestExpect] = [:]
) -> @Sendable (String) -> GuestExpect {
    { stateName in
        guard sessionPhases.contains(stateName) else {
            return .ignore
        }
        return rules[stateName] ?? fallback
    }
}

private let guestInputs: [GuestCase] = [
    GuestCase("open", .open, rule(.ignore, ["idle": .accept("En")])),
    GuestCase("preview request", .preview(.request(secondPreviewOp)),
              rule(.reject, each(["En", "Ee", "Pd", "Da"], .accept("Pv")))),
    GuestCase(
        "preview succeeded",
        .preview(.succeeded(previewOp, summary)),
        rule(.ignore, ["Pv": .accept("Pd")])
    ),
    GuestCase("preview failed", .preview(.failed(previewOp, .expired)), rule(.ignore, ["Pv": .accept("Ee")])),
    GuestCase("accept disclosure", .setDisclosure(true), rule(.reject, ["Pd": .accept("Da"), "Da": .ignore])),
    GuestCase(
        "withdraw disclosure",
        .setDisclosure(false),
        rule(.reject, ["Da": .accept("Pd"), "Pd": .ignore])
    ),
    GuestCase("start", .start(otherSession), rule(.reject, ["Da": .accept("Pr")])),
    GuestCase("back", .back, rule(.reject, each(["Pd", "Da", "E:failed(noPath)"], .accept("En")))),
    GuestCase(
        "leave",
        .leave,
        rule(.accept("L"), each(["En", "Ee", "Pv", "Pd", "Da", "E:failed(noPath)"], .accept("idle"))
            .merging(["idle": .ignore, "L": .ignore]) { $1 })
    ),
    GuestCase("reply ready", sessionInput(.replyReady(reply)), sessionRule(.ignore, ["Pr": .accept("W")])),
    GuestCase(
        "code ready",
        sessionInput(.codeReady(code)),
        sessionRule(.ignore, ["Pr": .reject, "W": .accept("V(a)"),
                              "Co": .accept("V(a)")])
    ),
    GuestCase(
        "submit code",
        sessionInput(.submitCode(secondCodeOp)),
        sessionRule(.reject, ["V(a)": .accept("V(s)")])
    ),
    GuestCase(
        "code accepted",
        sessionInput(.codeResult(codeOp, nil)),
        sessionRule(.ignore, ["V(s)": .accept("V(d)")])
    ),
    GuestCase("code wrong", sessionInput(.codeResult(codeOp, .pairingFailed)),
              sessionRule(.ignore, ["V(s)": .accept("E:failed(pairingFailed)")])),
    GuestCase("state waiting", state(.waiting), sessionRule(.reject, ["Pr": .ignore, "W": .ignore])),
    GuestCase(
        "state connecting",
        state(.connecting),
        sessionRule(.reject, ["Pr": .accept("Co"), "W": .accept("Co"), "Co": .ignore])
    ),
    GuestCase(
        "state verifying",
        state(.verifying),
        sessionRule(.reject, each(["Pr", "W", "Co"], .accept("V(a)"))
            .merging(each(codes, .ignore)) { $1 })
    ),
    GuestCase(
        "state admitting",
        state(.admitting),
        sessionRule(.reject, each(["W", "Co"] + codes, .accept("A"))
            .merging(["A": .ignore]) { $1 })
    ),
    GuestCase(
        "state ready wait",
        state(.readyWait, seat: 3),
        sessionRule(.reject, ["A": .accept("R"), "R": .ignore])
    ),
    GuestCase(
        "state active",
        state(.active, seat: 3),
        sessionRule(.reject, ["A": .accept("S(as)"), "R": .accept("S(as)")]
            .merging(each(streams, .ignore)) { $1 })
    ),
    GuestCase("state closing", state(.closing), sessionRule(.accept("E:closed(user,false)"))),
    GuestCase("state closed", state(.closed, error: .noPath), sessionRule(.accept("E:failed(noPath)"))),
    GuestCase(
        "stream ready",
        sessionInput(.streamReady(fps: 60)),
        sessionRule(.reject, each(["A", "R", "S(as)"], .accept("S(af)"))
            .merging(["S(af)": .ignore, "S(p)": .ignore]) { $1 })
    ),
    GuestCase(
        "first frame",
        sessionInput(.firstFrame),
        sessionRule(.reject, ["S(as)": .accept("S(p)"), "S(af)": .accept("S(p)"),
                              "S(p)": .ignore])
    ),
    GuestCase(
        "stream stopped",
        sessionInput(.streamStopped),
        sessionRule(.ignore, each(streams, .accept("E:closed(source,true)")))
    ),
    GuestCase("session failed", sessionInput(.failed(.codec)), sessionRule(.accept("E:failed(codec)"))),
    GuestCase("session ended", sessionInput(.ended), sessionRule(.accept("E:failed(internal)"),
                                                                 each(
                                                                     streams,
                                                                     .accept("E:closed(source,true)")
                                                                 ))),
    GuestCase(
        "expired",
        sessionInput(.expired),
        sessionRule(.ignore, each(["Pr", "W"], .accept("E:failed(expired)")))
    ),
    GuestCase("stopped", sessionInput(.stopped), { stateName in
        stateName == "L"
            ? .accept("idle")
            : .ignore
    }),
    GuestCase("stale session", .session(otherSession, .replyReady(reply)), rule(.ignore))
]

@Test func guestJoinBuildersReachEveryPhase() {
    for (name, steps) in guestBuilders {
        #expect(buildJoin(steps).tag == name)
    }
    #expect(Set(guestBuilders.map(\.0)).isSuperset(of: offline + sessionPhases + ["L"]))
}

@Test(arguments: guestInputs.indices)
func guestJoinHandlesInputInEveryState(_ index: Int) {
    let entry = guestInputs[index]
    let (inputName, input, expected) = (entry.name, entry.input, entry.expected)
    for (stateName, steps) in guestBuilders {
        let before = buildJoin(steps)
        var join = before
        let transition = join.apply(input)
        let expectation = expected(stateName)
        switch expectation {
        case .accept(let next):
            #expect(
                transition == .accepted,
                "\(inputName) in \(stateName) expected accept, got \(transition)"
            )
            #expect(join.tag == next, "\(inputName) in \(stateName) reached \(join.tag)")
        case .ignore:
            #expect(transition == .ignored, "\(inputName) in \(stateName) expected ignore, got \(transition)")
            #expect(join == before, "\(inputName) in \(stateName) changed state while ignored")
        case .reject:
            #expect(
                transition == .rejected,
                "\(inputName) in \(stateName) expected reject, got \(transition)"
            )
            #expect(join == before, "\(inputName) in \(stateName) changed state while rejected")
        }
    }
}

@Test func guestJoinRequiresTheDisclosureBeforeAReply() {
    var join = buildJoin(guestBuilders.first { $0.0 == "Pd" }!.1)
    #expect(join.apply(.start(session)) == .rejected)
    #expect(join.session == nil)
    #expect(join.apply(.setDisclosure(true)) == .accepted)
    #expect(join.apply(.start(session)) == .accepted)
    #expect(join.session == session)
    #expect(join.summary == summary)
}

@Test func guestJoinKeepsTheSeatAcrossReadiness() {
    let streaming = buildJoin(guestBuilders.first { $0.0 == "S(p)" }!.1)
    guard case .streaming(_, let stream) = streaming.phase else {
        Issue.record("not streaming")
        return
    }
    #expect(stream.seat == 3)
    #expect(stream.video == .playing(fps: 60))
    var verifying = buildJoin(guestBuilders.first { $0.0 == "V(a)" }!.1)
    #expect(verifying.apply(sessionInput(.codeReady(KakusanCode("0001")!))) == .rejected)
}
