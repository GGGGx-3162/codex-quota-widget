import Darwin
import Foundation

/// Watches the active Codex session file without repeatedly reading JSONL data.
/// The 30-second timer remains the fallback and periodically rebinds this
/// monitor in case Codex starts a session in a new date directory.
final class SessionChangeMonitor: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let queue = DispatchQueue(label: "com.local.codexgauge.session-monitor")
    private let onChange: @Sendable () -> Void
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var watchedFileURL: URL?

    init?(
        directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        onChange: @escaping @Sendable () -> Void
    ) {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return nil }
        self.sessionsDirectory = directoryURL
        self.onChange = onChange
        rescan()
    }

    func rescan() {
        queue.async { [weak self] in
            self?.bindToNewestSessionFile()
        }
    }

    private func bindToNewestSessionFile() {
        guard let newestFile = newestSessionFile() else { return }
        guard newestFile != watchedFileURL else { return }

        fileSource?.cancel()
        directorySource?.cancel()
        fileSource = nil
        directorySource = nil
        watchedFileURL = newestFile

        fileSource = makeSource(
            for: newestFile,
            events: [.write, .extend, .attrib, .rename, .delete]
        ) { [weak self] event in
            guard let self else { return }
            self.onChange()
            if !event.intersection([.rename, .delete]).isEmpty {
                self.bindToNewestSessionFile()
            }
        }

        directorySource = makeSource(
            for: newestFile.deletingLastPathComponent(),
            events: [.write, .extend, .attrib, .rename, .delete]
        ) { [weak self] _ in
            guard let self else { return }
            self.onChange()
            self.bindToNewestSessionFile()
        }
    }

    private func newestSessionFile() -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, modified: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            if newest == nil || modified > newest!.modified {
                newest = (url, modified)
            }
        }
        return newest?.url
    }

    private func makeSource(
        for url: URL,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: queue
        )
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
    }
}
