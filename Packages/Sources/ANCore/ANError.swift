/// Error domain lintas modul. Kode katalog mengikuti SDD §15.
public enum ANError: Error, Equatable, Sendable {
    case cardLimitReached
    case channelUnavailable(ChannelAvailability)
    case keyUnavailable
    case invalidData
    case internalError
}
