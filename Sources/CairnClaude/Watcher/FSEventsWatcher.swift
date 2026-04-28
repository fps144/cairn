import Foundation
import CoreServices

/// 根目录 FSEvents 监听器。spec §4.2 第一层。
public final class FSEventsWatcher: @unchecked Sendable {
    public enum FSEvent: Sendable, Equatable {
        case created(URL), removed(URL), renamed(URL)
    }

    public enum FSEventsError: Error {
        case streamCreateFailed
    }

    private let rootURL: URL
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<FSEvent>.Continuation?
    private var contextPtr: UnsafeMutablePointer<FSEventStreamContext>?
    private let lock = NSLock()
    private var isStarted = false

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
    }

    /// **单订阅**:多次调用会覆盖前一个 continuation,前一个 stream 不再收事件。
    /// 本 watcher 只被 `JSONLWatcher` 单一持有,此约束无实际影响。
    public func events() -> AsyncStream<FSEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    public func start() throws {
        guard !isStarted else { return }
        isStarted = true

        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.pointee = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        self.contextPtr = context

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            for i in 0..<numEvents {
                let path = paths[i]
                let flags = eventFlags[i]
                let url = URL(fileURLWithPath: path)
                guard url.pathExtension == "jsonl" else { continue }

                let isCreated = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
                let isRemoved = flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
                let isRenamed = flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0

                // Renamed 同时表示 rename-in(新文件出现)和 rename-out(消失)。
                // atomic write(tmp + rename)会触发 Renamed 而非 Created,
                // 所以按 path 存在性判定,统一用 .created / .removed 语义。
                if isRenamed {
                    if FileManager.default.fileExists(atPath: url.path) {
                        watcher.emit(.created(url))
                    } else {
                        watcher.emit(.removed(url))
                    }
                }
                if isCreated { watcher.emit(.created(url)) }
                if isRemoved { watcher.emit(.removed(url)) }
            }
        }

        let pathsToWatch = [rootURL.path] as CFArray
        // UseCFTypes 让 callback 的 eventPaths 参数是 CFArray<CFString>(可桥 NSArray<String>),
        // 否则默认是 C char**,强转 NSArray 崩溃(SIGTRAP)。
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,  // latency
            UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            throw FSEventsError.streamCreateFailed
        }
        self.stream = stream

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func emit(_ event: FSEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(event)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        if let ptr = contextPtr {
            ptr.deallocate()
            contextPtr = nil
        }
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    deinit { stop() }
}
