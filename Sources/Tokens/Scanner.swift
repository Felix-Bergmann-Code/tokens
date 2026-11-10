import Foundation

/// Reads Claude Code and Codex session logs and turns them into hourly usage buckets.
///
/// Results are cached per file. Session logs are append-only, so when a file grows only the
/// new lines are parsed; a refresh while an agent is working costs a few milliseconds.
final class UsageScanner {
    private static let cacheVersion = 6

    private struct ClaudeEntry: Codable {
        var key: String
        var bucket: Bucket
    }

    private enum Kind: String, Codable { case claude, codex }

    /// Where a Codex session left off, so parsing can resume mid-file.
    private struct CodexState: Codable {
        var source: Source = .codexCLI
        var model = "gpt-5"
        var lastTotal = -1
    }

    private struct FileRecord: Codable {
        var size: Int64
        var mtime: Double
        var kind: Kind
        var offset: Int64 = 0   // bytes consumed, always at a line boundary
        var buckets: [Bucket] = []
        var claude: [ClaudeEntry] = []
        var codex: CodexState?
        var limits: CodexLimits?
        var weeklyPeaks: [String: Double] = [:]
    }

    private struct CacheFile: Codable {
        var version: Int
        var records: [String: FileRecord]
    }

    private var records: [String: FileRecord] = [:]
    private var lastSave = Date.distantPast
    private var dirty = false
    private let saveLock = NSLock()
    private let cacheURL: URL
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokens", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("usage-cache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
           cache.version == Self.cacheVersion {
            records = cache.records
        }
    }

    func resetCache() {
        records = [:]
        try? fm.removeItem(at: cacheURL)
    }

    // MARK: - Scan

    func scan(progress: @escaping (Double) -> Void) -> Snapshot {
        var files: [(URL, Kind, Int64, Double)] = []
        for root in claudeRoots() { files += enumerate(root, kind: .claude) }
        for root in codexRoots() { files += enumerate(root, kind: .codex) }

        let livePaths = Set(files.map { $0.0.path })
        records = records.filter { livePaths.contains($0.key) }

        let changed = files.filter { url, _, size, mtime in
            guard let r = records[url.path] else { return true }
            return r.size != size || r.mtime != mtime
        }

        if !changed.isEmpty {
            let lock = NSLock()
            var done = 0
            let total = Double(changed.count)
            let previous = records
            DispatchQueue.concurrentPerform(iterations: changed.count) { i in
                let (url, kind, size, mtime) = changed[i]
                // Resume appended files; start over if a file shrank or was replaced.
                var rec: FileRecord
                if let old = previous[url.path], old.kind == kind, size >= old.size {
                    rec = old
                } else {
                    rec = FileRecord(size: size, mtime: mtime, kind: kind)
                }
                rec.size = size
                rec.mtime = mtime
                switch kind {
                case .claude: Self.parseClaude(url, into: &rec)
                case .codex: Self.parseCodex(url, into: &rec)
                }
                lock.lock()
                records[url.path] = rec
                done += 1
                let d = done
                lock.unlock()
                if d % 8 == 0 { progress(Double(d) / total) }
            }
            saveLock.withLock { dirty = true }
            // Writing the cache is the slowest part of a live refresh, so throttle it.
            if Date().timeIntervalSince(lastSave) > 60 || changed.count > 20 { saveCache() }
        }
        progress(1)
        return buildSnapshot(fileCount: files.count)
    }

    private func buildSnapshot(fileCount: Int) -> Snapshot {
        var merged: [String: Bucket] = [:]
        func add(_ b: Bucket) {
            if var existing = merged[b.key] {
                existing.usage += b.usage
                merged[b.key] = existing
            } else {
                merged[b.key] = b
            }
        }

        // Claude Code writes one line per content block with the same message id; it also
        // copies history into resumed/forked sessions. Keep the most complete copy of each.
        var claudeByKey: [String: Bucket] = [:]
        var limits: CodexLimits?
        var peaks: [String: Double] = [:]

        for rec in records.values {
            for e in rec.claude {
                if let prev = claudeByKey[e.key], prev.usage.output >= e.bucket.usage.output { continue }
                claudeByKey[e.key] = e.bucket
            }
            rec.buckets.forEach(add)
            if let l = rec.limits, l.timestamp > (limits?.timestamp ?? 0) { limits = l }
            for (day, p) in rec.weeklyPeaks { peaks[day] = max(peaks[day] ?? 0, p) }
        }
        claudeByKey.values.forEach(add)

        var snap = Snapshot()
        snap.buckets = Array(merged.values)
        snap.codexLimits = limits
        snap.codexWeeklyPeaks = peaks
        snap.fileCount = fileCount
        snap.scannedAt = .now
        (snap.claudeRateTier, snap.claudeSubscriptionStart) = readClaudeAccount()
        return snap
    }

    /// Persists the per-file index if it changed since the last write.
    func saveCache() {
        saveLock.lock()
        defer { saveLock.unlock() }
        guard dirty else { return }
        let cache = CacheFile(version: Self.cacheVersion, records: records)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        dirty = false
        lastSave = Date()
    }

    /// Folders that contain session logs, for the file-system watcher.
    func watchedFolders() -> [String] {
        (claudeRoots() + codexRoots()).map(\.path).filter { fm.fileExists(atPath: $0) }
    }

    // MARK: - File discovery

    private func claudeRoots() -> [URL] {
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            roots += env.split(separator: ",").map { URL(fileURLWithPath: String($0)).appendingPathComponent("projects") }
        }
        roots.append(home.appendingPathComponent(".claude/projects"))
        roots.append(home.appendingPathComponent(".config/claude/projects"))
        return dedupe(roots)
    }

    private func codexRoots() -> [URL] {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return [base.appendingPathComponent("sessions"), base.appendingPathComponent("archived_sessions")]
    }

    private func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    private func enumerate(_ root: URL, kind: Kind) -> [(URL, Kind, Int64, Double)] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var out: [(URL, Kind, Int64, Double)] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            out.append((url, kind, Int64(v.fileSize ?? 0), v.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return out
    }

    private func readClaudeAccount() -> (String?, Date?) {
        let url = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = obj["oauthAccount"] as? [String: Any] else { return (nil, nil) }
        let tier = acct["userRateLimitTier"] as? String
        let start = (acct["subscriptionCreatedAt"] as? String).flatMap(LineReader.parseISO)
        return (tier, start)
    }

    // MARK: - Claude Code

    private static let usageNeedle = Array(#""usage""#.utf8)

    private static func parseClaude(_ url: URL, into rec: inout FileRecord) {
        var entries: [String: ClaudeEntry] = [:]
        for e in rec.claude { entries[e.key] = e }
        rec.offset = LineReader.forEachLine(url, from: rec.offset) { line in
            guard LineReader.contains(line, usageNeedle) else { return }
            guard let obj = LineReader.json(line),
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let u = msg["usage"] as? [String: Any],
                  let ts = (obj["timestamp"] as? String).flatMap(LineReader.parseISO) else { return }
            let model = (msg["model"] as? String) ?? "claude"
            if model.hasPrefix("<") { return }   // <synthetic> placeholder messages

            let input = int(u["input_tokens"])
            let read = int(u["cache_read_input_tokens"])
            let out = int(u["output_tokens"])
            var w5 = int(u["cache_creation_input_tokens"]), w1h = 0
            if let cc = u["cache_creation"] as? [String: Any] {
                w5 = int(cc["ephemeral_5m_input_tokens"])
                w1h = int(cc["ephemeral_1h_input_tokens"])
            }
            let thinking = int((u["output_tokens_details"] as? [String: Any])?["thinking_tokens"])
            let fast = (u["speed"] as? String) == "fast"

            let p = Pricing.price(for: model, provider: .claude)
            var cost = (Double(input) * p.input + Double(w5) * p.cacheWrite5m + Double(w1h) * p.cacheWrite1h
                + Double(read) * p.cachedInput + Double(out) * p.output) / 1e6
            if fast { cost *= 2 }

            let usage = Usage(input: input, cacheWrite: w5 + w1h, cacheRead: read, output: out,
                              reasoning: thinking, requests: 1, cost: cost,
                              cacheSavings: Double(read) * (p.input - p.cachedInput) / 1e6)
            let (day, hour) = LineReader.localDayHour(ts)
            let bucket = Bucket(day: day, hour: hour, source: claudeSource(obj["entrypoint"] as? String),
                                model: model, usage: usage)
            let key = "\(msg["id"] as? String ?? UUID().uuidString)|\(obj["requestId"] as? String ?? "")"
            if let prev = entries[key], prev.bucket.usage.output >= out { return }
            entries[key] = ClaudeEntry(key: key, bucket: bucket)
        }
        rec.claude = Array(entries.values)
    }

    private static func claudeSource(_ entrypoint: String?) -> Source {
        let e = entrypoint?.lowercased() ?? ""
        if e.contains("desktop") { return .claudeDesktop }
        if e.hasPrefix("sdk") { return .claudeSDK }
        return .claudeCLI
    }

    // MARK: - Codex

    private static let tokenCountNeedle = Array(#""token_count""#.utf8)
    private static let turnContextNeedle = Array(#""turn_context""#.utf8)
    private static let sessionMetaNeedle = Array(#""session_meta""#.utf8)

    private static func parseCodex(_ url: URL, into rec: inout FileRecord) {
        let state = rec.codex ?? CodexState()
        var source = state.source
        var model = state.model
        var lastTotal = state.lastTotal
        var merged: [String: Bucket] = [:]
        for b in rec.buckets { merged[b.key] = b }
        var limits = rec.limits
        var peaks = rec.weeklyPeaks

        rec.offset = LineReader.forEachLine(url, from: rec.offset) { line in
            let isTokens = LineReader.contains(line, tokenCountNeedle)
            let isTurn = !isTokens && LineReader.contains(line, turnContextNeedle)
            let isMeta = !isTokens && !isTurn && LineReader.contains(line, sessionMetaNeedle)
            guard isTokens || isTurn || isMeta, let obj = LineReader.json(line),
                  let payload = obj["payload"] as? [String: Any] else { return }

            switch obj["type"] as? String {
            case "session_meta":
                // The desktop app reports source "vscode" too, so the originator decides first.
                source = codexSource(originator: payload["originator"] as? String, source: payload["source"] as? String)
                if let m = payload["model"] as? String { model = m }
            case "turn_context":
                if let m = payload["model"] as? String { model = m }
            case "event_msg" where payload["type"] as? String == "token_count":
                guard let ts = (obj["timestamp"] as? String).flatMap(LineReader.parseISO) else { return }
                let (day, hour) = LineReader.localDayHour(ts)

                if let rl = payload["rate_limits"] as? [String: Any] {
                    let snap = CodexLimits(timestamp: ts.timeIntervalSince1970,
                                           plan: rl["plan_type"] as? String,
                                           primary: window(rl["primary"]),
                                           secondary: window(rl["secondary"]))
                    if snap.timestamp > (limits?.timestamp ?? 0) { limits = snap }
                    if let w = snap.secondary { peaks[day] = max(peaks[day] ?? 0, w.usedPercent) }
                }

                guard let info = payload["info"] as? [String: Any] else { return }
                let totalUsage = info["total_token_usage"] as? [String: Any]
                let total = int(totalUsage?["total_tokens"])
                if totalUsage != nil {
                    // Codex re-emits the same counter after some events; skip unchanged totals.
                    if total == lastTotal { return }
                }
                var last = info["last_token_usage"] as? [String: Any]
                if last == nil, let t = totalUsage, lastTotal >= 0 {
                    last = ["total_tokens": total - lastTotal, "input_tokens": int(t["input_tokens"]),
                            "output_tokens": int(t["output_tokens"])]   // best effort
                }
                if totalUsage != nil { lastTotal = total }
                guard let u = last else { return }

                let inputAll = int(u["input_tokens"])
                let cached = min(int(u["cached_input_tokens"]), inputAll)
                let out = int(u["output_tokens"])
                let reasoning = int(u["reasoning_output_tokens"])
                if inputAll == 0 && out == 0 { return }

                let p = Pricing.price(for: model, provider: .codex)
                let uncached = inputAll - cached
                let cost = (Double(uncached) * p.input + Double(cached) * p.cachedInput + Double(out) * p.output) / 1e6
                let usage = Usage(input: uncached, cacheWrite: 0, cacheRead: cached, output: out,
                                  reasoning: reasoning, requests: 1, cost: cost,
                                  cacheSavings: Double(cached) * (p.input - p.cachedInput) / 1e6)
                let b = Bucket(day: day, hour: hour, source: source, model: model, usage: usage)
                merged[b.key, default: Bucket(day: day, hour: hour, source: source, model: model, usage: Usage())].usage += usage
            default:
                break
            }
        }
        rec.buckets = Array(merged.values)
        rec.limits = limits
        rec.weeklyPeaks = peaks
        rec.codex = CodexState(source: source, model: model, lastTotal: lastTotal)
    }

    private static func codexSource(originator: String?, source: String?) -> Source {
        let o = originator?.lowercased() ?? ""
        if o.contains("desktop") { return .codexDesktop }
        if o.contains("cli") || o.contains("exec") { return .codexCLI }
        if o.contains("vscode") || o.contains("cursor") || o.contains("jetbrains") || o.contains("ide") { return .codexIDE }
        switch source?.lowercased() {
        case "vscode": return .codexIDE
        case "app", "desktop": return .codexDesktop
        default: return .codexCLI
        }
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let d = any as? [String: Any], let used = d["used_percent"] as? Double else { return nil }
        return LimitWindow(usedPercent: used, windowMinutes: int(d["window_minutes"]),
                           resetsAt: (d["resets_at"] as? Double) ?? Double(int(d["resets_at"])))
    }

    private static func int(_ any: Any?) -> Int {
        switch any {
        case let i as Int: i
        case let d as Double: Int(d)
        case let n as NSNumber: n.intValue
        default: 0
        }
    }
}

// MARK: - Low-level line reading

enum LineReader {
    /// Memory-maps the file and calls `body` with each complete line from `offset` on (no copies).
    /// Returns the offset just past the last complete line; a partially written last line is
    /// left for the next call.
    @discardableResult
    static func forEachLine(_ url: URL, from offset: Int64 = 0, _ body: (UnsafeRawBufferPointer) -> Void) -> Int64 {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return offset }
        return data.withUnsafeBytes { raw -> Int64 in
            guard let base = raw.baseAddress else { return offset }
            let n = raw.count
            var start = Int(min(offset, Int64(n)))
            while start < n, let p = memchr(base + start, 0x0A, n - start) {
                let end = base.distance(to: UnsafeRawPointer(p))
                if end > start { body(UnsafeRawBufferPointer(start: base + start, count: end - start)) }
                start = end + 1
            }
            return Int64(start)
        }
    }

    static func contains(_ line: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { n in memmem(line.baseAddress, line.count, n.baseAddress, n.count) != nil }
    }

    static func json(_ line: UnsafeRawBufferPointer) -> [String: Any]? {
        let data = Data(bytes: line.baseAddress!, count: line.count)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Parses `2026-09-29T14:44:04.722Z` (or with a ±hh:mm offset) without a DateFormatter.
    static func parseISO(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 19 else { return nil }
        func num(_ a: Int, _ b: Int) -> Int32 {
            var v: Int32 = 0
            for i in a..<b { v = v * 10 + Int32(u[i] &- 48) }
            return v
        }
        var t = tm()
        t.tm_year = num(0, 4) - 1900
        t.tm_mon = num(5, 7) - 1
        t.tm_mday = num(8, 10)
        t.tm_hour = num(11, 13)
        t.tm_min = num(14, 16)
        t.tm_sec = num(17, 19)
        var secs = Double(timegm(&t))
        var i = 19
        if i < u.count, u[i] == UInt8(ascii: ".") {
            var frac = 0.0, scale = 0.1
            i += 1
            while i < u.count, u[i] >= 48, u[i] <= 57 {
                frac += Double(u[i] - 48) * scale
                scale /= 10
                i += 1
            }
            secs += frac
        }
        if i + 6 <= u.count, u[i] == UInt8(ascii: "+") || u[i] == UInt8(ascii: "-") {
            let sign: Double = u[i] == UInt8(ascii: "+") ? 1 : -1
            let off = Double(num(i + 1, i + 3)) * 3600 + Double(num(i + 4, i + 6)) * 60
            secs -= sign * off
        }
        return Date(timeIntervalSince1970: secs)
    }

    static func localDayHour(_ date: Date) -> (String, Int) {
        var t = time_t(date.timeIntervalSince1970)
        var lt = tm()
        localtime_r(&t, &lt)
        let y = Int(lt.tm_year) + 1900, m = Int(lt.tm_mon) + 1, d = Int(lt.tm_mday)
        let day = "\(y)-\(m < 10 ? "0" : "")\(m)-\(d < 10 ? "0" : "")\(d)"
        return (day, Int(lt.tm_hour))
    }
}
