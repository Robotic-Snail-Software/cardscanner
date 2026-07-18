#if os(iOS)
import AVFoundation

/// Owns the `AVCaptureSession` and streams camera frames into the
/// recognition pipeline. All session work happens on this actor, off the
/// main thread (Apple's AVCam-for-Swift-6 pattern).
///
/// Camera choices are tuned for reading small print on a card held close:
/// back wide camera, 1080p (plenty at card-fills-the-guide distance),
/// continuous autofocus restricted to the near range, and a frame-rate cap —
/// recognition only ever consumes the latest frame, so extra frames are
/// wasted power.
actor CameraCaptureService {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "com.roboticsnailsoftware.cardscanner.frames")
    private let configuration: CameraConfiguration

    private var device: AVCaptureDevice?
    private var frameDelegate: VideoFrameOutputDelegate?
    private var bufferOrientation: CGImagePropertyOrientation = .up
    private var appliedRotationAngle: CGFloat?
    private var isConfigured = false

    /// Connects the session to the preview view; safe to hand to the main actor.
    nonisolated let previewSource: PreviewSource

    init(configuration: CameraConfiguration = CameraConfiguration()) {
        self.configuration = configuration
        previewSource = PreviewSource(session: session)
    }

    /// Configures the session on first use, starts it, and returns the frame
    /// stream. Only the newest frame is buffered — recognition pace is the
    /// effective scan rate, and stale frames are dropped at the source.
    ///
    /// `bufferSize` is the pixel size of delivered (rotation-applied)
    /// buffers, for view→buffer region mapping; `nil` when the connection
    /// couldn't rotate, in which case callers keep the default regions.
    func startStreaming() throws -> (frames: AsyncStream<VideoFrame>, bufferSize: CGSize?) {
        try configureIfNeeded()

        let (stream, continuation) = AsyncStream.makeStream(
            of: VideoFrame.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let delegate = VideoFrameOutputDelegate(
            orientation: bufferOrientation,
            continuation: continuation
        )
        frameDelegate = delegate
        videoOutput.setSampleBufferDelegate(delegate, queue: frameQueue)
        if session.isRunning == false {
            session.startRunning()
        }
        return (stream, rotatedBufferSize())
    }

    /// Stops the session and ends the frame stream.
    func stopStreaming() {
        frameDelegate?.finish()
        frameDelegate = nil
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// Applies a zoom factor, clamped to the device's supported range.
    /// Zoom crops in the ISP, so delivered buffer dimensions — and therefore
    /// all region mapping — are unchanged.
    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let upperBound = min(device.maxAvailableVideoZoomFactor, 10)
            device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), upperBound)
            device.unlockForConfiguration()
        } catch {
            // Zoom is best-effort; scanning continues at the current factor.
        }
    }

    /// Toggles the torch for dim conditions.
    func setTorch(_ isOn: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Torch is best-effort; scanning continues without it.
        }
    }

    // MARK: Configuration

    private func configureIfNeeded() throws {
        guard isConfigured == false else { return }

        // Prefer a virtual multi-camera device: filling the card guide puts
        // the card closer than the wide lens's minimum focus distance, and
        // only virtual devices auto-switch to the ultra-wide for macro (the
        // same behavior as the system Camera app). Pinning the bare wide
        // camera means close cards can never be in focus.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first else {
            throw ScannerError.cameraUnavailable
        }
        self.device = device

        session.beginConfiguration()
        do {
            if configuration.prefersUltraHighResolutionCapture,
               session.canSetSessionPreset(.hd4K3840x2160) {
                session.sessionPreset = .hd4K3840x2160
            } else {
                session.sessionPreset = .hd1920x1080
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw ScannerError.cameraConfigurationFailed }
            session.addInput(input)

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else { throw ScannerError.cameraConfigurationFailed }
            session.addOutput(videoOutput)

            configureRotation(for: device)
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw (error as? ScannerError) ?? ScannerError.cameraConfigurationFailed
        }

        configureDevice(device)
        isConfigured = true
    }

    /// Rotates capture buffers upright for the current interface placement.
    /// When the connection can't rotate, recognition compensates via the
    /// frame's orientation tag instead.
    private func configureRotation(for device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            bufferOrientation = .up
            appliedRotationAngle = angle
        } else {
            bufferOrientation = switch angle {
            case 90: .right
            case 180: .down
            case 270: .left
            default: .up
            }
        }
    }

    /// Pixel size of delivered buffers with connection rotation applied, or
    /// `nil` when rotation wasn't available.
    private func rotatedBufferSize() -> CGSize? {
        guard let device, let angle = appliedRotationAngle else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let sensorSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
        let quarterTurned = angle == 90 || angle == 270
        return quarterTurned
            ? CGSize(width: sensorSize.height, height: sensorSize.width)
            : sensorSize
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isVirtualDevice {
                // Unrestricted constituent switching lets the device fall
                // back to the ultra-wide (macro) when the card is closer
                // than the wide lens can focus.
                device.setPrimaryConstituentDeviceSwitchingBehavior(
                    .auto,
                    restrictedSwitchingBehaviorConditions: []
                )
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isSmoothAutoFocusSupported {
                // Smooth AF trades refocus speed for cinematic focus pulls —
                // the wrong trade for scanning; snappy refocus wins.
                device.isSmoothAutoFocusEnabled = false
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.activeVideoMinFrameDuration = CMTime(
                value: 1,
                timescale: CMTimeScale(configuration.maximumFrameRate)
            )
            device.unlockForConfiguration()
        } catch {
            // Focus/exposure tuning is best-effort; defaults still scan.
        }
    }
}
#endif
