import Foundation
import os

/// The one logging surface. Every message goes to the unified log, where Console.app and
/// `log stream --predicate 'subsystem == "com.meldiron.meraline"'` can read it, and to an
/// in-memory buffer that the diagnostics report in Settings › About includes.
///
/// Messages describe events, providers, models, paths, and errors. They never contain a question,
/// an answer, or a key, which is why they are logged as public and why the buffer can be pasted
/// into a bug report as is.
nonisolated enum Log {
    static let subsystem = "com.meldiron.meraline"

    static let app = Category("app")
    static let panel = Category("panel")
    static let chat = Category("chat")
    static let providers = Category("providers")
    static let commandLine = Category("cli")
    static let updates = Category("updates")
    static let settings = Category("settings")

    struct Category: Sendable {
        let name: String
        private let logger: Logger

        init(_ name: String) {
            self.name = name
            logger = Logger(subsystem: Log.subsystem, category: name)
        }

        func debug(_ message: String) { record(.debug, message) }
        func info(_ message: String) { record(.info, message) }
        func error(_ message: String) { record(.error, message) }

        private func record(_ level: LogEntry.Level, _ message: String) {
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
            LogBuffer.shared.append(LogEntry(date: .now, category: name, level: level, message: message))
        }
    }
}

nonisolated struct LogEntry: Sendable, Equatable {
    enum Level: String, Sendable {
        case debug, info, error
    }

    let date: Date
    let category: String
    let level: Level
    let message: String
}

/// The most recent log entries, kept in memory so diagnostics can include them without reading the
/// unified log. Appending is safe from any thread; the networking and command-line code logs from
/// background tasks.
nonisolated final class LogBuffer: Sendable {
    static let shared = LogBuffer(capacity: 300)

    let capacity: Int
    private let storage: OSAllocatedUnfairLock<[LogEntry]>

    init(capacity: Int) {
        self.capacity = capacity
        storage = OSAllocatedUnfairLock(initialState: [])
    }

    var entries: [LogEntry] {
        storage.withLock { $0 }
    }

    func append(_ entry: LogEntry) {
        storage.withLock { entries in
            entries.append(entry)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    func removeAll() {
        storage.withLock { $0.removeAll() }
    }
}
