import Foundation

/// Scans `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` recursively.
/// Codex emits `type: "event_msg"` with `payload.type: "token_count"`
/// containing both `total_token_usage` (cumulative) and `last_token_usage`
/// (delta for this response). We use `last_token_usage` to avoid double-counting.
public struct CodexScanner: UsageScanner {
    public let sourceName = "Codex"
    private let root: String

    public init(codexHome: String = NSHomeDirectory() + "/.codex") {
        self.root = codexHome + "/sessions"
    }

    public func scan(
        cache: inout UsageFileCache,
        cutoff: Date,
        fm: FileManager
    ) -> Set<String> {
        // Force re-parse every scan: old cache entries may have been built
        // with total_token_usage (cumulative) instead of last_token_usage (delta).
        cache.files = cache.files.filter { $0.value.source != sourceName }

        var activeFiles = Set<String>()
        var filesFound = 0
        var filesParsed = 0

        guard let enumerator = fm.enumerator(atPath: root) else {
            usageLogger.notice("Codex: no enumerator for \(self.root, privacy: .public)")
            return activeFiles
        }
        while let subpath = enumerator.nextObject() as? String {
            let full = root + "/" + subpath
            guard subpath.hasSuffix(".jsonl") else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let mtime = attrs[.modificationDate] as? Date,
                  mtime >= cutoff else { continue }
            filesFound += 1
            activeFiles.insert(full)
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            var entry = cache.files[full] ?? UsageFileCache.FileEntry()
            entry.source = sourceName
            if size < entry.consumedBytes {
                entry = UsageFileCache.FileEntry()
                entry.source = sourceName
            }
            if size > entry.consumedBytes {
                consumeNewLines(path: full, parser: parseLine, into: &entry)
                filesParsed += 1
            }
            entry.entries.removeAll { $0.timestamp < cutoff }
            cache.files[full] = entry
        }
        let cachedCount = cache.files.values.filter { $0.source == sourceName }.count
        usageLogger.notice("Codex: found \(filesFound) files, parsed \(filesParsed) new, \(cachedCount) cached entries")
        return activeFiles
    }

    /// Parse one Codex transcript line.
    private func parseLine(_ line: String) -> ParsedUsageLine? {
        // Cheap pre-filter: `token_count` events contain both
        // `total_token_usage` and `last_token_usage`.
        guard line.contains("\"token_count\""), line.contains("token_usage") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "event_msg",
              let timestampRaw = obj["timestamp"] as? String,
              let timestamp = parseISO8601(timestampRaw),
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any]
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
        return ParsedUsageLine(timestamp: timestamp, messageId: messageId, usage: totals)
    }
}
