import SwiftUI
import CubeHubCore

/// A cube unfolded: U on top, then L F R B in a strip, D below F. Works for any
/// cube size; `faceSize` is how wide one face is drawn, in design points.
struct CubeNetView: View {
    let cube: Cube
    let faceSize: CGFloat
    let u: CGFloat

    private static let placement: [(face: Face, column: CGFloat, row: CGFloat)] = [
        (.up, 1, 0), (.left, 0, 1), (.front, 1, 1), (.right, 2, 1), (.back, 3, 1), (.down, 1, 2),
    ]

    /// The gap between faces, a little wider than the gap between stickers.
    private var faceGap: CGFloat { faceSize * 0.09 }

    var body: some View {
        let count = CGFloat(cube.size)
        let stickerGap = faceSize * 0.036
        let sticker = (faceSize - stickerGap * (count - 1)) / count
        Canvas { context, _ in
            for (face, faceColumn, faceRow) in Self.placement {
                let stickers = cube.stickers(on: face)
                let originX = faceColumn * (faceSize + faceGap)
                let originY = faceRow * (faceSize + faceGap)
                for index in stickers.indices {
                    let rect = CGRect(
                        x: (originX + CGFloat(index % cube.size) * (sticker + stickerGap)) * u,
                        y: (originY + CGFloat(index / cube.size) * (sticker + stickerGap)) * u,
                        width: sticker * u,
                        height: sticker * u
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: sticker * 0.19 * u),
                        with: .color(CubeColor(face: stickers[index]).color)
                    )
                }
            }
        }
        .frame(
            width: (faceSize * 4 + faceGap * 3) * u,
            height: (faceSize * 3 + faceGap * 2) * u
        )
        .accessibilityLabel("Scrambled cube preview")
    }
}
