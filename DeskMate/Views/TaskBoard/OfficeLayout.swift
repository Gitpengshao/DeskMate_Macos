import SwiftUI

// MARK: - Office Colors

enum OfficePalette {
    static let bgBase = Color(red: 0.984, green: 0.949, blue: 0.859) // #fbf2db
    static let deskSurface = Color(red: 0.910, green: 0.863, blue: 0.753) // #e8dcc0
    static let deskShadow = Color(red: 0.820, green: 0.760, blue: 0.650)
    static let deskLegs = Color(red: 0.600, green: 0.500, blue: 0.380)
    static let textPrimary = Color(red: 0.200, green: 0.150, blue: 0.100)
    static let textMuted = Color(red: 0.450, green: 0.380, blue: 0.300)
    static let statusWork = Color(red: 0.133, green: 0.773, blue: 0.369)
    static let statusIdle = Color(red: 0.231, green: 0.510, blue: 0.965)
    static let statusLeave = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let statusWalk = Color(red: 0.961, green: 0.620, blue: 0.043)
}

// MARK: - Decoration

struct OfficeDecoration: Identifiable {
    let imageName: String
    let position: CGPoint
    let size: CGSize

    var id: String { imageName }
}

// MARK: - Layout

enum OfficeLayout {

    /// 办公室背景色。
    static let bgColor = OfficePalette.bgBase

    /// 单个办公桌的占位尺寸（用于定位与碰撞计算）。
    static let deskSize = CGSize(width: 180, height: 190)

    /// 根据容器尺寸与 agent 数量返回每张办公桌的中心点。
    static func deskPositions(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }

        let columns = count <= 4 ? 2 : 3
        let rows = Int(ceil(Double(count) / Double(columns)))

        let horizontalMargin: CGFloat = 80
        let topMargin: CGFloat = 180
        let bottomMargin: CGFloat = 90

        let usableWidth = max(size.width - horizontalMargin * 2, deskSize.width)
        let usableHeight = max(size.height - topMargin - bottomMargin, deskSize.height)

        let totalGridWidth = CGFloat(columns) * deskSize.width
        let totalGridHeight = CGFloat(rows) * deskSize.height

        let startX = horizontalMargin + (usableWidth - totalGridWidth) / 2 + deskSize.width / 2
        let startY = topMargin + (usableHeight - totalGridHeight) / 2 + deskSize.height / 2

        var positions: [CGPoint] = []
        for index in 0..<count {
            let col = index % columns
            let row = index / columns
            let x = startX + CGFloat(col) * deskSize.width
            let y = startY + CGFloat(row) * deskSize.height
            positions.append(CGPoint(x: x, y: y))
        }
        return positions
    }

    /// 办公室装饰品配置：基于容器宽高的固定位置。
    static func decorations(in size: CGSize) -> [OfficeDecoration] {
        [
            OfficeDecoration(
                imageName: "clock",
                position: CGPoint(x: size.width * 0.12, y: size.height * 0.14),
                size: CGSize(width: 64, height: 54)
            ),
            OfficeDecoration(
                imageName: "curtain",
                position: CGPoint(x: size.width * 0.08, y: size.height * 0.28),
                size: CGSize(width: 110, height: 106)
            ),
            OfficeDecoration(
                imageName: "dailyBoard",
                position: CGPoint(x: size.width * 0.32, y: size.height * 0.15),
                size: CGSize(width: 130, height: 108)
            ),
            OfficeDecoration(
                imageName: "workBoard",
                position: CGPoint(x: size.width * 0.68, y: size.height * 0.16),
                size: CGSize(width: 120, height: 130)
            ),
            OfficeDecoration(
                imageName: "pottedPlant",
                position: CGPoint(x: size.width * 0.10, y: size.height * 0.84),
                size: CGSize(width: 86, height: 110)
            ),
            OfficeDecoration(
                imageName: "waterDispenser",
                position: CGPoint(x: size.width * 0.90, y: size.height * 0.80),
                size: CGSize(width: 66, height: 142)
            ),
        ]
    }
}
