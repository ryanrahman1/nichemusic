//
//  ArtworkCropView.swift
//  Niche Music
//

import SwiftUI

struct ArtworkCropView: View {
    let image: UIImage
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void

    @State private var cropSide: CGFloat = 0
    @State private var viewSize: CGSize = .zero
    @State private var userScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureStartScale: CGFloat = 1
    @State private var gestureStartOffset: CGSize = .zero

    private var normalizedImage: UIImage {
        image.normalizedUpOrientation()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    Color.black.ignoresSafeArea()

                    croppedImageLayer(in: size)

                    cropOverlay(in: size)

                    VStack {
                        Spacer()
                        Text("Move and pinch to frame your cover")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.bottom, 24)
                    }
                }
                .onAppear {
                    viewSize = size
                    cropSide = min(size.width, size.height) * 0.82
                    userScale = 1
                    offset = .zero
                }
                .onChange(of: size) { _, newSize in
                    viewSize = newSize
                    cropSide = min(newSize.width, newSize.height) * 0.82
                    offset = ArtworkImageProcessing.clampOffset(
                        offset,
                        image: normalizedImage,
                        cropSideInView: cropSide,
                        userScale: userScale,
                        viewSize: newSize
                    )
                }
            }
            .navigationTitle("Crop artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        confirmCrop()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func croppedImageLayer(in size: CGSize) -> some View {
        let baseScale = cropSide > 0 ? cropSide / min(normalizedImage.size.width, normalizedImage.size.height) : 1
        let scale = baseScale * userScale
        let displaySize = CGSize(
            width: normalizedImage.size.width * scale,
            height: normalizedImage.size.height * scale
        )

        Image(uiImage: normalizedImage)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize.width, height: displaySize.height)
            .offset(offset)
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    @ViewBuilder
    private func cropOverlay(in size: CGSize) -> some View {
        let cropRect = CGRect(
            x: (size.width - cropSide) / 2,
            y: (size.height - cropSide) / 2,
            width: cropSide,
            height: cropSide
        )

        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(cropRect)
            }
            .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                .frame(width: cropSide, height: cropSide)
                .position(x: size.width / 2, y: size.height / 2)

            Path { path in
                let third = cropSide / 3
                for index in 1...2 {
                    let x = cropRect.minX + third * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: cropRect.minY))
                    path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                }
                for index in 1...2 {
                    let y = cropRect.minY + third * CGFloat(index)
                    path.move(to: CGPoint(x: cropRect.minX, y: y))
                    path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.22), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: gestureStartOffset.width + value.translation.width,
                    height: gestureStartOffset.height + value.translation.height
                )
                offset = ArtworkImageProcessing.clampOffset(
                    proposed,
                    image: normalizedImage,
                    cropSideInView: cropSide,
                    userScale: userScale,
                    viewSize: viewSize
                )
            }
            .onEnded { _ in
                gestureStartOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let maxScale = ArtworkImageProcessing.maximumUserScale(
                    for: normalizedImage,
                    cropSideInView: cropSide
                )
                userScale = min(max(gestureStartScale * value, 1), maxScale)
                offset = ArtworkImageProcessing.clampOffset(
                    offset,
                    image: normalizedImage,
                    cropSideInView: cropSide,
                    userScale: userScale,
                    viewSize: viewSize
                )
            }
            .onEnded { _ in
                gestureStartScale = userScale
                gestureStartOffset = offset
            }
    }

    private func confirmCrop() {
        guard
            let jpeg = ArtworkImageProcessing.exportSquareJPEG(
                from: normalizedImage,
                cropSideInView: cropSide,
                userScale: userScale,
                offset: offset,
                viewSize: viewSize
            )
        else {
            return
        }

        onConfirm(jpeg)
    }
}

extension View {
    func artworkCropSheet(
        request: Binding<ArtworkCropRequest?>,
        onConfirm: @escaping (Data) -> Void
    ) -> some View {
        sheet(item: request) { cropRequest in
            ArtworkCropView(
                image: cropRequest.image,
                onConfirm: { jpeg in
                    request.wrappedValue = nil
                    onConfirm(jpeg)
                },
                onCancel: {
                    request.wrappedValue = nil
                }
            )
        }
    }
}
