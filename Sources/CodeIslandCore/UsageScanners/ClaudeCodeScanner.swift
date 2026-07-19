import Foundation

/// Scans `~/.claude/projects/**/*.jsonl` for assistant message usage.
/// Claude Code transcripts have `type: "assistant"` lines carrying
/// `message.usage` with `input_tokens`/`output_tokens`/`cache_*_input_tokens`.
public struct ClaudeCodeScanner: UsageScanner {
    public let sourceName = "Claude Code"
    private let root: String

    public init(claudeHome: String = NSHomeDirectory() + "/.claude") {
        self.root = claudeHome + "/projects"
    }

    public func scan(
        cache: inout UsageFileCache,
        cutoff: Date,
        fm: FileManager
    ) -> Set<String> {
        var activeFiles = Set<String>()
        enumerateProjects(
            root: root, cache: &cache, activeFiles: &activeFiles,
            cutoff: cutoff, fm: fm)
        return activeFiles
    }

    private func enumerateProjects(
        root: String,
        cache: inout UsageFileCache,
        activeFiles: inout Set<String>,
        cutoff: Date,
        fm: FileManager
    ) {
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: root) else { return }
        for project in projectDirs {
            let projectPath = root + "/" + project
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = projectPath + "/" + file
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mtime = attrs[.modificationDate] as? Date,
                      mtime >= cutoff else { continue }
                activeFiles.insert(path)
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                var entry = cache.files[path] ?? UsageFileCache.FileEntry()
                entry.source = sourceName
                if size < entry.consumedBytes {
                    entry = UsageFileCache.FileEntry()
                    entry.source = sourceName
                }
                if size > entry.consumedBytes {
                    consumeNewLines(path: path, parser: parseLine, into: &entry)
                }
                entry.entries.removeAll { $0.timestamp < cutoff }
                cache.files[path] = entry
            }
        }
    }

    /// Parse one Claude Code transcript line.
    /// Only assistant lines with `message.usage` are relevant.
    private func parseLine(_ line: String) -> ParsedUsageLine? {
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
        return ParsedUsageLine(timestamp: timestamp, messageId: messageId, usage: totals)
    }
}
