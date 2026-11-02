#if CHIAKI_KAKUSAN
    import ChiakiModels
    import Testing
    @testable import ChiakiFeatures

    @Test func aGuestWhoLeftIsNamedInTheHostsNotice() {
        let notice = KakusanHostNotice.ended(name: nil, .closed(.user, byPeer: true))
        #expect(notice.title == "The remote player left")
        #expect(notice.detail == nil)
        #expect(KakusanHostNotice.ended(name: "Alex", .closed(.user, byPeer: false))
            .title == "Alex was removed")
    }
#endif
