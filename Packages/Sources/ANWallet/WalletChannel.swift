import ANCore

/// Kanal W (Apple Wallet Access, Aliro) dijadwalkan R2 (ADR-0002, ADR-0008).
/// Sampai program Apple aktif untuk akun ini, kanal selalu `.programNotEnabled`.
public enum WalletGate {
    public static func availability(config: RemoteConfig) -> ChannelAvailability {
        guard config.enabledChannels.contains(.wallet) else { return .regionBlocked }
        return config.walletProgramEnabled ? .available : .programNotEnabled
    }
}
