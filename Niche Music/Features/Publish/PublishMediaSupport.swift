//
//  PublishMediaSupport.swift
//  Niche Music
//

import AVFoundation
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PickedVideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-moment-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

enum PublishMediaSupport {
    static let supportedAudioFormats: Set<String> = ["mp3", "m4a", "wav", "flac", "aac"]
    static let supportedVideoFormats: Set<String> = ["mp4", "webm", "mov", "mkv"]

    static func musicFormat(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return supportedAudioFormats.contains(ext) ? ext : nil
    }

    static func videoFormat(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return supportedVideoFormats.contains(ext) ? ext : nil
    }

    static func audioDurationMs(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Int(seconds * 1000)
    }

    static func jpegData(from imageData: Data, maxDimension: CGFloat = 1400) -> Data? {
        guard let image = UIImage(data: imageData)?.normalizedUpOrientation() else { return nil }
        _ = maxDimension
        return ArtworkImageProcessing.uploadJPEG(from: image)
    }

    static func copiedFileURL(from source: URL, prefix: String, ext: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static var audioContentTypes: [UTType] {
        [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
    }

    static var videoContentTypes: [UTType] {
        [.mpeg4Movie, .quickTimeMovie, .movie, .video]
    }

    static func formattedDuration(ms: Int?) -> String {
        guard let ms, ms > 0 else { return "—" }
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func videoThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
