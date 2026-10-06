<div align="center">

# McAmp

### Classic Winamp 2.x, reborn as a native macOS app

No Electron. No web views. Just Swift, AppKit, and nostalgia.


[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.3+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![UI](https://img.shields.io/badge/AppKit-100%25_programmatic-1d7dfa)](McAmp/UI)
[![Dependencies](https://img.shields.io/badge/dependencies-1_(zip_reader)-2ea44f)](#tech-stack)

</div>



## ✨ Highlights

- **Real Winamp skins** — load any classic `.wsz` skin and the entire app reskins: sprites, bitmap fonts, playlist colors, visualizer palette
- **Web radio support** — play your favorite stations from `.m3u`, `.m3u8`, and `.pls` playlists
- **Gapless CUE playback** — one FLAC + `.cue` becomes individual tracks with sample-accurate, gapless transitions
- **Jump to File** — incremental search over 10k-track playlists in under 16 ms
 

## 🎨 Skins

McAmp parses the original Winamp 2.x skin format — a `.wsz` archive of bitmap sprites and INI files.

By default, locally installed skins are searched in `~/Documents/McAmp Skins`.

Two classic skins are included in the DMG: *base-2.91* and *ExpensiveHi-Fi*. Simply copy them from [`skins/`](skins) to your skin directory.

<div align="center">

<img width="720" alt="McAmp with different classic Winamp skins" src="docs/media/skins-grid.png" />

</div>

On first startup, McAmp loads the base skin from its app bundle.

## 📜 Playlist

- Drag & drop files, folders, `.m3u`/`.m3u8`, `.pls` and `.cue` straight from Finder
- Multi-select like a real Mac app — Shift-click ranges, Cmd-click toggles, `⌘A`, Backspace removes
- Instant search box + **Jump to File** (`⌘J`) with prefix → word-boundary → substring ranking
- **Import from Music Library…** — pulls local tracks and playlists from Music.app
  (via `ITLibrary`, with an `iTunes Music Library.xml` fallback); streaming-only and
  missing files are skipped and counted

## 📻 Web Radio Streams

Play your favorite web radio stations from `.m3u`, `.m3u8`, or `.pls` playlists.

## 💿 CUE sheets, done properly

Drop a `.cue` next to a FLAC (or open a FLAC with an embedded `CUESHEET`
Vorbis comment) and the album splits into individual virtual tracks:

- Gapless transitions between consecutive tracks via chained `scheduleSegment` calls
- External `.cue` wins over embedded CUESHEET

## ⌨️ Keyboard shortcuts

| Playback | | View | |
|---|---|---|---|
| `Space` | Play / Pause | `⌘1` | Show Player |
| `⌘.` | Stop | `⌘2` | Toggle Equalizer |
| `⌘→` / `⌘←` | Next / Previous | `⌘3` | Toggle Playlist |
| `⌘R` | Repeat | `⌘⇧D` | Double Size |
| `⌘S` | Shuffle | `⌘⇧T` | Always on Top |
| `Return` | Play selected track | `⌘⇧S` | Load Skin… |
| `↑` `↓` | Navigate playlist | `⌘O` | Open File, Folder, Lists |
| `⌘J` | Jump to File… | `⌘A` | Select All |


## 🎛️ Hardware Media Keys

Play/Pause, Next, Previous

## 📦 Supported formats

| Audio | Playlists |
|---|---|
| MP3 · AAC · M4A · FLAC · WAV · AIFF | M3U · M3U8 · PLS · CUE (external & FLAC-embedded) |

## 🚀 Getting started

### 📥 Download

Grab the latest `McAmp-<version>-macOS-arm64.dmg` from
[**Releases**](https://github.com/lisanet/macamp/releases), open it and drag
McAmp to Applications. Requires macOS 26.3+ on Apple Silicon.

The app is ad-hoc signed, not notarized, so the first launch is blocked with
*"Apple could not verify McAmp is free of malware"*. Click **Done**, then go to
**System Settings → Privacy & Security** and click **Open Anyway** — once.
Terminal alternative:

```bash
xattr -c /Applications/McAmp.app
```

### 🛠️ Build from Source

**Requirements:** macOS 26.3+, Xcode 26+

```bash
git clone https://github.com/lisanet/macamp.git
cd mcamp

# Build
xcodebuild -project McAmp.xcodeproj -scheme McAmp -configuration Debug build

# Or just open in Xcode and hit ⌘R
open McAmp.xcodeproj
```

## 🙅 Non-goals

McAmp is a player for local files and web radio streams.

It will not stream tracks from the Spotify or Apple Music catalogs — both route
audio through a system-managed graph that bypasses McAmp’s DSP,
so the EQ and spectrum analyzer would be lying to you. Details in
[docs/non-goals.md](docs/non-goals.md).

## 🙏 Credits

This project started as a fork of [Wamp](https://github.com/wishval/wamp), but has since
evolved significantly. McAmp adds web radio streams, improves the rendering of skin elements,
reduces scaling artifacts, fixes various glitches, adds new features, and drops the unskinned mode.
The project was renamed to **McAmp** to better reflect the many changes and improvements it has undergone.

Without the original project, McAmp would never have seen the light of day, so credit goes to its creators.

## 📬 License

MIT – feel free to use, modify, and distribute.

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome. Please open an issue or submit a pull request if you have any improvements or suggestions.

## ⚠️ Disclaimer

McAmp is provided “as is” without any warranty.
Use at your own risk and ensure you have backups of your original media.
