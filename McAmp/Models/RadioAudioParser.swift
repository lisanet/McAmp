//
//  RadioAudioParserDelegate.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 24.09.26.
//


import Foundation
import AVFoundation
import AudioToolbox

protocol RadioAudioParserDelegate: AnyObject {
    func radioAudioParser(_ parser: RadioAudioParser,didFindFormat format: AVAudioFormat)
    func radioAudioParser(_ parser: RadioAudioParser,didFindMagicCookie cookie: Data)
    func radioAudioParser(_ parser: RadioAudioParser,didReceive data: Data,packetDescriptions:[AudioStreamPacketDescription])
    func radioAudioParser(_ parser: RadioAudioParser,didFail status: OSStatus)
}


final class RadioAudioParser {
    weak var delegate: RadioAudioParserDelegate?
    private var streamID: AudioFileStreamID?

    init() throws {
        var stream: AudioFileStreamID?

        let status =
            AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(),
            { clientData,
              streamID,
              propertyID,
              flags in
                let parser = Unmanaged<RadioAudioParser>.fromOpaque(clientData).takeUnretainedValue()
                parser.handleProperty(stream: streamID,propertyID: propertyID)
            },
            { clientData,
              numberBytes,
              numberPackets,
              inputData,
              packetDescriptions in
                let parser = Unmanaged<RadioAudioParser>.fromOpaque(clientData).takeUnretainedValue()
                parser.handlePackets(numberBytes: numberBytes, numberPackets: numberPackets, inputData: inputData, packetDescriptions:packetDescriptions)
            },
            0,
            &stream
        )

        guard status == noErr,
              let stream else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        streamID = stream
    }

    deinit {
        if let streamID { AudioFileStreamClose(streamID) }
    }

    func parse(_ data: Data) {
        guard let streamID else { return }
        
        let status = data.withUnsafeBytes {
            bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return noErr}
            
            return AudioFileStreamParseBytes(streamID, UInt32(data.count), base, [])
        }

        if status != noErr {
            delegate?.radioAudioParser(self, didFail: status)
        }
    }
}

private extension RadioAudioParser {
    
    func handleProperty(stream: AudioFileStreamID, propertyID: AudioFileStreamPropertyID) {
        switch propertyID {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            readDataFormat(from: stream)
            readMagicCookie(from: stream)
        default:
            break
        }
    }

    func readDataFormat(from stream: AudioFileStreamID) {
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description)
        guard status == noErr else { return }

        if let better = bestPlayableFormat(from: stream) {
            // format from format list (HE-AAC: kAudioFormatMPEG4AAC_HE, 44100/48000 Hz)
            description = better
        } else if description.mFormatID == kAudioFormatMPEG4AAC, description.mSampleRate <= 24000 {
            // Fallback-Heuristik: implizites SBR vermuten
            description.mFormatID = kAudioFormatMPEG4AAC_HE
            description.mSampleRate *= 2
            description.mFramesPerPacket = 2048
        }
        
        guard let format = AVAudioFormat(streamDescription: &description) else { return }
        delegate?.radioAudioParser(self, didFindFormat: format)
    }

    func bestPlayableFormat(from stream: AudioFileStreamID) -> AudioStreamBasicDescription? {
        var size: UInt32 = 0
        var writable = DarwinBoolean(false)

        guard AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_FormatList, &size, &writable) == noErr,
              size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<AudioFormatListItem>.size
        var items = [AudioFormatListItem](repeating: AudioFormatListItem(), count: count)

        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_FormatList, &size, &items) == noErr else { return nil }

        var index: UInt32 = 0
        var indexSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioFormatGetProperty(kAudioFormatProperty_FirstPlayableFormatFromList,
                                            UInt32(count * MemoryLayout<AudioFormatListItem>.size),
                                            items,
                                            &indexSize,
                                            &index)

        guard status == noErr, Int(index) < count else { return nil }
        return items[Int(index)].mASBD
    }
    
    func readMagicCookie(from stream: AudioFileStreamID) {
        var size: UInt32 = 0
        var writable = DarwinBoolean(false)

        let sizeStatus = AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &size,&writable)
        guard sizeStatus == noErr, size > 0 else { return }

        var cookie = Data(count: Int(size))

        let status = cookie.withUnsafeMutableBytes { bytes in
            AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &size, bytes.baseAddress!)
        }

        guard status == noErr else { return}

        delegate?.radioAudioParser(self, didFindMagicCookie: cookie)
    }
}


private extension RadioAudioParser {

    func handlePackets(numberBytes: UInt32, numberPackets: UInt32, inputData: UnsafeRawPointer, packetDescriptions:
            UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard numberPackets > 0 else { return}

        let data = Data(bytes: inputData, count: Int(numberBytes))
        var descriptions: [AudioStreamPacketDescription] = []

        if let packetDescriptions {
            descriptions = Array(UnsafeBufferPointer(start: packetDescriptions, count: Int(numberPackets)))
        } else {
            // CBR
            let packetSize = numberBytes / numberPackets
            for packet in 0..<numberPackets {
                descriptions.append(AudioStreamPacketDescription(mStartOffset: Int64(packet * packetSize),
                                                                 mVariableFramesInPacket: 0,
                                                                 mDataByteSize:packetSize)
                )
            }
        }

        delegate?.radioAudioParser(self, didReceive: data,packetDescriptions: descriptions)
    }
}
