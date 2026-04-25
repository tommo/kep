import Foundation
import Logging

/// Watches a single file for write/extend/rename/delete events using
/// `DispatchSource.makeFileSystemObjectSource`. Mirrors what
/// `io.methvin.watcher` does per-file in the Java app, scoped down to one
/// path so the per-document hookup is dead simple.
public final class FileWatcher {
    public typealias Handler = @Sendable (DispatchSource.FileSystemEvent) -> Void

    private let url: URL
    private let queue: DispatchQueue
    private let handler: Handler
    private let logger = Logger(label: "mindo.core.file-watcher")

    private var source: (any DispatchSourceFileSystemObject)?
    private var fileDescriptor: Int32 = -1

    public init(url: URL, queue: DispatchQueue = .main, handler: @escaping Handler) {
        self.url = url
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    /// Begin watching. Returns false when the file can't be opened (missing,
    /// no permission, etc).
    @discardableResult
    public func start() -> Bool {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("FileWatcher could not open \(url.path)")
            return false
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.handler(src.data)
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        src.resume()
        self.source = src
        self.fileDescriptor = fd
        return true
    }

    public func stop() {
        if let src = source {
            src.cancel()
        }
        source = nil
        fileDescriptor = -1
    }

    public var isWatching: Bool { source != nil }
}
