import SwiftUI

/// 设置页面 — 展示版本号、桌宠大小与悬浮透明等配置项。
struct SettingsPage: View {
    @StateObject private var settings = SettingsManager.shared

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 2.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                versionSection
                Divider()
                    .background(Palette.border)
                petSizeSection
                Divider()
                    .background(Palette.border)
                hoverTransparencySection

                Spacer()
            }
            .padding(28)
        }
        .background(Palette.bgBase)
    }

    // MARK: - Version Section

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.textPrimary)

            HStack(spacing: 12) {
                Image("applogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DeskMate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)

                    Text("版本 \(settings.appVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                }

                Spacer()
            }
            .padding(14)
            .background(Palette.bgPanel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }

    // MARK: - Pet Size Section

    private var petSizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("桌宠大小")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)

                Spacer()

                Text(String(format: "%.0f%%", settings.petSizeScale * 100))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textSecond)
                    .frame(minWidth: 44, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Text("小")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)

                Slider(value: $settings.petSizeScale, in: minScale...maxScale, step: 0.1)
                    .tint(Palette.textPrimary)

                Text("大")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }

            Text("拖动滑块调整桌宠显示尺寸，更改会立即生效。")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
        }
    }

    // MARK: - Hover Transparency Section

    private var hoverTransparencySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("悬浮时透明")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)

                    Text("鼠标悬浮在桌宠上时自动变透明并忽略点击，防止遮挡其他软件。")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.isHoverTransparentEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.textPrimary))
                    .labelsHidden()
                    .frame(width: 44)
            }
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
}

// MARK: - Preview

#if DEBUG
struct SettingsPage_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPage()
            .frame(width: 700, height: 500)
    }
}
#endif
