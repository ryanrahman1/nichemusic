//
//  Color.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: Int, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: opacity
        )
    }
}

extension UIImage {
    func dominantColor() -> UIColor {
        let size = CGSize(width: 40, height: 40)
        UIGraphicsBeginImageContext(size)
        draw(in: CGRect(origin: .zero, size: size))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = scaledImage?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return .black
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        var rTotal = 0, gTotal = 0, bTotal = 0, count = 0

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = (y * width + x) * bytesPerPixel
                let r = Int(bytes[offset])
                let g = Int(bytes[offset + 1])
                let b = Int(bytes[offset + 2])

                let brightness = (r + g + b) / 3
                guard brightness > 30 && brightness < 220 else { continue }

                rTotal += r; gTotal += g; bTotal += b; count += 1
            }
        }

        guard count > 0 else { return UIColor(white: 0.12, alpha: 1) }

        return UIColor(
            red: CGFloat(rTotal / count) / 255,
            green: CGFloat(gTotal / count) / 255,
            blue: CGFloat(bTotal / count) / 255,
            alpha: 1
        )
    }
}

extension Color {
    func mix(with color: Color, by amount: CGFloat) -> Color {
        let uiColor1 = UIColor(self)
        let uiColor2 = UIColor(color)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0

        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            opacity: a1 + (a2 - a1) * amount
        )
    }
}
extension Color {
    func desaturated(by amount: CGFloat) -> Color {
        let uiColor = UIColor(self)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )

        return Color(
            hue: Double(hue),
            saturation: Double(max(0, saturation * (1 - amount))),
            brightness: Double(brightness),
            opacity: Double(alpha)
        )
    }
}
