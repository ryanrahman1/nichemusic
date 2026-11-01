//
//  GiphyMediaPicker.swift
//  Niche Music
//

import GiphyUISDK
import SwiftUI
import UIKit

enum GiphyMediaPicker {
    /// Presents Giphy from an existing UIKit presenter (e.g. message threads).
    @MainActor
    static func pickGIF(from presenter: UIViewController) async -> GiphyPickResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<GiphyPickResult?, Never>) in
            let coordinator = PresentationCoordinator { result in
                continuation.resume(returning: result)
            }

            let giphy = makeConfiguredGiphyViewController(delegate: coordinator)
            coordinator.giphyViewController = giphy
            coordinator.presenter = presenter

            presenter.present(giphy, animated: true)
        }
    }

    private static func makeConfiguredGiphyViewController(delegate: GiphyDelegate) -> GiphyViewController {
        Giphy.configure(apiKey: GiphyConfig.apiKey)
        GiphyViewController.trayHeightMultiplier = 1.0

        let giphy = GiphyViewController()
        giphy.delegate = delegate
        giphy.mediaTypeConfig = [.gifs]
        giphy.theme = GPHTheme(type: .dark)
        giphy.showConfirmationScreen = false
        giphy.swiftUIEnabled = true
        giphy.dimBackground = true
        giphy.modalPresentationStyle = .overCurrentContext
        return giphy
    }

    static func result(from media: GPHMedia) -> GiphyPickResult? {
        let url = media.url(rendition: .fixedWidth, fileType: .gif)
            ?? media.url(rendition: .downsized, fileType: .gif)
            ?? media.url(rendition: .original, fileType: .gif)

        guard let url, !url.isEmpty else { return nil }

        let width = 480
        let aspect = media.aspectRatio > 0 ? media.aspectRatio : 1
        let height = max(1, Int(Double(width) / aspect))

        return GiphyPickResult(
            id: media.id,
            url: url,
            width: width,
            height: height
        )
    }

    /// SwiftUI wrapper for presenting Giphy from inside another sheet.
    /// Uses a transparent container that lets Giphy manage its own tray presentation.
    struct PickerSheet: UIViewControllerRepresentable {
        var onComplete: (GiphyPickResult?) -> Void

        func makeCoordinator() -> SheetCoordinator {
            SheetCoordinator(onComplete: onComplete)
        }

        func makeUIViewController(context: Context) -> UIViewController {
            let container = UIViewController()
            container.view.backgroundColor = .clear

            let giphy = makeConfiguredGiphyViewController(delegate: context.coordinator)
            context.coordinator.giphyViewController = giphy

            DispatchQueue.main.async {
                container.present(giphy, animated: true)
            }

            return container
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    }

    private final class PresentationCoordinator: NSObject, GiphyDelegate {
        private let completion: (GiphyPickResult?) -> Void
        private var selfRetain: PresentationCoordinator?
        weak var giphyViewController: GiphyViewController?
        weak var presenter: UIViewController?

        init(completion: @escaping (GiphyPickResult?) -> Void) {
            self.completion = completion
            super.init()
            self.selfRetain = self
        }

        func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia) {
            finish(GiphyMediaPicker.result(from: media))
        }

        func didDismiss(controller: GiphyViewController?) {
            finish(nil)
        }

        private var didFinish = false

        private func finish(_ result: GiphyPickResult?) {
            guard !didFinish else { return }
            didFinish = true
            giphyViewController?.dismiss(animated: true)
            selfRetain = nil
            completion(result)
        }
    }

    final class SheetCoordinator: NSObject, GiphyDelegate {
        let onComplete: (GiphyPickResult?) -> Void
        var giphyViewController: GiphyViewController?
        private var didFinish = false

        init(onComplete: @escaping (GiphyPickResult?) -> Void) {
            self.onComplete = onComplete
            super.init()
        }

        func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia) {
            finish(GiphyMediaPicker.result(from: media))
        }

        func didDismiss(controller: GiphyViewController?) {
            finish(nil)
        }

        private func finish(_ result: GiphyPickResult?) {
            guard !didFinish else { return }
            didFinish = true

            if let giphyViewController {
                giphyViewController.dismiss(animated: true) { [onComplete] in
                    onComplete(result)
                }
            } else {
                onComplete(result)
            }
        }
    }
}
