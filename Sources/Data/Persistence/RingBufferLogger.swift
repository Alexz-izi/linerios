//
//  RingBufferLogger.swift
//  LineriOS
//
//  In-memory circular log buffer for Windows-less on-device diagnostics.
//  Captures IPC latency, HTTP response codes, and background state transitions.
//

import Foundation

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    public let latencyMs: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String,
        latencyMs: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.latencyMs = latencyMs
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

public enum LogLevel: String, Sendable, Equatable {
    case debug = "DBG"
    case info = "INF"
    case warn = "WRN"
    case error = "ERR"
}

public final class RingBufferLogger: @unchecked Sendable {
    public static let shared = RingBufferLogger()

    private let capacity: Int
    private var buffer: [LogEntry]
    private var writeIndex: Int = 0
    private var isFull: Bool = false
    private let lock = NSLock()

    public init(capacity: Int = 100) {
        self.capacity = max(10, capacity)
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    public func log(
        level: LogLevel,
        category: String,
        message: String,
        latencyMs: Double? = nil
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            latencyMs: latencyMs
        )

        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(entry)
        } else {
            buffer[writeIndex] = entry
            isFull = true
        }

        writeIndex = (writeIndex + 1) % capacity
    }

    public func getRecentLogs() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        if !isFull {
            return buffer.reversed()
        }

        var result: [LogEntry] = []
        result.reserveCapacity(capacity)

        // Read from newest to oldest
        for i in 1...capacity {
            let idx = (writeIndex - i + capacity) % capacity
            result.append(buffer[idx])
        }
        return result
    }

    public func exportPlaintext() -> String {
        let entries = getRecentLogs().reversed()
        var text = "=== LINERiOS DIAGNOSTIC LOG EXPORT ===\n"
        text += "Exported At: \(Date().ISO8601Format())\n"
        text += "Total Entries: \(entries.count)\n\n"

        for entry in entries {
            let latencyStr = entry.latencyMs.map { String(format: " (%.1fms)", $0) } ?? ""
            text += "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)\(latencyStr)\n"
        }
        return text
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        isFull = false
    }
}
