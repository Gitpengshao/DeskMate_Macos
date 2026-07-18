import SwiftUI

/// Onboarding / startup wizard page — MVVM View layer.
///
/// Guides the user through a 3-step setup:
///   1. 环境检测 (Environment Check)
///   2. 安装引擎 (Install Engine)
///   3. 欢迎引导 (Welcome Guide)
///
/// Mirrors Flutter's OnboardingPage.
struct OnboardingView: View {
    @StateObject var viewModel: OnboardingViewModel
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("DeskMate")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .padding(.top, 24)

            // Step indicator bar
            StepIndicatorView(
                steps: viewModel.model.steps,
                currentStep: viewModel.model.currentStep
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer(minLength: 0)

            // Step content — switches based on current step
            stepContent
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.model.currentStep)

            // Show error if installation failed
            if viewModel.model.isInstallFailed && viewModel.model.currentStep == 1 {
                InstallErrorBannerView(
                    errorMessage: viewModel.model.installError ?? "安装失败",
                    onRetry: { viewModel.retryInstallation() }
                )
                .padding(.horizontal, 24)
            }

            // Show error if onboarding completion failed (e.g. Gateway could not start)
            if let error = viewModel.model.onboardingError {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Bottom actions
            BottomActionsView(
                isFirstStep: viewModel.model.currentStep == 0,
                isLastStep: viewModel.model.currentStep == viewModel.model.totalSteps - 1,
                isDownloading: viewModel.model.isInstalling,
                isCheckingEnv: viewModel.model.isCheckingEnvironment,
                canAdvance: viewModel.model.canAdvance,
                onBack: { viewModel.previousStep() },
                onNext: { handleNext() },
                onStart: { viewModel.startEnvironmentCheck() }
            )
        }
        .frame(width: 558, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: viewModel.model.isCompleted) { _, newValue in
            if newValue {
                onComplete()
            }
        }
        .onChange(of: viewModel.model.currentStep) { _, newValue in
            // 进入第三步时刷新 SOUL.md 内容，确保展示最新状态。
            if newValue == 2 {
                viewModel.loadSoulFile()
            }
        }
        .alert("选择下载源", isPresented: showMirrorAlert) {
            Button("国内镜像加速") {
                viewModel.startInstallationWithMirrorChoice(useMirror: true)
            }
            Button("官方原始地址") {
                viewModel.startInstallationWithMirrorChoice(useMirror: false)
            }
        } message: {
            Text("检测到当前环境缺少 Hermes / Python / venv 等依赖。建议中国大陆用户选择国内镜像加速下载，否则可能因网络问题导致安装缓慢或失败。")
        }
        .sheet(isPresented: showSoulPreviewBinding) {
            SoulPreviewSheet(content: viewModel.model.soulFileContent)
        }
    }

    // MARK: - Bindings

    private var showMirrorAlert: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.model.showInitialMirrorPrompt },
            set: { viewModel.model.showInitialMirrorPrompt = $0 }
        )
    }

    private var showSoulPreviewBinding: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.model.showSoulPreview },
            set: { viewModel.model.showSoulPreview = $0 }
        )
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.model.currentStep {
            case 0:
                EnvironmentCheckStepView(
                    isReady: viewModel.model.isEnvironmentReady,
                    isChecking: viewModel.model.isCheckingEnvironment,
                    checkItems: viewModel.model.environmentCheckItems,
                    hermesHome: viewModel.model.hermesHome,
                    hermesInstalled: viewModel.model.hermesInstalled,
                    hermesConfigured: viewModel.model.hermesConfigured,
                    hermesHasApiKey: viewModel.model.hermesHasApiKey,
                    hermesHasModelConfigured: viewModel.model.hermesHasModelConfigured
                )
                .id("step_0")
                .stepTransition()

            case 1:
                InstallEngineStepView(
                    progress: viewModel.model.downloadProgress,
                    speed: viewModel.model.downloadSpeed,
                    eta: viewModel.model.estimatedTime,
                    failedCheckIds: viewModel.model.failedCheckIds,
                    currentDownloadingItem: viewModel.model.currentDownloadingItem,
                    isDownloadSlow: viewModel.model.isDownloadSlow,
                    showMirrorPrompt: viewModel.model.showMirrorPrompt,
                    isConfiguringMirror: viewModel.model.isConfiguringMirror,
                    mirrorUrl: viewModel.model.mirrorUrl,
                    installLogTail: viewModel.model.installLogTail,
                    onCancel: { viewModel.cancelDownload() },
                    onConfigureMirror: { viewModel.configureMirrorAndRestart() },
                    onDismissMirror: { viewModel.dismissMirrorPrompt() }
                )
                .id("step_1")
                .stepTransition()

            case 2:
                WelcomeGuideStepView(
                    model: viewModel.model,
                    onModelProviderTypeChanged: { viewModel.setModelProviderType($0) },
                    onBuiltInProviderChanged: { viewModel.selectBuiltInProvider($0) },
                    onBuiltInModelIdChanged: { viewModel.setBuiltInModelId($0) },
                    onCustomModelIdChanged: { viewModel.setCustomModelId($0) },
                    onCustomModelUrlChanged: { viewModel.setCustomModelUrl($0) },
                    onCustomProviderNameChanged: { viewModel.setCustomProviderName($0) },
                    onApiKeyChanged: { viewModel.setApiKey($0) },
                    onSoulFileSelected: { viewModel.selectSoulFile($0) },
                    onClearSoulFile: { viewModel.clearSoulFile() },
                    onViewSoulFile: { viewModel.toggleSoulPreview() }
                )
                .id("step_2")
                .stepTransition()

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Actions (mirrors Flutter's onNext logic)

    private func handleNext() {
        let state = viewModel.model

        // 如果 onboarding 正在保存/完成中，避免重复触发（尤其是自动跳过和用户点击并发时）。
        if state.isSaving || state.isCompleted {
            return
        }

        if state.currentStep == state.totalSteps - 1 {
            // Completing onboarding
            viewModel.completeOnboarding()
        } else if state.currentStep == 0 {
            if state.hermesInstalled && state.isEnvironmentReady && state.hermesHasModelConfigured && state.hermesHasApiKey {
                // 全部配置完成（含API Key）→ 直接进入首页
                viewModel.completeOnboarding()
            } else if state.hermesInstalled && state.isEnvironmentReady {
                // Hermes已安装但大模型未配置 → 跳过安装步骤，直接到欢迎引导
                viewModel.goToStep(2)
            } else {
                // 需要安装 Hermes：先进入安装步骤，再弹出镜像选择 Alert
                viewModel.nextStep()
                // 延迟到下一 runloop，避免在视图更新期间修改 @Published 状态
                DispatchQueue.main.async { [weak viewModel] in
                    viewModel?.promptForMirrorThenInstall()
                }
            }
        } else if state.currentStep == 1 && state.downloadProgress >= 1.0 && !state.isInstallFailed {
            // 安装步骤完成，前进到欢迎引导
            viewModel.nextStep()
        }
    }
}

// MARK: - View Modifiers

private extension View {
    /// 统一的步骤切换转场动画。
    func stepTransition() -> some View {
        self.transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
    }
}

// MARK: - SOUL.md Preview Sheet

struct SoulPreviewSheet: View {
    let content: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("当前 SOUL.md")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                Text(displayContent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 520, height: 420)
    }

    private var displayContent: String {
        if let content = content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        return "当前 SOUL.md 为空，Hermes 将使用内置默认身份。"
    }
}
