import SwiftUI

/// The full-screen dimming layer with a card-shaped hole over the guide.
/// Filled with `FillStyle(eoFill: true)` so the guide stays clear.
struct GuideDimmingShape: Shape {
    var guide: CGRect
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: guide,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}
