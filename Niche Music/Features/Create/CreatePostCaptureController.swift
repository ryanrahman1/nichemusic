//
//  CreatePostCaptureController.swift
//  Niche Music
//

import AVFoundation
import Combine
import UIKit

@MainActor
final class CreatePostCaptureController: NSObject, ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case authorized
        case denied
        case unavailable
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isCapturingPhoto = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.nichemusic.create.capture.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var captureMode: CreatePostCaptureMode = .photo
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    private var videoContinuation: CheckedContinuation<URL?, Never>?
    private var configurationTask: Task<Void, Never>?

    override init() {
        super.init()
    }

    func setActive(_ active: Bool, mode: CreatePostCaptureMode) {
        configurationTask?.cancel()
        configurationTask = Task {
            if active {
                await prepare(mode: mode)
                await start()
            } else {
                await stop()
            }
        }
    }

    func setMode(_ mode: CreatePostCaptureMode) {
        guard mode != captureMode else { return }
        configurationTask?.cancel()
        configurationTask = Task {
            await stop()
            guard !Task.isCancelled else { return }
            await prepare(mode: mode)
            await start()
        }
    }

    func flipCamera() {
        currentPosition = currentPosition == .back ? .front : .back
        configurationTask?.cancel()
        configurationTask = Task {
            await stop()
            guard !Task.isCancelled else { return }
            await prepare(mode: captureMode)
            await start()
        }
    }

    func prepare(mode: CreatePostCaptureMode) async {
        captureMode = mode

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationState = granted ? .authorized : .denied
        case .denied, .restricted:
            authorizationState = .denied
            return
        @unknown default:
            authorizationState = .denied
            return
        }

        guard authorizationState == .authorized else { return }
        guard AVCaptureDevice.default(for: .video) != nil else {
            authorizationState = .unavailable
            return
        }

        if mode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        await configureSession(for: mode)
    }

    func start() async {
        guard authorizationState == .authorized else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isRunning = true
                    continuation.resume()
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }

                if self.session.isRunning {
                    self.session.stopRunning()
                }

                DispatchQueue.main.async {
                    self.isRunning = false
                    self.isRecording = false
                    continuation.resume()
                }
            }
        }
    }

    func capturePhoto() async -> UIImage? {
        guard captureMode == .photo, !isCapturingPhoto, !isRecording else { return nil }

        isCapturingPhoto = true
        defer { isCapturingPhoto = false }

        return await withCheckedContinuation { continuation in
            photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }

            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func toggleVideoRecording() async -> URL? {
        guard captureMode == .video else { return nil }

        if isRecording {
            return await stopVideoRecording()
        }

        await startVideoRecording()
        return nil
    }

    private func startVideoRecording() async {
        guard !movieOutput.isRecording else { return }

        let url = CreatePostMediaSupport.temporaryMediaURL(kind: .video)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                DispatchQueue.main.async {
                    self.isRecording = true
                    continuation.resume()
                }
            }
        }
    }

    private func stopVideoRecording() async -> URL? {
        guard isRecording else { return nil }

        return await withCheckedContinuation { continuation in
            videoContinuation = continuation
            sessionQueue.async { [weak self] in
                self?.movieOutput.stopRecording()
            }
        }
    }

    private func configureSession(for mode: CreatePostCaptureMode) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if self.session.isRunning {
                    self.session.stopRunning()
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = mode == .video ? .high : .photo

                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }

                guard
                    let device = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: self.currentPosition
                    ),
                    let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.authorizationState = .unavailable
                    }
                    continuation.resume()
                    return
                }

                self.session.addInput(input)

                if mode == .photo {
                    if self.session.canAddOutput(self.photoOutput) {
                        self.session.addOutput(self.photoOutput)
                    }
                } else if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)

                    if let audioDevice = AVCaptureDevice.default(for: .audio),
                       let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                       self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                }

                self.session.commitConfiguration()
                continuation.resume()
            }
        }
    }
}

extension CreatePostCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }

        Task { @MainActor in
            photoContinuation?.resume(returning: image)
            photoContinuation = nil
        }
    }
}

extension CreatePostCaptureController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            isRecording = false
            let url = error == nil ? outputFileURL : nil
            videoContinuation?.resume(returning: url)
            videoContinuation = nil
        }
    }
}
