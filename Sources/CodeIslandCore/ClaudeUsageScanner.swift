import Foundation
import SQLite3

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

/// Token-usage aggregation over local transcripts — local-first, no provider
/// API calls. Two sources are merged:
///   • Claude Code: `~/.claude/projects/**/*.jsonl` — assistant lines carry
///     `message.usage` with `input_tokens`/`output_tokens`/`cache_*_input_tokens`.
///   • OMP: `~/.omp/agent/sessions/**/*.jsonl` — `type:"message"` lines carry
///     `message.usage` with `input`/`output`/`cacheRead`/`cacheWrite`.
/// Every assistant line carries `message.usage`; `message.id` (Claude) or the
/// top-level `id` (OMP) repeats across tool-use continuation lines of the same
/// API response, so totals dedupe on it — per file, since ids never straddle
/// files (Claude UUIDs are global; OMP short hex are unique within a session).
public enum ClaudeUsageScanner {
    /// Sparkline resolution: one bucket per hour, oldest first.
    public static let sparklineHours = 12

    /// History resolution: one bucket per day, oldest first.
    public static let historyDays = 14

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

    public struct Snapshot: Equatable, Sendable {
        public let last5h: ClaudeUsageTotals
        public let today: ClaudeUsageTotals
        /// Output tokens per hour for the trailing `sparklineHours` hours,
        /// index 0 oldest, last index = the current hour.
        public let hourlyOutputTokens: [Int]
        /// Daily totals for the trailing `historyDays` days. `dailyTotals[0]`
        /// is 13 days ago (midnight-to-midnight), `dailyTotals[last]` is
        /// today. Merges Claude Code and OMP usage.
        public let dailyTotals: [ClaudeUsageTotals]
        /// Per-source breakdown (Claude Code, OMP) for the 14-day window.
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
    /// rescan reads only the bytes past `consumedBytes` — a day-long multi-MB
    /// transcript is never re-read in full. Value semantics: the caller owns a
    /// copy, hands it to the background scan, and stores the returned state.
    public struct FileCache: Sendable {
        struct CachedMessage: Sendable, Equatable {
            let timestamp: Date
            let usage: ClaudeUsageTotals
        }
        struct FileEntry: Sendable {
            var consumedBytes: UInt64 = 0
            var entries: [CachedMessage] = []
            var seenIds: Set<String> = []
            var source: String = ""
        }
        var files: [String: FileEntry] = [:]
        public init() {}
    }

    /// One-shot convenience (tests, callers without persistent state).
    public static func scan(
        claudeHome: String = NSHomeDirectory() + "/.claude",
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/workspaceStorage",
        now: Date = Date()
    ) -> Snapshot {
        var cache = FileCache()
        return scan(claudeHome: claudeHome, ompHome: ompHome, codexHome: codexHome, cursorStorage: cursorStorage, now: now, cache: &cache)
    }

    public static func scan(
        claudeHome: String = NSHomeDirectory() + "/.claude",
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/workspaceStorage",
        now: Date = Date(),
        cache: inout FileCache
    ) -> Snapshot {
        let calendar = Calendar.current
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let midnight = calendar.startOfDay(for: now)
        let sparklineStart = now.addingTimeInterval(-Double(sparklineHours) * 3600)
        let historyStart = midnight.addingTimeInterval(-Double(historyDays - 1) * 86_400)
        let cutoff = min(fiveHoursAgo, midnight, sparklineStart, historyStart)

        var last5h = ClaudeUsageTotals()
        var today = ClaudeUsageTotals()
        var hourly = [Int](repeating: 0, count: sparklineHours)
        // daily[0] = 13 days ago, daily[last] = today.
        var daily = [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
        var activeFiles = Set<String>()

        let fm = FileManager.default
        // Claude: ~/.claude/projects/<project>/<file>.jsonl
        // OMP:    ~/.omp/agent/sessions/<project>/<file>.jsonl
        let sources: [(root: String, name: String, parser: (String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)?)] = [
            (claudeHome + "/projects", "Claude Code", parseAssistantUsage),
            (ompHome + "/agent/sessions", "OMP", parseOMPUsage),
        ]
        for source in sources {
            enumerateProjects(
                root: source.root, sourceName: source.name, parser: source.parser, fm: fm,
                cutoff: cutoff, cache: &cache, activeFiles: &activeFiles)
        }

        // Codex: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (recursive)
        enumerateRecursive(
            root: codexHome + "/sessions", sourceName: "Codex", parser: parseCodexUsage,
            fm: fm, cutoff: cutoff, cache: &cache, activeFiles: &activeFiles)

        // Cursor: message count only (no token counts stored). Scan all
        // workspaceStorage state.vscdb files for aiService.generations.
        enumerateCursorUsage(
            cursorStorage: cursorStorage, fm: fm, cutoff: cutoff,
            cache: &cache, activeFiles: &activeFiles)

        // Per-source accumulators.
        var perSourceTotals: [String: ClaudeUsageTotals] = [:]
        var perSourceDaily: [String: [ClaudeUsageTotals]] = [:]

        func tally(_ message: FileCache.CachedMessage, _ sourceName: String) {
            guard message.timestamp <= now else { return }
            if message.timestamp >= fiveHoursAgo { last5h.add(message.usage) }
            if message.timestamp >= midnight { today.add(message.usage) }
            let hoursAgo = Int(now.timeIntervalSince(message.timestamp) / 3600)
            if hoursAgo >= 0 && hoursAgo < sparklineHours {
                hourly[sparklineHours - 1 - hoursAgo] += message.usage.outputTokens
            }
            let messageDay = calendar.startOfDay(for: message.timestamp)
            let daysAgo = Int(midnight.timeIntervalSince(messageDay) / 86_400)
            if daysAgo >= 0 && daysAgo < historyDays {
                daily[historyDays - 1 - daysAgo].add(message.usage)
            }
            // Per-source tracking.
            perSourceTotals[sourceName, default: ClaudeUsageTotals()].add(message.usage)
            if daysAgo >= 0 && daysAgo < historyDays {
                var sd = perSourceDaily[sourceName] ?? [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
                sd[historyDays - 1 - daysAgo].add(message.usage)
                perSourceDaily[sourceName] = sd
            }
        }

        // Files that fell out of the mtime window carry no in-window entries.
        cache.files = cache.files.filter { activeFiles.contains($0.key) }
        for (path, entry) in cache.files {
            let src = entry.source.isEmpty ? "Unknown" : entry.source
            for message in entry.entries where message.timestamp >= cutoff {
                tally(message, src)
            }
        }

        let allSourceNames = ["Claude Code", "OMP", "Codex", "Cursor"]
        let perSource = allSourceNames.map { name in
            SourceTotals(
                name: name,
                total: perSourceTotals[name] ?? ClaudeUsageTotals(),
                dailyTotals: perSourceDaily[name] ?? [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
            )
        }.filter { !$0.total.isEmpty }

        return Snapshot(
            last5h: last5h, today: today,
            hourlyOutputTokens: hourly, dailyTotals: daily,
            perSource: perSource, scannedAt: now)
    }

    /// cached offset, prune entries older than `cutoff`, and record active
    private static func enumerateProjects(
        root: String,
        sourceName: String,
        parser: (String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)?,
        fm: FileManager,
        cutoff: Date,
        cache: inout FileCache,
        activeFiles: inout Set<String>
    ) {
        for project in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let projectPath = root + "/" + project
            for file in (try? fm.contentsOfDirectory(atPath: projectPath)) ?? [] {
                guard file.hasSuffix(".jsonl") else { continue }
                let path = projectPath + "/" + file
                // mtime gate: untouched-since-cutoff transcripts can't contain
                // in-window lines, so the scan stays cheap on big histories.
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mtime = attrs[.modificationDate] as? Date,
                      mtime >= cutoff else { continue }
                activeFiles.insert(path)
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

                var entry = cache.files[path] ?? FileCache.FileEntry()
                entry.source = sourceName
                if size < entry.consumedBytes {
                    // Truncated or replaced — start over.
                    entry = FileCache.FileEntry()
                    entry.source = sourceName
                }
                if size > entry.consumedBytes {
                    consumeNewLines(path: path, parser: parser, into: &entry)
                }
                entry.entries.removeAll { $0.timestamp < cutoff }
                cache.files[path] = entry
            }
        }
    }

    /// Read bytes past `entry.consumedBytes` and parse the COMPLETE lines only —
    /// a partial trailing line (writer mid-append) is left for the next scan.
    /// `parser` selects the source-specific line shape (Claude vs OMP).
    private static func consumeNewLines(
        path: String,
        parser: (String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)?,
        into entry: inout FileCache.FileEntry
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

    /// Parse one transcript line into (timestamp, message id, usage) — nil for
    /// non-assistant lines and lines without usage.
    static func parseAssistantUsage(_ line: String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)? {
        // Cheap pre-filter before full JSON decoding: assistant lines only.
        guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let timestampRaw = obj["timestamp"] as? String,
              let timestamp = parseISO8601(timestampRaw),
              let message = obj["message"] as? [String: Any],
              let messageId = message["id"] as? String,
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        var totals = ClaudeUsageTotals()
        totals.inputTokens = usage["input_tokens"] as? Int ?? 0
        totals.outputTokens = usage["output_tokens"] as? Int ?? 0
        totals.cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        totals.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
        totals.messageCount = 1
        return (timestamp, messageId, totals)
    }

    /// Parse one OMP transcript line into (timestamp, message id, usage) — nil
    /// for non-`message` lines and lines without usage. OMP's schema differs
    /// from Claude's: `type` is `"message"` (not `"assistant"`), the dedupe id
    /// is the top-level `id` (not `message.id`), and `message.usage` uses
    /// `input`/`output`/`cacheRead`/`cacheWrite` keys (no `_tokens` suffix).
    static func parseOMPUsage(_ line: String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)? {
        // Cheap pre-filter before full JSON decoding.
        guard line.contains("\"message\""), line.contains("\"usage\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "message",
              let timestampRaw = obj["timestamp"] as? String,
              let timestamp = parseISO8601(timestampRaw),
              let messageId = obj["id"] as? String,
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        var totals = ClaudeUsageTotals()
        totals.inputTokens = usage["input"] as? Int ?? 0
        totals.outputTokens = usage["output"] as? Int ?? 0
        // OMP's `cacheWrite` maps to Claude's cache-creation bucket.
        totals.cacheCreationTokens = usage["cacheWrite"] as? Int ?? 0
        totals.cacheReadTokens = usage["cacheRead"] as? Int ?? 0
        totals.messageCount = 1
        return (timestamp, messageId, totals)
    }


    /// Parse one Codex transcript line. Codex emits `type: "event_msg"` with
    /// `payload.type: "token_count"` containing `total_token_usage`. Each
    /// `total_token_usage` is cumulative for the session, so we only record
    /// the LAST one per session file — but the incremental cache dedupes by
    /// the `id` field on the message, and token_count events have no `id`,
    /// so we synthesize one from the timestamp.
    static func parseCodexUsage(_ line: String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)? {
        guard line.contains("\"token_count\""), line.contains("\"total_token_usage\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "event_msg",
              let timestampRaw = obj["timestamp"] as? String,
              let timestamp = parseISO8601(timestampRaw),
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any]
        else { return nil }

        var totals = ClaudeUsageTotals()
        totals.inputTokens = usage["input_tokens"] as? Int ?? 0
        totals.outputTokens = (usage["output_tokens"] as? Int ?? 0)
            + (usage["reasoning_output_tokens"] as? Int ?? 0)
        totals.cacheReadTokens = usage["cached_input_tokens"] as? Int ?? 0
        totals.cacheCreationTokens = usage["cache_write_input_tokens"] as? Int ?? 0
        totals.messageCount = 1
        // Dedupe by timestamp — each token_count event has a unique timestamp.
        let messageId = "codex-tc-\(timestampRaw)"
        return (timestamp, messageId, totals)
    }

    /// Recursively walk a directory tree (Codex: sessions/YYYY/MM/DD/*.jsonl),
    /// applying the same mtime gate and incremental cache as `enumerateProjects`.
    private static func enumerateRecursive(
        root: String,
        sourceName: String,
        parser: (String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)?,
        fm: FileManager,
        cutoff: Date,
        cache: inout FileCache,
        activeFiles: inout Set<String>
    ) {
        guard let enumerator = fm.enumerator(atPath: root) else { return }
        while let subpath = enumerator.nextObject() as? String {
            let full = root + "/" + subpath
            guard subpath.hasSuffix(".jsonl") else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let mtime = attrs[.modificationDate] as? Date,
                  mtime >= cutoff else { continue }
            activeFiles.insert(full)
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

            var entry = cache.files[full] ?? FileCache.FileEntry()
            entry.source = sourceName
            if size < entry.consumedBytes {
                entry = FileCache.FileEntry()
                entry.source = sourceName
            }
            if size > entry.consumedBytes {
                consumeNewLines(path: full, parser: parser, into: &entry)
            }
            entry.entries.removeAll { $0.timestamp < cutoff }
            cache.files[full] = entry
        }
    }

    /// Scan Cursor workspaceStorage for aiService.generations in state.vscdb.
    /// Cursor doesn't store token counts — only conversation metadata — so we
    /// record one messageCount per generation (no token data).
    private static func enumerateCursorUsage(
        cursorStorage: String,
        fm: FileManager,
        cutoff: Date,
        cache: inout FileCache,
        activeFiles: inout Set<String>
    ) {
        let cacheKey = "cursor:usage-csv"
        let csvPath = NSHomeDirectory() + "/.codeisland/cursor-usage.csv"

        // Try to fetch fresh CSV from Cursor's usage export API.
        // Uses the session token from Cursor's globalStorage state.vscdb.
        let globalStorageDb = cursorStorage.replacingOccurrences(
            of: "/User/workspaceStorage",
            with: "/User/globalStorage/state.vscdb"
        )
        if let token = readCursorSessionToken(dbPath: globalStorageDb) {
            if let csv = fetchCursorUsageCSV(token: token) {
                try? csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
            }
        }

        // Parse the cached CSV (either freshly fetched or from a previous run).
        guard fm.fileExists(atPath: csvPath),
              let attrs = try? fm.attributesOfItem(atPath: csvPath),
              let mtime = attrs[.modificationDate] as? Date,
              mtime >= cutoff.addingTimeInterval(-Double(historyDays) * 86_400)
        else { return }

        activeFiles.insert(cacheKey)
        var entry = cache.files[cacheKey] ?? FileCache.FileEntry()
        entry.source = "Cursor"

        let rows = parseCursorUsageCSV(path: csvPath)
        for row in rows {
            let id = "cursor-csv-\(row.date.timeIntervalSince1970)-\(row.model)"
            guard !entry.seenIds.contains(id) else { continue }
            entry.seenIds.insert(id)
            guard row.date >= cutoff else { continue }
            entry.entries.append(.init(timestamp: row.date, usage: row.usage))
        }
        entry.entries.removeAll { $0.timestamp < cutoff }
        cache.files[cacheKey] = entry
    }

    /// Read the Cursor session token from globalStorage/state.vscdb.
    private static func readCursorSessionToken(dbPath: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }

    /// Fetch the usage CSV from Cursor's dashboard export API.
    /// Returns the CSV text, or nil on failure (expired token, network error).
    private static func fetchCursorUsageCSV(token: String) -> String? {
        let url = URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { result = String(data: data, encoding: .utf8) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }

    /// Parse a Cursor usage CSV file (tokscale-compatible: v1/v2/v3 formats).
    /// Returns (date, model, usage) for each row.
    private static func parseCursorUsageCSV(path: String) -> [(date: Date, model: String, usage: ClaudeUsageTotals)] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        let header = parseCSVLine(lines[0])
        guard header.contains("Date"), header.contains("Model") else { return [] }

        // Detect format by checking for "Kind" column and column count.
        let hasKind = header.contains { $0.trimmingCharacters(in: .whitespaces) == "Kind" }
        let (
            modelIdx, inputCacheWriteIdx, inputNoCacheIdx, cacheReadIdx, outputIdx
        ): (Int, Int, Int, Int, Int) = if hasKind && header.count >= 11 {
            // v3: Date,Cloud Agent ID,Automation ID,Kind,Model,...
            (4, 6, 7, 8, 9)
        } else if hasKind {
            // v2: Date,Kind,Model,Max Mode,Input (w/ Cache Write),...
            (2, 4, 5, 6, 7)
        } else {
            // v1: Date,Model,Input (w/ Cache Write),...
            (1, 2, 3, 4, 5)
        }

        var results: [(date: Date, model: String, usage: ClaudeUsageTotals)] = []
        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count > outputIdx else { continue }
            let dateStr = fields[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let model = fields[modelIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard model.isEmpty == false else { continue }
            guard let date = parseCursorDate(dateStr) else { continue }

            let inputWithCache = Int(fields[inputCacheWriteIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            let inputNoCache = Int(fields[inputNoCacheIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            let cacheRead = Int(fields[cacheReadIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            let output = Int(fields[outputIdx].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0

            var totals = ClaudeUsageTotals()
            totals.inputTokens = max(0, inputNoCache)
            totals.outputTokens = max(0, output)
            totals.cacheReadTokens = max(0, cacheRead)
            totals.cacheCreationTokens = max(0, inputWithCache - inputNoCache)
            totals.messageCount = 1
            results.append((date, model, totals))
        }
        return results
    }

    /// Parse a Cursor CSV date string (e.g. "2026-07-18 03:09:23") to Date.
    private static func parseCursorDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: str) { return date }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }

    /// Simple CSV line parser handling quoted fields.
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if inQuotes {
                if ch == "\"" { inQuotes = false }
                else { current.append(ch) }
            } else {
                if ch == "\"" { inQuotes = true }
                else if ch == "," { fields.append(current); current = "" }
                else { current.append(ch) }
            }
        }
        fields.append(current)
        return fields
    }
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainFormatter = ISO8601DateFormatter()

    static func parseISO8601(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }

    /// Compact human token count: 950, 32.5K, 1.4M. Unit selection uses the
    /// rounded value so 999,950 rolls over to "1M" instead of "1000K".
    public static func formatTokens(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        func fmt(_ value: Double, _ unit: String) -> String {
            String(format: "%.1f\(unit)", value).replacingOccurrences(of: ".0\(unit)", with: unit)
        }
        let thousands = Double(count) / 1000
        if thousands < 999.95 { return fmt(thousands, "K") }
        let millions = Double(count) / 1_000_000
        if millions < 999.95 { return fmt(millions, "M") }
        return fmt(Double(count) / 1_000_000_000, "B")
    }
}
