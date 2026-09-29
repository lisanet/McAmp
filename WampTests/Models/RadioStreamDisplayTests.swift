import Testing
import Foundation
@testable import Wamp

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

    @Test func loadStream_withStationTitle_prepopulatesRadioTitle() {
        let engine = AudioEngine()
        let url = URL(string: "http://example.com/radio.mp3")!
        engine.loadStream(url: url, stationTitle: "Rock Antenne", play: false)

        #expect(engine.isRadioStream)
        #expect(engine.stationTitle == "Rock Antenne")
        #expect(engine.radioDisplayTitle == "Rock Antenne")
        engine.stop()
    }

    @Test func loadStream_withGenericInternetRadio_leavesRadioTitleEmpty() {
        let engine = AudioEngine()
        let url = URL(string: "http://example.com/radio.mp3")!
        engine.loadStream(url: url, stationTitle: "LIVE Internet Radio", play: false)

        #expect(engine.isRadioStream)
        #expect(engine.stationTitle.isEmpty)
        #expect(engine.radioDisplayTitle == "LIVE")
        engine.stop()
    }
}
