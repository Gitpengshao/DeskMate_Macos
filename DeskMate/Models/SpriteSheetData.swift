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
    case leave
    case idle
    case walk
    case workAtDesk

    var config: SpriteSheetConfig {
        switch self {
        case .run:   return SpriteSheets.run
        case .drag:  return SpriteSheets.drag
        case .think: return SpriteSheets.think
        case .work:  return SpriteSheets.work
        case .sleep: return SpriteSheets.sleep
        case .leave: return SpriteSheets.leave
        case .idle:  return SpriteSheets.idle
        case .walk:  return SpriteSheets.walk
        case .workAtDesk: return SpriteSheets.workAtDesk
        }
    }
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

    static let think = SpriteSheetConfig(
        imageName: "think",
        columns: 6,
        totalFrames: 41,
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
        totalFrames: 34,
        frameSize: 180
    )

    static let leave = SpriteSheetConfig(
        imageName: "leave",
        columns: 6,
        totalFrames: 42,
        frameSize: 180
    )

    static let idle = SpriteSheetConfig(
        imageName: "idle",
        columns: 6,
        totalFrames: 36,
        frameSize: 180
    )

    static let walk = SpriteSheetConfig(
        imageName: "walk",
        columns: 6,
        totalFrames: 30,
        frameSize: 180
    )

    static let workAtDesk = SpriteSheetConfig(
        imageName: "workAtDesk",
        columns: 6,
        totalFrames: 24,
        frameSize: 180
    )

    static let frameSize: CGFloat = 180
    static let petSize = CGSize(width: frameSize, height: frameSize)
}
