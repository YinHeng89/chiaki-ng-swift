import ChiakiModels
import Foundation
import Testing

@Suite struct CatalogIDTests {
    @Test func productIDKeepsItsTextAndRejectsEmpty() {
        #expect(ProductID(rawValue: "UP9000-PPSA01411_00-0000000000000000")?.rawValue
            == "UP9000-PPSA01411_00-0000000000000000")
        #expect(ProductID(rawValue: "") == nil)
    }

    @Test func encodesAsABareString() throws {
        let product = try #require(ProductID(rawValue: "UP9000-PPSA01411_00-0000000000000000"))
        let encodedProduct = try JSONEncoder().encode([product])
        #expect(String(bytes: encodedProduct, encoding: .utf8) ==
            #"["UP9000-PPSA01411_00-0000000000000000"]"#)
        #expect(try JSONDecoder().decode([ProductID].self, from: encodedProduct) == [product])
    }

    @Test func decodingRejectsEmptyText() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([ProductID].self, from: Data(#"[""]"#.utf8))
        }
    }
}
