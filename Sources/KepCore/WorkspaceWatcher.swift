import Foundation
import CoreServices
import Logging

/// Recursive directory watcher backed by FSEvents. Used to refresh the
/// workspace sidebar when files appear, disappear, or change outside of Kep.
/// Mirrors `io.methvin.watcher.DirectoryWatcher` from the Java app.
public final class WorkspaceWatcher {
    public typealias Handler = @Sendable ([URL]) -> Void

    private let path: String
    private let queue: DispatchQueue
    private let handler: Handler
    private let logger = Logger(label: "kep.core.workspace-watcher")
    private var stream: FSEventStreamRef?

    public init(url: URL, queue: DispatchQueue = .main, handler: @escaping Handler) {
        self.path = url.path
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    @discardableResult
    public func start() -> Bool {
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let pathsToWatch: CFArray = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<WorkspaceWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self)
            var urls: [URL] = []
            urls.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                if let cfStr = unsafeBitCast(CFArrayGetValueAtIndex(cfPaths, i), to: CFString?.self) {
                    urls.append(URL(fileURLWithPath: cfStr as String))
                }
            }
            watcher.queue.async { watcher.handler(urls) }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                  // 500 ms latency — coalesces bursts
            flags
        ) else {
            logger.warning("FSEventStreamCreate failed for \(path)")
            return false
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        return true
    }

    public func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    public var isWatching: Bool { stream != nil }
}
