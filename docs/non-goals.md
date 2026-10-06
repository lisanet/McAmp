# Non-goals

Things McAmp deliberately does **not** do, and why. These aren't "not yet" — they're "no".

## Spotify playback

Not possible. `libspotify` — the only API that ever allowed third-party apps to decode and play Spotify audio — was deprecated in 2015 and the servers were shut down. What remains:

- **Spotify Web API** only controls the official Spotify desktop client via Spotify Connect. Audio flows through the Spotify app, not through McAmp. Our EQ, spectrum analyzer, and (future) skins never see the bits, so the features that define McAmp wouldn't apply.
- **Reverse-engineered alternatives** like librespot violate Spotify's Terms of Service and get accounts banned. Not a foundation we'll build on.

If you want to play Spotify, use the Spotify app. McAmp is a local player.

## Apple Music streaming

MusicKit on macOS exposes `ApplicationMusicPlayer`, which will play Apple Music catalog tracks for subscribers. We're not integrating it either, for the same reason as Spotify: `ApplicationMusicPlayer` routes audio through a system-managed graph that bypasses our DSP pipeline. You get Apple Music playback, but without EQ and without visualization — which is most of what McAmp is for. The trade-off isn't worth it.

We *do* read your Music.app library to import **local** files — tracks on disk, including ones you downloaded from Apple Music for offline playback. That's done via the `iTunesLibrary` framework (`ITLibrary`), not `ApplicationMusicPlayer`. Streaming-only tracks are skipped with a count, never played.

## iTunes Match / iCloud Music Library sync

McAmp reads your local Music.app library. It does not sync with iCloud, does not download cloud-only tracks, does not re-evaluate smart playlists. If the file isn't on disk, McAmp can't play it.
