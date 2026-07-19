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

        var allActiveFiles = Set<String>()
        for scanner in scanners {
            let active = scanner.scan(cache: &cache, cutoff: cutoff, fm: fm)
            allActiveFiles.formUnion(active)
        }

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
