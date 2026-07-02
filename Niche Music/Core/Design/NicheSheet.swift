//
//  NicheSheet.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/25/26.
//

import SwiftUI

enum NicheSheetDetent: CGFloat, CaseIterable {
    case medium = 0.52
    case large = 0.92
}

struct NicheSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool

    let detents: [NicheSheetDetent]
    let cornerRadius: CGFloat
    let dismissOnBackgroundTap: Bool
    let content: () -> SheetContent

    @State private var selectedDetent: NicheSheetDetent
    @State private var dragOffset: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        detents: [NicheSheetDetent],
        initialDetent: NicheSheetDetent,
        cornerRadius: CGFloat,
        dismissOnBackgroundTap: Bool,
        content: @escaping () -> SheetContent
    ) {
        self._isPresented = isPresented
        self.detents = detents.sorted { $0.rawValue < $1.rawValue }
        self.cornerRadius = cornerRadius
        self.dismissOnBackgroundTap = dismissOnBackgroundTap
        self.content = content
        self._selectedDetent = State(initialValue: initialDetent)
    }

    func body(content base: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                base

                if isPresented {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            guard dismissOnBackgroundTap else { return }
                            dismiss()
                        }

                    sheetView(in: geo)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isPresented)
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: selectedDetent)
        }
    }

    private func sheetView(in geo: GeometryProxy) -> some View {
        let height = sheetHeight(in: geo)

        return VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(width: 38, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 10)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, geo.safeAreaInsets.bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(sheetBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
            .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: -8)
        .offset(y: max(0, dragOffset))
        .gesture(sheetDragGesture(in: geo))
        .ignoresSafeArea(edges: .bottom)
    }

    private var sheetBackground: some View {
        ZStack {
            Rectangle()
                .fill(Theme.backgroundColor.opacity(0.42))

            LinearGradient(
                colors: [
                    .white.opacity(0.16),
                    .white.opacity(0.055),
                    .black.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func sheetDragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                let actual = value.translation.height

                if actual > 110 || predicted > 190 {
                    if selectedDetent == smallestDetent {
                        dismiss()
                    } else {
                        snap(to: previousDetent)
                    }
                    return
                }

                if actual < -70 || predicted < -130 {
                    snap(to: nextDetent)
                    return
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            }
    }

    private func sheetHeight(in geo: GeometryProxy) -> CGFloat {
        geo.size.height * selectedDetent.rawValue + geo.safeAreaInsets.bottom
    }

    private var smallestDetent: NicheSheetDetent {
        detents.first ?? .medium
    }

    private var largestDetent: NicheSheetDetent {
        detents.last ?? .large
    }

    private var previousDetent: NicheSheetDetent {
        guard let index = detents.firstIndex(of: selectedDetent), index > 0 else {
            return selectedDetent
        }
        return detents[index - 1]
    }

    private var nextDetent: NicheSheetDetent {
        guard let index = detents.firstIndex(of: selectedDetent), index < detents.count - 1 else {
            return selectedDetent
        }
        return detents[index + 1]
    }

    private func snap(to detent: NicheSheetDetent) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            selectedDetent = detent
            dragOffset = 0
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) {
            isPresented = false
            dragOffset = 0
        }
    }
}

extension View {
    func nicheSheet<Content: View>(
        isPresented: Binding<Bool>,
        detents: [NicheSheetDetent] = [.medium, .large],
        initialDetent: NicheSheetDetent = .medium,
        cornerRadius: CGFloat = 28,
        dismissOnBackgroundTap: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            NicheSheetModifier(
                isPresented: isPresented,
                detents: detents,
                initialDetent: initialDetent,
                cornerRadius: cornerRadius,
                dismissOnBackgroundTap: dismissOnBackgroundTap,
                content: content
            )
        )
    }
}
