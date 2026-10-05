// McAmp/Skinning/SkinProvider.swift
// Provider protocol + BuiltInSkin (no skin loaded). See spec §6.

import AppKit

protocol SkinProvider: AnyObject {
    /// Returns the requested sprite as an NSImage, or nil if the underlying sheet is missing.
    func sprite(_ key: SpriteKey) -> NSImage?

    /// The full text.bmp sheet, for TextSpriteRenderer to slice glyphs from.
    var textSheet: NSImage? { get }

    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var eqGraphLineColors: [NSColor] { get }
    var eqPreampLineColor: NSColor { get }
    var mainWindowRegion: NSBezierPath? { get }
}
