import SwiftUI

/// Step 2: Install engine progress UI.
///
/// Shows download progress, stage info, and a mirror configuration prompt
/// when the download speed is detected as slow (common for users in China).
/// Mirrors Flutter's InstallEngineStep.
struct InstallEngineStepView: View {
    let progress: Double
    let speed: String
    let eta: String
    let failedCheckIds: [String]
    let currentDownloadingItem: String?
    let isDownloadSlow: Bool
    let showMirrorPrompt: Bool
    let isConfiguringMirror: Bool
    let mirrorUrl: String?
    let installLogTail: String?
    let onCancel: (() -> Void)?
    let onConfigureMirror: (() -> Void)?
    let onDismissMirror: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Install info — show what needs to be installed
                if !failedCheckIds.isEmpty {
                    installInfoBanner
                        .padding(.bottom, 12)
                }

                // Mirror configuration prompt banner
                if showMirrorPrompt {
                    mirrorPromptBanner
                        .padding(.bottom, 12)
                }

                // Mirror configuring banner
                if mirrorUrl != nil && !showMirrorPrompt && isConfiguringMirror {
                    mirrorConfiguringBanner
                        .padding(.bottom, 12)
                }

                // Mirror active indicator
                if mirrorUrl != nil && !showMirrorPrompt && !isConfiguringMirror {
                    mirrorActiveBanner
                        .padding(.bottom, 12)
                }

                // Install card
                installCard
            }
        }
    }

    // MARK: - Install Info Banner

    private var installInfoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在帮您安装缺失环境")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(failedCheckIds.map(failedItemLabel).joined(separator: "、"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Mirror Prompt

    private var mirrorPromptBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载速度较慢？")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("检测到当前下载速度较慢，可能是由于 GitHub 访问受限。\n是否配置 GitHub 国内镜像加速下载？镜像将替换原始 GitHub 地址为您加速安装。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("继续等待") {
                    onDismissMirror?()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Button(action: {
                    onConfigureMirror?()
                }) {
                    if isConfiguringMirror {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                            Text("配置中...")
                        }
                    } else {
                        Text("配置镜像加速")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfiguringMirror)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var mirrorConfiguringBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
            Text("正在使用镜像加速重新下载...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var mirrorActiveBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
            Text("已启用国内镜像加速")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.green)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Install Card

    private var installCard: some View {
        let pct = Int(progress * 100)
        let currentStage = min(max(Int(ceil(progress * 5)), 1), 5)

        return VStack(spacing: 0) {
            // Title row
            HStack {
                Text("安装 Hermes 引擎")
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer().frame(height: 40)

            // Egg icon in circle
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 2)
                    )

                if isConfiguringMirror {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    Text(progress >= 1.0 ? "🐣" : "🥚")
                        .font(.largeTitle)
                }
            }

            Spacer().frame(height: 24)

            // Status text
            if isConfiguringMirror {
                Text("正在配置镜像加速...")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    Text("正在下载安装...")
                        .font(.body)
                        .foregroundColor(.secondary)

                    if let item = currentDownloadingItem, !item.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor.opacity(0.7))
                            Text(item)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            Spacer().frame(height: 16)

            // Progress section
            VStack(spacing: 6) {
                // Stage & percentage row
                HStack {
                    Text("阶段 \(currentStage)/5")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(mirrorUrl != nil ? Color.green : Color.primary)
                            .frame(width: geo.size.width * CGFloat(progress), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: 400)

            Spacer().frame(height: 12)

            // Status & elapsed（不再使用"下载速度/预计剩余时间"误导词）
            Text("状态: \(speed) · \(eta)")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            // 实时安装日志区：展示真实 install.sh 输出，替代假进度条观感
            if let tail = installLogTail, !tail.isEmpty {
                ScrollView {
                    Text(tail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 78)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
                .frame(maxWidth: 400)
                .padding(.top, 4)
            }

            Spacer().frame(height: 20)

            // Fun fact
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Did you know? Hermes 支持 30+ 大模型服务商")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
                    .italic()
            }

            Spacer().frame(height: 12)

            // Cancel button
            if let onCancel = onCancel {
                Button("取消安装", action: onCancel)
                    .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func failedItemLabel(_ id: String) -> String {
        switch id {
        case "python": return "Python 环境"
        case "hermes": return "Hermes 大脑"
        case "network": return "网络连通性"
        case "disk": return "磁盘空间（不足）"
        default: return id
        }
    }
}
