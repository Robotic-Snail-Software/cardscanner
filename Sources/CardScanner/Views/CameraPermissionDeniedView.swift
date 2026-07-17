import SwiftUI

/// Shown in place of the preview when camera access is denied.
struct CameraPermissionDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("Scanning cards uses the camera. Enable camera access for this app in Settings, then return here.")
        }
    }
}
