import Foundation

// MARK: - Provider Constants (mirrors Flutter's hermes_service.dart constants)

/// Hermes 官方安装脚本地址。
let kHermesOfficialInstallUrl = "https://hermes-agent.nousresearch.com/install.sh"
/// Hermes 国内镜像安装脚本地址（推荐中国大陆用户使用）。
let kHermesChinaInstallUrl = "https://res1.hermesagent.org.cn/install.sh"
/// GitHub 国内代理，用于 git clone 加速（gitclone.com 为 insteadOf 前缀）。
let kDefaultGithubMirror = "https://gitclone.com/"
/// PyPI 国内镜像（清华大学 TUNA），用于 pip/uv 安装 Python 依赖加速。
let kDefaultPipIndexUrl = "https://pypi.tuna.tsinghua.edu.cn/simple"
let kSlowDownloadProgressThreshold: Double = 0.15
let kSlowDownloadTimeoutSeconds: TimeInterval = 15

let kProviderBaseUrls: [String: String] = [
    "openai": "https://api.openai.com/v1",
    "openrouter": "https://openrouter.ai/api/v1",
    "anthropic": "https://api.anthropic.com/v1",
    "deepseek": "https://api.deepseek.com/v1",
    "google": "https://generativelanguage.googleapis.com/v1beta",
    "groq": "https://api.groq.com/openai/v1",
    "mistral": "https://api.mistral.ai/v1",
    "atlascloud": "https://api.atlascloud.ai/v1",
    "huggingface": "https://router.huggingface.co/v1",
    "xiaomi": "https://api.xiaomimimo.com/v1",
    // 硅基流动：Hermes 端会把所有非一等供应商映射为 `custom`，
    // base_url 必须是 OpenAI 兼容 base（不含 /chat/completions 这种 endpoint 后缀）。
    "siliconflow": "https://api.siliconflow.cn/v1",
    "ollama": "http://localhost:11434/v1",
    "lmstudio": "http://localhost:1234/v1",
    "vllm": "http://localhost:8000/v1",
    "llamacpp": "http://localhost:8080/v1",
]

let kDefaultModelForProvider: [String: String] = [
    "openai": "gpt-4o",
    "openrouter": "anthropic/claude-sonnet-4-20250514",
    "anthropic": "claude-sonnet-4-20250514",
    "deepseek": "deepseek-chat",
    "google": "gemini-2.5-flash",
    "groq": "llama-4-maverick-17b-128e-instruct",
    "mistral": "mistral-large-latest",
    "atlascloud": "deepseek-ai/deepseek-v4-pro",
    "huggingface": "Qwen/Qwen2.5-72B-Instruct",
    "xiaomi": "mi-llm-3.0",
    // 硅基流动默认模型：`Qwen/Qwen3-235B-A22B` 在很多账号下会返回 Model disabled，
    // `zai-org/GLM-4.7` 又是不存在的 id。使用当前 GLM 主推版（5.2 系列）作为默认。
    "siliconflow": "zai-org/GLM-5.2",
    "ollama": "llama3.2",
    "lmstudio": "llama-3.2-3b-instruct",
    "vllm": "llama3.2",
    "llamacpp": "llama3.2",
]

let kProviderDisplayNames: [String: String] = [
    "openai": "OpenAI",
    "openrouter": "OpenRouter",
    "anthropic": "Anthropic",
    "deepseek": "DeepSeek",
    "google": "Google Gemini",
    "groq": "Groq",
    "mistral": "Mistral",
    "atlascloud": "Atlas Cloud",
    "huggingface": "HuggingFace",
    "xiaomi": "XiaoMi",
    "siliconflow": "硅基流动",
    "ollama": "Ollama",
    "lmstudio": "LM Studio",
    "vllm": "vLLM",
    "llamacpp": "llama.cpp",
]

let kProviderIconEmojis: [String: String] = [
    "openai": "🟢",
    "openrouter": "🔄",
    "anthropic": "🟠",
    "deepseek": "🔵",
    "google": "🔷",
    "groq": "⚡",
    "mistral": "💜",
    "atlascloud": "☁️",
    "huggingface": "🤗",
    "xiaomi": "📱",
    "siliconflow": "🔶",
    "ollama": "🦙",
    "lmstudio": "💻",
    "vllm": "🚀",
    "llamacpp": "🦾",
]

/// 内置供应商 id 列表（按显示顺序），对齐 Flutter `kBuiltInProviders`。
let kBuiltInProviders: [String] = [
    "openai",
    "anthropic",
    "google",
    "deepseek",
    "openrouter",
    "groq",
    "mistral",
    "atlascloud",
    "huggingface",
    "xiaomi",
    "siliconflow",
    "ollama",
    "lmstudio",
    "vllm",
    "llamacpp",
]

/// 在 Hermes 中需要用 `provider: custom` 写入的 DeskMate 预设。
///
/// 原因：Hermes 一等供应商（见其 `cli-config.yaml.example`）只有
/// `openrouter` / `anthropic` / `openai-codex` / `copilot` / `gemini` / `custom`，
/// 且 `ollama` / `vllm` / `llamacpp` 已是 `custom` 的别名。
/// 因此 DeskMate 暴露的 `openai` / `deepseek` / `groq` / `mistral` /
/// `atlascloud` / `siliconflow` 必须走 `custom` + `base_url` 通路。
/// API key 仍按 DeskMate 预设 id 落到对应的 env 变量（如 `SILICONFLOW_API_KEY`）：
/// Hermes 对 custom provider 会通过 base_url 主机名自动推导 `<VENDOR>_API_KEY`。
let kProvidersAsCustomAlias: Set<String> = [
    "openai",
    "deepseek",
    "groq",
    "mistral",
    "atlascloud",
    "siliconflow",  // 硅基流动：非 Hermes 一等
]

/// 给定 Hermes 写入的 base_url，反查 DeskMate 预设 id。
///
/// 用于在 `load()` 时把 `provider: custom` + `base_url` 还原成 UI 友好的预设名。
func kProviderPresetByBaseUrl(_ baseUrl: String) -> String? {
    for (key, value) in kProviderBaseUrls {
        if value == baseUrl { return key }
    }
    return nil
}

// MARK: - OnboardingModel

/// Onboarding flow data model.
///
/// Represents the state of the 3-step onboarding wizard:
///   1. 环境检测 (Environment Check)
///   2. 安装引擎 (Install Engine)
///   3. 欢迎引导 (Welcome Guide)
struct OnboardingModel {
    // 0-based index of the current step
    var currentStep: Int = 0
    var totalSteps: Int = 3
    var steps: [OnboardingStep] = []

    // Step 1: Environment Check
    var isEnvironmentReady: Bool = false
    var isCheckingEnvironment: Bool = false
    var environmentCheckItems: [EnvironmentCheckItem] = []
    var environmentCheckSummary: String?
    var hermesHome: String?
    var hermesInstalled: Bool = false
    var hermesConfigured: Bool = false
    var hermesHasApiKey: Bool = false
    var hermesHasModelConfigured: Bool = false
    var failedCheckIds: [String] = []

    // Step 2: Install Engine
    var downloadProgress: Double = 0.0
    var downloadSpeed: String = "-- MB/s"
    var estimatedTime: String = "-- s"
    var funFact: String = ""
    var installStageLabel: String = ""
    var isInstalling: Bool = false
    var isInstallFailed: Bool = false
    var installError: String?
    var isDownloadSlow: Bool = false
    /// 慢速下载后提示用户切换到镜像的横幅。
    var showMirrorPrompt: Bool = false
    /// 开始安装前询问使用国内镜像还是官方地址的 Alert。
    var showInitialMirrorPrompt: Bool = false
    var isConfiguringMirror: Bool = false
    var mirrorUrl: String?
    var installStartTime: Date?
    var currentDownloadingItem: String?
    /// 实时安装日志尾部（多行），供 UI 展示真实输出，替代假进度条观感。
    var installLogTail: String?

    // Step 3: Welcome Guide
    var selectedAiModel: String? = "auto"
    var aiModelOptions: [AiModelOption] = [
        AiModelOption(id: "auto", name: ""),
        AiModelOption(id: "custom", name: "")
    ]
    var petPersonalityFile: String?

    // SOUL.md 对话风格/身份标识
    /// 当前 ~/.hermes/SOUL.md 的完整内容（空字符串表示文件不存在）。
    var soulFileContent: String? = nil
    /// 用户选择用于替换 SOUL.md 的本地 .md 文件 URL。
    var soulFileURL: URL? = nil
    /// 是否正在读取或替换 SOUL.md。
    var isSoulFileLoading: Bool = false
    /// SOUL.md 读取/替换失败的错误信息。
    var soulFileError: String? = nil
    /// 是否显示 SOUL.md 内容预览弹窗。
    var showSoulPreview: Bool = false

    var modelProviderType: String = "builtin"
    var selectedBuiltInProvider: String?
    var builtInProviders: [BuiltInModelProvider] = []
    var customModelId: String?
    var customModelUrl: String?
    var customProviderName: String?
    var selectedBuiltInModelId: String?
    var apiKey: String?

    // Completion
    var isCompleted: Bool = false
    var isSaving: Bool = false
    /// 完成 onboarding 过程中出现的错误（如 Gateway 启动失败）。
    var onboardingError: String? = nil

    // MARK: Computed Properties

    /// Whether the environment check has been run at least once (regardless of result).
    var hasRunEnvironmentCheck: Bool {
        !environmentCheckItems.isEmpty && !isCheckingEnvironment
    }

    /// Whether the user can advance from the current step.
    var canAdvance: Bool {
        if currentStep == 0 { return isEnvironmentReady || hasRunEnvironmentCheck }
        if currentStep == 1 { return downloadProgress >= 1.0 && !isInstalling && !isInstallFailed }
        if currentStep == 2 { return isWelcomeStepValid }
        return true
    }

    /// Whether the welcome step (step 2) form is valid.
    var isWelcomeStepValid: Bool {
        if modelProviderType == "builtin" {
            return selectedBuiltInProvider != nil && apiKey != nil && !(apiKey?.isEmpty ?? true)
        }
        return customModelId != nil && !(customModelId?.isEmpty ?? true) &&
               customModelUrl != nil && !(customModelUrl?.isEmpty ?? true) &&
               apiKey != nil && !(apiKey?.isEmpty ?? true)
    }
}

// MARK: - OnboardingStep

/// Metadata for a single onboarding step.
struct OnboardingStep {
    let index: Int
    let label: String
    var description: String? = nil
}

// MARK: - AiModelOption

/// An AI model choice shown in the dropdown.
struct AiModelOption {
    let id: String
    let name: String
}

// MARK: - BuiltInModelProvider

/// A built-in model provider (e.g. OpenAI, Anthropic).
struct BuiltInModelProvider: Identifiable {
    let id: String
    let name: String
    let iconEmoji: String
}

// MARK: - EnvironmentCheckItem

/// A single environment check item displayed in step 1.
struct EnvironmentCheckItem: Identifiable {
    /// Unique identifier, e.g. 'sys_ver', 'network'.
    let id: String

    /// Whether the check has completed and passed.
    var isPassed: Bool = false

    /// Whether the check is still in progress.
    var isChecking: Bool = false

    /// Dynamic detail text, e.g. "macOS 14.5", "v2.4.1", "Apple M2".
    var detail: String?

    /// Display text for the check result, e.g. "通过", "充足", "硬件加速可用".
    var statusText: String?
}
