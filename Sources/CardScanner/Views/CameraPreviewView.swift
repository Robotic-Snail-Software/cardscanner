import AVFoundation
import SwiftUI

/// Hosts the `AVCaptureVideoPreviewLayer` — the package's only UIKit, since
/// there is no first-party pure-SwiftUI capture preview. On every layout
/// change it republishes the recognition regions derived from the card guide.
struct CameraPreviewView: UIViewRepresentable {
    let source: PreviewSource
    let bufferSize: CGSize?
    let onRegionsChange: (ScanRegions) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.bufferSize = bufferSize
        view.onRegionsChange = onRegionsChange
        source.connect(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.bufferSize = bufferSize
        uiView.onRegionsChange = onRegionsChange
    }

    final class PreviewUIView: UIView, PreviewTarget {
        var onRegionsChange: ((ScanRegions) -> Void)?

        var bufferSize: CGSize? {
            didSet {
                if bufferSize != oldValue {
                    publishRegions()
                }
            }
        }

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        private var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func setSession(_ session: AVCaptureSession) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishRegions()
        }

        private func publishRegions() {
            guard let bufferSize else { return }
            let guide = CardGuideGeometry.guideRect(in: bounds)
            guard let nameBand = CardGuideGeometry.visionRegion(
                forViewRect: CardGuideGeometry.nameBand(inGuide: guide),
                viewBounds: bounds,
                bufferSize: bufferSize
            ), let collectorBand = CardGuideGeometry.visionRegion(
                forViewRect: CardGuideGeometry.collectorBand(inGuide: guide),
                viewBounds: bounds,
                bufferSize: bufferSize
            ) else { return }
            onRegionsChange?(ScanRegions(nameBand: nameBand, collectorBand: collectorBand))
        }
    }
}
