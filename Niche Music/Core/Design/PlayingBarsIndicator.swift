//
//  PlayingBarsIndicator.swift
//  Niche Music
//

import SwiftUI

struct PlayingBarsIndicator: View {
    var color: Color
    var size: CGFloat = 14

    @State private var heights: [CGFloat] = [0.42, 0.88, 0.58]

    private let barCount = 3
    private var barWidth: CGFloat { max(2, size * 0.16) }
    private var barSpacing: CGFloat { max(1.5, size * 0.14) }
    private var minHeightRatio: CGFloat { 0.2 }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(
                        width: barWidth,
                        height: max(size * minHeightRatio, size * heights[index])
                    )
            }
        }
        .frame(
            width: barWidth * CGFloat(barCount) + barSpacing * CGFloat(barCount - 1),
            height: size,
            alignment: .bottom
        )
        .accessibilityLabel("Now playing")
        .task {
            await animateBars()
        }
    }

    @MainActor
    private func animateBars() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<barCount {
                group.addTask { @MainActor in
                    await animateBar(at: index)
                }
            }
        }
    }

    @MainActor
    private func animateBar(at index: Int) async {
        while !Task.isCancelled {
            let duration = Double.random(in: 0.24...0.46)
            withAnimation(.easeInOut(duration: duration)) {
                heights[index] = CGFloat.random(in: 0.22...1.0)
            }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}

#Preview {
    PlayingBarsIndicator(color: .green, size: 14)
        .padding()
        .background(Color.black)
}
