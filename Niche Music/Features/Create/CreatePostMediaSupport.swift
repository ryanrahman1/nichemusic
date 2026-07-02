//
//  CreatePostMediaSupport.swift
//  Niche Music
//

import AVFoundation
import UIKit

enum CreatePostMediaSupport {
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.86) -> Data? {
        let resized = resize(image: image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    static func writeJPEG(_ image: UIImage, to url: URL) throws {
        guard let data = jpegData(from: image) else {
            throw CreatePostStoreError.invalidState
        }
        try data.write(to: url, options: .atomic)
    }

    static func dimensions(for image: UIImage) -> (width: Int, height: Int) {
        (Int(image.size.width.rounded()), Int(image.size.height.rounded()))
    }

    static func videoMetadata(for url: URL) async -> (width: Int, height: Int, durationMs: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        guard
            let naturalSize = try? await track.load(.naturalSize),
            let duration = try? await asset.load(.duration)
        else {
            return nil
        }

        let width = Int(abs(naturalSize.width).rounded())
        let height = Int(abs(naturalSize.height).rounded())
        let durationMs = Int(duration.seconds * 1000)
        return (max(width, 1), max(height, 1), max(durationMs, 1))
    }

    static func copyVideo(from source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static func temporaryMediaURL(kind: CreatePostLocalMedia.Kind) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("create-post-\(UUID().uuidString).\(kind == .video ? "mp4" : "jpg")")
    }

    private static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }

        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
