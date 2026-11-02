@testable import ChiakiFeatures
import Foundation
import SwiftUI
import Testing
import MenuFocus

private let guest = UUID()

private let couchControls: [StreamMenuControl] = [
    .playerControls(0), .playerReassign(0),
    .playerControls(1), .playerReassign(1), .playerRemove(1),
    .remote(.remember(guest)), .playerRemove(2),
    .playerAdd(3),
    .remote(.invite), .remote(.open(guest)), .remote(.cancel(guest))
]

private func destination(
    _ control: StreamMenuControl,
    _ direction: MenuMoveDirection,
    lastSeat: UInt8? = nil
) -> StreamPlayersNavigation.Destination {
    StreamPlayersNavigation.destination(
        from: control, direction: direction, controls: couchControls, lastSeat: lastSeat
    )
}

@Test func playersPanelMovesBetweenSeatCardsSideways() {
    #expect(destination(.playerReassign(0), .right) == .control(.playerReassign(1)))
    #expect(destination(.playerRemove(1), .right) == .control(.playerRemove(2)))
    #expect(destination(.playerRemove(2), .right) == .control(.playerAdd(3)))
    #expect(destination(.playerAdd(3), .right) == .stay)
    #expect(destination(.playerControls(1), .left) == .control(.playerControls(0)))
    #expect(destination(.playerControls(0), .left) == .stay)
}

@Test func playersPanelMovesVerticallyWithinACardThenIntoRemotePlayers() {
    #expect(destination(.playerControls(1), .down) == .control(.playerReassign(1)))
    #expect(destination(.remote(.remember(guest)), .down) == .control(.playerRemove(2)))
    #expect(destination(.playerRemove(2), .up) == .control(.remote(.remember(guest))))
    #expect(destination(.playerReassign(0), .down) == .control(.remote(.invite)))
    #expect(destination(.playerControls(0), .up) == .stay)
    #expect(destination(.remote(.cancel(guest)), .down) == .tabs)
}

@Test func remotePlayersReturnToTheLastSeatAndStaySideways() {
    #expect(destination(.remote(.invite), .up, lastSeat: 1) == .control(.playerRemove(1)))
    #expect(destination(.remote(.invite), .up) == .control(.playerAdd(3)))
    #expect(destination(.remote(.open(guest)), .right) == .control(.remote(.cancel(guest))))
    #expect(destination(.remote(.invite), .left) == .stay)
}

@Test func controllerPickerStaysAVerticalList() {
    let picker: [StreamMenuControl] = [.playerPick(1), .playerPick(2), .playerCancelPick]
    let down = StreamPlayersNavigation.destination(from: .playerPick(1), direction: .down, controls: picker)
    let right = StreamPlayersNavigation.destination(from: .playerPick(1), direction: .right, controls: picker)
    let last = StreamPlayersNavigation.destination(
        from: .playerCancelPick,
        direction: .down,
        controls: picker
    )
    #expect(down == .control(.playerPick(2)))
    #expect(right == .stay)
    #expect(last == .tabs)
}
