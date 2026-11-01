import ANCore
import CryptoKit
import Foundation
import Testing
@testable import ANStorage

@Suite("Token baca status kartu (ADR-0037)")
struct StatusTokenStoreTests {
    @Test func tokenDisimpanTanpaKehadiranPengguna() throws {
        // SDD §5.3: token sesi terbaca setelah buka kunci pertama tanpa prompt, dan tidak ikut backup.
        let secrets = InMemorySecretStore()
        let store = KeychainStatusTokenStore(store: secrets)
        let token = Data(repeating: 0x7A, count: 32)
        try store.save(token, forCard: "6F1C2A9E-0000-4000-8000-000000000001")
        #expect(secrets.accessibility(for: "status-token.6f1c2a9e-0000-4000-8000-000000000001") == .afterFirstUnlockThisDeviceOnly)
        #expect(try store.token(forCard: "6f1c2a9e-0000-4000-8000-000000000001") == token)
        try store.delete(forCard: "6f1c2a9e-0000-4000-8000-000000000001")
        #expect(try store.token(forCard: "6f1c2a9e-0000-4000-8000-000000000001") == nil)
    }

    @Test func tokenHarus32Byte() {
        let store = KeychainStatusTokenStore(store: InMemorySecretStore())
        #expect(throws: ANError.invalidData) { try store.save(Data(repeating: 1, count: 31), forCard: "c1") }
    }

    @Test func tokenAcakDanHashSHA256() throws {
        let first = try StatusToken.generate()
        let second = try StatusToken.generate()
        #expect(first.count == 32 && second.count == 32 && first != second)
        #expect(StatusToken.hash(first) == Data(SHA256.hash(data: first)))
    }
}
