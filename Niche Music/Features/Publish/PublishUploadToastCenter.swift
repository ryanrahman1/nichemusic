//
//  PublishUploadToastCenter.swift
//  Niche Music
//

import Combine
import SwiftUI
import UIKit

enum PublishHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

@MainActor
final class PublishUploadToastCenter: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        var label: String
        var phase: Phase

        enum Phase: Equatable {
            case uploading
            case complete
            case failed
        }
    }

    @Published private(set) var toasts: [Toast] = []

    @discardableResult
    func begin(_ label: String) -> UUID {
        let toast = Toast(id: UUID(), label: label, phase: .uploading)
        toasts.append(toast)
        PublishHaptics.tap()
        return toast.id
    }

    func complete(_ id: UUID, label: String? = nil) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        if let label {
            toasts[index].label = label
        } else {
            toasts[index].label = "Upload complete"
        }
        toasts[index].phase = .complete
        PublishHaptics.success()

        let toastID = id
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            remove(toastID)
        }
    }

    func fail(_ id: UUID, label: String = "Upload failed") {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        toasts[index].label = label
        toasts[index].phase = .failed
        PublishHaptics.error()

        let toastID = id
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            remove(toastID)
        }
    }

    private func remove(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

struct PublishUploadToastOverlay: View {
    @ObservedObject var center: PublishUploadToastCenter

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.toasts) { toast in
                HStack(spacing: 10) {
                    switch toast.phase {
                    case .uploading:
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    case .complete:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(toast.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.78), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: center.toasts)
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}
