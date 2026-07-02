//
//  BadgeSupport.swift
//  Niche Music
//

import SwiftUI

struct BadgePillView: View {
    let text: String
    let colorHex: String
    var fontSize: CGFloat = 12
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 7

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var badgeColor: Color {
        Color.badgeHex(colorHex) ?? .white.opacity(0.82)
    }
}

struct BadgeHeroView: View {
    let badge: BadgeDetail

    var body: some View {
        VStack(spacing: 14) {
            BadgePillView(
                text: badge.text,
                colorHex: badge.colorHex,
                fontSize: 18,
                horizontalPadding: 18,
                verticalPadding: 11
            )

            Text(holderCountLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var holderCountLabel: String {
        let count = badge.holderCount
        if count == 1 {
            return "1 person has this badge"
        }
        return "\(count) people have this badge"
    }
}

extension Color {
    static func badgeHex(_ hex: String) -> Color? {
        var sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        if sanitized.count == 6, let value = UInt64(sanitized, radix: 16) {
            let red = Double((value >> 16) & 0xFF) / 255
            let green = Double((value >> 8) & 0xFF) / 255
            let blue = Double(value & 0xFF) / 255
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }

        if sanitized.count == 8, let value = UInt64(sanitized, radix: 16) {
            let red = Double((value >> 24) & 0xFF) / 255
            let green = Double((value >> 16) & 0xFF) / 255
            let blue = Double((value >> 8) & 0xFF) / 255
            let alpha = Double(value & 0xFF) / 255
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }

        return nil
    }
}
