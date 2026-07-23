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
}
