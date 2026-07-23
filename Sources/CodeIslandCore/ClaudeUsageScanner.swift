import Foundation

/// Compatibility shim — delegates to the new per-source scanner architecture.
/// All parsing logic now lives in `UsageScanners/` — one class per source:
///   • `ClaudeCodeScanner` — `~/.claude/projects/**/*.jsonl`
///   • `OMPScanner` — `~/.omp/agent/sessions/**/*.jsonl`
///   • `CodexScanner` — `~/.codex/sessions/**/*.jsonl`
///   • `CursorScanner` — CSV export API (tokscale approach)
/// `UsageScannerCoordinator` runs them all and merges results.
public enum ClaudeUsageScanner {
    public static let sparklineHours = UsageScannerCoordinator.sparklineHours
    public static let historyDays = UsageScannerCoordinator.historyDays

    public typealias Snapshot = UsageSnapshot
    public typealias FileCache = UsageFileCache
    public typealias SourceTotals = CodeIslandCore.SourceTotals

    public static func scan(
        claudeHome: String = ClaudeConfigPaths.configDir(),
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage",
        now: Date = Date()
    ) -> Snapshot {
        UsageScannerCoordinator.scan(
            claudeHome: claudeHome, ompHome: ompHome, codexHome: codexHome,
            cursorStorage: cursorStorage, now: now)
    }

    public static func scan(
        claudeHome: String = ClaudeConfigPaths.configDir(),
        ompHome: String = NSHomeDirectory() + "/.omp",
        codexHome: String = NSHomeDirectory() + "/.codex",
        cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage",
        now: Date = Date(),
        cache: inout FileCache
    ) -> Snapshot {
        UsageScannerCoordinator.scan(
            claudeHome: claudeHome, ompHome: ompHome, codexHome: codexHome,
            cursorStorage: cursorStorage, now: now, cache: &cache)
    }

    public static func formatTokens(_ count: Int) -> String {
        CodeIslandCore.formatTokens(count)
    }

    /// Parse one Claude Code transcript line into (timestamp, message id, usage).
    /// Exposed for tests; mirrors `ClaudeCodeScanner.parseLine`.
    static func parseAssistantUsage(_ line: String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)? {
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
}
