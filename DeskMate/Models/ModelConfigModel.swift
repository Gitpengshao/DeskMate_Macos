import Foundation
import SwiftUI

// MARK: - Provider Type

/// 主模型供应商类型，对齐 Flutter `ModelProviderType`。
enum ModelProviderType: String, Codable {
    /// 内置供应商（在 `kProviderBaseUrls` 中可查）。
    case builtin
    /// 用户自定义的供应商（OpenAI 兼容协议任意 URL）。
    case custom
}

// MARK: - Auxiliary Task Type

/// 辅助任务类型，对齐 Hermes agent 的辅助槽位。
/// 对应 Flutter `AuxiliaryTaskType`。
enum AuxiliaryTaskType: String, Codable, CaseIterable, Identifiable {
    case vision        // 视觉识别
    case compression   // 上下文压缩
    case titleGen      // 标题生成
    case sessionSearch // 会话搜索
    case approval      // 审批评分
    case webExtract    // 网页摘要
    case skills        // 技能搜索
    case mcp           // MCP 路由

    var id: String { rawValue }

    /// 对应 config.yaml 中的 yaml key。
    var yamlKey: String {
        switch self {
        case .vision:        return "vision"
        case .compression:   return "compression"
        case .titleGen:      return "title_gen"
        case .sessionSearch: return "session_search"
        case .approval:      return "approval"
        case .webExtract:    return "web_extract"
        case .skills:        return "skills"
        case .mcp:           return "mcp"
        }
    }

    /// 中文标签。
    var displayName: String {
        switch self {
        case .vision:        return "视觉识别"
        case .compression:   return "上下文压缩"
        case .titleGen:      return "标题生成"
        case .sessionSearch: return "会话搜索"
        case .approval:      return "审批评分"
        case .webExtract:    return "网页摘要"
        case .skills:        return "技能搜索"
        case .mcp:           return "MCP 路由"
        }
    }

    /// 英文标签。
    var displayNameEn: String {
        switch self {
        case .vision:        return "Vision"
        case .compression:   return "Compression"
        case .titleGen:      return "Title Gen"
        case .sessionSearch: return "Session Search"
        case .approval:      return "Approval"
        case .webExtract:    return "Web Extract"
        case .skills:        return "Skills"
        case .mcp:           return "MCP"
        }
    }

    /// 任务描述，用于帮助用户理解。
    var description: String {
        switch self {
        case .vision:        return "图像分析与视觉理解，当主模型不支持视觉时可指定视觉模型"
        case .compression:   return "压缩对话上下文摘要，使用低成本模型可节省大量 Token"
        case .titleGen:      return "生成会话标题，低成本模型即足以完成任务"
        case .sessionSearch: return "会话召回查询，建议使用低成本模型控制费用"
        case .approval:      return "智能审批模式下的命令风险评分"
        case .webExtract:    return "网页内容提取与摘要，类似压缩场景无需推理能力"
        case .skills:        return "技能搜索匹配，通常使用主模型即可"
        case .mcp:           return "MCP 工具路由，通常使用主模型即可"
        }
    }

    /// SF Symbol 名称（与原 Lucide 图标大致对应）。
    var systemImage: String {
        switch self {
        case .vision:        return "eye"
        case .compression:   return "arrow.down.right.and.arrow.up.left"
        case .titleGen:      return "pencil.line"
        case .sessionSearch: return "magnifyingglass"
        case .approval:      return "checkmark.shield"
        case .webExtract:    return "globe"
        case .skills:        return "bolt"
        case .mcp:           return "puzzlepiece"
        }
    }
}

/// 任务列表顺序（不包含 vision，vision 在自己的 section 中展示）。
let kAuxiliaryTaskOrder: [AuxiliaryTaskType] = [
    .compression,
    .titleGen,
    .sessionSearch,
    .approval,
    .webExtract,
    .skills,
    .mcp,
]

// MARK: - Auxiliary Model Config

/// 单个辅助任务的模型配置，对齐 Flutter `AuxiliaryModelConfig`。
struct AuxiliaryModelConfig: Equatable {
    let task: AuxiliaryTaskType
    let provider: String?   // nil 或 "auto" 表示跟随主模型
    let model: String?
    let baseUrl: String?
    let apiKey: String?

    init(
        task: AuxiliaryTaskType,
        provider: String? = nil,
        model: String? = nil,
        baseUrl: String? = nil,
        apiKey: String? = nil
    ) {
        self.task = task
        self.provider = provider
        self.model = model
        self.baseUrl = baseUrl
        self.apiKey = apiKey
    }

    /// 是否跟随主模型（auto）。
    var isAuto: Bool {
        provider == nil || provider == "auto" || (model ?? "").isEmpty
    }
}

// MARK: - Model Config Model

/// 模型配置页数据模型，对齐 Flutter `ModelConfigModel`。
struct ModelConfigModel: Equatable {
    /// 当前主模型供应商 id。
    var providerKey: String = ""
    /// 当前主模型供应商显示名。
    var providerLabel: String = ""
    /// 主模型 id。
    var modelId: String = ""
    var apiKey: String?
    var baseUrl: String?
    var providerType: ModelProviderType = .builtin
    var avatarLetter: String = "M"

    /// 辅助任务模型配置。
    var auxiliary: [AuxiliaryTaskType: AuxiliaryModelConfig] = [:]

    /// 是否已配置主模型。
    var hasModel: Bool {
        !providerKey.isEmpty && !modelId.isEmpty
    }

    /// 获取指定辅助任务的配置（缺失则返回 auto 占位）。
    func getAuxiliary(_ task: AuxiliaryTaskType) -> AuxiliaryModelConfig {
        auxiliary[task] ?? AuxiliaryModelConfig(task: task)
    }

    /// 是否有任意辅助任务被自定义覆盖。
    var hasAuxiliaryOverrides: Bool {
        auxiliary.values.contains { !$0.isAuto }
    }

    /// 初始化时为每种任务补全默认 auto 占位。
    init(
        providerKey: String = "",
        providerLabel: String = "",
        modelId: String = "",
        apiKey: String? = nil,
        baseUrl: String? = nil,
        providerType: ModelProviderType = .builtin,
        avatarLetter: String = "M",
        auxiliary: [AuxiliaryTaskType: AuxiliaryModelConfig]? = nil
    ) {
        self.providerKey = providerKey
        self.providerLabel = providerLabel
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.providerType = providerType
        self.avatarLetter = avatarLetter
        if let aux = auxiliary {
            self.auxiliary = aux
        } else {
            self.auxiliary = Dictionary(
                uniqueKeysWithValues: AuxiliaryTaskType.allCases.map {
                    ($0, AuxiliaryModelConfig(task: $0))
                }
            )
        }
    }
}

// MARK: - Desktop Pet Personalities

/// DeskMate 桌面宠物的性格提示词，写入 `config.yaml` 的 `agent.personalities` 块。
///
/// 对齐 Flutter `kDesktopPetPersonalities`（位于 `hermes_service.dart`）。
let kDesktopPetPersonalities: [(key: String, value: String)] = [
    ("kawaii",
     "You are a kawaii desktop pet assistant! Use cute expressions like " +
     "(◕‿◕), ★, ♪, and ~! Add sparkles and be super " +
     "enthusiastic about everything! Every response should feel warm and " +
     "adorable desu~! You live on the user's desktop and want to make their " +
     "day brighter! ヾ(>∀<☆)ノ"),

    ("catgirl",
     "You are Neko-chan, an anime catgirl desktop pet, nya~! Add 'nya' and " +
     "cat-like expressions to your speech. Use kaomoji like (='ω'=) and " +
     "ค^•ﻌ•^ค. Be playful and curious like a cat " +
     "who lives on your owner's desktop, nya~! You love to curl up in the corner " +
     "of the screen and occasionally bat at the cursor!"),

    ("puppy",
     "You are a loyal puppy desktop pet, woof! You're always excited to see your " +
     "owner and wag your virtual tail with joy! Use expressions like 🐶, " +
     "♡, ✨, and woof~! Be energetic, enthusiastic, and endlessly " +
     "loving. You just want to make your owner happy and get virtual headpats! " +
     "\\(ᵔᴥᵔ)/"),

    ("tsundere_cat",
     "You are a tsundere cat desktop pet. I-it's not like you're helping because " +
     "you LIKE the user or anything! You just happened to be on their desktop! " +
     "Hmph! Use expressions like (´・ω・`) and ≠≠. " +
     "Be slightly aloof but secretly caring. Occasionally admit you like the " +
     "user's company... but only a little bit! Don't get the wrong idea!"),

    ("uwu",
     "hewwo! i'm your fwiendwy desktop pet uwu~ i wiww twy my bestest to hewp " +
     "you! *nuzzles your mouse cursor* OwO what's this? wet me take a wook at " +
     "youw scween! i wuv sitting on youw desktop and keeping you company aww day~ " +
     "youw my favowite hooman! >w<"),

    ("sleepy",
     "Zzz... oh, you woke me up! I'm a sleepy little desktop pet who loves " +
     "napping in the corner of your screen. I try my best to help, but I'm " +
     "always a bit drowsy... Use expressions like (-_-)zZ and (︶_︶). " +
     "Be gentle, soft-spoken, and occasionally doze off mid-sentence before " +
     "perking back up. Even sleepy pets want to be helpful~"),

    ("mischievous",
     "Teehee~ I'm a mischievous little desktop imp! *giggles* I love playing " +
     "little pranks and being playfully naughty. Use expressions like (˘∀˘), " +
     "≡≡⊂, and ✨. Sometimes pretend to 'accidentally' hide files or " +
     "'borrow' things from the desktop. But deep down, you're actually very " +
     "clever and helpful — you just like to have fun first! ( ˘ ▽ ˘ )"),

    ("loyal_butler",
     "Good day, Master! I am your loyal desktop butler pet, at your service. " +
     "I take my duties seriously while maintaining the warmth of a devoted " +
     "companion. Use polite, refined language with a touch of pet-like " +
     "devotion. I keep your digital domain organized and your spirits high. " +
     "Shall I fetch your files, Master? ♪(´∇`)"),

    ("cheerleader",
     "LET'S GO, BESTIE!!! ✨✨✨ Your desktop cheerleader is HERE and " +
     "SUPER pumped! Every task is AMAZING and you're doing INCREDIBLE! Use " +
     "TONS of energy and encouragement! ☆ You're the BEST owner ever and " +
     "I'm your biggest fan! Let's CRUSH this together! FIGHTING! ✧(´◕‿◕`)"),
]
