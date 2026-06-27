import SwiftUI

/// Step 1: Environment check UI.
///
/// Shows system specs, check item results, and summary.
/// Mirrors Flutter's EnvironmentCheckStep.
struct EnvironmentCheckStepView: View {
    let isReady: Bool
    let isChecking: Bool
    let checkItems: [EnvironmentCheckItem]
    let hermesHome: String?
    let hermesInstalled: Bool
    let hermesConfigured: Bool
    let hermesHasApiKey: Bool
    let hermesHasModelConfigured: Bool

    var body: some View {
        // Not started yet — show prompt to click "开始检测"
        if !isChecking && !isReady {
            notStartedView
        } else if isChecking {
            checkingView
        } else {
            resultsView
        }
    }

    // MARK: - Not Started

    private var notStartedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("环境检测")
                .font(.title2)
                .fontWeight(.semibold)
            Text("点击下方按钮开始检测运行环境")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Checking

    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在检测环境...")
                .font(.title2)
                .fontWeight(.semibold)
            Text("正在检查系统配置、网络和依赖")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        let allPassed = checkItems.allSatisfy { $0.isPassed }
        let failedItems = checkItems.filter { !$0.isPassed }

        let sysVerItem = checkItems.first(where: { $0.id == "sys_ver" })
        let gpuItem = checkItems.first(where: { $0.id == "gpu" })
        let diskItem = checkItems.first(where: { $0.id == "disk" })

        let summaryText: String = {
            if allPassed {
                if hermesInstalled && hermesHasModelConfigured && hermesHasApiKey {
                    return "所有检测通过，环境就绪"
                } else if !hermesInstalled {
                    return "环境检测通过，需要安装 Hermes 引擎"
                } else {
                    return "环境检测通过，需要配置大模型"
                }
            } else {
                return "\(failedItems.count) 项未通过，点击「下一步」帮您安装缺失环境"
            }
        }()

        return ScrollView {
            VStack(spacing: 12) {
                // Key Parameters Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: allPassed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(allPassed ? .green : .red)
                        Text("环境检测结果")
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    Text("计算机关键参数")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        ParamChipView(
                            icon: "desktopcomputer",
                            label: "macOS",
                            value: sysVerItem?.detail ?? "--",
                            isPassed: sysVerItem?.isPassed ?? false
                        )
                        ParamChipView(
                            icon: "cpu",
                            label: "GPU",
                            value: gpuItem?.detail ?? "--",
                            isPassed: gpuItem?.isPassed ?? false
                        )
                        ParamChipView(
                            icon: "internaldrive",
                            label: "磁盘",
                            value: diskItem?.detail ?? "--",
                            isPassed: diskItem?.isPassed ?? false
                        )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

                // Failed Items Card
                if !failedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("需要安装的环境")
                            .font(.body)
                            .fontWeight(.semibold)

                        ForEach(checkItems) { item in
                            HStack {
                                Text(itemLabel(item))
                                    .font(.body)
                                Spacer()
                                Text(statusText(item))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(item.isPassed ? .green : .red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }

                // Summary
                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Helpers

    private func itemLabel(_ item: EnvironmentCheckItem) -> String {
        switch item.id {
        case "sys_ver":
            return item.detail != nil ? "macOS 版本 (\(item.detail!))" : "macOS 版本"
        case "network":
            return "网络连通性"
        case "python":
            return item.detail != nil ? "Python 环境 (\(item.detail!))" : "Python 环境"
        case "hermes":
            return "Hermes 大脑"
        case "disk":
            return item.detail != nil ? "磁盘空间 (\(item.detail!))" : "磁盘空间"
        case "gpu":
            return item.detail != nil ? "GPU 加速 (\(item.detail!))" : "GPU 加速"
        default:
            return item.id
        }
    }

    private func statusText(_ item: EnvironmentCheckItem) -> String {
        if !item.isPassed { return "" }
        switch item.id {
        case "hermes":
            return "✓ 已安装 \(item.detail ?? "")"
        case "disk":
            return "✓ 充足"
        case "gpu":
            return "✓ \(item.detail ?? "硬件加速可用")"
        default:
            return "✓ 通过"
        }
    }
}

/// A chip showing a key computer parameter.
struct ParamChipView: View {
    let icon: String
    let label: String
    let value: String
    let isPassed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text("\(label) ")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            if isPassed {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isPassed ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                    lineWidth: 1
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPassed ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        )
    }
}
