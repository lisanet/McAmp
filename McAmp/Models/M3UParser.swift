import Foundation

struct M3UEntry: Equatable {
    let url: URL
    let duration: TimeInterval?
    let title: String?
}

enum M3UParseError: Error {
    case encoding
}

enum M3UParser {
    static func parse(url: URL) throws -> [M3UEntry] {
        let data = try Data(contentsOf: url)
        let base = url.deletingLastPathComponent()
        let ext = url.pathExtension.lowercased()
        return try parse(data: data, baseURL: base, fileExtension: ext)
    }

    static func parse(
        data: Data,
        baseURL: URL,
        fileExtension: String = "m3u8"
    ) throws -> [M3UEntry] {
        let text = try decode(data)
        return parseText(text, baseURL: baseURL, fileExtension: fileExtension)
    }

    // MARK: - Decoding

    private static func decode(_ data: Data) throws -> String {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) {
            body = body.dropFirst(3)
        }
        // Strict UTF-8 first regardless of extension: it rejects ill-formed
        // sequences, so legacy 8-bit files fall through, while modern tools'
        // UTF-8 .m3u files decode correctly. CP-1252 next (superset of
        // Latin-1's printable range, maps 0x80–0x9F to real glyphs), then
        // Latin-1 as the never-failing last resort.
        if let s = String(data: body, encoding: .utf8) {
            return s
        }
        if let s = String(data: body, encoding: .windowsCP1252) {
            return s
        }
        if let s = String(data: body, encoding: .isoLatin1) {
            return s
        }
        throw M3UParseError.encoding
    }

    // MARK: - Text parsing

    private static func parseText(_ text: String, baseURL: URL, fileExtension: String) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        switch fileExtension {
        case "m3u", "m3u8":
            entries = parseTextM3U(text, baseURL: baseURL)
        case "pls":
            entries = parseTextPLS(text, baseURL: baseURL)
        default:
            break
        }
        return entries
    }
    
    private static func parseTextM3U(_ text: String, baseURL: URL) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        var pendingDuration: TimeInterval?
        var pendingTitle: String?

        for rawLine in splitLines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#EXTINF:") {
                    (pendingDuration, pendingTitle) = parseExtInf(line)
                }
                // All other directives (including #EXTM3U, unknown ones, bare comments) ignored.
                continue
            }

            // Non-# line → path.
            if let resolved = resolveURL(line, baseURL: baseURL) {
                entries.append(M3UEntry(
                    url: resolved,
                    duration: pendingDuration,
                    title: pendingTitle
                ))
            }
            pendingDuration = nil
            pendingTitle = nil
        }
        return entries
    }

    private static func parseTextPLS(_ text: String, baseURL: URL) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        var duration: [Int: String] = [:]
        var pendingDuration: TimeInterval = 0
        var pendingTitle: String?

        for rawLine in splitLines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("[") { continue }
            
            guard let eq = line.firstIndex(of: "=") else  { continue }
            
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    
            if key.hasPrefix("file"), let index = Int(key.dropFirst(4)) {
                files[index] = value
            } else if key.hasPrefix("title"), let index = Int(key.dropFirst(5)) {
                titles[index] = value
            } else if key.hasPrefix("length"), let index = Int(key.dropFirst(6)) {
                duration[index] = value
            }
        }
            
        _ = files.keys.sorted().compactMap { index in
            if let file = files[index], !file.isEmpty {
                pendingDuration = max(0, TimeInterval(duration[index] ?? "0") ?? 0)
                pendingTitle = titles[index]
                if let resolved = resolveURL(file, baseURL: baseURL) {
                    entries.append(M3UEntry(
                        url: resolved,
                        duration: pendingDuration,
                        title: pendingTitle
                    ))
                }
                pendingDuration = 0
                pendingTitle = nil
            }
        }
        return entries
    }

    
    private static func parseExtInf(_ line: String) -> (TimeInterval?, String?) {
        // Format: #EXTINF:<duration>[,<title>]
        let afterPrefix = line.dropFirst("#EXTINF:".count)
        let parts = afterPrefix.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let durationStr = parts[0].trimmingCharacters(in: .whitespaces)
        
        var duration: TimeInterval
        duration = max(0, TimeInterval(durationStr) ?? 0)
        
        let t = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        let title = t.isEmpty ? nil : t
        
        return (duration, title)
    }


    private static func resolveURL(_ path: String, baseURL: URL) -> URL? {
        if path.hasPrefix("file://") {
            if let u = URL(string: path), u.isFileURL {
                return u
            }

            let raw = String(path.dropFirst("file://".count))
            let decoded = raw.removingPercentEncoding ?? raw
            return URL(fileURLWithPath: decoded)
        }
        // Webradio / andere absolute URLs
        if let url = URL(string: path),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    /// Split on any of CRLF, LF, CR — handling mixed line endings in a single pass.
    /// Iterates over Unicode scalars because Swift treats "\r\n" as a single
    /// grapheme cluster at the Character level, which would skip CRLF splits.
    private static func splitLines(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "\r" {
                out.append(current)
                current = ""
                i += 1
                if i < scalars.count, scalars[i] == "\n" { i += 1 }
                continue
            }
            if c == "\n" {
                out.append(current)
                current = ""
                i += 1
                continue
            }
            current.unicodeScalars.append(c)
            i += 1
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
