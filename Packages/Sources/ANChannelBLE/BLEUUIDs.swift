import CoreBluetooth

/// UUID GATT ANP/1 (SDD §6.3), UUIDv4 yang dibuat sekali saat M1.
/// Properti terhitung karena `CBUUID` tidak `Sendable`.
public enum BLEUUIDs {
    /// Service `ANP`; data iklannya memuat `group_id` 8 B.
    public static var service: CBUUID { CBUUID(string: "8F7AED59-144E-47BD-BEFC-E80CD73BB7C0") }
    /// `ANP-Control`: frame ponsel → reader (write with response).
    public static var control: CBUUID { CBUUID(string: "FA06A2CF-289D-47B7-B3C9-842636994663") }
    /// `ANP-Response`: frame reader → ponsel (indicate).
    public static var response: CBUUID { CBUUID(string: "8E68331B-4026-4FBB-A670-0EE8E56698D8") }
}
