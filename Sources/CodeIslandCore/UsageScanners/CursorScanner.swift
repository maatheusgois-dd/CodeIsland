import Foundation
import SQLite3
import CommonCrypto

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
    private let chromeCookiesPath: String

    public init(cursorStorage: String = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage") {
        self.stateDBPath = cursorStorage + "/state.vscdb"
        self.csvCachePath = NSHomeDirectory() + "/.codeisland/cursor-usage.csv"
        self.tokscaleCachePath = NSHomeDirectory() + "/.config/tokscale/cursor-cache/usage.csv"
        self.chromeCookiesPath = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies"
    }

    public func scan(
        cache: inout UsageFileCache,
        cutoff: Date,
        fm: FileManager
    ) -> Set<String> {
        var activeFiles = Set<String>()
        let cacheKey = "cursor-csv"
        // Fast path: use cached CSV if available and recent (< 1 hour old).
        if let attrs = try? fm.attributesOfItem(atPath: csvCachePath),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < 3600,
           let cached = try? String(contentsOfFile: csvCachePath, encoding: .utf8),
           !cached.hasPrefix("<") {
            usageLogger.notice("Cursor: using recent cached CSV")
            var entry = cache.files[cacheKey] ?? UsageFileCache.FileEntry()
            entry.source = sourceName
            entry.entries = parseCursorUsageCSV(text: cached)
            entry.entries.removeAll { $0.timestamp < cutoff }
            cache.files[cacheKey] = entry
            activeFiles.insert(cacheKey)
            usageLogger.notice("Cursor: \(entry.entries.count) entries in window")
            return activeFiles
        }

        // Try Chrome cookie (like spinnaker-mcp/pycookiecheat), then IDE token.
        var sessionToken: String?
        if let chromeToken = readChromeCursorSessionToken() {
            usageLogger.notice("Cursor: extracted WorkosCursorSessionToken from Chrome (len=\(chromeToken.count))")
            sessionToken = chromeToken
        }
        if sessionToken == nil, let ideToken = readCursorSessionToken(dbPath: stateDBPath) {
            usageLogger.notice("Cursor: using IDE session token (len=\(ideToken.count))")
            sessionToken = ideToken
        }
        guard let token = sessionToken else {
            // Last resort: try any old cached CSV or tokscale cache.
            if let cached = try? String(contentsOfFile: csvCachePath, encoding: .utf8), !cached.hasPrefix("<") {
                usageLogger.notice("Cursor: using stale cached CSV (no token)")
                var entry = cache.files[cacheKey] ?? UsageFileCache.FileEntry()
                entry.source = sourceName
                entry.entries = parseCursorUsageCSV(text: cached)
                entry.entries.removeAll { $0.timestamp < cutoff }
                cache.files[cacheKey] = entry
                activeFiles.insert(cacheKey)
                usageLogger.notice("Cursor: \(entry.entries.count) entries in window")
            }
            return activeFiles
        }
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
            // Last resort: try gRPC GetCurrentPeriodUsage for billing cycle summary.
            usageLogger.notice("Cursor: CSV unavailable, trying gRPC GetCurrentPeriodUsage")
            if let grpcEntries = fetchCurrentPeriodUsage(token: token, cutoff: cutoff) {
                var entry = cache.files[cacheKey] ?? UsageFileCache.FileEntry()
                entry.source = sourceName
                entry.entries = grpcEntries
                cache.files[cacheKey] = entry
                activeFiles.insert(cacheKey)
                usageLogger.notice("Cursor: gRPC returned \(grpcEntries.count) entries")
                return activeFiles
            }
            usageLogger.notice("Cursor: all methods failed")
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

    // MARK: - gRPC fallback

    /// Fetch current period usage via gRPC-web to api2.cursor.sh.
    /// Returns a single synthetic entry for today with the billing cycle totals.
    /// The CSV export API is the preferred source, but it requires a browser
    /// session cookie; the gRPC call works with the IDE access token.
    private func fetchCurrentPeriodUsage(token: String, cutoff: Date) -> [UsageFileCache.CachedMessage]? {
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("0.50.0", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        // Empty protobuf message (gRPC-web frame: 0x00 flag + 4-byte length=0)
        request.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let response = response as? HTTPURLResponse,
               response.statusCode == 200,
               let data {
                responseData = data
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)

        guard let data = responseData, data.count > 10 else { return nil }

        // Parse gRPC-web frame: byte 0 = flag, bytes 1-4 = big-endian length
        let length = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        guard data.count >= 5 + length, length > 0 else { return nil }
        let proto = data[5..<(5 + length)]

        // Parse GetCurrentPeriodUsageResponse:
        // field 1 = billing_cycle_start (int64 millis)
        // field 2 = billing_cycle_end (int64 millis)
        // We don't get per-event token counts from this — only billing info.
        // Return nil to indicate no token data available.
        // The CSV export is the only source of per-event token counts.
        usageLogger.notice("Cursor: gRPC response \(data.count) bytes, proto \(length) bytes")
        return nil
    }

    // MARK: - Chrome cookie extraction

    /// Extract the `WorkosCursorSessionToken` cookie from Chrome's cookie DB.
    /// Uses the same technique as `pycookiecheat` / spinnaker-mcp:
    ///   1. Read the AES key from macOS Keychain (service "Chrome Safe Storage")
   ///   2. Derive a 16-byte key via PBKDF2 (password=key, salt="saltysalt", 1003 rounds)
    ///   3. Decrypt the cookie value from Chrome's SQLite Cookies DB (AES-128-CBC, IV=16*" ")
    ///   4. Strip the v10 prefix and PKCS7 padding
    /// Requires Chrome to have been logged into cursor.com.
    private func readChromeCursorSessionToken() -> String? {
        guard FileManager.default.fileExists(atPath: chromeCookiesPath) else { return nil }

        // Step 1: Read the Chrome Safe Storage key from Keychain.
        guard let chromeKey = readChromeSafeStorageKey() else {
            usageLogger.notice("Cursor: could not read Chrome Safe Storage key from Keychain")
            return nil
        }

        // Step 2: Derive AES key via PBKDF2.
        let derivedKey = deriveChromeAESKey(password: chromeKey)

        // Step 3: Read the encrypted cookie value from Chrome's SQLite DB.
        guard let encryptedValue = readEncryptedCookieValue() else {
            usageLogger.notice("Cursor: no WorkosCursorSessionToken in Chrome cookies")
            return nil
        }

        // Step 4: Decrypt the cookie value.
        // Chrome cookie encryption format: "v10" prefix + AES-128-CBC ciphertext, IV = 16 space bytes.
        guard encryptedValue.count > 3,
              encryptedValue.prefix(3) == Data("v10".utf8) else { return nil }
        let ciphertext = encryptedValue.subdata(in: 3..<encryptedValue.count)
        let iv = Data(repeating: 0x20, count: 16) // 16 space chars

        guard let plaintext = aesDecrypt(ciphertext: ciphertext, key: derivedKey, iv: iv) else {
            usageLogger.notice("Cursor: AES decryption failed for Chrome cookie")
            return nil
        }

        // Strip PKCS7 padding.
        guard let plaintextStr = String(data: plaintext, encoding: .utf8) else { return nil }
        return plaintextStr
    }

    /// Read the Chrome Safe Storage password from the macOS Keychain.
    private func readChromeSafeStorageKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecAttrAccount as String: "Chrome",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    /// Derive the 16-byte AES key using PBKDF2-HMAC-SHA1 (Chrome's scheme).
    private func deriveChromeAESKey(password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        let salt = Data("saltysalt".utf8)
        let derivedKey = self.pbkdf2(password: passwordData, salt: salt, iterations: 1003, keyLength: 16)
        return derivedKey
    }

    /// PBKDF2-HMAC-SHA1 key derivation.
    private func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKey = Data(count: keyLength)
        derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress, password.count,
                        saltBytes.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress, keyLength
                    )
                }
            }
        }
        return derivedKey
    }

    /// AES-128-CBC decryption.
    private func aesDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var bytesDecrypted = 0
        let status = buffer.withUnsafeMutableBytes { bufferBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, ciphertext.count,
                            bufferBytes.baseAddress, bufferSize,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return buffer.prefix(bytesDecrypted)
    }

    /// Read the encrypted WorkosCursorSessionToken cookie value from Chrome's Cookies SQLite DB.
    private func readEncryptedCookieValue() -> Data? {
        var db: OpaquePointer?
        guard sqlite3_open(chromeCookiesPath, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT encrypted_value FROM cookies WHERE name = 'WorkosCursorSessionToken' AND host_key LIKE '%cursor.com%' LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let blob = sqlite3_column_blob(stmt, 0)
        let length = sqlite3_column_bytes(stmt, 0)
        guard let blob, length > 0 else { return nil }
        return Data(bytes: blob, count: Int(length))
    }
}
