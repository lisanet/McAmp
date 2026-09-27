//
//  RadioStream.swift
//  Wamp
//
//  Created by Simone Karin Lehmann on 24.09.26.
//
import Foundation

protocol RadioStreamDelegate: AnyObject {
    func radioStream(_ stream: RadioStream, didReceiveAudio data: Data)
    func radioStream(_ stream: RadioStream, didReceiveStationTitle title: String)
    func radioStream(_ stream: RadioStream, didReceiveStreamTitle title: String)
    func radioStream(_ stream: RadioStream, didFail error: Error)
}

final class RadioStream: NSObject {

    weak var delegate: RadioStreamDelegate?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var metadataInterval: Int?
    private var audioBytesRemaining = 0
    private var metadataBytesRemaining = 0
    private var metadataBuffer = Data()

    func start(url: URL) {
        
        stop()
        metadataInterval = nil
        audioBytesRemaining = 0
        metadataBytesRemaining = 0
        metadataBuffer.removeAll()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 24 * 60 * 60

        session = URLSession(configuration: config, delegate: self,delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("Wamp/1.0", forHTTPHeaderField: "User-Agent")

        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil

        session?.invalidateAndCancel()
        session = nil

        metadataInterval = nil
        audioBytesRemaining = 0
        metadataBytesRemaining = 0
        metadataBuffer.removeAll()
    }

    private func process(_ data: Data) {
        guard let interval = metadataInterval else {
            // Server liefert keine ICY-Metadaten.
            delegate?.radioStream(self,didReceiveAudio: data)
            return
        }

        var offset = 0

        while offset < data.count {
            // Metadata lesen
            if metadataBytesRemaining > 0 {
                let available = data.count - offset
                let count = min(available,metadataBytesRemaining)

                metadataBuffer.append(data.subdata(in: offset ..< offset + count))

                offset += count
                metadataBytesRemaining -= count

                if metadataBytesRemaining == 0 {
                    parseMetadata(metadataBuffer)
                    metadataBuffer.removeAll()
                    audioBytesRemaining = interval
                }
                continue
            }

            // Audio lesen
            if audioBytesRemaining > 0 {
                let available = data.count - offset
                let count = min(available,audioBytesRemaining)
                let audio = data.subdata(in: offset ..< offset + count)

                if !audio.isEmpty {
                    delegate?.radioStream(self,didReceiveAudio: audio)
                }

                offset += count
                audioBytesRemaining -= count
                continue
            }

            // Das Byte nach icy-metaint enthält
            // Metadata-Länge / 16.
            let lengthByte = Int(data[offset])
            offset += 1

            metadataBytesRemaining = lengthByte * 16
            if metadataBytesRemaining == 0 {
                audioBytesRemaining = interval
            }
        }
    }

    private func parseMetadata(_ data: Data) {
        let trimmed = Data(data.prefix { $0 != 0 })

        guard !trimmed.isEmpty else { return }
        guard let raw = String(data: trimmed, encoding: .utf8) ?? String(data: trimmed, encoding: .isoLatin1) else { return }
        guard let title = extractICYValue(key: "StreamTitle", from: raw) else { return }

        let streamTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamTitle.isEmpty else { return }

        delegate?.radioStream(self, didReceiveStreamTitle: streamTitle)
    }
    
    private func extractICYValue(key: String, from raw: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "\(escapedKey)='((?:[^'\\\\]|\\\\.)*)'"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(raw.startIndex..., in: raw)

        guard let match = regex.firstMatch(in: raw, range: range),
                let valueRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }

        return String(raw[valueRange]).replacingOccurrences(of: "\\'", with: "'")
    }
    
    
}

extension RadioStream: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
    {
        if let http = response as? HTTPURLResponse {
            
            if let value = http.value(forHTTPHeaderField: "icy-metaint" ), let interval = Int(value) {
                metadataInterval = interval
                audioBytesRemaining = interval
            }
            
            if let name = http.value(forHTTPHeaderField: "icy-name") {
                let stationTitle = name.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📻 Station:", stationTitle)
                if !stationTitle.isEmpty {
                    delegate?.radioStream(self, didReceiveStationTitle: stationTitle)
                }
                if let bitrate = http.value(forHTTPHeaderField: "icy-br") {
                    print("📻 Bitrate:", bitrate)
                }
                if let type = http.value(forHTTPHeaderField: "Content-Type") { print("📻 Content-Type:", type)}
            }
            completionHandler(.allow)
        }
    }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            process(data)
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            delegate?.radioStream(self, didFail: error)
        }
    
}
