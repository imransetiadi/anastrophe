import ANCore
import Foundation
import Testing
@testable import ANNFCEnroll

@Suite("Pemetaan kartu terdeteksi ke identitas (FR-11, ADR-0001)")
struct CardIdentityMapperTests {
    let uid7 = Data([0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])

    @Test func mifareTujuhByteMenjadiISO14443A() {
        #expect(CardIdentityMapper.identity(for: .miFare(identifier: uid7)) == CardIdentity(technology: .iso14443a, identifier: uid7))
    }

    @Test func iso7816TipeAMemakaiUID() {
        #expect(CardIdentityMapper.identity(for: .iso7816(identifier: uid7, typeA: true)) == CardIdentity(technology: .iso14443a, identifier: uid7))
    }

    @Test func iso7816TipeBTidakDidukung() {
        // PUPI tipe B bukan UID yang tercatat di registri (identitas berbasis AID menyusul).
        #expect(CardIdentityMapper.identity(for: .iso7816(identifier: Data([1, 2, 3, 4]), typeA: false)) == nil)
    }

    @Test func iso15693DelapanByte() {
        let uid = Data([0xE0, 0x04, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        #expect(CardIdentityMapper.identity(for: .iso15693(identifier: uid)) == CardIdentity(technology: .iso15693, identifier: uid))
    }

    @Test func panjangTidakSahDitolak() {
        #expect(CardIdentityMapper.identity(for: .miFare(identifier: Data(repeating: 1, count: 5))) == nil)
        #expect(CardIdentityMapper.identity(for: .iso15693(identifier: Data(repeating: 1, count: 7))) == nil)
    }

    @Test func unsupportedDitolak() {
        #expect(CardIdentityMapper.identity(for: .unsupported) == nil)
    }

    @Test func pembacaTetapMengembalikanHasil() async throws {
        let identity = try #require(CardIdentity(technology: .iso14443a, identifier: uid7))
        #expect(try await FixedCardOwnershipReader(.identity(identity)).readIdentity() == identity)
        await #expect(throws: ANError.cardUnreadable) { try await FixedCardOwnershipReader(.failure(.cardUnreadable)).readIdentity() }
        await #expect(throws: CancellationError.self) { try await FixedCardOwnershipReader(.cancelled).readIdentity() }
    }
}
