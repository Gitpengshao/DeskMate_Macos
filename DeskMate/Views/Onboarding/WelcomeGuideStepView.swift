import SwiftUI
import UniformTypeIdentifiers

/// Step 3: Welcome guide & model configuration UI.
/// Mirrors Flutter's WelcomeGuideStep.
struct WelcomeGuideStepView: View {
    let model: OnboardingModel
    let onModelProviderTypeChanged: (String) -> Void
    let onBuiltInProviderChanged: (String) -> Void
    let onBuiltInModelIdChanged: (String) -> Void
    let onCustomModelIdChanged: (String) -> Void
    let onCustomModelUrlChanged: (String) -> Void
    let onCustomProviderNameChanged: (String) -> Void
    let onApiKeyChanged: (String) -> Void
    let onSoulFileSelected: (URL) -> Void
    let onClearSoulFile: () -> Void
    let onViewSoulFile: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cat pet icon
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.1), lineWidth: 2)
                        )
                    Text("🐱")
                        .font(.largeTitle)
                }

                Spacer().frame(height: 16)

                Text("欢迎来到 DeskMate")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("配置你的 AI 宠物伙伴")
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer().frame(height: 24)

                // SOUL.md Personality Section
                SectionCardView(title: "对话风格 (SOUL.md)") {
                    SoulFileSection(
                        content: model.soulFileContent,
                        selectedURL: model.soulFileURL,
                        isLoading: model.isSoulFileLoading,
                        error: model.soulFileError,
                        onSelect: onSoulFileSelected,
                        onClear: onClearSoulFile,
                        onView: onViewSoulFile
                    )
                }

                Spacer().frame(height: 16)

                // Model Provider Section
                SectionCardView(title: "大模型配置") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Provider type toggle
                        Text("选择模型提供商类型")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ProviderTypeToggle(
                            currentType: model.modelProviderType,
                            onChanged: onModelProviderTypeChanged
                        )

                        // Provider-specific forms
                        if model.modelProviderType == "builtin" {
                            BuiltInProviderForm(
                                providers: model.builtInProviders,
                                selectedProvider: model.selectedBuiltInProvider,
                                onProviderChanged: onBuiltInProviderChanged,
                                modelId: model.selectedBuiltInModelId,
                                onModelIdChanged: onBuiltInModelIdChanged,
                                apiKey: model.apiKey,
                                onApiKeyChanged: onApiKeyChanged
                            )
                        } else {
                            CustomProviderForm(
                                providerName: model.customProviderName,
                                modelId: model.customModelId,
                                modelUrl: model.customModelUrl,
                                apiKey: model.apiKey,
                                onProviderNameChanged: onCustomProviderNameChanged,
                                onModelIdChanged: onCustomModelIdChanged,
                                onModelUrlChanged: onCustomModelUrlChanged,
                                onApiKeyChanged: onApiKeyChanged
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Section Card

struct SectionCardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - SOUL.md File Section

struct SoulFileSection: View {
    let content: String?
    let selectedURL: URL?
    let isLoading: Bool
    let error: String?
    let onSelect: (URL) -> Void
    let onClear: () -> Void
    let onView: () -> Void

    private var statusText: String {
        if isLoading { return "正在读取 SOUL.md..." }
        if selectedURL != nil { return "已选择新文件，将替换 SOUL.md" }
        if let content = content {
            return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "当前使用 Hermes 默认身份"
                : "已自定义 SOUL.md"
        }
        return "尚未读取 SOUL.md"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("查看当前 SOUL.md") {
                    onView()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || content == nil)

                Button(selectedURL != nil ? "更换 .md 文件" : "上传 .md 文件") {
                    pickSoulFile()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                if selectedURL != nil {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let url = selectedURL {
                Text("已选择: \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("SOUL.md 是 Hermes Agent 的主要身份标识，定义 AI 的对话风格与语气。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pickSoulFile() {
        let panel = NSOpenPanel()
        // 严格限制为 Markdown 文件（兼容旧版本 SDK）
        let mdType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
        panel.allowedContentTypes = [mdType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }
}

// MARK: - Provider Type Toggle

struct ProviderTypeToggle: View {
    let currentType: String
    let onChanged: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToggleChipView(
                label: "内置模型",
                isSelected: currentType == "builtin",
                onTap: { onChanged("builtin") }
            )
            ToggleChipView(
                label: "自定义模型",
                isSelected: currentType == "custom",
                onTap: { onChanged("custom") }
            )
        }
    }
}

struct ToggleChipView: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color(NSColor.windowBackgroundColor) : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.primary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Built-in Provider Form

struct BuiltInProviderForm: View {
    let providers: [BuiltInModelProvider]
    let selectedProvider: String?
    let onProviderChanged: (String) -> Void
    let modelId: String?
    let onModelIdChanged: (String) -> Void
    let apiKey: String?
    let onApiKeyChanged: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider selection
            Text("选择服务商")
                .font(.caption)
                .fontWeight(.semibold)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                spacing: 8
            ) {
                ForEach(providers) { provider in
                    let isSelected = selectedProvider == provider.id
                    Button {
                        onProviderChanged(provider.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text(provider.iconEmoji)
                                .font(.caption)
                            Text(provider.name)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(isSelected ? Color(NSColor.windowBackgroundColor) : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.primary : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.primary : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Model ID
            Text("模型 ID")
                .font(.caption)
                .fontWeight(.semibold)
            TextField("输入模型 ID（如 gpt-4o）", text: Binding(
                get: { modelId ?? "" },
                set: { onModelIdChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            // API Key
            Text("API Key")
                .font(.caption)
                .fontWeight(.semibold)
            SecureField("输入 API Key", text: Binding(
                get: { apiKey ?? "" },
                set: { onApiKeyChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
    }
}

// MARK: - Custom Provider Form

struct CustomProviderForm: View {
    let providerName: String?
    let modelId: String?
    let modelUrl: String?
    let apiKey: String?
    let onProviderNameChanged: (String) -> Void
    let onModelIdChanged: (String) -> Void
    let onModelUrlChanged: (String) -> Void
    let onApiKeyChanged: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider Name
            Text("服务商名称")
                .font(.caption)
                .fontWeight(.semibold)
            TextField("opencode", text: Binding(
                get: { providerName ?? "" },
                set: { onProviderNameChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            // Model ID
            Text("模型 ID")
                .font(.caption)
                .fontWeight(.semibold)
            TextField("输入自定义模型 ID", text: Binding(
                get: { modelId ?? "" },
                set: { onModelIdChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            // Model Request URL
            Text("模型请求地址")
                .font(.caption)
                .fontWeight(.semibold)
            TextField("http://localhost:11434/v1", text: Binding(
                get: { modelUrl ?? "" },
                set: { onModelUrlChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            // API Key
            Text("API Key")
                .font(.caption)
                .fontWeight(.semibold)
            SecureField("输入 API Key", text: Binding(
                get: { apiKey ?? "" },
                set: { onApiKeyChanged($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
    }
}
