//
//  NicheProgress.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import SwiftUI

struct NicheProgress: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0x962a72).opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color(hex: 0x962a72),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

#Preview {
    ZStack {
        Theme.backgroundColor.ignoresSafeArea()
        VStack(spacing: 32) {
            NicheProgress()

            // Larger size
            NicheProgress()
                .frame(width: 44, height: 44)
                .scaleEffect(44/24)

            // In context
            HStack(spacing: 10) {
                NicheProgress()
                Text("Loading...")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 14))
            }
        }
    }
}
