import Foundation

struct SpriteSheetConfig {
    let imageName: String
    let columns: Int
    let totalFrames: Int
    let frameSize: CGFloat
}

enum SpriteSheets {
    static let run = SpriteSheetConfig(
        imageName: "run",
        columns: 6,
        totalFrames: 21,
        frameSize: 180
    )

    static let drag = SpriteSheetConfig(
        imageName: "drag",
        columns: 6,
        totalFrames: 26,
        frameSize: 180
    )

    static let frameSize: CGFloat = 180
    static let petSize = CGSize(width: frameSize, height: frameSize)
}
