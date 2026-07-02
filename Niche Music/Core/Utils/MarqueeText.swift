//
//  MarqueeText.swift
//  Niche Music
//

import SwiftUI

private struct MarqueeContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var foreground: Color = .primary
    var textAlignment: TextAlignment = .leading

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var marqueeTask: Task<Void, Never>?

    private var isTruncated: Bool {
        textWidth > containerWidth + 0.5 && containerWidth > 0 && !text.isEmpty
    }

    private var frameAlignment: Alignment {
        switch textAlignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(font)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: containerWidth > 0 ? containerWidth : .infinity, alignment: frameAlignment)
                .opacity(isTruncated ? 0 : 1)

            if isTruncated {
                Text(text)
                    .font(font)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
            }

            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MarqueeContentWidthKey.self, value: proxy.size.width)
                    }
                )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, alignment: frameAlignment)
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MarqueeContainerWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MarqueeContentWidthKey.self) { textWidth = $0; restartMarquee() }
        .onPreferenceChange(MarqueeContainerWidthKey.self) { containerWidth = $0; restartMarquee() }
        .onChange(of: text) { _, _ in
            offset = 0
            restartMarquee()
        }
        .onDisappear {
            marqueeTask?.cancel()
            marqueeTask = nil
        }
    }

    private func restartMarquee() {
        marqueeTask?.cancel()
        marqueeTask = nil
        offset = 0

        guard isTruncated else { return }

        let distance = textWidth - containerWidth
        guard distance > 0 else { return }

        marqueeTask = Task { @MainActor in
            let scrollDuration = max(2.8, Double(distance) / 26)
            let pause: Duration = .seconds(1.35)

            while !Task.isCancelled {
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled, isTruncated else { return }

                withAnimation(.linear(duration: scrollDuration)) {
                    offset = -distance
                }

                try? await Task.sleep(for: .seconds(scrollDuration) + pause)
                guard !Task.isCancelled, isTruncated else { return }

                withAnimation(.linear(duration: scrollDuration)) {
                    offset = 0
                }

                try? await Task.sleep(for: .seconds(scrollDuration) + .milliseconds(500))
            }
        }
    }
}
