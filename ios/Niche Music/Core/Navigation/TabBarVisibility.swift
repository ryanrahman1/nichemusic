//
//  TabBarVisibility.swift
//  Niche Music
//

import UIKit

enum TabBarVisibility {
    static func setVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            guard let tabBarController = findTabBarController() else { return }
            tabBarController.tabBar.isHidden = !visible
            if visible {
                tabBarController.tabBar.alpha = 1
            }
        }
    }

    private static func findTabBarController() -> UITabBarController? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return nil
        }

        return findTabBarController(in: window.rootViewController)
    }

    private static func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let found = findTabBarController(in: child) {
                return found
            }
        }
        if let presented = viewController.presentedViewController {
            return findTabBarController(in: presented)
        }
        return nil
    }
}
