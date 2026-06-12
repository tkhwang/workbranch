import CoreServices
import Foundation
import CompanionCore

final class RootWatcher {
    private final class CallbackBox: @unchecked Sendable {
        let root: String
        let filter: EventFilter
        let onChange: @MainActor (String) -> Void

        init(root: String, filter: EventFilter, onChange: @escaping @MainActor (String) -> Void) {
            self.root = root
            self.filter = filter
            self.onChange = onChange
        }
    }

    private struct StreamHandle {
        let stream: FSEventStreamRef
        let box: UnsafeMutableRawPointer
    }

    private var handles: [StreamHandle] = []

    init(roots: [String], configURL: URL? = nil, onRootChange: @escaping @MainActor (String) -> Void, onConfigChange: (@MainActor () -> Void)? = nil) {
        let filter = EventFilter()
        for root in roots {
            addStream(path: root, root: root, filter: filter, onRootChange: onRootChange)
        }
        if let configURL, let onConfigChange {
            addStream(path: configURL.deletingLastPathComponent().path, root: configURL.deletingLastPathComponent().path, filter: EventFilter()) { changedRoot in
                if changedRoot == configURL.deletingLastPathComponent().path {
                    onConfigChange()
                }
            }
        }
    }

    deinit {
        stop()
    }

    func start() {
        for handle in handles {
            FSEventStreamStart(handle.stream)
        }
    }

    func stop() {
        for handle in handles {
            FSEventStreamStop(handle.stream)
            FSEventStreamInvalidate(handle.stream)
            FSEventStreamRelease(handle.stream)
            Unmanaged<CallbackBox>.fromOpaque(handle.box).release()
        }
        handles.removeAll()
    }

    private func addStream(path: String, root: String, filter: EventFilter, onRootChange: @escaping @MainActor (String) -> Void) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let box = CallbackBox(root: root, filter: filter, onChange: onRootChange)
        let opaque = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(version: 0, info: opaque, retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            for path in paths.prefix(count) where box.filter.shouldRefresh(forPath: path, root: box.root) {
                let root = box.root
                let onChange = box.onChange
                Task { @MainActor in onChange(root) }
                break
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(opaque).release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        handles.append(StreamHandle(stream: stream, box: opaque))
    }
}
