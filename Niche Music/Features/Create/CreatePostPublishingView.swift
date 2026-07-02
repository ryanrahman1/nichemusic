//
//  CreatePostPublishingView.swift
//  Niche Music
//

import SwiftUI

struct CreatePostPublishingView: View {
    let progress: Double
    let stage: CreatePostPublishStage

    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: 0x962a72).opacity(0.18), lineWidth: 4)
                        .frame(width: 112, height: 112)

                    Circle()
                        .trim(from: 0, to: max(0.08, progress))
                        .stroke(
                            Color(hex: 0x962a72),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 112, height: 112)
                        .animation(.easeInOut(duration: 0.35), value: progress)

                    Image(systemName: stageIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .scaleEffect(pulse ? 1.04 : 0.96)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                VStack(spacing: 8) {
                    Text(stageTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Text(stageSubtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .onAppear { pulse = true }
    }

    private var stageIcon: String {
        switch stage {
        case .uploadingMedia: return "arrow.up.circle.fill"
        case .creatingPost: return "checkmark.circle.fill"
        case .finishing, .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "sparkles"
        }
    }

    private var stageTitle: String {
        switch stage {
        case .preparing: return "Getting ready"
        case .uploadingMedia: return "Uploading"
        case .creatingPost: return "Creating post"
        case .finishing: return "Almost there"
        case .completed: return "Posted"
        case .failed: return "Something went wrong"
        case .idle: return "Posting"
        }
    }

    private var stageSubtitle: String {
        switch stage {
        case .preparing: return "Preparing your post..."
        case .uploadingMedia: return "Sending media to Niche."
        case .creatingPost: return "Saving caption and music."
        case .finishing: return "Opening your post."
        case .completed: return "Your post is live."
        case .failed(let message): return message
        case .idle: return "Hang tight."
        }
    }
}
