import SwiftUI

/// Main page with sidebar navigation — mirrors Flutter `MainPage`.
/// MVVM: View observes MainViewModel.
struct MainPage: View {
    @StateObject private var viewModel = MainViewModel.shared
    // Main 页面与 AI 对话页统一使用黑色主题
    @State private var isDark: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                MainSidebar(viewModel: viewModel, isDark: isDark)
                MainContentArea(
                    activeNavId: viewModel.model.activeNavId,
                    viewModel: viewModel,
                    isDark: isDark
                )
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .preferredColorScheme(.dark)
        // 环境与 Gateway 就绪检查已前移到 AppDelegate.openMainConsole，
        // 避免在视图 onAppear 中关闭窗口/跳转页面触发 "Modifying state during view update"。
    }
}

// MARK: - Preview

#if DEBUG
struct MainPage_Previews: PreviewProvider {
    static var previews: some View {
        MainPage()
    }
}
#endif
