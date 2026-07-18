# DeskMate for macOS

一款专为 macOS 打造的桌面 AI 伴侣应用。DeskMate 在桌面右上角以灵动岛 / 桌宠形态常驻，随时响应语音或快捷键唤醒，提供 AI 对话、任务看板、智能体管理、工作区浏览等能力。

---

## 功能特性

- **桌面宠物 & 灵动岛**
  - 可爱的松鼠桌宠常驻桌面，支持 idle、run、work、think、sleep、sick 等多种动画状态。
  - 点击菜单栏图标或灵动岛即可展开主控制台。

- **AI 对话控制台**
  - 基于 Hermes Gateway 提供流式 AI 对话。
  - 支持会话历史、新建会话、会话搜索、推理强度设置。
  - 支持选择工作区、图片附件、语音输入。
  - 工具调用结果可折叠/展开，文件变更自动高亮并显示 `+N/-N` 行数。

- **任务看板（Task Board）**
  - 2D 办公室场景式任务管理。
  - 以智能体工位、办公区布局呈现任务状态。

- **智能体 & 记忆管理**
  - 智能体（Agent）配置与能力管理。
  - 长期记忆文件管理。

- **模型 & Gateway 配置**
  - 模型参数配置页面。
  - Gateway 启动、状态监控与连接管理。

- **引导式 onboarding**
  - 首次启动自动检测系统版本、网络、Python、Hermes 引擎、API Key、模型配置。
  - 未完成环境配置前不会进入主控制台。

- **单实例运行**
  - 应用仅允许单个实例；重复启动会自动激活已有窗口。

---

## 技术栈

- **语言 / 框架**：Swift 6 + SwiftUI
- **开发工具**：Xcode 26.2+
- **架构**：MVVM，ViewModel 单例通过 `@ObservedObject` 注入
- **依赖管理**：Swift Package Manager
  - [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI) — Markdown 渲染
  - [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) — 代码编辑 / 文件预览
- **后端引擎**：Hermes Agent Gateway（本地 Python 环境）

---

## 项目结构

```
DeskMate/
├── DeskMate/
│   ├── App/                    # App 入口与生命周期
│   ├── Assets.xcassets/        # 应用图标与宠物/场景素材
│   ├── SceneAssets.xcassets/   # 任务看板场景素材
│   ├── Core/Constants/         # 常量配置
│   ├── Dependencies/           # 内嵌第三方库（DynamicNotchKit 等）
│   ├── Managers/               # 窗口、灵动岛、权限、语音快捷键等管理器
│   ├── Models/                 # 数据模型
│   ├── Services/               # 网络、Gateway、Hermes、Git、文件状态等服务
│   ├── Utils/                  # 聊天内容解析、日志、Sprite 切片等工具
│   ├── ViewModels/             # 业务逻辑与状态管理
│   └── Views/                  # SwiftUI 视图
│       ├── AIChat/             # AI 对话页面
│       ├── Main/               # 主控制台与设置
│       ├── Onboarding/         # 首次引导
│       ├── TaskBoard/          # 任务看板
│       ├── AgentManagement/    # 智能体管理
│       ├── MemoryManagement/   # 记忆管理
│       ├── ModelConfig/        # 模型配置
│       ├── GatewayConfig/      # Gateway 配置
│       └── WorkspaceExplorer/  # 工作区文件浏览器
├── DeskMate.xcodeproj/         # Xcode 工程
├── gif/                        # 演示 GIF
├── script/                     # 辅助脚本
└── log/                        # 运行日志
```

---

## 演示

### 灵动岛与桌宠

![灵动岛与桌宠演示](gif/20260718152559_rec_.gif)

> 桌宠悬浮在 Xcode 编辑器上方，灵动岛展开后可快速进入控制台。

### AI 对话控制台

![AI 对话控制台演示](gif/20260718152729_rec_.gif)

> 主控制台包含会话列表、AI 对话区域、推理强度与 Gateway 状态指示。

---

## 运行要求

- macOS 15+（开发环境为 macOS 26.3）
- Xcode 26.2+
- Swift 6
- 已安装 Python 3（用于 Hermes 引擎）
- 已配置 Hermes 环境：`~/.hermes/`

## 本地运行

1. 克隆仓库：

```bash
git clone git@github.com:Gitpengshao/DeskMate_Macos.git
cd DeskMate_Macos
```

2. 使用 Xcode 打开工程：

```bash
open DeskMate.xcodeproj
```

3. 等待 Swift Package Manager 依赖解析完成后，选择目标 Mac 设备，按 `Cmd + R` 运行。

---

## 使用说明

1. 首次启动会进入 **Onboarding** 流程，按提示完成：
   - 系统版本 / 网络 / Python 检测
   - Hermes 引擎安装与配置
   - API Key 与模型配置

2. 环境就绪后，点击菜单栏 **DeskMate** 图标或桌面灵动岛，打开主控制台。

3. 快捷键（默认）：`⌃Y` 可触发语音快捷指令。

---

## 未签名应用「已损坏」提示

若通过非 App Store 渠道获取 DeskMate.app 后，macOS 弹出「已损坏，无法打开」「无法验证开发者」或「Apple 无法检查其是否包含恶意软件」等提示，通常是 Gatekeeper 的隔离标记（扩展属性）导致，并非应用本身损坏。

处理步骤可参考：[macOS 未签名应用「已损坏」问题解决方案](https://juejin.cn/post/7602512226999418930)

核心操作如下：

1. **开启「任何来源」**（只需执行一次）：

   ```bash
   sudo spctl --master-disable
   ```

   输入登录密码后，前往「系统设置 → 隐私与安全性」，将安全性设置为「任何来源」。

2. **清除应用扩展属性**：

   将 DeskMate.app 拖入「应用程序」文件夹后，执行：

   ```bash
   xattr -cr "/Applications/DeskMate.app"
   ```

3. **右键打开应用**：

   右键点击 DeskMate.app → 选择「打开」→ 再次点击「打开」即可运行。

> 注意：DeskMate 当前未进行 Apple 开发者签名，仅供个人学习与非商业用途使用，不可用于商业分发或商用场景。

---

## 注意事项

- 本项目为单实例应用，请勿使用 `open -n` 强制多开。
- Gateway 启动命令使用 `gateway run --replace`，会自动替换旧实例。
- 部分状态变更通过 `@MainActor Task` 提交，避免在 SwiftUI `body` 更新期间修改状态。

---

## License

MIT License

---

> 由 Swift + SwiftUI 构建，搭配 Hermes AI 引擎，让 macOS 桌面多一位聪明的小伙伴。
