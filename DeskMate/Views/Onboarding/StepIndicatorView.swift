import SwiftUI

/// Horizontal step indicator bar showing numbered circles with labels.
/// Mirrors Flutter's StepIndicator / StepCircle.
struct StepIndicatorView: View {
    let steps: [OnboardingStep]
    let currentStep: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { (i, _) in
                let isActive = i == currentStep
                let isCompleted = i < currentStep

                HStack(spacing: 8) {
                    StepCircleView(
                        number: i + 1,
                        isActive: isActive,
                        isCompleted: isCompleted
                    )
                    Text(stepLabel(i))
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundColor(.primary)
                }

                if i < steps.count - 1 {
                    Spacer().frame(width: 40)
                }
            }
        }
    }

    private func stepLabel(_ index: Int) -> String {
        switch index {
        case 1: return "安装引擎"
        case 2: return "欢迎引导"
        default: return "环境检测"
        }
    }
}

/// Numbered circle used in the step indicator.
struct StepCircleView: View {
    let number: Int
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        let isFilled = isActive || isCompleted
        ZStack {
            Circle()
                .stroke(Color.primary, lineWidth: 2)
                .background(
                    Circle()
                        .fill(isFilled ? Color.primary : Color.clear)
                )
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isFilled ? Color(NSColor.windowBackgroundColor) : .primary)
        }
        .frame(width: 28, height: 28)
    }
}
