import Foundation

/// Per-file vnode 监听器。spec §4.2 第二层兜底。
/// DispatchSourceFileSystemObject `.write | .extend | .delete | .rename`。
public final class VnodeWatcher: @unchecked Sendable {
    public enum VnodeEvent: Sendable, Equatable {
        case write, extend, delete, rename
    }

    public enum VnodeError: Error {
        case openFailed(String)
    }

    private let fd: Int32
    private let source: DispatchSourceFileSystemObject
    private var continuation: AsyncStream<VnodeEvent>.Continuation?
    private let lock = NSLock()

    public init(fileURL: URL) throws {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { throw VnodeError.openFailed(fileURL.path) }
        self.fd = fd
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
    }

    /// **单订阅**:多次调用会覆盖前一个 continuation。本 watcher 只被
    /// `JSONLWatcher` 单一持有,此约束无实际影响。
    public func events() -> AsyncStream<VnodeEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                let mask = self.source.data
                if mask.contains(.write)  { continuation.yield(.write)  }
                if mask.contains(.extend) { continuation.yield(.extend) }
                if mask.contains(.delete) { continuation.yield(.delete); continuation.finish() }
                if mask.contains(.rename) { continuation.yield(.rename); continuation.finish() }
            }
            source.setCancelHandler { [fd = self.fd] in close(fd) }
            source.resume()
        }
    }

    public func stop() {
        if !source.isCancelled { source.cancel() }
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    deinit { stop() }
}
