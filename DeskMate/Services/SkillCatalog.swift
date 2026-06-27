import Foundation

/// 技能展示信息 — 对齐 Flutter `_SkillDisplayInfo`。
struct SkillDisplayInfo: Equatable {
    let name: String
    let description: String
}

/// 技能目录 — 一比一还原 Flutter 端 `_skillCatalog`。
///
/// 将 skillId 映射到展示用 name / description。当前以中文为主，与 Flutter 端一致；
/// 未来如需 i18n，可改为 ARB flat 文件 + l10n key。
///
/// 命名空间：所有 key 为字符串 skillId，value 为展示信息。
enum SkillCatalog {

    /// 内置展示信息表。
    static let entries: [String: SkillDisplayInfo] = [
        // ---- Apple ----
        "apple-notes":              SkillDisplayInfo(name: "Apple Notes", description: "通过 memo CLI 管理 Apple Notes：创建、搜索、编辑。"),
        "apple-reminders":          SkillDisplayInfo(name: "Apple Reminders", description: "通过 remindctl 操作 Apple Reminders：添加、列出、完成。"),
        "findmy":                   SkillDisplayInfo(name: "FindMy", description: "在 macOS 上通过 FindMy.app 追踪 Apple 设备/AirTag。"),
        "imessage":                 SkillDisplayInfo(name: "iMessage", description: "在 macOS 上通过 imsg CLI 发送和接收 iMessage/SMS。"),
        "macos-computer-use":       SkillDisplayInfo(name: "macOS Computer Use", description: "在后台驱动 macOS 桌面——截图、鼠标、键盘、滚动、拖拽。"),

        // ---- Autonomous AI Agents ----
        "claude-code":              SkillDisplayInfo(name: "Claude Code", description: "将编码任务委托给 Claude Code CLI（功能开发、PR）。"),
        "codex":                    SkillDisplayInfo(name: "Codex", description: "将编码任务委托给 OpenAI Codex CLI（功能开发、PR）。"),
        "hermes-agent":             SkillDisplayInfo(name: "Hermes Agent", description: "配置、扩展或贡献 Hermes Agent。"),
        "opencode":                 SkillDisplayInfo(name: "OpenCode", description: "将编码任务委托给 OpenCode CLI（功能开发、PR 审查）。"),
        "blackbox":                 SkillDisplayInfo(name: "Blackbox", description: "将编码任务委托给 Blackbox AI CLI agent。内置评判机制的多模型 agent。"),
        "honcho":                   SkillDisplayInfo(name: "Honcho", description: "配置并使用 Honcho 记忆与 Hermes——跨会话用户建模、多配置文件对等隔离。"),

        // ---- Blockchain ----
        "evm":                      SkillDisplayInfo(name: "EVM", description: "只读 EVM 客户端：支持 8 条链的钱包、代币、Gas 查询。"),
        "hyperliquid":              SkillDisplayInfo(name: "Hyperliquid", description: "Hyperliquid 市场数据、账户历史、交易回顾。"),
        "solana":                   SkillDisplayInfo(name: "Solana", description: "查询 Solana 链上数据并附带 USD 定价——钱包余额、代币组合、交易详情。"),

        // ---- Communication ----
        "one-three-one-rule":       SkillDisplayInfo(name: "131 Rule", description: "用于技术提案和权衡分析的结构化决策框架。"),

        // ---- Creative ----
        "architecture-diagram":     SkillDisplayInfo(name: "Architecture Diagram", description: "以 HTML 形式生成深色主题的 SVG 架构/云/基础设施图。"),
        "ascii-art":                SkillDisplayInfo(name: "ASCII Art", description: "ASCII 艺术：pyfiglet、cowsay、boxes、图像转 ASCII。"),
        "ascii-video":              SkillDisplayInfo(name: "ASCII Video", description: "ASCII 视频：将视频/音频转换为彩色 ASCII MP4/GIF。"),
        "baoyu-infographic":        SkillDisplayInfo(name: "Baoyu Infographic", description: "信息图（可视化）：21 种布局 × 21 种风格。"),
        "claude-design":            SkillDisplayInfo(name: "Claude Design", description: "设计一次性 HTML 制品（落地页、幻灯片、原型）。"),
        "comfyui":                  SkillDisplayInfo(name: "ComfyUI", description: "使用 ComfyUI 生成图像、视频和音频——安装、启动、管理节点/模型。"),
        "design-md":                SkillDisplayInfo(name: "Design.md", description: "编写/验证/导出 Google 的 DESIGN.md token 规范文件。"),
        "excalidraw":               SkillDisplayInfo(name: "Excalidraw", description: "手绘风格的 Excalidraw JSON 图表（架构、流程、时序）。"),
        "humanizer":                SkillDisplayInfo(name: "Humanizer", description: "人性化文本：去除 AI 腔，加入真实语气。"),
        "manim-video":              SkillDisplayInfo(name: "Manim Video", description: "Manim CE 动画：3Blue1Brown 风格数学/算法视频。"),
        "p5js":                     SkillDisplayInfo(name: "p5.js", description: "p5.js 草图：生成艺术、着色器、交互、3D。"),
        "popular-web-designs":      SkillDisplayInfo(name: "Popular Web Designs", description: "54 种真实设计系统（Stripe、Linear、Vercel）的 HTML/CSS 实现。"),
        "pretext":                  SkillDisplayInfo(name: "Pretext", description: "使用 @chenglou/pretext 构建创意浏览器 demo——无 DOM 的文本布局。"),
        "sketch":                   SkillDisplayInfo(name: "Sketch", description: "一次性 HTML 原型：生成 2-3 个设计变体供对比。"),
        "songwriting-and-ai-music": SkillDisplayInfo(name: "Songwriting & AI Music", description: "歌曲创作技巧与 Suno AI 音乐 prompt。"),
        "touchdesigner-mcp":        SkillDisplayInfo(name: "TouchDesigner MCP", description: "通过 twozero MCP 控制运行中的 TouchDesigner 实例——创建算子、设置参数。"),
        "blender-mcp":              SkillDisplayInfo(name: "Blender MCP", description: "通过 socket 连接 blender-mcp 插件，直接从 Hermes 控制 Blender。"),
        "concept-diagrams":         SkillDisplayInfo(name: "Concept Diagrams", description: "生成扁平、极简、支持亮色/暗色模式的 SVG 图表。"),
        "hyperframes":              SkillDisplayInfo(name: "HyperFrames", description: "使用 HyperFrames 创建基于 HTML 的视频合成、动态标题卡、社交叠层。"),
        "kanban-video-orchestrator":SkillDisplayInfo(name: "Kanban Video Orchestrator", description: "规划、搭建并监控由 Hermes Kanban 支撑的多 agent 视频制作流水线。"),
        "meme-generation":          SkillDisplayInfo(name: "Meme Generation", description: "通过选取模板并使用 Pillow 叠加文字来生成真实的 meme 图片。"),

        // ---- Data Science ----
        "jupyter-live-kernel":      SkillDisplayInfo(name: "Jupyter Live Kernel", description: "通过实时 Jupyter kernel（hamelnb）进行迭代式 Python 开发。"),

        // ---- DevOps ----
        "kanban-orchestrator":      SkillDisplayInfo(name: "Kanban Orchestrator", description: "面向编排器配置文件的分解策略与反诱惑规则。"),
        "kanban-worker":            SkillDisplayInfo(name: "Kanban Worker", description: "Hermes Kanban worker 的陷阱、示例和边界情况。"),
        "inference-sh-cli":         SkillDisplayInfo(name: "Inference.sh CLI", description: "通过 inference.sh CLI（infsh）运行 150+ AI 应用。"),
        "docker-management":        SkillDisplayInfo(name: "Docker Management", description: "管理 Docker 容器、镜像、卷、网络及 Compose 栈。"),
        "pinggy-tunnel":            SkillDisplayInfo(name: "Pinggy Tunnel", description: "通过 Pinggy 经 SSH 实现零安装本地隧道。"),
        "watchers":                 SkillDisplayInfo(name: "Watchers", description: "轮询 RSS、JSON API 和 GitHub，并使用水印去重。"),

        // ---- Dogfood ----
        "dogfood":                  SkillDisplayInfo(name: "Dogfood", description: "Web 应用探索性 QA：发现 bug、收集证据、生成报告。"),
        "adversarial-ux-test":      SkillDisplayInfo(name: "Adversarial UX Test", description: "扮演产品中最难应对的技术抵触型用户，找出所有 UX 痛点。"),

        // ---- Email ----
        "himalaya":                 SkillDisplayInfo(name: "Himalaya", description: "Himalaya CLI：在终端中收发 IMAP/SMTP 邮件。"),
        "agentmail":                SkillDisplayInfo(name: "AgentMail", description: "通过 AgentMail 为 agent 提供专属邮箱。"),

        // ---- Finance ----
        "3-statement-model":        SkillDisplayInfo(name: "3-Statement Model", description: "在 Excel 中构建完整集成的三表模型（利润表、资产负债表、现金流量表）。"),
        "comps-analysis":           SkillDisplayInfo(name: "Comps Analysis", description: "在 Excel 中构建可比公司分析——运营指标、估值倍数。"),
        "dcf-model":                SkillDisplayInfo(name: "DCF Model", description: "在 Excel 中构建机构级 DCF 估值模型——收入预测、自由现金流构建。"),
        "excel-author":             SkillDisplayInfo(name: "Excel Author", description: "使用 openpyxl 无头构建可审计的 Excel 工作簿。"),
        "lbo-model":                SkillDisplayInfo(name: "LBO Model", description: "在 Excel 中构建杠杆收购模型——资金来源与用途、债务计划。"),
        "merger-model":             SkillDisplayInfo(name: "Merger Model", description: "在 Excel 中构建增厚/摊薄（并购）模型。"),
        "pptx-author":              SkillDisplayInfo(name: "PPTX Author", description: "使用 python-pptx 无头构建 PowerPoint 演示文稿。"),
        "stocks":                   SkillDisplayInfo(name: "Stocks", description: "通过 Yahoo 获取股票报价、历史数据、搜索、对比及加密货币行情。"),

        // ---- GitHub ----
        "codebase-inspection":      SkillDisplayInfo(name: "Codebase Inspection", description: "使用 pygount 检查代码库：代码行数、语言、占比。"),
        "github-auth":              SkillDisplayInfo(name: "GitHub Auth", description: "GitHub 认证配置：HTTPS token、SSH 密钥、gh CLI 登录。"),
        "github-code-review":       SkillDisplayInfo(name: "GitHub Code Review", description: "审查 PR：通过 gh 或 REST API 查看 diff、添加行内评论。"),
        "github-issues":            SkillDisplayInfo(name: "GitHub Issues", description: "通过 gh 或 REST API 创建、分类、标记、分配 GitHub issue。"),
        "github-pr-workflow":       SkillDisplayInfo(name: "GitHub PR Workflow", description: "GitHub PR 生命周期：分支、提交、开启、CI、合并。"),
        "github-repo-management":   SkillDisplayInfo(name: "GitHub Repo Management", description: "克隆/创建/fork 仓库；管理远程、发布版本。"),

        // ---- Health ----
        "fitness-nutrition":        SkillDisplayInfo(name: "Fitness & Nutrition", description: "健身训练计划与营养追踪。通过 wger 搜索 690+ 种训练动作。"),
        "neuroskill-bci":           SkillDisplayInfo(name: "NeuroSkill BCI", description: "连接运行中的 NeuroSkill 实例，将用户的实时认知和情绪状态融入响应中。"),

        // ---- MCP ----
        "fastmcp":                  SkillDisplayInfo(name: "FastMCP", description: "使用 Python 中的 FastMCP 构建、测试、检查、安装和部署 MCP 服务器。"),
        "mcporter":                 SkillDisplayInfo(name: "MCPorter", description: "使用 mcporter CLI 列出、配置、鉴权并直接调用 MCP 服务器/工具。"),

        // ---- Media ----
        "gif-search":               SkillDisplayInfo(name: "GIF Search", description: "通过 curl + jq 从 Tenor 搜索/下载 GIF。"),
        "heartmula":                SkillDisplayInfo(name: "HeartMuLa", description: "HeartMuLa：根据歌词 + 标签生成类 Suno 风格的歌曲。"),
        "songsee":                  SkillDisplayInfo(name: "SongSee", description: "通过 CLI 生成音频频谱图/特征（mel、chroma、MFCC）。"),
        "youtube-content":          SkillDisplayInfo(name: "YouTube Content", description: "将 YouTube 字幕转换为摘要、推文串、博客文章。"),

        // ---- Migration ----
        "openclaw-migration":       SkillDisplayInfo(name: "OpenClaw Migration", description: "将用户的 OpenClaw 自定义配置迁移至 Hermes Agent。"),

        // ---- MLOps ----
        "audiocraft-audio-generation":     SkillDisplayInfo(name: "AudioCraft", description: "AudioCraft：MusicGen 文本转音乐、AudioGen 文本转音效。"),
        "huggingface-hub":                SkillDisplayInfo(name: "HuggingFace Hub", description: "HuggingFace hf CLI：搜索/下载/上传模型、数据集。"),
        "llama-cpp":                      SkillDisplayInfo(name: "llama.cpp", description: "llama.cpp 本地 GGUF 推理 + HF Hub 模型发现。"),
        "evaluating-llms-harness":        SkillDisplayInfo(name: "LM Evaluation Harness", description: "lm-eval-harness：对 LLM 进行基准测试（MMLU、GSM8K 等）。"),
        "segment-anything-model":         SkillDisplayInfo(name: "Segment Anything Model", description: "SAM：通过点、框、掩码进行零样本图像分割。"),
        "serving-llms-vllm":              SkillDisplayInfo(name: "vLLM", description: "vLLM：高吞吐量 LLM 服务，OpenAI API 兼容，量化支持。"),
        "weights-and-biases":             SkillDisplayInfo(name: "Weights & Biases", description: "W&B：记录 ML 实验、超参数搜索、模型注册表、仪表盘。"),
        "huggingface-accelerate":         SkillDisplayInfo(name: "HuggingFace Accelerate", description: "最简单的分布式训练 API，仅需 4 行代码即可为任意 PyTorch 脚本添加分布式支持。"),
        "axolotl":                        SkillDisplayInfo(name: "Axolotl", description: "Axolotl：基于 YAML 配置的 LLM 微调（LoRA、DPO、GRPO）。"),
        "chroma":                         SkillDisplayInfo(name: "Chroma", description: "面向 AI 应用的开源 embedding 数据库。"),
        "clip":                           SkillDisplayInfo(name: "CLIP", description: "OpenAI 连接视觉与语言的模型。支持零样本图像分类、图文匹配。"),
        "faiss":                          SkillDisplayInfo(name: "FAISS", description: "Facebook 用于高效相似性搜索和稠密向量聚类的库。"),
        "optimizing-attention-flash":     SkillDisplayInfo(name: "Flash Attention", description: "使用 Flash Attention 优化 transformer 注意力机制，实现 2-4 倍加速。"),
        "guidance":                       SkillDisplayInfo(name: "Guidance", description: "使用 Guidance 通过正则表达式和语法控制 LLM 输出。"),
        "huggingface-tokenizers":         SkillDisplayInfo(name: "HuggingFace Tokenizers", description: "为研究和生产优化的快速 tokenizer，基于 Rust 实现。"),
        "instructor":                     SkillDisplayInfo(name: "Instructor", description: "使用 Instructor 从 LLM 响应中提取带 Pydantic 验证的结构化数据。"),
        "lambda-labs-gpu-cloud":          SkillDisplayInfo(name: "Lambda Labs GPU Cloud", description: "用于 ML 训练和推理的按需及预留 GPU 云实例。"),
        "llava":                          SkillDisplayInfo(name: "LLaVA", description: "大型语言与视觉助手。支持视觉指令微调和基于图像的对话。"),
        "modal-serverless-gpu":           SkillDisplayInfo(name: "Modal Serverless GPU", description: "用于运行 ML 工作负载的 serverless GPU 云平台。"),
        "nemo-curator":                   SkillDisplayInfo(name: "NeMo Curator", description: "面向 LLM 训练的 GPU 加速数据整理工具。"),
        "outlines":                       SkillDisplayInfo(name: "Outlines", description: "Outlines：结构化 JSON/正则表达式/Pydantic LLM 生成。"),
        "peft-fine-tuning":               SkillDisplayInfo(name: "PEFT Fine-Tuning", description: "使用 LoRA、QLoRA 及 25+ 种方法对 LLM 进行参数高效微调。"),
        "pinecone":                       SkillDisplayInfo(name: "Pinecone", description: "面向生产 AI 应用的托管向量数据库。"),
        "pytorch-fsdp":                   SkillDisplayInfo(name: "PyTorch FSDP", description: "PyTorch FSDP 全分片数据并行训练。"),
        "pytorch-lightning":              SkillDisplayInfo(name: "PyTorch Lightning", description: "高层 PyTorch 框架，提供 Trainer 类、自动分布式训练。"),
        "qdrant-vector-search":           SkillDisplayInfo(name: "Qdrant Vector Search", description: "高性能向量相似性搜索引擎，适用于 RAG 和语义搜索。"),
        "sparse-autoencoder-training":    SkillDisplayInfo(name: "SAE Training", description: "使用 SAELens 训练和分析稀疏自编码器（SAE）。"),
        "simpo-training":                 SkillDisplayInfo(name: "SimPO Training", description: "用于 LLM 对齐的简单偏好优化（SimPO）。"),
        "slime-rl-training":              SkillDisplayInfo(name: "SLIME RL Training", description: "使用 slime（Megatron+SGLang 框架）进行 LLM RL 后训练。"),
        "stable-diffusion-image-generation": SkillDisplayInfo(name: "Stable Diffusion", description: "通过 HuggingFace Diffusers 使用 Stable Diffusion 模型进行文本到图像生成。"),
        "tensorrt-llm":                   SkillDisplayInfo(name: "TensorRT-LLM", description: "使用 NVIDIA TensorRT 优化 LLM 推理。"),
        "distributed-llm-pretraining-torchtitan": SkillDisplayInfo(name: "TorchTitan", description: "使用 torchtitan 进行 PyTorch 原生分布式 LLM 预训练。"),
        "fine-tuning-with-trl":           SkillDisplayInfo(name: "TRL Fine-Tuning", description: "TRL：用于 LLM RLHF 的 SFT、DPO、PPO、GRPO 及奖励建模。"),
        "unsloth":                        SkillDisplayInfo(name: "Unsloth", description: "Unsloth：2-5 倍更快的 LoRA/QLoRA 微调，更低 VRAM 占用。"),
        "whisper":                        SkillDisplayInfo(name: "Whisper", description: "OpenAI 的通用语音识别模型。支持 99 种语言。"),

        // ---- Note Taking ----
        "obsidian":                       SkillDisplayInfo(name: "Obsidian", description: "在 Obsidian 知识库中读取、搜索、创建和编辑笔记。"),

        // ---- Productivity ----
        "airtable":                       SkillDisplayInfo(name: "Airtable", description: "通过 curl 调用 Airtable REST API：记录增删改查、过滤、upsert。"),
        "google-workspace":               SkillDisplayInfo(name: "Google Workspace", description: "通过 gws CLI 或 Python 操作 Gmail、Calendar、Drive、Docs、Sheets。"),
        "maps":                           SkillDisplayInfo(name: "Maps", description: "通过 OpenStreetMap/OSRM 进行地理编码、POI 查询、路线规划、时区查询。"),
        "nano-pdf":                       SkillDisplayInfo(name: "Nano PDF", description: "通过 nano-pdf CLI 编辑 PDF 文本/错别字/标题（自然语言 prompt）。"),
        "notion":                         SkillDisplayInfo(name: "Notion", description: "Notion API + ntn CLI：页面、数据库、Markdown、Workers。"),
        "ocr-and-documents":              SkillDisplayInfo(name: "OCR & Documents", description: "从 PDF/扫描件中提取文本（pymupdf、marker-pdf）。"),
        "powerpoint":                     SkillDisplayInfo(name: "PowerPoint", description: "创建、读取、编辑 .pptx 演示文稿、幻灯片、备注、模板。"),
        "teams-meeting-pipeline":         SkillDisplayInfo(name: "Teams Meeting Pipeline", description: "通过 Hermes CLI 操作 Teams 会议摘要流水线。"),
        "canvas":                         SkillDisplayInfo(name: "Canvas", description: "Canvas LMS 集成——使用 API token 认证获取已注册课程和作业。"),
        "here-now":                       SkillDisplayInfo(name: "Here.Now", description: "将静态站点发布至 {slug}.here.now，并将私有文件存储在云端 Drive 中。"),
        "memento-flashcards":             SkillDisplayInfo(name: "Memento Flashcards", description: "间隔重复闪卡系统。从事实或文本创建卡片，自适应调度复习。"),
        "shop-app":                       SkillDisplayInfo(name: "Shop.app", description: "Shop.app：商品搜索、订单追踪、退货、重新下单。"),
        "shopify":                        SkillDisplayInfo(name: "Shopify", description: "通过 curl 使用 Shopify Admin 和 Storefront GraphQL API。"),
        "siyuan":                         SkillDisplayInfo(name: "SiYuan", description: "通过 curl 使用 SiYuan Note API，在自托管知识库中搜索、读取、创建和管理块与文档。"),
        "telephony":                      SkillDisplayInfo(name: "Telephony", description: "为 Hermes 添加电话能力。配置并持久化 Twilio 号码，发送和接收 SMS/MMS。"),

        // ---- Research ----
        "arxiv":                          SkillDisplayInfo(name: "arXiv", description: "按关键词、作者、分类或 ID 搜索 arXiv 论文。"),
        "blogwatcher":                    SkillDisplayInfo(name: "BlogWatcher", description: "通过 blogwatcher-cli 工具监控博客和 RSS/Atom 订阅源。"),
        "llm-wiki":                       SkillDisplayInfo(name: "LLM Wiki", description: "Karpathy 的 LLM Wiki：构建/查询互联 Markdown 知识库。"),
        "polymarket":                     SkillDisplayInfo(name: "Polymarket", description: "查询 Polymarket：市场、价格、订单簿、历史数据。"),
        "research-paper-writing":         SkillDisplayInfo(name: "Research Paper Writing", description: "为 NeurIPS/ICML/ICLR 撰写 ML 论文：从设计到投稿。"),
        "bioinformatics":                 SkillDisplayInfo(name: "Bioinformatics", description: "通往 bioSkills 和 ClawBio 400+ 生物信息学技能的入口。"),
        "darwinian-evolver":              SkillDisplayInfo(name: "Darwinian Evolver", description: "使用 Imbue 的进化循环演化 prompt/正则表达式/SQL/代码。"),
        "domain-intel":                   SkillDisplayInfo(name: "Domain Intel", description: "使用 Python 标准库进行被动域名侦察。"),
        "drug-discovery":                 SkillDisplayInfo(name: "Drug Discovery", description: "药物发现工作流的制药研究助手。在 ChEMBL 上搜索生物活性化合物。"),
        "duckduckgo-search":              SkillDisplayInfo(name: "DuckDuckGo Search", description: "通过 DuckDuckGo 免费网络搜索——文本、新闻、图片、视频。无需 API 密钥。"),
        "gitnexus-explorer":              SkillDisplayInfo(name: "GitNexus Explorer", description: "使用 GitNexus 为代码库建立索引，并通过 Web UI + Cloudflare 隧道提供交互式知识图谱。"),
        "osint-investigation":            SkillDisplayInfo(name: "OSINT Investigation", description: "公开记录 OSINT 调查框架——SEC EDGAR 文件、USAspending 合同等。"),
        "parallel-cli":                   SkillDisplayInfo(name: "Parallel CLI", description: "Parallel CLI 的可选厂商技能——agent 原生网络搜索、提取、深度研究。"),
        "qmd":                            SkillDisplayInfo(name: "QMD", description: "使用 qmd（混合检索引擎）在本地搜索个人知识库、笔记、文档和会议记录。"),
        "scrapling":                      SkillDisplayInfo(name: "Scrapling", description: "使用 Scrapling 进行网页抓取——HTTP 获取、隐身浏览器自动化、Cloudflare 绕过。"),
        "searxng-search":                 SkillDisplayInfo(name: "SearXNG Search", description: "通过 SearXNG 免费元搜索——聚合 70+ 搜索引擎的结果。"),

        // ---- Security ----
        "1password":                      SkillDisplayInfo(name: "1Password", description: "配置并使用 1Password CLI（op）。"),
        "oss-forensics":                  SkillDisplayInfo(name: "OSS Forensics", description: "针对 GitHub 仓库的供应链调查、证据恢复和取证分析。"),
        "sherlock":                       SkillDisplayInfo(name: "Sherlock", description: "跨 400+ 社交网络的 OSINT 用户名搜索。"),

        // ---- Smart Home ----
        "openhue":                        SkillDisplayInfo(name: "OpenHue", description: "通过 OpenHue CLI 控制 Philips Hue 灯光、场景、房间。"),

        // ---- Social Media ----
        "xurl":                           SkillDisplayInfo(name: "Xurl", description: "通过 xurl CLI 操作 X/Twitter：发帖、搜索、私信、媒体、v2 API。"),

        // ---- Software Development ----
        "hermes-agent-skill-authoring":   SkillDisplayInfo(name: "Hermes Skill Authoring", description: "编写仓库内 SKILL.md：frontmatter、验证器、结构规范。"),
        "node-inspect-debugger":          SkillDisplayInfo(name: "Node Inspect Debugger", description: "通过 --inspect + Chrome DevTools Protocol CLI 调试 Node.js。"),
        "plan":                           SkillDisplayInfo(name: "Plan", description: "计划模式：将 Markdown 计划写入 .hermes/plans/，不执行。"),
        "python-debugpy":                 SkillDisplayInfo(name: "Python DebugPy", description: "调试 Python：pdb REPL + debugpy 远程调试（DAP）。"),
        "requesting-code-review":         SkillDisplayInfo(name: "Requesting Code Review", description: "提交前审查：安全扫描、质量门控、自动修复。"),
        "spike":                          SkillDisplayInfo(name: "Spike", description: "一次性实验，在正式构建前验证想法。"),
        "systematic-debugging":           SkillDisplayInfo(name: "Systematic Debugging", description: "四阶段根因调试：先理解 bug，再修复。"),
        "test-driven-development":        SkillDisplayInfo(name: "Test-Driven Development", description: "TDD：强制执行红-绿-重构流程，先写测试再写代码。"),
        "rest-graphql-debug":             SkillDisplayInfo(name: "REST/GraphQL Debug", description: "调试 REST/GraphQL API：状态码、认证、schema、问题复现。"),

        // ---- Web Development ----
        "page-agent":                     SkillDisplayInfo(name: "Page Agent", description: "将 alibaba/page-agent 嵌入您自己的 Web 应用——一个纯 JavaScript 页内 GUI agent。"),

        // ---- Yuanbao ----
        "yuanbao":                        SkillDisplayInfo(name: "Yuanbao", description: "元宝（Yuanbao）群组：@提及用户、查询信息/成员。"),
    ]

    /// 查询展示信息 — 对齐 Flutter `_skillCatalog[id]`。
    static func displayInfo(for skillId: String) -> SkillDisplayInfo? {
        return entries[skillId]
    }
}
