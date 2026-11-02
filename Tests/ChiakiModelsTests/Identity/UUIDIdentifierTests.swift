import ChiakiModels
import Foundation
import Testing

@Suite struct UUIDIdentifierTests {
    private let text = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    @Test func textFormIsTheUppercaseUUIDString() throws {
        let profile = try #require(ProfileID(uuidString: text.lowercased()))
        #expect(profile.uuidString == text)
        #expect(profile.uuid == UUID(uuidString: text))
    }

    @Test func rejectsTextThatIsNotAUUID() {
        #expect(ProfileID(uuidString: "") == nil)
        #expect(ConsoleID(uuidString: "console") == nil)
        #expect(ConsoleID(uuidString: "E621E1F8-C36C-495A-93FC") == nil)
    }

    @Test func encodesAsABareUUID() throws {
        let uuid = try #require(UUID(uuidString: text))
        let identifiers = [ConsoleID(uuid: uuid)]
        let encoded = try JSONEncoder().encode(identifiers)
        #expect(encoded == (try JSONEncoder().encode([uuid])))
        #expect(try JSONDecoder().decode([ConsoleID].self, from: encoded) == identifiers)
    }

    @Test func rejectsEncodedValuesThatAreNotUUIDs() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([ProfileID].self, from: Data(#"["profile"]"#.utf8))
        }
    }

    @Test func newIdentifiersAreDistinct() {
        #expect(ProfileID() != ProfileID())
    }
}
