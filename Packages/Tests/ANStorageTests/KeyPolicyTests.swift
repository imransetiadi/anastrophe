import Foundation
import Security
import Testing
@testable import ANStorage

@Suite("Kebijakan kunci kredensial (ADR-0009, CLAUDE.md aturan 5)")
struct KeyPolicyTests {
    @Test func flagUserPresenceDanPrivateKeyUsage() {
        #expect(CredentialKeyPolicy.accessControlFlags == [.privateKeyUsage, .userPresence])
    }

    @Test func hanyaBilaPasscodeDanTidakIkutBackup() {
        #expect(CredentialKeyPolicy.accessibility == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
    }

    @Test func accessControlDapatDibuat() throws {
        _ = try CredentialKeyPolicy.makeAccessControl()
    }

    @Test func storeInMemory() throws {
        let store = InMemorySecretStore()
        try store.set(Data([1, 2]), for: "k", accessibility: .afterFirstUnlockThisDeviceOnly)
        #expect(try store.get("k") == Data([1, 2]))
        try store.delete("k")
        #expect(try store.get("k") == nil)
    }
}
