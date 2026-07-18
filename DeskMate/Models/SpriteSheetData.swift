import Foundation

struct SpriteSheetConfig {
    let imageName: String
    let columns: Int
    let totalFrames: Int
    let frameSize: CGFloat
    /// 源图中每一帧的真实像素尺寸。如果为 nil，则按图片总宽高除以行列数自动计算。
    let sourceFrameSize: CGSize?
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
    case listen
    case sick
    case downloadComplete
    case downloading

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
        case .listen: return SpriteSheets.listen
        case .sick:   return SpriteSheets.sick
        case .downloadComplete: return SpriteSheets.downloadComplete
        case .downloading:      return SpriteSheets.downloading
        }
    }
}

enum SpriteSheets {
    static let run = SpriteSheetConfig(
        imageName: "run",
        columns: 6,
        totalFrames: 21,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let drag = SpriteSheetConfig(
        imageName: "drag",
        columns: 6,
        totalFrames: 26,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let think = SpriteSheetConfig(
        imageName: "think",
        columns: 6,
        totalFrames: 41,
        frameSize: 90,
        sourceFrameSize: nil
    )

    static let work = SpriteSheetConfig(
        imageName: "work",
        columns: 6,
        totalFrames: 30,
        frameSize: 90,
        sourceFrameSize: nil
    )

    static let sleep = SpriteSheetConfig(
        imageName: "sleep",
        columns: 6,
        totalFrames: 34,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let leave = SpriteSheetConfig(
        imageName: "leave",
        columns: 6,
        totalFrames: 40,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let idle = SpriteSheetConfig(
        imageName: "idle",
        columns: 6,
        totalFrames: 32,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let walk = SpriteSheetConfig(
        imageName: "walk",
        columns: 6,
        totalFrames: 30,
        frameSize: 180,
        sourceFrameSize: CGSize(width: 180, height: 189)
    )

    static let workAtDesk = SpriteSheetConfig(
        imageName: "workAtDesk",
        columns: 6,
        totalFrames: 24,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let listen = SpriteSheetConfig(
        imageName: "listen",
        columns: 6,
        totalFrames: 39,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let sick = SpriteSheetConfig(
        imageName: "sick",
        columns: 6,
        totalFrames: 37,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let downloadComplete = SpriteSheetConfig(
        imageName: "downloadComplete",
        columns: 6,
        totalFrames: 40,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let downloading = SpriteSheetConfig(
        imageName: "downloading",
        columns: 6,
        totalFrames: 30,
        frameSize: 180,
        sourceFrameSize: nil
    )

    static let frameSize: CGFloat = 180
    static let petSize = CGSize(width: frameSize, height: frameSize)
}
