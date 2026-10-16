//
//  TransportActions.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 16.10.26.
//
import Foundation

@MainActor
final class TransportActions {
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?
    private weak var playlistView: PlaylistView?

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager, playlistView: PlaylistView) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager
        self.playlistView = playlistView
    }

    private var selectedIndex: Int {
        playlistView?.selectedTrackIndex() ?? 0
    }

    func previous() { playlistManager?.playPrevious() }

    func play() {
        guard let engine = audioEngine else { return }
        if engine.playState == .stopped, let pm = playlistManager {
            pm.playTrack(at: selectedIndex)
        } else {
            engine.play()
        }
    }

    func pause() { audioEngine?.pause() }
    func stop()  { audioEngine?.stop() }

    func next() {
        guard let pm = playlistManager else { return }
        let index = selectedIndex
        if index != pm.currentIndex {
            pm.currentIndex = index - 1
        }
        pm.playNext()
    }

    func eject() { playlistManager?.openFileFolderList() }
}
