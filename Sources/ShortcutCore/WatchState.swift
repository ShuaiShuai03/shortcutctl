import Foundation

/// Content-based debounce independent of file modification timestamps and editor replacement strategy.
public struct WatchState: Sendable {
    private let debounce: TimeInterval
    private var initialized = false
    private var published: Data?
    private var pending: Data?
    private var changedAt: TimeInterval = 0

    public init(debounce: TimeInterval) { self.debounce = debounce }

    public mutating func invalidate() {
        pending = nil
        published = nil
    }

    public mutating func observe(_ data: Data, at time: TimeInterval) -> Bool {
        if !initialized {
            initialized = true
            published = data
            return true
        }
        if data == published {
            pending = nil
            return false
        }
        if data != pending {
            pending = data
            changedAt = time
        }
        guard time - changedAt >= debounce else { return false }
        published = data
        pending = nil
        return true
    }
}
