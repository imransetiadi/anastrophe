import ANCore
import ANNetworking
import ANNFCEnroll
import ANStorage
import Foundation
import Testing
@testable import ANFeatures

@MainActor
@Suite("Alur Tambah Kartu (FR-10–FR-13, ADR-0043)")
struct AddCardModelTests {
    static let siteID = "5d2c0a9e-0000-4000-8000-000000000009"
    let site = (200, #"{"site_id":"\#(AddCardModelTests.siteID)","name":"Menara Uji"}"#, "application/json")
    let enrolled = (201, #"{"enrollment_id":"6f1c2a9e-0000-4000-8000-000000000001","status":"PROVISIONING"}"#, "application/json")
    let credentialID = Data(repeating: 0x5E, count: 16)
    let token = String(repeating: "A", count: 42) + "w"

    func problem(_ type: String, _ status: Int = 404) -> (status: Int, body: String, contentType: String) {
        (status, #"{"type":"\#(type)","status":\#(status)}"#, "application/problem+json")
    }

    func make(_ replies: [(status: Int, body: String, contentType: String)], reader: FixedCardOwnershipReader.Outcome = .identity(labTestCard),
              baseURL: URL? = URL(string: "http://127.0.0.1:8080")) -> (AddCardModel, SequenceTransport, AppServices) {
        let transport = SequenceTransport(replies)
        let services = AppServices.inMemory(events: [.waitingForReader], apiBaseURL: baseURL)
        return (AddCardModel(services: services, reader: FixedCardOwnershipReader(reader), transport: transport), transport, services)
    }

    func json(_ data: Data?) throws -> [String: Any] {
        let body = try #require(data)
        let object = try JSONSerialization.jsonObject(with: body)
        return try #require(object as? [String: Any])
    }

    /// Kode gedung dikenal → langkah konfirmasi.
    func confirmed(_ model: AddCardModel) async {
        model.chooseCard()
        model.codeInput = "7k2q-9xa4"
        await model.submitCode()
    }

    @Test func kodeRusakTidakMemanggilJaringan() async {
        let (model, transport, _) = make([])
        model.chooseCard()
        model.codeInput = "abc"
        await model.submitCode()
        #expect(model.step == .siteCode)
        #expect(model.fieldError == localized("add.code.invalid"))
        #expect(transport.paths.isEmpty)
    }

    @Test func kodeTakDikenalTetapDiLangkahKode() async {
        let (model, _, _) = make([problem("SITE-NOT-FOUND")])
        await confirmed(model)
        #expect(model.step == .siteCode)
        #expect(model.fieldError == localized("add.error.site_code_unknown"))
    }

    @Test func kodeDikenalMenampilkanNamaGedung() async {
        let (model, transport, _) = make([site])
        await confirmed(model)
        #expect(model.step == .confirmSite(SiteSummary(siteID: Self.siteID, name: "Menara Uji")))
        #expect(model.fieldError == nil)
        #expect(transport.paths == ["/v1/sites/lookup"])
    }

    @Test func kartuTerdaftarMenjadiAktif() async throws {
        let (model, transport, services) = make([site, configBody(["ble"]), enrolled, (200, provisionedBody(credentialID: credentialID), "application/json")])
        await confirmed(model)
        await model.confirmAndRead()
        guard case .done(let card) = model.step else { Issue.record("langkah \(model.step)"); return }
        #expect(card.credentials[.ble] == credentialID)
        #expect(try await services.cards.all().map(\.id) == [card.id])
        #expect(transport.paths == ["/v1/sites/lookup", "/v1/config", "/v1/enrollments", "/v1/enrollments/6f1c2a9e-0000-4000-8000-000000000001/credentials"])
        let body = try json(transport.bodies[2])
        #expect(body["device_id"] as? String == (try services.deviceIdentity.deviceID()))
        #expect(body["site_id"] as? String == Self.siteID)
    }

    @Test func kartuTakTerdaftarMenawarkanUndangan() async {
        let (model, _, _) = make([site, configBody(["ble"]), problem("ENR-NOT-REGISTERED")])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("enroll.error.not_registered"), offersInvitation: true)))
    }

    @Test func gedungTanpaRegistriMenawarkanUndangan() async {
        // Review akhir #7: ENR-SITE-UNSUPPORTED berarti gedung belum memakai registri kartu (hanya undangan),
        // jadi FR-13 menawarkan jalur undangan dengan teks yang tidak bertentangan dengan gedung terkonfirmasi.
        let (model, _, _) = make([site, configBody(["ble"]), problem("ENR-SITE-UNSUPPORTED")])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("enroll.error.site_unsupported"), offersInvitation: true)))
        #expect(!localized("enroll.error.site_unsupported").contains("Anastrophe"))
    }

    @Test func batasPermintaanMenungguMengarahkanKePengelola() async {
        let (model, _, _) = make([site, configBody(["ble"]), problem("ENR-PENDING-LIMIT", 409)])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("enroll.error.pending_limit"), offersInvitation: false)))
    }

    @Test func kanalGedungDariKodeGedungDipakai() async {
        // ADR-0049: gedung hanya mengizinkan "Tempel ke pembaca", iPhone ini hanya punya Bluetooth.
        let site = (200, #"{"site_id":"\#(Self.siteID)","name":"Menara Uji","channels":["nfcHCE"]}"#, "application/json")
        let (model, transport, _) = make([site, configBody(["ble", "nfcHCE"])])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("add.error.site_channel_unavailable"), offersInvitation: false)))
        #expect(transport.paths == ["/v1/sites/lookup", "/v1/config"])
    }

    @Test func cobaLagiSetelahKanalGedungMencariUlang() async {
        // Review akhir (Minor 1, dinaikkan): setelah pengelola melonggarkan kebijakan, "Coba lagi" mencari
        // ulang kode gedung, bukan memakai kanal dari lookup pertama.
        let restricted = (200, #"{"site_id":"\#(Self.siteID)","name":"Menara Uji","channels":["nfcHCE"]}"#, "application/json")
        let loosened = (200, #"{"site_id":"\#(Self.siteID)","name":"Menara Uji","channels":["ble","nfcHCE"]}"#, "application/json")
        let (model, transport, _) = make([restricted, configBody(["ble", "nfcHCE"]), loosened])
        await confirmed(model)
        await model.confirmAndRead()
        guard case .failed = model.step else { Issue.record("langkah \(model.step)"); return }
        model.back()
        #expect(model.step == .siteCode)
        #expect(model.codeInput == "7k2q-9xa4")
        await model.submitCode()
        #expect(model.step == .confirmSite(SiteSummary(siteID: Self.siteID, name: "Menara Uji", channels: [.ble, .nfcHCE])))
        #expect(transport.paths == ["/v1/sites/lookup", "/v1/config", "/v1/sites/lookup"])
    }

    @Test func kartuTakTerbacaMenawarkanUndangan() async {
        let (model, transport, _) = make([site], reader: .failure(.cardUnreadable))
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("add.error.unreadable"), offersInvitation: true)))
        #expect(transport.paths == ["/v1/sites/lookup"])
    }

    @Test func pembacaTidakTersediaMenawarkanUndangan() async {
        let (model, _, _) = make([site], reader: .failure(.cardReaderUnavailable))
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .failed(.init(message: localized("add.error.reader_unavailable"), offersInvitation: true)))
    }

    @Test func pembatalanKembaliKeKonfirmasi() async {
        let (model, transport, _) = make([site], reader: .cancelled)
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .confirmSite(SiteSummary(siteID: Self.siteID, name: "Menara Uji")))
        #expect(model.fieldError == nil && !model.isBusy)
        #expect(transport.paths == ["/v1/sites/lookup"])
    }

    @Test func menungguPersetujuanMenjelaskanLangkah() async {
        let (model, _, _) = make([site, configBody(["ble"]), (201, #"{"enrollment_id":"e1","status":"PENDING_APPROVAL"}"#, "application/json")])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(model.step == .pending(siteName: "Menara Uji"))
    }

    @Test func tautanUndanganMenambahKartu() async throws {
        let (model, transport, _) = make([configBody(["ble"]), enrolled, (200, provisionedBody(credentialID: credentialID), "application/json")])
        model.chooseInvitation()
        model.linkInput = "  https://contoh.test/i/\(token)  "
        await model.submitInvitation()
        guard case .done = model.step else { Issue.record("langkah \(model.step)"); return }
        #expect(try json(transport.bodies[1])["invitation"] as? String == token)
    }

    @Test func tautanRusakDitolakDiField() async {
        let (model, transport, _) = make([])
        model.chooseInvitation()
        model.linkInput = "https://contoh.test/x/\(token)"
        await model.submitInvitation()
        #expect(model.step == .invitation)
        #expect(model.fieldError == localized("add.link.invalid"))
        #expect(transport.paths.isEmpty)
    }

    @Test func tanpaBaseURLLayananBelumTersedia() async {
        let (model, transport, _) = make([], baseURL: nil)
        #expect(!model.isServiceAvailable)
        model.chooseCard()
        model.codeInput = "7K2Q9XA4"
        await model.submitCode()
        #expect(model.step == .failed(.init(message: localized("add.error.service_unavailable"), offersInvitation: false)))
        #expect(transport.paths.isEmpty)
    }

    @Test func ketukGandaHanyaSatuEnrolment() async {
        // Review Focus 4: ketukan kedua selama pembacaan kartu berjalan diabaikan.
        let transport = SequenceTransport([site, configBody(["ble"]), enrolled, (200, provisionedBody(credentialID: credentialID), "application/json")])
        let reader = GatedReader()
        let model = AddCardModel(services: AppServices.inMemory(events: [.waitingForReader], apiBaseURL: URL(string: "http://127.0.0.1:8080")),
                                 reader: reader, transport: transport)
        await confirmed(model)
        let first = Task { await model.confirmAndRead() }
        for _ in 0..<10_000 where reader.callCount == 0 { await Task.yield() }
        #expect(reader.callCount == 1)
        let second = Task { await model.confirmAndRead() }
        for _ in 0..<1_000 where reader.callCount == 1 { await Task.yield() }
        reader.releaseAll()
        await first.value
        await second.value
        #expect(reader.callCount == 1)
        #expect(transport.paths.filter { $0 == "/v1/enrollments" }.count == 1)
        guard case .done = model.step else { Issue.record("langkah \(model.step)"); return }
    }

    @Test func identitasKartuTidakTertinggal() async throws {
        // Review Focus 1: identitas kartu hanya dikirim ke server, tidak tertinggal di state atau store app.
        let hex = labTestCard.hex
        let (model, _, services) = make([site, configBody(["ble"]), enrolled, (200, provisionedBody(credentialID: credentialID), "application/json")])
        await confirmed(model)
        await model.confirmAndRead()
        #expect(!String(describing: model.step).contains(hex))
        let cards = String(decoding: try JSONEncoder().encode(try await services.cards.all()), as: UTF8.self)
        #expect(!cards.contains(hex))
        let record = try #require(try services.records.record(for: credentialID))
        #expect(!String(decoding: try JSONEncoder().encode(record), as: UTF8.self).contains(hex))

        let (failing, _, _) = make([site, configBody(["ble"]), problem("ENR-NOT-REGISTERED")])
        await confirmed(failing)
        await failing.confirmAndRead()
        #expect(!String(describing: failing.step).contains(hex))
    }

    @Test func entriDariURLUndangan() {
        let link = URL(string: "https://contoh.test/i/\(token)")!
        #expect(AddCardEntry.entry(for: link) == .invitation(link))
        #expect(AddCardEntry.entry(for: URL(string: "http://contoh.test/i/\(token)")!) == nil)
        #expect(AddCardEntry.entry(for: URL(string: "https://contoh.test/g/\(token)")!) == nil)
    }

    @Test func tautanDariSistemDiisiTanpaLangsungMendaftar() async {
        // Tautan yang dibuka sistem hanya mengisi field; pengguna tetap mengetuk "Tambahkan kartu", jadi
        // tautan kiriman orang lain tidak mendaftarkan kartu diam-diam.
        let (model, transport, _) = make([])
        model.prefill(invitationURL: URL(string: "https://contoh.test/i/\(token)")!)
        #expect(model.step == .invitation)
        #expect(model.linkInput == "https://contoh.test/i/\(token)")
        #expect(transport.paths.isEmpty)
    }

    @Test func cobaLagiKembaliKeKonfirmasiGedung() async {
        // Kartu tak terbaca: "Coba lagi" kembali ke gedung yang sudah dikonfirmasi tanpa mengetik ulang kode.
        let (model, _, _) = make([site], reader: .failure(.cardUnreadable))
        await confirmed(model)
        await model.confirmAndRead()
        model.back()
        #expect(model.step == .confirmSite(SiteSummary(siteID: Self.siteID, name: "Menara Uji")))
        model.chooseInvitation()
        model.back()
        #expect(model.step == .chooseMethod)
    }
}

/// Pembaca yang menahan pembacaan sampai dilepas, agar ketukan kedua benar-benar terjadi selama pembacaan.
final class GatedReader: CardOwnershipReader, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    func readIdentity() async throws -> CardIdentity {
        await withCheckedContinuation { continuation in
            lock.withLock {
                calls += 1
                waiting.append(continuation)
            }
        }
        return labTestCard
    }

    func releaseAll() {
        let released = lock.withLock {
            defer { waiting = [] }
            return waiting
        }
        released.forEach { $0.resume() }
    }
}
