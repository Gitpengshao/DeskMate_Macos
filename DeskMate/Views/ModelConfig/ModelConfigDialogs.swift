import SwiftUI

// MARK: - Add / Edit Main Model Dialog

/// 新增 / 编辑主模型对话框。
/// 对齐 Flutter `ModelConfigPage._showAddModelDialog` 的语义。
struct AddMainModelSheet: View {
    @ObservedObject var viewModel: ModelConfigViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: String = "openai"
    @State private var modelId: String = ""
    @State private var apiKey: String = ""
    @State private var customBaseUrl: String = ""
    @State private var providerType: ModelProviderType = .builtin
    @State private var isSubmitting: Bool = false
    @State private var showError: Bool = false
    @State private var errorText: String = ""

    private let onSaved: (() -> Void)?

    init(viewModel: ModelConfigViewModel, onSaved: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSaved = onSaved

        // 初始填充当前配置
        let current = viewModel.model
        _selectedProvider = State(initialValue: current.providerKey.isEmpty
                                   ? "openai"
                                   : current.providerKey)
        _modelId = State(initialValue: current.modelId)
        _apiKey = State(initialValue: current.apiKey ?? "")
        _customBaseUrl = State(initialValue: current.baseUrl ?? "")
        _providerType = State(initialValue: current.providerType)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MCPalette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    providerTypePicker
                    providerPicker
                    if providerType == .custom {
                        customBaseUrlField
                    }
                    modelIdField
                    apiKeyField
                    hint
                }
                .padding(20)
            }
            Divider().background(MCPalette.border)
            footer
        }
        .frame(width: 480, height: 560)
        .background(MCPalette.bgBase)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedProvider.hasPrefix("custom:") {
                providerType = .custom
            }
        }
    }

    // MARK: Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MCPalette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.model.hasModel ? "编辑主模型" : "添加主模型")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MCPalette.textPrimary)
                Text("主模型用于所有未指定专用模型的任务")
                    .font(.system(size: 11))
                    .foregroundColor(MCPalette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var providerTypePicker: some View {
        HStack(spacing: 8) {
            Text("供应商类型")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
                .frame(width: 88, alignment: .leading)
            HStack(spacing: 8) {
                ProviderTypeToggleChip(
                    label: "内置供应商",
                    isSelected: providerType == .builtin,
                    onTap: { providerType = .builtin }
                )
                ProviderTypeToggleChip(
                    label: "自定义（兼容 OpenAI）",
                    isSelected: providerType == .custom,
                    onTap: { providerType = .custom }
                )
            }
            Spacer()
        }
    }

    private var providerPicker: some View {
        HStack(spacing: 10) {
            Text("供应商")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
                .frame(width: 88, alignment: .leading)
            Menu {
                ForEach(kBuiltInProviders, id: \.self) { p in
                    Button(action: { selectedProvider = p }) {
                        Label(
                            kProviderDisplayNames[p] ?? p,
                            systemImage: providerType == .builtin
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            } label: {
                HStack {
                    Text(
                        providerType == .custom
                            ? "自定义"
                            : (kProviderDisplayNames[selectedProvider] ?? selectedProvider)
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MCPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(MCPalette.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MCPalette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MCPalette.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 280)
            .disabled(providerType == .custom)
            .opacity(providerType == .custom ? 0.4 : 1.0)
            Spacer()
        }
    }

    private var customBaseUrlField: some View {
        FormField(label: "Base URL", placeholder: "https://api.example.com/v1", text: $customBaseUrl)
    }

    private var modelIdField: some View {
        FormField(
            label: "模型 ID",
            placeholder: providerType == .custom
                ? "my-model-name"
                : (kDefaultModelForProvider[selectedProvider] ?? "gpt-4o"),
            text: $modelId
        )
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            FormField(
                label: "API Key",
                placeholder: "sk-...",
                text: $apiKey,
                isSecure: true
            )
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                Text("API Key 将写入 `~/.hermes/.env`，不会明文存放在 config.yaml")
                    .font(.system(size: 10.5))
            }
            .foregroundColor(MCPalette.textTertiary)
            .padding(.leading, 96)
        }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(MCPalette.textTertiary)
            Text("保存后会自动重启 Gateway 使新模型生效。")
                .font(.system(size: 11))
                .foregroundColor(MCPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            if showError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(MCPalette.textPrimary)
                    Text(errorText)
                        .font(.system(size: 11.5))
                        .foregroundColor(MCPalette.textPrimary)
                }
            }
            Spacer()
            Button(action: { dismiss() }) {
                Text("取消")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MCPalette.textSecond)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MCPalette.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: submit) {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .colorScheme(.dark)
                    }
                    Text(isSubmitting ? "保存中..." : (viewModel.model.hasModel ? "保存" : "添加"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MCPalette.inverseInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(canSubmit ? MCPalette.inverse : MCPalette.inverse.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Logic

    private var canSubmit: Bool {
        !modelId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        showError = false

        let provider: String
        let baseUrl: String?
        if providerType == .custom {
            provider = "custom"
            baseUrl = customBaseUrl.trimmingCharacters(in: .whitespaces)
        } else {
            provider = selectedProvider
            baseUrl = nil
        }

        Task {
            await viewModel.updateCurrentModel(
                provider: provider,
                model: modelId.trimmingCharacters(in: .whitespaces),
                baseUrl: (baseUrl?.isEmpty == true) ? nil : baseUrl,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
            isSubmitting = false
            onSaved?()
            dismiss()
        }
    }
}

// MARK: - Form Field

/// 表单字段（Label + Input），统一黑白样式。
struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
                .frame(width: 88, alignment: .leading)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(MCPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MCPalette.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MCPalette.border, lineWidth: 1)
            )
            Spacer()
        }
    }
}

// MARK: - Edit Auxiliary Task Dialog

/// 编辑辅助任务对话框。
struct EditAuxiliarySheet: View {
    @ObservedObject var viewModel: ModelConfigViewModel
    let task: AuxiliaryTaskType
    @Environment(\.dismiss) private var dismiss

    @State private var useOverride: Bool = false
    @State private var selectedProvider: String = "openai"
    @State private var modelId: String = ""
    @State private var apiKey: String = ""
    @State private var customBaseUrl: String = ""
    @State private var providerType: ModelProviderType = .builtin
    @State private var isSubmitting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MCPalette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    taskInfo
                    modePicker
                    if useOverride {
                        providerTypePicker
                        providerPicker
                        if providerType == .custom {
                            FormField(
                                label: "Base URL",
                                placeholder: "https://api.example.com/v1",
                                text: $customBaseUrl
                            )
                        }
                        FormField(
                            label: "模型 ID",
                            placeholder: kDefaultModelForProvider[selectedProvider] ?? "",
                            text: $modelId
                        )
                        FormField(
                            label: "API Key",
                            placeholder: "（留空使用 .env 中的值）",
                            text: $apiKey,
                            isSecure: true
                        )
                    }
                    hint
                }
                .padding(20)
            }
            Divider().background(MCPalette.border)
            footer
        }
        .frame(width: 480, height: useOverride ? 620 : 320)
        .background(MCPalette.bgBase)
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: task.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MCPalette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置 \(task.displayName) 模型")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MCPalette.textPrimary)
                Text("默认跟随主模型；设置专用模型可降低成本或支持视觉等特殊能力")
                    .font(.system(size: 11))
                    .foregroundColor(MCPalette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var taskInfo: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(MCPalette.textTertiary)
            Text(task.description)
                .font(.system(size: 11))
                .foregroundColor(MCPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模型模式")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
            HStack(spacing: 8) {
                ProviderTypeToggleChip(
                    label: "跟随主模型",
                    isSelected: !useOverride,
                    onTap: { useOverride = false }
                )
                ProviderTypeToggleChip(
                    label: "使用专用模型",
                    isSelected: useOverride,
                    onTap: { useOverride = true }
                )
                Spacer()
            }
        }
    }

    private var providerTypePicker: some View {
        HStack(spacing: 8) {
            Text("供应商类型")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
                .frame(width: 88, alignment: .leading)
            HStack(spacing: 8) {
                ProviderTypeToggleChip(
                    label: "内置供应商",
                    isSelected: providerType == .builtin,
                    onTap: { providerType = .builtin }
                )
                ProviderTypeToggleChip(
                    label: "自定义（兼容 OpenAI）",
                    isSelected: providerType == .custom,
                    onTap: { providerType = .custom }
                )
            }
            Spacer()
        }
    }

    private var providerPicker: some View {
        HStack(spacing: 10) {
            Text("供应商")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MCPalette.textSecond)
                .frame(width: 88, alignment: .leading)
            Menu {
                ForEach(kBuiltInProviders, id: \.self) { p in
                    Button(action: { selectedProvider = p }) {
                        Label(
                            kProviderDisplayNames[p] ?? p,
                            systemImage: providerType == .builtin
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            } label: {
                HStack {
                    Text(
                        providerType == .custom
                            ? "自定义"
                            : (kProviderDisplayNames[selectedProvider] ?? selectedProvider)
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MCPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(MCPalette.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MCPalette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MCPalette.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 280)
            .disabled(providerType == .custom)
            .opacity(providerType == .custom ? 0.4 : 1.0)
            Spacer()
        }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(MCPalette.textTertiary)
            Text("保存后会自动重启 Gateway 让配置生效。")
                .font(.system(size: 11))
                .foregroundColor(MCPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: { dismiss() }) {
                Text("取消")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MCPalette.textSecond)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MCPalette.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: submit) {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .colorScheme(.dark)
                    }
                    Text(isSubmitting ? "保存中..." : "保存")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MCPalette.inverseInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(canSubmit ? MCPalette.inverse : MCPalette.inverse.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Logic

    private var canSubmit: Bool {
        if !useOverride { return true }
        return !modelId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func prefill() {
        let current = viewModel.model.getAuxiliary(task)
        useOverride = !current.isAuto
        if !current.isAuto {
            providerType = (current.provider == "custom") ? .custom : .builtin
            selectedProvider = current.provider ?? "openai"
            modelId = current.model ?? ""
            apiKey = current.apiKey ?? ""
            customBaseUrl = current.baseUrl ?? ""
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true

        Task {
            if !useOverride {
                await viewModel.resetAuxiliaryTask(task)
            } else {
                let provider: String
                let baseUrl: String?
                if providerType == .custom {
                    provider = "custom"
                    baseUrl = customBaseUrl.trimmingCharacters(in: .whitespaces)
                } else {
                    provider = selectedProvider
                    baseUrl = nil
                }
                await viewModel.setAuxiliaryModel(
                    task: task,
                    provider: provider,
                    model: modelId.trimmingCharacters(in: .whitespaces),
                    baseUrl: (baseUrl?.isEmpty == true) ? nil : baseUrl,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )
            }
            isSubmitting = false
            dismiss()
        }
    }
}
