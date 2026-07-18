import SwiftUI

/// The scanner's ready-made UI: camera preview, card guide, live feedback,
/// lock banner, and torch control. Hosts that want custom chrome can build
/// their own view against `CardScannerModel` instead.
///
/// The model's pipeline runs inside this view's `.task`, so presenting and
/// dismissing the view starts and stops the camera automatically.
public struct CardScannerView: View {
    @Bindable private var model: CardScannerModel

    public init(model: CardScannerModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            #if os(iOS)
            if model.authorization == .denied {
                CameraPermissionDeniedView()
            } else {
                ScannerContentView(model: model)
            }
            #else
            ContentUnavailableView(
                "Scanning Not Available",
                systemImage: "camera.fill",
                description: Text("Card scanning uses the iPhone camera.")
            )
            #endif
        }
        .task { await model.start() }
        .sensoryFeedback(.success, trigger: model.lockCount)
    }
}

#if os(iOS)
/// The live scanning stack: preview, overlay, lock banner, torch button.
struct ScannerContentView: View {
    @Bindable var model: CardScannerModel

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(
                source: model.previewSource,
                bufferSize: model.captureBufferSize,
                onRegionsChange: model.updateScanRegions
            )
            .ignoresSafeArea()

            ScannerGuideOverlay(candidate: model.liveCandidate, isLocked: isLocked)
                .ignoresSafeArea()

            if case .locked(let card) = model.phase {
                ScanResultChip(card: card, onContinue: continueAction)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: isLocked)
        .overlay(alignment: .topTrailing) {
            TorchButton(isOn: $model.isTorchOn)
                .padding()
        }
    }

    private var isLocked: Bool {
        if case .locked = model.phase { return true }
        return false
    }

    /// Only manual-resume configurations show a continue button; auto-resume
    /// moves on by itself.
    private var continueAction: (() -> Void)? {
        guard model.configurationRequiresManualResume else { return nil }
        return model.resumeScanning
    }
}

/// Torch toggle for scanning in dim light.
struct TorchButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Torch", systemImage: isOn ? "flashlight.on.fill" : "flashlight.off.fill", isOn: $isOn)
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .tint(.white)
            .padding(10)
            .background(.black.opacity(0.35), in: .circle)
    }
}
#endif
