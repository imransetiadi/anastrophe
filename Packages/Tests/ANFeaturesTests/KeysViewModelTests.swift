import ANCore
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Daftar kartu: kartu kedaluwarsa (ADR-0023, TC-DEV-11)")
struct KeysViewModelTests {
    let credentialID = Data(repeating: 0x5E, count: 16)
    let expiredAt = Date(timeIntervalSince1970: 1_000)

    func expiredCard(in services: AppServices, renewalURL: URL?) async throws -> Card {
        _ = try services.keys.createKey(for: credentialID)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: expiredAt, groupKeys: [:], renewalURL: renewalURL))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: expiredAt)
        try await services.cards.add(card)
        return card
    }

    @Test func kartuKedaluwarsaDariBackendBisaDipakai() async throws {
        // Tanpa ini tombol "Gunakan kartu" nonaktif dan perpanjangan saat tap tidak pernah terjadi.
        let services = AppServices.inMemory()
        let card = try await expiredCard(in: services, renewalURL: URL(string: "http://127.0.0.1:8080"))
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.presentability(of: card) == .available(.ble))
    }

    @Test func kartuKedaluwarsaTanpaBackendTetapDitolak() async throws {
        // Kartu lab_ca.py tidak bisa diperpanjang, jadi tap pasti gagal: tetap nonaktif.
        let services = AppServices.inMemory()
        let card = try await expiredCard(in: services, renewalURL: nil)
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.presentability(of: card) == .unavailable(.expired))
    }

    @Test func masaBerlakuKartuMengikutiRecord() async throws {
        // Review I1: record adalah sumber kebenaran masa berlaku; kartu di daftar disesuaikan.
        let services = AppServices.inMemory()
        let renewedUntil = Date(timeIntervalSince1970: 1_794_787_200)
        _ = try services.keys.createKey(for: credentialID)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: renewedUntil, groupKeys: [:], renewalURL: URL(string: "http://127.0.0.1:8080")))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: expiredAt)
        try await services.cards.add(card)
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.cards.first?.notAfter == renewedUntil)
        #expect(try await services.cards.all().first?.notAfter == renewedUntil)
    }

    func nearExpiryModel(online: Bool, hoursLeft: Double) async throws -> (KeysViewModel, Card) {
        let services = AppServices.inMemory(events: [.waitingForReader], connectivity: FixedConnectivity(isOnline: online))
        _ = try services.keys.createKey(for: credentialID)
        let notAfter = Date.now.addingTimeInterval(hoursLeft * 3_600)
        try services.records.save(CredentialRecord(credentialID: credentialID, certificate: Data(repeating: 0xAA, count: 188), notAfter: notAfter, groupKeys: [:], renewalURL: URL(string: "http://127.0.0.1:8080")))
        let card = Card(id: UUID(), name: "Gedung Lab", siteName: "Gedung Lab", zones: [], status: .active, credentials: [.ble: credentialID], notAfter: notAfter)
        try await services.cards.add(card)
        let model = KeysViewModel(services: services)
        await model.load()
        return (model, card)
    }

    @Test func peringatanOfflineSaatPerluDiperbarui() async throws {
        // TC-DEV-10: sisa < 24 jam dan offline → "Perlu terhubung ke internet".
        let (offline, card) = try await nearExpiryModel(online: false, hoursLeft: 12)
        #expect(offline.renewalNotice(for: card) == .needsInternet)
        let (online, sameCard) = try await nearExpiryModel(online: true, hoursLeft: 12)
        #expect(online.renewalNotice(for: sameCard) == .renewsOnNextUse)
    }

    @Test func tanpaPeringatanBilaMasihLama() async throws {
        let (model, card) = try await nearExpiryModel(online: false, hoursLeft: 5 * 24)
        #expect(model.renewalNotice(for: card) == nil)
    }

    @Test func riwayatLebihDariTigaPuluhHariDipangkas() async throws {
        // Review Focus 3 (FR-30): hanya 30 hari terakhir yang tampil dan disimpan.
        let services = AppServices.inMemory()
        let card = Card(id: UUID(), name: "Lobi", siteName: "Menara A", zones: [], status: .active, credentials: [:], notAfter: nil)
        try await services.cards.add(card)
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(-31 * 86_400), channel: .ble, granted: true, denyReason: nil))
        try await services.tapHistory.append(TapEntry(cardID: card.id, date: .now.addingTimeInterval(-86_400), channel: .ble, granted: false, denyReason: .suspended))
        let model = KeysViewModel(services: services)
        await model.load()
        #expect(model.history(for: card).count == 1)
        #expect(try await services.tapHistory.entries(for: card.id, since: .distantPast).count == 1)
    }
}

