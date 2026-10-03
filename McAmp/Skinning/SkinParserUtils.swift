// McAmp/Skinning/SkinParserUtils.swift
// ZIP extraction, image loading, nums_ex unification. See spec §4.1, §4.3.

import AppKit
import ZIPFoundation

enum SkinParserUtils {

    // MARK: ZIP

    /// Extracts all entries from a ZIP into [lowercased basename: data]. Last write wins.
    /// Path components and case are stripped — only the filename matters.
    static func extractZip(_ data: Data) throws -> [String: Data] {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw SkinParserError.invalidArchive
        }

        // Real skins unpack to well under a few MB; the caps stop zip bombs
        // from exhausting memory mid-load.
        let perEntryCap = 32 * 1024 * 1024
        let totalCap = 96 * 1024 * 1024
        struct EntryTooLarge: Error {}

        var entries: [String: Data] = [:]
        var totalBytes = 0
        for entry in archive where entry.type == .file {
            guard entry.uncompressedSize <= UInt64(perEntryCap) else { continue }
            var bytes = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    bytes.append(chunk)
                    if bytes.count > perEntryCap { throw EntryTooLarge() }
                }
            } catch {
                // A single damaged or oversized entry (bad CRC, exotic method)
                // must not abort the whole skin — decades-old archives are
                // frequently slightly broken. Required-file validation later
                // catches the case where the entry actually mattered.
                continue
            }
            totalBytes += bytes.count
            guard totalBytes <= totalCap else { break }
            let basename = entry.path
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .last
                .map { $0.lowercased() } ?? ""
            if !basename.isEmpty {
                entries[basename] = bytes
            }
        }
        return entries
    }

    // MARK: Image loading

    /// Decodes BMP/PNG data via NSImage and returns the underlying CGImage.
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Loads a named image (tries .bmp then .png) from extracted entries.
    static func loadImage(named name: String, from entries: [String: Data]) -> CGImage? {
        let base = (name as NSString).deletingPathExtension.lowercased()
        for ext in ["bmp", "png"] {
            if let data = entries["\(base).\(ext)"], let img = decodeImage(data) {
                return img
            }
        }
        return nil
    }

    /// Loads all sprite sheets from spec §4.1 into [basename: CGImage].
    /// Special case: numbers.bmp and nums_ex.bmp both populate "numbers" (last write wins).
    /// Mirrors Webamp's CSS-cascade behavior where DIGIT_N and DIGIT_N_EX both target .digit-N.
    static func loadAllSheets(from entries: [String: Data]) -> [String: CGImage] {
        let sheetBaseNames = [
            "main", "titlebar", "cbuttons", "numbers",
            "playpaus", "monoster", "posbar", "volume", "balance",
            "shufrep", "eqmain", "pledit", "text",
        ]
        var images: [String: CGImage] = [:]
        for name in sheetBaseNames {
            if let img = loadImage(named: name, from: entries) {
                images[name] = img
            }
        }
        // nums_ex.bmp overwrites "numbers" if present (matches Webamp cascade order)
        if let nums_ex = loadImage(named: "nums_ex", from: entries) {
            images["numbers"] = nums_ex
        }
        // skin with german umlaut ü intead of å at pos(2,0) in textu.bmp
        if let textu = loadImage(named: "textu", from: entries) {
            images["text"] = textu
            TextSpriteRenderer.useGermanUmlaut(true)
        } else {
            TextSpriteRenderer.useGermanUmlaut(false)
        }
            
        return images
    }
}
