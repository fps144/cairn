import Foundation

/// 每 N 秒 tick 一次,调回调做兜底扫描。spec §4.2 第三层。
public actor Reconciler {
    private let interval: Duration
    private let onTick: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    public init(interval: Duration, onTick: @Sendable @escaping () async -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [interval, onTick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                await onTick()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
