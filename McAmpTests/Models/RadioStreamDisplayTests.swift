import Testing
import Foundation
@testable import McAmp

@MainActor
@Suite("RadioStreamDisplay")
struct RadioStreamDisplayTests {

    @Test func radioDisplayTitle_bothStationAndSong_formatsWithLiveSuffix() {
        let engine = AudioEngine()
        engine.stationTitle = "SWR3"
        engine.streamTitle = "Queen - Radio Ga Ga"
        #expect(engine.radioDisplayTitle == "SWR3 - Queen - Radio Ga Ga")
    }

    @Test func radioDisplayTitle_stationOnly_formatsWithLiveSuffix() {
        let engine = AudioEngine()
        engine.stationTitle = "SWR3"
        engine.streamTitle = ""
        #expect(engine.radioDisplayTitle == "SWR3")
    }

    @Test func radioDisplayTitle_songOnly_formatsWithLiveSuffix() {
        let engine = AudioEngine()
        engine.stationTitle = ""
        engine.streamTitle = "Queen - Radio Ga Ga"
        #expect(engine.radioDisplayTitle == "Queen - Radio Ga Ga")
    }

    @Test func radioDisplayTitle_empty_returnsLive() {
        let engine = AudioEngine()
        engine.stationTitle = ""
        engine.streamTitle = ""
        #expect(engine.radioDisplayTitle == "LIVE")
    }
}
