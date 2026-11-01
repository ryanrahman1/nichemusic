//
//  ArtworkImageProcessing.swift
//  Niche Music
//

import PhotosUI
import SwiftUI
import UIKit

enum ArtworkImageProcessing {
    static let uploadMaxDimension: CGFloat = 1200
    static let uploadJPEGQuality: CGFloat = 0.82
    static let uploadMaxBytes = 2_000_000
    static let squareAspectTolerance: CGFloat = 0.015

    static func needsManualCrop(for image: UIImage) -> Bool {
        let size = image.normalizedUpOrientation().size
        guard size.width > 0, size.height > 0 else { return true }
        let aspect = size.width / size.height
        return abs(aspect - 1) > squareAspectTolerance
    }

    static func uploadJPEG(from image: UIImage) -> Data? {
        let normalized = image.normalizedUpOrientation()
        let squared = centerSquareCrop(normalized)
        return compressJPEG(squared)
    }

    static func exportSquareJPEG(
        from image: UIImage,
        cropSideInView: CGFloat,
        userScale: CGFloat,
        offset: CGSize,
        viewSize: CGSize
    ) -> Data? {
        let normalized = image.normalizedUpOrientation()
        guard
            cropSideInView > 0,
            viewSize.width > 0,
            viewSize.height > 0,
            let cropped = cropImage(
                normalized,
                cropSideInView: cropSideInView,
                userScale: userScale,
                offset: offset,
                viewSize: viewSize
            )
        else {
            return nil
        }

        return compressJPEG(cropped)
    }

    static func cropImage(
        _ image: UIImage,
        cropSideInView: CGFloat,
        userScale: CGFloat,
        offset: CGSize,
        viewSize: CGSize
    ) -> UIImage? {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return nil }

        let baseScale = cropSideInView / min(iw, ih)
        let scale = baseScale * max(userScale, 1)

        let imageWidth = iw * scale
        let imageHeight = ih * scale
        let imageCenter = CGPoint(
            x: viewSize.width / 2 + offset.width,
            y: viewSize.height / 2 + offset.height
        )
        let imageOrigin = CGPoint(
            x: imageCenter.x - imageWidth / 2,
            y: imageCenter.y - imageHeight / 2
        )
        let cropOriginView = CGPoint(
            x: viewSize.width / 2 - cropSideInView / 2,
            y: viewSize.height / 2 - cropSideInView / 2
        )

        var cropRect = CGRect(
            x: (cropOriginView.x - imageOrigin.x) / scale,
            y: (cropOriginView.y - imageOrigin.y) / scale,
            width: cropSideInView / scale,
            height: cropSideInView / scale
        )

        cropRect = cropRect.intersection(CGRect(origin: .zero, size: image.size))
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        let pixelScale = image.scale
        let pixelRect = CGRect(
            x: cropRect.origin.x * pixelScale,
            y: cropRect.origin.y * pixelScale,
            width: cropRect.size.width * pixelScale,
            height: cropRect.size.height * pixelScale
        ).integral

        guard let cgImage = image.cgImage?.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    static func clampOffset(
        _ offset: CGSize,
        image: UIImage,
        cropSideInView: CGFloat,
        userScale: CGFloat,
        viewSize: CGSize
    ) -> CGSize {
        let normalized = image.normalizedUpOrientation()
        let iw = normalized.size.width
        let ih = normalized.size.height
        guard iw > 0, ih > 0, cropSideInView > 0 else { return .zero }

        let baseScale = cropSideInView / min(iw, ih)
        let scale = baseScale * max(userScale, 1)
        let imageWidth = iw * scale
        let imageHeight = ih * scale

        let maxX = max(0, (imageWidth - cropSideInView) / 2)
        let maxY = max(0, (imageHeight - cropSideInView) / 2)

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    static func maximumUserScale(for image: UIImage, cropSideInView: CGFloat) -> CGFloat {
        let normalized = image.normalizedUpOrientation()
        let iw = normalized.size.width
        let ih = normalized.size.height
        guard iw > 0, ih > 0, cropSideInView > 0 else { return 4 }

        let maxByPixels = (max(iw, ih) * normalized.scale) / uploadMaxDimension
        return max(1, min(4, maxByPixels))
    }

    private static func centerSquareCrop(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0, abs(size.width - size.height) > 0.5 else { return image }

        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let pixelRect = CGRect(
            x: cropRect.origin.x * image.scale,
            y: cropRect.origin.y * image.scale,
            width: cropRect.size.width * image.scale,
            height: cropRect.size.height * image.scale
        ).integral

        guard let cgImage = image.cgImage?.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }

        let scale = maxDimension / largest
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func compressJPEG(_ image: UIImage) -> Data? {
        let resized = resize(image, maxDimension: uploadMaxDimension)
        var quality = uploadJPEGQuality
        guard var data = resized.jpegData(compressionQuality: quality) else { return nil }

        while data.count > uploadMaxBytes, quality > 0.52 {
            quality -= 0.07
            guard let next = resized.jpegData(compressionQuality: quality) else { break }
            data = next
        }

        return data
    }
}

struct ArtworkCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum ArtworkPickFlow {
    enum Result {
        case ready(Data)
        case needsCrop(UIImage)
        case failed(String)
    }

    static func process(_ item: PhotosPickerItem?) async -> Result? {
        guard let item else { return nil }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)?.normalizedUpOrientation()
        else {
            return .failed("Couldn't use that photo.")
        }

        if ArtworkImageProcessing.needsManualCrop(for: image) {
            return .needsCrop(image)
        }

        guard let jpeg = ArtworkImageProcessing.uploadJPEG(from: image) else {
            return .failed("Couldn't prepare that photo.")
        }

        return .ready(jpeg)
    }

    @MainActor
    static func consume(
        _ item: PhotosPickerItem?,
        setCropRequest: (ArtworkCropRequest?) -> Void,
        onError: (String) -> Void,
        onJPEG: (Data) async -> Void
    ) async {
        guard let result = await process(item) else { return }

        switch result {
        case .failed(let message):
            onError(message)
        case .needsCrop(let image):
            setCropRequest(ArtworkCropRequest(image: image))
        case .ready(let jpeg):
            await onJPEG(jpeg)
        }
    }
}

extension UIImage {
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
