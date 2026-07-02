//
//  ExplicitBadge.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/25/26.
//


import SwiftUI

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(Theme.backgroundColor) // Text color matches theme background
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.white)) // Filled box matches theme text color
            )
            .accessibilityLabel("Explicit content") // Accessible to screen readers
    }
}

#Preview {
    ZStack {
        Theme.backgroundColor.ignoresSafeArea()
        ExplicitBadge()
    }
}
