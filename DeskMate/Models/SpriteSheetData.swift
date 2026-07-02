import Foundation

struct SpriteSheetConfig {
    let imageName: String
    let columns: Int
    let totalFrames: Int
    let frameSize: CGFloat
}

enum PetAnimation {
    case run
    case drag
    case think
    case work
    case sleep

    var config: SpriteSheetConfig {
        switch self {
        case .run:   return SpriteSheets.run
        case .drag:  return SpriteSheets.drag
        case .think: return SpriteSheets.think
        case .work:  return SpriteSheets.work
        case .sleep: return SpriteSheets.sleep
        }
    }
}

enum SpriteSheets {
    static let run = SpriteSheetConfig(
        imageName: "run",
        columns: 6,
        totalFrames: 24,
        frameSize: 180
    )

    static let drag = SpriteSheetConfig(
        imageName: "drag",
        columns: 6,
        totalFrames: 30,
        frameSize: 180
    )

    static let think = SpriteSheetConfig(
        imageName: "think",
        columns: 6,
        totalFrames: 30,
        frameSize: 90
    )

    static let work = SpriteSheetConfig(
        imageName: "work",
        columns: 6,
        totalFrames: 30,
        frameSize: 90
    )

    static let sleep = SpriteSheetConfig(
        imageName: "sleep",
        columns: 6,
        totalFrames: 36,
        frameSize: 180
    )

    static let petSize = CGSize(width: 180, height: 180)
}
