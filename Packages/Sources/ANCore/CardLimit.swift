/// Batas 8 kartu per perangkat, dihitung per kartu (bukan per kredensial).
/// Ditegakkan di app **dan** server (CLAUDE.md aturan 8, SDD §4.2).
public enum CardLimit {
    public static let maxCardsPerDevice = 8

    public static func canAddCard(currentCount: Int) -> Bool {
        currentCount < maxCardsPerDevice
    }

    public static func ensureCanAdd(currentCount: Int) throws(ANError) {
        guard canAddCard(currentCount: currentCount) else { throw .cardLimitReached }
    }
}
