import ChiakiModels
import Darwin
import Testing
@testable import ChiakiNG

@Test func fileDescriptorLimitRaisesTheSoftLimitWithinTheHardLimit() {
    #expect(FileDescriptorLimit.target(soft: 256, hard: rlim_t(Int64.max)) == 4096)
    #expect(FileDescriptorLimit.target(soft: 256, hard: 1024) == 1024)
    #expect(FileDescriptorLimit.target(soft: 4096, hard: 10240) == nil)
    #expect(FileDescriptorLimit.target(soft: 8192, hard: 10240) == nil)
}

@Test func fileDescriptorLimitLeavesHeadroomForRemoteProbeSockets() {
    FileDescriptorLimit.raise()
    var limit = rlimit()
    #expect(getrlimit(RLIMIT_NOFILE, &limit) == 0)
    #expect(limit.rlim_cur >= min(limit.rlim_max, FileDescriptorLimit.ceiling))
}
