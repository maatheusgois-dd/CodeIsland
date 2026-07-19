import Foundation
import os

/// Shared logger for all usage scanners.
let usageLogger = Logger(subsystem: "com.codeisland", category: "usage-scanner")

/// Aggregated token counts for one message or one time bucket.
public struct ClaudeUsageTotals: Equatable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationTokens = 0
    public var cacheReadTokens = 0
    public var messageCount = 0

    public var isEmpty: Bool { messageCount == 0 }

    public init() {}

    mutating func add(_ other: ClaudeUsageTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        messageCount += other.messageCount
    }
}

/// Per-source totals for the history window.
public struct SourceTotals: Equatable, Sendable {
    public let name: String
    public let total: ClaudeUsageTotals
    public let dailyTotals: [ClaudeUsageTotals]
    public init(name: String, total: ClaudeUsageTotals, dailyTotals: [ClaudeUsageTotals]) {
        self.name = name
        self.total = total
        self.dailyTotals = dailyTotals
    }
}

/// Immutable result of a full scan — all sources merged.
public struct UsageSnapshot: Equatable, Sendable {
    public let last5h: ClaudeUsageTotals
    public let today: ClaudeUsageTotals
    public let hourlyOutputTokens: [Int]
    public let dailyTotals: [ClaudeUsageTotals]
    public let perSource: [SourceTotals]
    public let scannedAt: Date

    public init(
        last5h: ClaudeUsageTotals,
        today: ClaudeUsageTotals,
        hourlyOutputTokens: [Int],
        dailyTotals: [ClaudeUsageTotals] = [],
        perSource: [SourceTotals] = [],
        scannedAt: Date
    ) {
        self.last5h = last5h
        self.today = today
        self.hourlyOutputTokens = hourlyOutputTokens
        self.dailyTotals = dailyTotals
        self.perSource = perSource
        self.scannedAt = scannedAt
    }
}

/// Per-file incremental parse state. Transcripts are append-only, so each
/// rescan reads only the bytes past `consumedBytes`.
public struct UsageFileCache: Sendable {
    public struct CachedMessage: Sendable, Equatable {
        public let timestamp: Date
        public let usage: ClaudeUsageTotals
    }

    public struct FileEntry: Sendable {
        public var consumedBytes: UInt64 = 0
        public var entries: [CachedMessage] = []
        public var seenIds: Set<String> = []
        public var source: String = ""
    }

    public var files: [String: FileEntry] = [:]
    public init() {}
}

/// One parsed line from a transcript — the common output of all line parsers.
public struct ParsedUsageLine: Sendable {
    public let timestamp: Date
    public let messageId: String
    public let usage: ClaudeUsageTotals
}

/// A single AI source scanner. Each implementation owns its parsing,
/// file enumeration, and cache management. The coordinator runs all
/// scanners and merges their results into a `UsageSnapshot`.
public protocol UsageScanner: Sendable {
    /// Human-readable source name, e.g. "Claude Code", "Codex".
    var sourceName: String { get }
    /// Walk the source's files, parse new lines, update the cache, and
    /// return the set of active file paths (for cache pruning).
    func scan(
        cache: inout UsageFileCache,
        cutoff: Date,
        fm: FileManager
    ) -> Set<String>
}

// MARK: - Shared helpers

/// Read new bytes from an append-only transcript, parse each line with
/// `parser`, dedupe by message id, and append to `entry.entries`.
func consumeNewLines(
    path: String,
    parser: (String) -> ParsedUsageLine?,
    into entry: inout UsageFileCache.FileEntry
) {
    guard let handle = FileHandle(forReadingAtPath: path) else { return }
    defer { handle.closeFile() }
    handle.seek(toFileOffset: entry.consumedBytes)
    let data = handle.readDataToEndOfFile()
    guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
    let consumable = data[data.startIndex...lastNewline]
    entry.consumedBytes += UInt64(consumable.count)
    guard let text = String(data: consumable, encoding: .utf8) else { return }

    for line in text.split(separator: "\n") {
        guard let parsed = parser(String(line)),
              !entry.seenIds.contains(parsed.messageId) else { continue }
        entry.seenIds.insert(parsed.messageId)
        entry.entries.append(.init(timestamp: parsed.timestamp, usage: parsed.usage))
    }
}

let fractionalISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let plainISOFormatter = ISO8601DateFormatter()

func parseISO8601(_ raw: String) -> Date? {
    fractionalISOFormatter.date(from: raw) ?? plainISOFormatter.date(from: raw)
}

/// Compact human token count: 950, 32.5K, 1.4M.
public func formatTokens(_ count: Int) -> String {
    let abs = Swift.abs(count)
    if abs < 1000 { return "\(count)" }
    let k = Double(abs) / 1000
    if k < 1000 { return String(format: "%.1fK", k) }
    let m = k / 1000
    if m < 1000 { return String(format: "%.1fM", m) }
    return String(format: "%.1fB", m / 1000)
}
