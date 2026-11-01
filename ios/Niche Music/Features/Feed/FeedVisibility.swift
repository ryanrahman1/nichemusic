//
//  FeedVisibility.swift
//  Niche Music
//

import SwiftUI

struct FeedPostVisibility: Equatable {
    let index: Int
    let frame: CGRect
}

struct FeedVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [FeedPostVisibility] = []

    static func reduce(value: inout [FeedPostVisibility], nextValue: () -> [FeedPostVisibility]) {
        for entry in nextValue() {
            if let existing = value.firstIndex(where: { $0.index == entry.index }) {
                value[existing] = entry
            } else {
                value.append(entry)
            }
        }
    }
}

enum FeedVisibility {
    /// Portion of the cell intersecting the viewport (0...1).
    static func visibleRatio(cellFrame: CGRect, viewportFrame: CGRect) -> CGFloat {
        let intersection = cellFrame.intersection(viewportFrame)
        guard !intersection.isNull, cellFrame.height > 0 else { return 0 }
        return intersection.height / cellFrame.height
    }

    /// Index of the post that should be active (≥ `threshold` visible), or nil.
    static func activeIndex(
        in visibilities: [FeedPostVisibility],
        viewportFrame: CGRect,
        threshold: CGFloat = 0.5
    ) -> Int? {
        let ranked = visibilities.compactMap { entry -> (index: Int, ratio: CGFloat)? in
            let ratio = visibleRatio(cellFrame: entry.frame, viewportFrame: viewportFrame)
            guard ratio >= threshold else { return nil }
            return (entry.index, ratio)
        }
        return ranked.max(by: { $0.ratio < $1.ratio })?.index
    }
}

extension View {
    func feedPostVisibility(index: Int) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: FeedVisibilityPreferenceKey.self,
                    value: [FeedPostVisibility(index: index, frame: geo.frame(in: .global))]
                )
            }
        )
    }
}
