import Testing
@testable import ChiakiClientsLive

@Test(arguments: [
    "192.168.1.27", "10.0.0.5", "172.16.4.2", "172.31.255.1", "169.254.10.1", "127.0.0.1",
    "fe80::1", "fd12:3456::1", "::1", "[fe80::1%en0]", "::ffff:192.168.1.27"
])
func privateAddressesAreLocal(address: String) {
    #expect(ConsoleNetworkLocality.isLocal(literal: address) == true)
}

@Test(arguments: [
    "8.8.8.8",
    "172.32.0.1",
    "100.64.0.1",
    "100.100.1.2",
    "2001:4860:4860::8888",
    "::ffff:8.8.8.8"
])
func publicAddressesAreNotLocal(address: String) {
    #expect(ConsoleNetworkLocality.isLocal(literal: address) == false)
}

@Test func hostnamesNeedResolving() {
    #expect(ConsoleNetworkLocality.isLocal(literal: "ps5.example.com") == nil)
}

@Test(arguments: ["PS5-839.local", "ps5", "localhost"])
func localNamesAreLocalWithoutResolving(name: String) async {
    #expect(await ConsoleNetworkLocality.isLocal(name))
}
