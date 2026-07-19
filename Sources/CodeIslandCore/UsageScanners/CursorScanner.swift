import Foundation
import SQLite3

/// Scans Cursor usage via the CSV export API (tokscale approach).
/// Reads `cursorAuth/accessToken` from `globalStorage/state.vscdb`, sends it
/// as `WorkosCursorSessionToken` cookie to
/// `cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens`, and
/// caches the CSV at `~/.codeisland/cursor-usage.csv`.
/// Falls back to the cached CSV if the token is expired.
public struct CursorScanner: UsageScanner {
    public let sourceName = "Cursor"
    private let stateDBPath: String
    private let csvCachePath: String
    private let tokscaleCachePath: String

    public init(cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage") {
        self.stateDBPath = cursorStorage + "/state.vscdb"
        self.csvCachePath = NSHomeDirectory() + "/.codeisland/cursor-usage.csv"
        self.tokscaleCachePath = NSHomeDirectory() + "/.config/tokscale/cursor-cache/usage.csv"
    }

    public func scan(
        cache: inout UsageFileCache,
        cutoff: Date,
        fm: FileManager
    ) -> Set<String> {
        var activeFiles = Set<String>()
        let cacheKey = "cursor-csv"

        guard let token = readCursorSessionToken(dbPath: stateDBPath) else {
            usageLogger.notice("Cursor: no session token found")
            return activeFiles
        }
        usageLogger.notice("Cursor: found session token (len=\(token.count))")

        // Try to fetch fresh CSV; fall back to cache.
        var csvText: String?
        if let fresh = fetchCursorUsageCSV(token: token), !fresh.hasPrefix("<") {
            csvText = fresh
            try? fresh.write(toFile: csvCachePath, atomically: true, encoding: .utf8)
        } else if let cached = try? String(contentsOfFile: csvCachePath, encoding: .utf8),
                  !cached.hasPrefix("<") {
            usageLogger.notice("Cursor: using cached CSV")
            csvText = cached
        } else if let tokscale = try? String(contentsOfFile: tokscaleCachePath, encoding: .utf8),
                  !tokscale.hasPrefix("<") {
            usageLogger.notice("Cursor: using tokscale cache at \(self.tokscaleCachePath, privacy: .public)")
            csvText = tokscale
        } else {
            usageLogger.notice("Cursor: CSV fetch failed (token expired?) and no cache")
            return activeFiles
        }

        var entry = cache.files[cacheKey] ?? UsageFileCache.FileEntry()
        entry.source = sourceName
        entry.entries = parseCursorUsageCSV(text: csvText!)
        entry.entries.removeAll { $0.timestamp < cutoff }
        cache.files[cacheKey] = entry
        activeFiles.insert(cacheKey)
        usageLogger.notice("Cursor: \(entry.entries.count) entries in window")
        return activeFiles
    }

    // MARK: - Token reading

    private func readCursorSessionToken(dbPath: String) -> String? {
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

    // MARK: - CSV fetch

    private func fetchCursorUsageCSV(token: String) -> String? {
        let url = URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let response = response as? HTTPURLResponse,
               let data, let text = String(data: data, encoding: .utf8) {
                if response.statusCode == 200 && !text.hasPrefix("<") {
                    result = text
                } else {
                    usageLogger.notice("Cursor: HTTP \(response.statusCode), response starts with: \(String(text.prefix(50)), privacy: .public)")
                }
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }

    // MARK: - CSV parsing

    private func parseCursorUsageCSV(text: String) -> [UsageFileCache.CachedMessage] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { return [] }
        let headerFields = parseCSVLine(header)
        guard headerFields.contains(where: { $0.contains("Date") }) else {
            usageLogger.notice("Cursor: parsed 0 CSV rows (no Date header)")
            return []
        }
        let hasKind = headerFields.contains(where: { $0.contains("Kind") })
        var rows = 0
        var entries: [UsageFileCache.CachedMessage] = []
        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count >= (hasKind ? 5 : 4) else { continue }
            let modelIdx = hasKind ? (fields.count >= 7 ? 4 : 2) : 1
            let inputWithCacheIdx = modelIdx + 1
            let inputWithoutCacheIdx = modelIdx + 2
            let cacheReadIdx = modelIdx + 3
            let outputIdx = modelIdx + 4
            guard fields.indices.contains(0),
                  let date = parseCursorDate(fields[0]) else { continue }
            var totals = ClaudeUsageTotals()
            if fields.indices.contains(inputWithoutCacheIdx) {
                totals.inputTokens = Int(fields[inputWithoutCacheIdx]) ?? 0
            }
            if fields.indices.contains(inputWithCacheIdx),
               fields.indices.contains(inputWithoutCacheIdx) {
                let withCache = Int(fields[inputWithCacheIdx]) ?? 0
                let withoutCache = Int(fields[inputWithoutCacheIdx]) ?? 0
                totals.cacheCreationTokens = max(0, withCache - withoutCache)
            }
            if fields.indices.contains(cacheReadIdx) {
                totals.cacheReadTokens = Int(fields[cacheReadIdx]) ?? 0
            }
            if fields.indices.contains(outputIdx) {
                totals.outputTokens = Int(fields[outputIdx]) ?? 0
            }
            totals.messageCount = 1
            entries.append(.init(timestamp: date, usage: totals))
            rows += 1
        }
        usageLogger.notice("Cursor: parsed \(rows) CSV rows")
        return entries
    }

    private func parseCursorDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: raw) { return d }
        return parseISO8601(raw)
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
