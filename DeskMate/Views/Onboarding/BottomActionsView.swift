import SwiftUI

/// Bottom action bar with back/next/start buttons for the onboarding flow.
/// Mirrors Flutter's BottomActions.
struct BottomActionsView: View {
    let isFirstStep: Bool
    let isLastStep: Bool
    let isDownloading: Bool
    let isCheckingEnv: Bool
    let canAdvance: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onStart: () -> Void

    var body: some View {
        // Hide bottom actions during download — cancel is inside the card
        if isDownloading {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                // Back button (not on first step)
                if !isFirstStep {
                    Button("上一步", action: onBack)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundColor(.secondary)
                }

                // Main CTA button
                if isCheckingEnv {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("检测中...")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                    .foregroundColor(.white)
                } else if !canAdvance && isFirstStep {
                    Button("开始检测", action: onStart)
                        .buttonStyle(.borderedProminent)
                } else if isLastStep {
                    Button("开始使用", action: onNext)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdvance)
                } else {
                    Button("下一步", action: onNext)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdvance)
                }
            }
            .padding(.vertical, 20)
        }
    }
}

/// Error banner shown when installation fails, with retry action.
/// Mirrors Flutter's InstallErrorBanner.
struct InstallErrorBannerView: View {
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button("重试", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.top, 8)
    }
}
