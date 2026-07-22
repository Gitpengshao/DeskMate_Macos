[AppDelegate] applicationDidFinishLaunching: 启动
[AppDelegate] 启动步骤 1/8 hidePlaceholderWindow 完成，耗时 0.019s，主线程=YES
Adding 'HoverTrackingView' as a subview of NSHostingView is not supported and may result in a broken view hierarchy. Add your view above NSHostingView in a common superview or insert it into your SwiftUI content in a NSViewRepresentable instead.
[AppDelegate] 启动步骤 2/8 setupPetWindow 完成，耗时 0.013s，主线程=YES
[AppDelegate] 启动步骤 3/8 GlobalShortcutManager 完成，耗时 0.001s，主线程=YES
[2026-07-22 22:55:05.807] [INFO] [HermesConfigWriter] HermesConfigWriter init: profile=default hermesHome=/Users/mac002/.hermes  ← HermesConfigWriter.swift:57
[2026-07-22 22:55:05.807] [INFO] [HermesConfigWriter] HermesConfigWriter init: profile=default hermesHome=/Users/mac002/.hermes  ← HermesConfigWriter.swift:57
[2026-07-22 22:55:05.807] [INFO] [HermesConfigWriter] readReasoningEffort: raw=medium -> medium  ← HermesConfigWriter.swift:463
[2026-07-22 22:55:05.807] [INFO] [HermesConfigWriter] readReasoningEffort: raw=medium -> medium  ← HermesConfigWriter.swift:463
[2026-07-22 22:55:05.808] [INFO] [AiChatVM] [AiChatVM] setupInitialConfigIfNeeded: reasoning=medium cwd=.  ← AiChatViewModel.swift:99
[2026-07-22 22:55:05.808] [INFO] [AiChatVM] [AiChatVM] setupInitialConfigIfNeeded: reasoning=medium cwd=.  ← AiChatViewModel.swift:99
[AppDelegate] 启动步骤 4/8 预初始化 ViewModels 完成，耗时 0.004s，主线程=YES
[AppDelegate] 启动步骤 5/8 设置灵动岛回调 完成，耗时 0.000s，主线程=YES
[AppDelegate] updateConsoleKeyState: mainWindow.isKeyWindow=false, onboardingWindow.isKeyWindow=false, isConsoleKeyWindow=false
[AppDelegate] 启动步骤 6/8 添加窗口观察者 完成，耗时 0.001s，主线程=YES
[AppDelegate] 启动步骤 7/8 已调度灵动岛显示，耗时 0.000s，主线程=YES
[AppDelegate] onboarding_completed = true
[AppDelegate] 启动步骤 8/8 已调度 Hermes 环境检测，耗时 0.000s，主线程=YES
[AppDelegate] 启动步骤 8/8 开始检测 Hermes 环境，主线程=NO
[2026-07-22 22:55:05.848] [INFO] [GlobalShortcut] updateRegistration enabled=true valid=true shortcut=⌃Y  ← GlobalShortcutManager.swift:42
[2026-07-22 22:55:05.848] [INFO] [GlobalShortcut] updateRegistration enabled=true valid=true shortcut=⌃Y  ← GlobalShortcutManager.swift:42
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] register succeeded  ← GlobalShortcutManager.swift:64
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] register succeeded  ← GlobalShortcutManager.swift:64
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] updateRegistration enabled=true valid=true shortcut=⌃Y  ← GlobalShortcutManager.swift:42
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] updateRegistration enabled=true valid=true shortcut=⌃Y  ← GlobalShortcutManager.swift:42
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] register skipped: monitor already exists  ← GlobalShortcutManager.swift:53
[2026-07-22 22:55:05.855] [INFO] [GlobalShortcut] register skipped: monitor already exists  ← GlobalShortcutManager.swift:53
[AppDelegate] isHermesEnvironmentReady: 开始后台检测，主线程=YES
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: 开始检测，hermesHome=/Users/mac002/.hermes  ← OnboardingViewModel.swift:435
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: 开始检测，hermesHome=/Users/mac002/.hermes  ← OnboardingViewModel.swift:435
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: realHomeDirectory()=/Users/mac002  ← OnboardingViewModel.swift:436
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: realHomeDirectory()=/Users/mac002  ← OnboardingViewModel.swift:436
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: homeExists=true, isDirectory=true  ← OnboardingViewModel.swift:441
[2026-07-22 22:55:05.862] [INFO] [OnboardingViewModel] checkHermes: homeExists=true, isDirectory=true  ← OnboardingViewModel.swift:441
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] checkHermes: agentDirExists=true, scriptExists=true  ← OnboardingViewModel.swift:453
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] checkHermes: agentDirExists=true, scriptExists=true  ← OnboardingViewModel.swift:453
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] checkHermes: 即将执行脚本版本检测: /Users/mac002/.hermes/hermes-agent/hermes  ← OnboardingViewModel.swift:458
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] checkHermes: 即将执行脚本版本检测: /Users/mac002/.hermes/hermes-agent/hermes  ← OnboardingViewModel.swift:458
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] [runShell] 开始执行 (timeout=10.0s): '/Users/mac002/.hermes/hermes-agent/hermes' --version 2>/dev/null  ← OnboardingViewModel.swift:725
[2026-07-22 22:55:05.865] [INFO] [OnboardingViewModel] [runShell] 开始执行 (timeout=10.0s): '/Users/mac002/.hermes/hermes-agent/hermes' --version 2>/dev/null  ← OnboardingViewModel.swift:725
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] [runShell] 完成: 耗时=0.06s, 退出码=1, 输出长度=0, command='/Users/mac002/.hermes/hermes-agent/hermes' --version 2>/dev/null  ← OnboardingViewModel.swift:779
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] [runShell] 完成: 耗时=0.06s, 退出码=1, 输出长度=0, command='/Users/mac002/.hermes/hermes-agent/hermes' --version 2>/dev/null  ← OnboardingViewModel.swift:779
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: 脚本版本检测完成, output=  ← OnboardingViewModel.swift:461
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: 脚本版本检测完成, output=  ← OnboardingViewModel.swift:461
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: installed=true  ← OnboardingViewModel.swift:498
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: installed=true  ← OnboardingViewModel.swift:498
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: 检查配置文件路径  ← OnboardingViewModel.swift:505
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: 检查配置文件路径  ← OnboardingViewModel.swift:505
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: envPath=/Users/mac002/.hermes/.env  ← OnboardingViewModel.swift:506
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: envPath=/Users/mac002/.hermes/.env  ← OnboardingViewModel.swift:506
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: authPath=/Users/mac002/.hermes/auth.json  ← OnboardingViewModel.swift:507
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: authPath=/Users/mac002/.hermes/auth.json  ← OnboardingViewModel.swift:507
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: configPath=/Users/mac002/.hermes/config.yaml  ← OnboardingViewModel.swift:508
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: configPath=/Users/mac002/.hermes/config.yaml  ← OnboardingViewModel.swift:508
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(envPath)=true  ← OnboardingViewModel.swift:511
[2026-07-22 22:55:05.929] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(envPath)=true  ← OnboardingViewModel.swift:511
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(authPath)=false  ← OnboardingViewModel.swift:514
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(authPath)=false  ← OnboardingViewModel.swift:514
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(configPath)=true  ← OnboardingViewModel.swift:517
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: fm.fileExists(configPath)=true  ← OnboardingViewModel.swift:517
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: configured=true  ← OnboardingViewModel.swift:520
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: configured=true  ← OnboardingViewModel.swift:520
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: 尝试读取 .env 文件  ← OnboardingViewModel.swift:527
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: 尝试读取 .env 文件  ← OnboardingViewModel.swift:527
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: .env 文件读取成功，长度=24431  ← OnboardingViewModel.swift:530
[2026-07-22 22:55:05.930] [INFO] [OnboardingViewModel] checkHermes: .env 文件读取成功，长度=24431  ← OnboardingViewModel.swift:530
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkHermes: parseApiKeyFromEnv 返回 true  ← OnboardingViewModel.swift:532
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkHermes: parseApiKeyFromEnv 返回 true  ← OnboardingViewModel.swift:532
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: configPath=/Users/mac002/.hermes/config.yaml  ← OnboardingViewModel.swift:609
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: configPath=/Users/mac002/.hermes/config.yaml  ← OnboardingViewModel.swift:609
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: FileManager 读取结果长度=7253  ← OnboardingViewModel.swift:616
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: FileManager 读取结果长度=7253  ← OnboardingViewModel.swift:616
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 内容预览=model:
  provider: custom
  default: moonshotai/Kimi-K2.7-Code
  base_url: https://api.siliconflow.cn/v1
agent:
  max_turns: 60
  gateway_timeout: 1800
  restart_drain_timeout: 180
  api_max_retries: 3
  service_tier: ''
  tool_use_enforcement: auto
  task_completion_guidance: true
  environment_probe: true
  environment_hint: ''
  coding_context: auto
  gateway_timeout_warning: 900
  clarify_timeout: 600
  gateway_notify_interval: 180
  gateway_auto_continue_freshness: 3600
  image_input_mode:   ← OnboardingViewModel.swift:628
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 内容预览=model:
  provider: custom
  default: moonshotai/Kimi-K2.7-Code
  base_url: https://api.siliconflow.cn/v1
agent:
  max_turns: 60
  gateway_timeout: 1800
  restart_drain_timeout: 180
  api_max_retries: 3
  service_tier: ''
  tool_use_enforcement: auto
  task_completion_guidance: true
  environment_probe: true
  environment_hint: ''
  coding_context: auto
  gateway_timeout_warning: 900
  clarify_timeout: 600
  gateway_notify_interval: 180
  gateway_auto_continue_freshness: 3600
  image_input_mode:   ← OnboardingViewModel.swift:628
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] parseYamlForModel: 开始解析，内容长度=7253  ← OnboardingViewModel.swift:637
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] parseYamlForModel: 开始解析，内容长度=7253  ← OnboardingViewModel.swift:637
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 进入 model: section  ← OnboardingViewModel.swift:659
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 进入 model: section  ← OnboardingViewModel.swift:659
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 找到默认模型 'moonshotai/Kimi-K2.7-Code'  ← OnboardingViewModel.swift:677
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: 找到默认模型 'moonshotai/Kimi-K2.7-Code'  ← OnboardingViewModel.swift:677
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: parseYamlForModel 返回 true  ← OnboardingViewModel.swift:631
[2026-07-22 22:55:05.931] [INFO] [OnboardingViewModel] checkConfigYamlForModel: parseYamlForModel 返回 true  ← OnboardingViewModel.swift:631
[2026-07-22 22:55:05.932] [INFO] [OnboardingViewModel] Hermes 检测结果: installed=true, configured=true, hasApiKey=true, hasModelConfigured=true, hermesHome=/Users/mac002/.hermes, version=nil  ← OnboardingViewModel.swift:569
[2026-07-22 22:55:05.932] [INFO] [OnboardingViewModel] Hermes 检测结果: installed=true, configured=true, hasApiKey=true, hasModelConfigured=true, hermesHome=/Users/mac002/.hermes, version=nil  ← OnboardingViewModel.swift:569
[AppDelegate] isHermesEnvironmentReady: installed=true, configured=true, hasApiKey=true, hasModelConfigured=true, ready=true, 检测耗时 0.076s, 主线程=NO
[2026-07-22 22:55:05.934] [INFO] [ModelConfigService] parseModelSection: provider=custom, default=moonshotai/Kimi-K2.7-Code, displayName=Kimi-K2.7-Code  ← ModelConfigService.swift:156
[2026-07-22 22:55:05.934] [INFO] [ModelConfigService] parseModelSection: provider=custom, default=moonshotai/Kimi-K2.7-Code, displayName=Kimi-K2.7-Code  ← ModelConfigService.swift:156
[AppDelegate] isHermesEnvironmentReady: 返回 ready=true，总耗时 0.079s
[AppDelegate] 启动步骤 8/8 Hermes 环境检测完成 ready=true，耗时 0.125s，主线程=NO
[2026-07-22 22:55:05.934] [INFO] [AiChatVM] setupInitialConfigIfNeeded: currentModel=moonshotai/Kimi-K2.7-Code  ← AiChatViewModel.swift:109
[2026-07-22 22:55:05.934] [INFO] [AiChatVM] setupInitialConfigIfNeeded: currentModel=moonshotai/Kimi-K2.7-Code  ← AiChatViewModel.swift:109
[AppDelegate] Hermes 环境完整，后台启动 Gateway
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] stopAllGateways: 进入，主线程=YES  ← HermesGatewayService.swift:87
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] stopAllGateways: 进入，主线程=YES  ← HermesGatewayService.swift:87
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] killOrphanedGatewayProcesses: 进入，主线程=YES  ← HermesGatewayService.swift:438
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] killOrphanedGatewayProcesses: 进入，主线程=YES  ← HermesGatewayService.swift:438
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[h]ermes_cli.main.*gateway' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:05.934] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[h]ermes_cli.main.*gateway' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.126s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.126s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[h]ermes_cli.main.*gateway' 耗时 0.127s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[h]ermes_cli.main.*gateway' 耗时 0.127s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[h]ermes-agent.*gateway' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.061] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[h]ermes-agent.*gateway' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.080s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.080s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[h]ermes-agent.*gateway' 耗时 0.080s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[h]ermes-agent.*gateway' 耗时 0.080s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[g]ateway/run.py' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.141] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='ps auxww | grep -E '[g]ateway/run.py' | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.238] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.097s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.238] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.097s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.239] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[g]ateway/run.py' 耗时 0.097s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.239] [INFO] [HermesGateway] killOrphanedGatewayProcesses: ps pattern='[g]ateway/run.py' 耗时 0.097s，输出=''  ← HermesGatewayService.swift:453
[2026-07-22 22:55:06.239] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='lsof -i:8642 -P -n | tail -n +2 | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.239] [INFO] [HermesGateway] runShellSync: 开始，主线程=YES，cmd='lsof -i:8642 -P -n | tail -n +2 | awk '{print $2}' || true'  ← HermesGatewayService.swift:702
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.031s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] runShellSync: 完成，耗时 0.031s，exit=0，主线程=YES  ← HermesGatewayService.swift:715
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] killOrphanedGatewayProcesses: lsof 耗时 0.031s，输出=''  ← HermesGatewayService.swift:470
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] killOrphanedGatewayProcesses: lsof 耗时 0.031s，输出=''  ← HermesGatewayService.swift:470
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] killOrphanedGatewayProcesses: 未发现残留进程，总耗时 0.335s  ← HermesGatewayService.swift:482
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] killOrphanedGatewayProcesses: 未发现残留进程，总耗时 0.335s  ← HermesGatewayService.swift:482
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] waitForPortRelease: 端口 8642 已释放，耗时 0.000s  ← HermesGatewayService.swift:547
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] waitForPortRelease: 端口 8642 已释放，耗时 0.000s  ← HermesGatewayService.swift:547
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] stopAllGateways: 完成，总耗时 0.335s  ← HermesGatewayService.swift:117
[2026-07-22 22:55:06.269] [INFO] [HermesGateway] stopAllGateways: 完成，总耗时 0.335s  ← HermesGatewayService.swift:117
[AppDelegate] startHermesGatewayIfNeeded: gatewayStarted=false，主线程=YES
[AppDelegate] startHermesGatewayIfNeeded Task: 开始启动 Gateway，主线程=NO
[AppDelegate] startHermesDashboardIfNeeded: 主线程=YES
[AppDelegate] startAndWaitForHermesGateway: 进入，gatewayStarted=false，主线程=YES
[AppDelegate] startHermesDashboardIfNeeded Task: 开始启动 Dashboard，主线程=NO
[HermesDashboard] startDashboard: 进入，port=9119，主线程=YES
nw_socket_handle_socket_event [C2:2] Socket SO_ERROR [61: Connection refused]
nw_endpoint_flow_failed_with_error [C2 127.0.0.1:8642 in_progress socket-flow (satisfied (Path is satisfied), viable, interface: lo0)] already failing, returning
Connection 2: received failure notification
Connection 2: failed to connect 1:61, reason -1
Connection 2: encountered error(1:61)
nw_connection_copy_protocol_metadata_internal_block_invoke [C2] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_protocol_metadata_internal_block_invoke [C2] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_protocol_metadata_internal_block_invoke [C2] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_connected_local_endpoint_block_invoke [C2] Client called nw_connection_copy_connected_local_endpoint on unconnected nw_connection
nw_connection_copy_connected_remote_endpoint_block_invoke [C2] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection
Task <C65C58DD-924A-44D3-AEA4-4D47F114F703>.<1> HTTP load failed, 0/0 bytes (error code: -1004 [1:61])
Task <C65C58DD-924A-44D3-AEA4-4D47F114F703>.<1> finished with error [-1004] Error Domain=NSURLErrorDomain Code=-1004 "Could not connect to the server." UserInfo={_kCFStreamErrorCodeKey=61, NSUnderlyingError=0xa5e890090 {Error Domain=kCFErrorDomainCFNetwork Code=-1004 "(null)" UserInfo={_NSURLErrorNWPathKey=satisfied (Path is satisfied), viable, interface: lo0, _kCFStreamErrorCodeKey=61, _kCFStreamErrorDomainKey=1}}, _NSURLErrorFailingURLSessionTaskErrorKey=LocalDataTask <C65C58DD-924A-44D3-AEA4-4D47F114F703>.<1>, _NSURLErrorRelatedURLSessionTaskErrorKey=(
    "LocalDataTask <C65C58DD-924A-44D3-AEA4-4D47F114F703>.<1>"
), NSLocalizedDescription=Could not connect to the server., NSErrorFailingURLStringKey=http://127.0.0.1:8642/health, NSErrorFailingURLKey=http://127.0.0.1:8642/health, _kCFStreamErrorDomainKey=1}
[HermesGateway] startGatewayInternal: profile=default hermesHome=/Users/mac002/.hermes
[HermesGateway] startGatewayInternal: targetPythonPath=/Users/mac002/.hermes/hermes-agent/venv/bin/python
[HermesGateway] startGatewayInternal: targetPython 存在=true
[HermesGateway] startGatewayInternal: 使用 port=8642
[HermesDashboard] startDashboard: portOccupied=true, alreadyHealthy=true，耗时 0.066s
[HermesDashboard] startDashboard: 开始清理残留 Dashboard 进程
[HermesDashboard] killOrphanedDashboardProcesses: 进入，主线程=YES
[HermesDashboard] runShellSync: 开始，主线程=YES，cmd=ps auxww | grep -E '[h]ermes_cli.main.*dashboard' | awk '{print $2}' || true
[HermesDashboard] runShellSync: 完成，耗时 0.077s，exit=0，主线程=YES
[HermesDashboard] killOrphanedDashboardProcesses: ps pattern='[h]ermes_cli.main.*dashboard' 耗时 0.077s，输出=
[HermesDashboard] runShellSync: 开始，主线程=YES，cmd=lsof -i:9119 -P -n | tail -n +2 | awk '{print $2}' || true
[HermesDashboard] runShellSync: 完成，耗时 0.032s，exit=0，主线程=YES
[HermesDashboard] killOrphanedDashboardProcesses: lsof 耗时 0.032s，输出=258
87783
87783
[HermesDashboard] killOrphanedDashboardProcesses: 发现 2 个残留进程: [87783, 258]
[HermesDashboard] killOrphanedDashboardProcesses: 发送 SIGTERM 到 pid=87783
[HermesDashboard] killOrphanedDashboardProcesses: 发送 SIGTERM 到 pid=258