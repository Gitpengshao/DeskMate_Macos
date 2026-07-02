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
        .onChange(of: viewModel.didCompleteEarly) { _, newValue in
            if newValue {
                onComplete()
            }
        }
    }

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
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

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
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

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
                    onPetPersonalityFileChanged: { viewModel.setPetPersonalityFile($0) }
                )
                .id("step_2")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Actions (mirrors Flutter's onNext logic)

    private func handleNext() {
        let state = viewModel.model

        if state.currentStep == state.totalSteps - 1 {
            // Completing onboarding
            viewModel.completeOnboarding()
            onComplete()
        } else if state.currentStep == 0 {
            if state.hermesInstalled && state.isEnvironmentReady && state.hermesHasModelConfigured && state.hermesHasApiKey {
                // 全部配置完成（含API Key）→ 直接进入首页
                viewModel.completeOnboarding()
                onComplete()
            } else if state.hermesInstalled && state.isEnvironmentReady {
                // Hermes已安装但大模型未配置 → 跳过安装步骤，直接到欢迎引导
                viewModel.nextStep()
                viewModel.nextStep()
            } else {
                // 需要安装Hermes
                viewModel.nextStep()
                viewModel.startInstallation()
            }
        } else if state.currentStep == 1 && state.downloadProgress >= 1.0 && !state.isInstallFailed {
            // 安装步骤完成，前进到欢迎引导
            viewModel.nextStep()
        }
    }
}
