import SwiftUI

/// 模型配置页 — 一比一还原 Flutter `ModelConfigPage` 的结构与交互。
///
/// 三段式布局：
/// 1. **主模型** — 当前主模型卡片 + 编辑/新增按钮
/// 2. **视觉模型** — 单独的视觉识别辅助任务
/// 3. **辅助任务** — 其余低优先级任务，列表展示 + 一键全部重置
///
/// UI 风格：黑白主题，无圆角装饰边框，灰阶区分层次。
struct ModelConfigPage: View {
    @StateObject private var viewModel = ModelConfigViewModel()

    @State private var showAddMainSheet: Bool = false
    @State private var editingAuxTask: AuxiliaryTaskType? = nil
    @State private var showResetAllConfirm: Bool = false
    @State private var hasLoadedOnce: Bool = false

    var body: some View {
        ZStack {
            MCPalette.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                pageHeader
                Divider().background(MCPalette.border)
                content
            }
        }
        .preferredColorScheme(.dark)
        .task { await initialLoad() }
        .sheet(isPresented: $showAddMainSheet) {
            AddMainModelSheet(viewModel: viewModel) {
                // onSaved: 模型已更新，state 会在 updateCurrentModel 中重拉
            }
        }
        .sheet(item: $editingAuxTask) { task in
            EditAuxiliarySheet(viewModel: viewModel, task: task)
        }
        .alert("重置所有辅助任务？", isPresented: $showResetAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                Task { await viewModel.resetAllAuxiliary() }
            }
        } message: {
            Text("所有自定义辅助任务模型将被清空，恢复为「跟随主模型」。Gateway 会被重启。")
        }
    }

    // MARK: Header

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MCPalette.textPrimary)
                    Text("开发模型配置")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MCPalette.textPrimary)
                }
                Text("管理 DeskMate 使用的主模型与各类辅助任务模型")
                    .font(.system(size: 12))
                    .foregroundColor(MCPalette.textSecond)
            }

            Spacer()

            // Refresh button
            Button(action: { Task { await viewModel.refresh() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("刷新")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(MCPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(MCPalette.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MCPalette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.5 : 1.0)

            // Add main model button
            Button(action: { showAddMainSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.model.hasModel ? "pencil" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(viewModel.model.hasModel ? "编辑主模型" : "添加主模型")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(MCPalette.inverseInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(MCPalette.inverse)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !hasLoadedOnce {
            loadingView
        } else if let err = viewModel.loadError, !hasLoadedOnce {
            errorView(err)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mainModelSection
                    visionSection
                    auxiliarySection
                    footerHint
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.0)
                .colorScheme(.dark)
            Text("加载中...")
                .font(.system(size: 12))
                .foregroundColor(MCPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundColor(MCPalette.textTertiary)
            Text("加载失败")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MCPalette.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(MCPalette.textSecond)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await initialLoad() }
            }
            .buttonStyle(.borderless)
            .foregroundColor(MCPalette.inverse)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(MCPalette.inverse.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MCPalette.borderStrong, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Sections

    private var mainModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "cpu.fill",
                title: "主模型",
                description: "所有未指定专用模型的任务都会使用主模型"
            )
            CurrentModelCard(
                state: viewModel.model,
                onEdit: { showAddMainSheet = true }
            )
        }
    }

    private var visionSection: some View {
        let visionConfig = viewModel.model.getAuxiliary(.vision)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "eye.fill",
                title: "视觉模型",
                description: "处理图像识别任务；未设置时主模型需自带视觉能力"
            )
            AuxiliaryTaskRow(
                task: .vision,
                config: visionConfig,
                isHighlighted: !visionConfig.isAuto,
                onChange: { editingAuxTask = .vision },
                onReset: {
                    Task { await viewModel.resetAuxiliaryTask(.vision) }
                }
            )
        }
    }

    private var auxiliarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "rectangle.stack.fill",
                title: "辅助任务模型",
                description: "为低优先级任务指定专用低成本模型可节省 Token",
                trailing: AnyView(
                    Button(action: { showResetAllConfirm = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                            Text("全部重置")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(MCPalette.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(MCPalette.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.model.hasAuxiliaryOverrides)
                    .opacity(viewModel.model.hasAuxiliaryOverrides ? 1.0 : 0.4)
                )
            )

            VStack(spacing: 8) {
                ForEach(kAuxiliaryTaskOrder, id: \.self) { task in
                    AuxiliaryTaskRow(
                        task: task,
                        config: viewModel.model.getAuxiliary(task),
                        isHighlighted: !viewModel.model.getAuxiliary(task).isAuto,
                        onChange: { editingAuxTask = task },
                        onReset: {
                            Task { await viewModel.resetAuxiliaryTask(task) }
                        }
                    )
                }
            }
        }
    }

    private var footerHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11))
            Text("提示：所有配置会写入 `~/.hermes/config.yaml`，API Key 保存在 `~/.hermes/.env`，保存后会自动重启 Gateway。")
                .font(.system(size: 10.5))
                .foregroundColor(MCPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MCPalette.bgPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MCPalette.border, lineWidth: 1)
        )
    }

    // MARK: Lifecycle

    private func initialLoad() async {
        await viewModel.load()
        hasLoadedOnce = true
    }
}
