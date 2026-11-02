import ChiakiModels
import Foundation
import Testing

@Suite struct CloudServiceTests {
    @Test func rawValuesMatchTheCatalogServiceTypes() {
        #expect(CloudService(rawValue: "pscloud") == .psCloud)
        #expect(CloudService(rawValue: "psnow") == .psNow)
        #expect(CloudService(rawValue: "PSCLOUD") == nil)
        #expect(CloudService(rawValue: "") == nil)
    }

    @Test func encodesAsItsRawValue() throws {
        let encoded = try JSONEncoder().encode([CloudService.psNow, .psCloud])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["psnow","pscloud"]"#)
        #expect(try JSONDecoder().decode([CloudService].self, from: encoded) == [.psNow, .psCloud])
    }
}
