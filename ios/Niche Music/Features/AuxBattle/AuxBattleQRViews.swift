//
//  AuxBattleQRViews.swift
//  Niche Music
//

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Vision
import VisionKit

enum AuxRoomCode {
    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    static func copy(_ code: String) {
        UIPasteboard.general.string = code
    }

    static func qrImage(for code: String, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct AuxBattleQRCodeSheet: View {
    let code: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Scan to join")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)

                if let image = AuxRoomCode.qrImage(for: code) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                Text(code)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Room QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct AuxBattleQRScannerView: View {
    let onCodeScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    AuxQRScannerRepresentable { code in
                        AuxBattleHaptics.success()
                        onCodeScanned(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView {
                        Label("Scanner unavailable", systemImage: "camera.fill")
                    } description: {
                        Text(scannerError ?? "QR scanning isn't available on this device.")
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct AuxQRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard DataScannerViewController.isAvailable else { return }
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeScanned: (String) -> Void
        private var didScan = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan else { return }

            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }

                let code = AuxRoomCode.normalize(payload)
                guard code.count >= 4 else { continue }

                didScan = true
                dataScanner.stopScanning()
                onCodeScanned(code)
                return
            }
        }
    }
}
