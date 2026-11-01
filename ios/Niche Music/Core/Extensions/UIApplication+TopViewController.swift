//
//  UIApplication+TopViewController.swift
//  Niche Music
//

import UIKit

extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
