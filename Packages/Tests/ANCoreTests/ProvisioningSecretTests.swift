import Foundation
import Testing
@testable import ANCore

@Suite("Tipe rahasia enrolment vs hash-nya (ADR-0040, ADR-0061)")
struct ProvisioningSecretTests {
    @Test func rahasiaDanHashBisaIsiSamaTapiTipeBeda() {
        // ADR-0061: keduanya bungkus Data dengan isi yang sama di test ini, tapi tipe Swift
        // yang berbeda — pemanggil yang menaruh ProvisioningSecret di parameter yang mengharap
        // ProvisioningSecretHash (atau sebaliknya) gagal kompilasi, bukan tertukar diam-diam
        // saat runtime. Jaminan ini tidak bisa diuji lewat assertion runtime; dibuktikan oleh
        // berkas ini dan pemanggil (CardProvisioner, APIClient) berhasil dikompilasi memakai
        // tipe yang benar di tempat yang benar.
        let raw = Data(repeating: 0x11, count: 32)
        let secret = ProvisioningSecret(raw: raw)
        let hash = ProvisioningSecretHash(raw: raw)
        #expect(secret.raw == hash.raw)
    }

    @Test func rawRoundtrip() {
        let raw = Data(repeating: 0x22, count: 32)
        #expect(ProvisioningSecret(raw: raw).raw == raw)
        #expect(ProvisioningSecretHash(raw: raw).raw == raw)
    }

    @Test func kesetaraanBerdasarkanRaw() {
        let a = Data(repeating: 0x33, count: 32)
        let b = Data(repeating: 0x34, count: 32)
        #expect(ProvisioningSecret(raw: a) == ProvisioningSecret(raw: a))
        #expect(ProvisioningSecret(raw: a) != ProvisioningSecret(raw: b))
        #expect(ProvisioningSecretHash(raw: a) == ProvisioningSecretHash(raw: a))
        #expect(ProvisioningSecretHash(raw: a) != ProvisioningSecretHash(raw: b))
    }
}
