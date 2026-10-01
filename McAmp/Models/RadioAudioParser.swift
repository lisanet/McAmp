//
//  RadioAudioParserDelegate.swift
//  Wamp
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
        case kAudioFileStreamProperty_DataFormat:
            readDataFormat(from: stream)
        case kAudioFileStreamProperty_MagicCookieData:
            readMagicCookie(from: stream)
        case kAudioFileStreamProperty_ReadyToProducePackets:
            readDataFormat(from: stream)
            readMagicCookie(from: stream)
//        case kAudioFileStreamProperty_FormatList:
//            readFormatList(from: stream)
        default:
            break
        }
    }

    func readDataFormat(from stream: AudioFileStreamID) {
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description)
        guard status == noErr else { return }
        guard let format = AVAudioFormat(streamDescription: &description) else { return }

        delegate?.radioAudioParser(self, didFindFormat: format)
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
    
//    func readFormatList(from stream: AudioFileStreamID) {
//        var size: UInt32 = 0
//        var writable = DarwinBoolean(false)
//
//        let status = AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_FormatList, &size, &writable)
//        guard status == noErr, size > 0 else { return}
//
//        let count = Int(size) / MemoryLayout<AudioFormatListItem>.size
//        var items = Array(repeating: AudioFormatListItem(), count: count)
//        let readStatus = AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_FormatList, &size, &items)
//
//        guard readStatus == noErr else {
//            return
//        }
//    }
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
