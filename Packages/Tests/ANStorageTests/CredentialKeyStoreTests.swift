import ANCore
import ANCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Synchronization
import Testing
@testable import ANStorage

@Suite("Kunci kredensial, counter, dan record (ADR-0009, SDD §5.3)")
struct CredentialKeyStoreTests {
    let credentialID = Data(repeating: 0xC1, count: 16)

    @Test func counterNaikLintasInstance() throws {
        // Review Focus 5: counter tidak pernah terulang/mundur walau store dibuat ulang.
        let secrets = InMemorySecretStore()
        let a = KeychainCounterStore(store: secrets)
        #expect(try a.next(for: credentialID) == 1)
        #expect(try a.next(for: credentialID) == 2)
        let b = KeychainCounterStore(store: secrets)
        #expect(try b.next(for: credentialID) == 3)
        #expect(try b.next(for: Data(repeating: 0xC2, count: 16)) == 1)
    }

    @Test func counterTidakTerulangSaatParalel() throws {
        let counters = KeychainCounterStore(store: InMemorySecretStore())
        let results = Mutex<[UInt32]>([])
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let value = try! counters.next(for: credentialID)
            results.withLock { $0.append(value) }
        }
        let values = results.withLock { $0 }
        #expect(Set(values).count == 100)
        #expect(values.max() == 100)
    }

    @Test func kunciPerangkatDisimpanDenganAksesibilitasPasscode() throws {
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let publicKey = try keys.createKey(for: credentialID)
        #expect(publicKey.count == 65)
        #expect(secrets.accessibility(for: DeviceKeyStore.storageKey(for: credentialID)) == .whenPasscodeSetThisDeviceOnly)
        #expect(try keys.hasKey(for: credentialID))
    }

    @Test func signerDariKunciTersimpanValid() throws {
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let publicKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(for: credentialID))
        let signer = try keys.signer(for: credentialID, context: AuthorizedContext(laContext: LAContext()))
        let message = Data("ANP1-P".utf8)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signer.sign(message))
        #expect(publicKey.isValidSignature(signature, for: message))
    }

    @Test func kunciHilangSetelahDihapus() throws {
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        _ = try keys.createKey(for: credentialID)
        try keys.deleteKey(for: credentialID)
        #expect(try !keys.hasKey(for: credentialID))
        #expect(throws: ANError.keyUnavailable) {
            try keys.signer(for: credentialID, context: AuthorizedContext(laContext: LAContext()))
        }
    }

    @Test func kunciDipindahKeCredIDServer() throws {
        // cred_id ditetapkan server setelah kunci dibuat; kunci tetap bisa menandatangani.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        let local = Data(repeating: 0x0A, count: 16), server = Data(repeating: 0x0B, count: 16)
        let publicKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(for: local))
        try keys.moveKey(from: local, to: server)
        #expect(try !keys.hasKey(for: local))
        // Review lab M2: kelas proteksi ikut dipindah (CLAUDE.md aturan 5).
        #expect(secrets.accessibility(for: DeviceKeyStore.storageKey(for: server)) == .whenPasscodeSetThisDeviceOnly)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: keys.signer(for: server, context: AuthorizedContext(laContext: LAContext())).sign(Data("m".utf8)))
        #expect(publicKey.isValidSignature(signature, for: Data("m".utf8)))
    }

    @Test func moveKeyKeIDSamaTidakMenghapusKunci() throws {
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let id = Data(repeating: 0x0C, count: 16)
        _ = try keys.createKey(for: id)
        try keys.moveKey(from: id, to: id)
        #expect(try keys.hasKey(for: id))
    }

    @Test func moveKeyTidakMenimpaKunciLain() throws {
        // Review lab M1: cred_id dari server yang bentrok tidak boleh menghapus kunci kartu lain.
        let keys = DeviceKeyStore(store: InMemorySecretStore(), factory: SoftwareKeyFactory())
        let local = Data(repeating: 0x0A, count: 16), other = Data(repeating: 0x0B, count: 16)
        _ = try keys.createKey(for: local)
        let otherKey = try P256.Signing.PublicKey(x963Representation: keys.createKey(for: other))
        #expect(throws: ANError.invalidData) { try keys.moveKey(from: local, to: other) }
        #expect(try keys.hasKey(for: local))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: keys.signer(for: other, context: AuthorizedContext(laContext: LAContext())).sign(Data("m".utf8)))
        #expect(otherKey.isValidSignature(signature, for: Data("m".utf8)))
    }

    @Test func moveKeyGagalHapusSumberMengembalikanTujuan() throws {
        // Review lab M1: tulis tujuan sukses tetapi hapus sumber gagal → tidak ada salinan yatim.
        let local = Data(repeating: 0x0A, count: 16), server = Data(repeating: 0x0B, count: 16)
        let secrets = DeleteFailingSecretStore(failingKey: DeviceKeyStore.storageKey(for: local))
        let keys = DeviceKeyStore(store: secrets, factory: SoftwareKeyFactory())
        _ = try keys.createKey(for: local)
        #expect(throws: (any Error).self) { try keys.moveKey(from: local, to: server) }
        #expect(try keys.hasKey(for: local))
        #expect(try !keys.hasKey(for: server))
    }

    @Test func recordLamaTetapTerbaca() throws {
        // Review Focus 4: record Keychain yang ditulis sebelum perpanjangan ada tetap terbaca.
        struct OldRecord: Codable { let credentialID: Data; let certificate: Data; let notAfter: Date; let groupKeys: [String: [Data]] }
        let old = OldRecord(credentialID: credentialID, certificate: Data([0xCE]), notAfter: Date(timeIntervalSince1970: 1_794_000_000), groupKeys: ["a1a2a3a4a5a6a7a8": [Data([0x04])]])
        let record = try JSONDecoder().decode(CredentialRecord.self, from: JSONEncoder().encode(old))
        #expect(record.notAfter == old.notAfter)
        #expect(record.notBefore == nil)
        #expect(record.renewalURL == nil)
    }

    @Test func recordMenyimpanNotBeforeDanRenewalURL() throws {
        let records = KeychainCredentialRecordStore(store: InMemorySecretStore())
        let record = CredentialRecord(credentialID: credentialID, certificate: Data([0xCE]), notAfter: Date(timeIntervalSince1970: 1_794_604_800), groupKeys: [:],
                                      notBefore: Date(timeIntervalSince1970: 1_794_000_000), renewalURL: URL(string: "http://127.0.0.1:8080"))
        try records.save(record)
        #expect(try records.record(for: credentialID) == record)
    }

    @Test func recordMenjadiMaterial() throws {
        let groupID = Data(repeating: 0xA1, count: 8)
        let record = CredentialRecord(
            credentialID: credentialID,
            certificate: Data(repeating: 0xCE, count: 150),
            notAfter: Date(timeIntervalSince1970: 1_900_000_000),
            groupKeys: [groupID.hexString: [P256.Signing.PrivateKey().publicKey.x963Representation, P256.Signing.PrivateKey().publicKey.x963Representation]]
        )
        let store = KeychainCredentialRecordStore(store: InMemorySecretStore())
        try store.save(record)
        #expect(try store.record(for: credentialID) == record)
        let material = try record.material(suspended: false)
        #expect(material.groupKeys[groupID]?.count == 2)
        #expect(material.credentialID == credentialID)
        try store.delete(credentialID)
        #expect(try store.record(for: credentialID) == nil)
    }

    @Test func recordDenganLebihDariDuaKunciDitolak() {
        // Minor 5: paritas timing mengasumsikan ≤ 2 kunci per group (aktif + berikutnya).
        let keys = (0..<3).map { _ in P256.Signing.PrivateKey().publicKey.x963Representation }
        let record = CredentialRecord(credentialID: credentialID, certificate: Data(), notAfter: .now, groupKeys: ["a1a2a3a4a5a6a7a8": keys])
        #expect(throws: ANError.invalidData) { try record.material(suspended: false) }
    }

    @Test func kunciDecoyTidakBolehDiprovisikan() throws {
        let decoy = try P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x01, count: 32)).publicKey.x963Representation
        let record = CredentialRecord(credentialID: credentialID, certificate: Data(), notAfter: .now, groupKeys: ["a1a2a3a4a5a6a7a8": [decoy]])
        #expect(throws: ANError.invalidData) { try record.material(suspended: false) }
    }

    @Test func recordDenganKunciRusakDitolak() {
        let record = CredentialRecord(credentialID: credentialID, certificate: Data(), notAfter: .now, groupKeys: ["a1a2a3a4a5a6a7a8": [Data(repeating: 0x04, count: 65)]])
        #expect(throws: ANError.invalidData) { try record.material(suspended: false) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AN_DEVICE_TESTS"] == "1"))
    func kunciSecureEnclaveTidakDapatDiekspor() throws {
        // TC-ENR-13 (tipe H): hanya di iPhone fisik.
        let secrets = InMemorySecretStore()
        let keys = DeviceKeyStore(store: secrets, factory: SecureEnclaveKeyFactory())
        _ = try keys.createKey(for: credentialID)
        let blob = try #require(try secrets.get(DeviceKeyStore.storageKey(for: credentialID)))
        #expect(throws: (any Error).self) { try P256.Signing.PrivateKey(rawRepresentation: blob) }
        #expect(secrets.accessibility(for: DeviceKeyStore.storageKey(for: credentialID)) == .whenPasscodeSetThisDeviceOnly)
    }
}

/// Store yang gagal menghapus satu kunci tertentu (uji pemulihan `moveKey`).
private final class DeleteFailingSecretStore: SecretStore, @unchecked Sendable {
    private let base = InMemorySecretStore()
    private let failingKey: String

    init(failingKey: String) { self.failingKey = failingKey }

    func set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws {
        try base.set(data, for: key, accessibility: accessibility)
    }

    func get(_ key: String) throws -> Data? { try base.get(key) }

    func delete(_ key: String) throws {
        if key == failingKey { throw ANError.internalError }
        try base.delete(key)
    }
}
