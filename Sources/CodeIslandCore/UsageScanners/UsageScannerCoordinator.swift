import Foundation

/// Coordinates all usage scanners and merges their results into a single
/// `UsageSnapshot`. Each scanner is an independent `UsageScanner` that owns
/// its parsing, file enumeration, and cache management.
public enum UsageScannerCoordinator {
    public static let sparklineHours = 12
    public static let historyDays = 14

    /// One-shot convenience (tests, callers without persistent state).
    public static func scan(
        claudeHome: String = NSHomeDirectory() + "/.claude",
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage",
        now: Date = Date()
    ) -> UsageSnapshot {
        var cache = UsageFileCache()
        return scan(
            claudeHome: claudeHome, ompHome: ompHome, codexHome: codexHome,
            cursorStorage: cursorStorage, now: now, cache: &cache)
    }

    /// Persistent-state scan: callers keep a `UsageFileCache` across scans so
    /// only new transcript bytes are parsed.
    public static func scan(
        claudeHome: String = NSHomeDirectory() + "/.claude",
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage",
        now: Date = Date(),
        cache: inout UsageFileCache
    ) -> UsageSnapshot {
        let calendar = Calendar.current
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let midnight = calendar.startOfDay(for: now)
        let sparklineStart = now.addingTimeInterval(-Double(sparklineHours) * 3600)
        let historyStart = midnight.addingTimeInterval(-Double(historyDays - 1) * 86_400)
        let cutoff = min(fiveHoursAgo, midnight, sparklineStart, historyStart)

        let fm = FileManager.default
        let scanners: [UsageScanner] = [
            ClaudeCodeScanner(claudeHome: claudeHome),
            OMPScanner(ompHome: ompHome),
            CodexScanner(codexHome: codexHome),
            CursorScanner(cursorStorage: cursorStorage),
        ]

        // Run all scanners concurrently — each only touches its own files
        // (different directories), so cache.files keys never collide.
        // Copy cache to a local value so escaping closures can capture it.
        var baseCache = cache
        let scannerCount = scanners.count
        let results = (0..<scannerCount).map { _ in UnsafeBox<ScanResult?>(nil) }
        let group = DispatchGroup()
        for i in 0..<scannerCount {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                var localCache = baseCache
                let active = scanners[i].scan(cache: &localCache, cutoff: cutoff, fm: fm)
                results[i].value = ScanResult(activeFiles: active, files: localCache.files)
                group.leave()
            }
        }
        group.wait()

        var allActiveFiles = Set<String>()
        for r in results {
            if let r = r.value {
                allActiveFiles.formUnion(r.activeFiles)
                baseCache.files.merge(r.files) { _, new in new }
            }
        }
        cache = baseCache

        // Prune cache entries that fell out of the mtime window.
        cache.files = cache.files.filter { allActiveFiles.contains($0.key) }

        // Tally all cached entries into aggregates.
        var last5h = ClaudeUsageTotals()
        var today = ClaudeUsageTotals()
        var hourly = [Int](repeating: 0, count: sparklineHours)
        var daily = [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
        var perSourceTotals: [String: ClaudeUsageTotals] = [:]
        var perSourceDaily: [String: [ClaudeUsageTotals]] = [:]

        for (_, entry) in cache.files {
            let src = entry.source.isEmpty ? "Unknown" : entry.source
            for message in entry.entries where message.timestamp >= cutoff {
                guard message.timestamp <= now else { continue }
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
                perSourceTotals[src, default: ClaudeUsageTotals()].add(message.usage)
                if daysAgo >= 0 && daysAgo < historyDays {
                    var sd = perSourceDaily[src] ?? [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
                    sd[historyDays - 1 - daysAgo].add(message.usage)
                    perSourceDaily[src] = sd
                }
            }
        }

        let allSourceNames = scanners.map { $0.sourceName }
        let perSource = allSourceNames.map { name in
            SourceTotals(
                name: name,
                total: perSourceTotals[name] ?? ClaudeUsageTotals(),
                dailyTotals: perSourceDaily[name] ?? [ClaudeUsageTotals](repeating: ClaudeUsageTotals(), count: historyDays)
            )
        }.filter { !$0.total.isEmpty }

        for s in perSource {
            usageLogger.notice("perSource [\(s.name, privacy: .public)]: in=\(s.total.inputTokens) out=\(s.total.outputTokens) cache=\(s.total.cacheReadTokens) msgs=\(s.total.messageCount)")
        }

        return UsageSnapshot(
            last5h: last5h, today: today,
            hourlyOutputTokens: hourly, dailyTotals: daily,
            perSource: perSource, scannedAt: now)
    }
}

/// Result of one scanner's run.
private struct ScanResult {
    let activeFiles: Set<String>
    let files: [String: UsageFileCache.FileEntry]
}

/// Thread-safe box for storing a scan result from a background queue.
private final class UnsafeBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
