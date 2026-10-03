//
//  RadioDecoder.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 24.09.26.
//


import Foundation
import AVFoundation
import AudioToolbox

final class RadioDecoder {

    let inputFormat: AVAudioFormat
    let outputFormat: AVAudioFormat

    private let converter: AVAudioConverter

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            else { return nil}

        self.converter = converter
    }

    func setMagicCookie(_ cookie: Data) {
        converter.magicCookie = cookie
    }
    
    func decode(data: Data, packetDescriptions: [AudioStreamPacketDescription]) -> AVAudioPCMBuffer? {
        guard !packetDescriptions.isEmpty else { return nil }
        guard !data.isEmpty else { return nil }
        
        let packetCount = packetDescriptions.count
        let largestPacket = packetDescriptions
                .map { Int($0.mDataByteSize) }
                .max() ?? 0

        let minimumPacketSizeForData = (data.count + packetCount - 1) / packetCount
        let maximumPacketSize = max(largestPacket, minimumPacketSizeForData)
        let compressed = AVAudioCompressedBuffer(format: inputFormat,
                packetCapacity: AVAudioPacketCount(packetCount),
                maximumPacketSize: maximumPacketSize)
        
        guard data.count <= compressed.byteCapacity else { return nil }

        compressed.packetCount = AVAudioPacketCount(packetCount)
        compressed.byteLength = UInt32(data.count)
        
        data.withUnsafeBytes { source in
            guard let sourceAddress = source.baseAddress else { return }
            memcpy(compressed.data, sourceAddress, data.count)
        }

        if let destination = compressed.packetDescriptions {
            for index in packetDescriptions.indices {
                destination[index] = packetDescriptions[index]
            }
        }

        let framesPerPacket = Int(inputFormat.streamDescription.pointee.mFramesPerPacket)
        let inputFrames = packetDescriptions.count * max(framesPerPacket, 1152)
        let sampleRateRatio = outputFormat.sampleRate / inputFormat.sampleRate
        let estimatedFrames = max(4096, Int(ceil(Double(inputFrames) * sampleRateRatio)) + 1024)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(estimatedFrames))
                else { return nil}

        var supplied = false
        var error: NSError?

        let result = converter.convert(to: pcm, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return compressed
        }

        switch result {
        case .haveData, .inputRanDry:
            return pcm.frameLength > 0 ? pcm : nil
        case .endOfStream:
            return pcm.frameLength > 0 ? pcm : nil
        case .error:
            debugLog("🔴 Radio decoder:", error?.localizedDescription ?? "unknown error")
            return nil
        @unknown default:
            return nil
        }
    }
}
