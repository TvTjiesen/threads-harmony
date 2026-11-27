# 项目状态

## 当前阶段

**2026-11-27：原生讨论阅读（`conversation-reading`）。** 点正文读原帖，点摘要直达所显示的回复；编辑时可以看见收件人与上下文。未添加的文字受到返回保护，本机回复不会发送到 Threads，也不跨重启保存。模拟器发现并修复「计数已变、摘要仍指向旧回复」：现按最新回复 ID 更新摘要，返回首页不重建整张帖子。见[连续六屏](docs/screenshots/conversation-reading-sequence.jpg)和[测试矩阵](TEST-MATRIX.md)。

**2026-11-27：HDS 阅读首页（`hds-reading-home`）。** 四个浏览栏目改用华为 UIDesignKit 的 `HdsTabs`，窄窗写帖由独立辅助栏承载，不改变选中的栏目。首页换成系统分段控件和连续帖子／回复排版，设置与网页从「我的」进入。手机模拟器已签装，检查了首屏、单击写帖、设置、详情及网页容器返回；滚动后三条作者行位置一致。[同机新旧对照](docs/screenshots/hds-reading-home-comparison.jpg)及[测试记录](TEST-MATRIX.md)可复核。真实账号、当前版宽窗、折叠和帧率分别待验。

**2026-11-27：整套原生界面候选（`native-ui-shell`）。** 总入口采用 ArkUI 原生底栏／宽窗侧栏；首页「为你／关注中」、本机搜索、独立写帖、可筛选的本机动态、个人主页及完整设置串在一起。关注筛选和读位是本机行为，不代表账号关注关系；真实网页继续独立。真机折叠、手势和视觉表现待验，详见[测试矩阵](TEST-MATRIX.md)。

**2026-11-27：原生整合基线（`20049f7`）。** 本机时间线、详情、草稿、预览、搜索与「我的」串成一条流程。本机帖子、点赞、关注和收藏通过版本化存储跨重启；本地回复仍只在当前运行中保留。网页入口独立；网络设置可以将固定的官方 Threads 首页交给系统。真实账号不进入原生区，不读取网页登录会话。详见[测试矩阵](TEST-MATRIX.md)，下文按历史迭代保留证据。

**2026-11-26：原生模拟时间线高品质首轮迭代已通过代码、编译和部分设备交互验收（历史基线）。** ArkUI 首屏使用 8 条本地演示帖子，点赞/关注只影响运行态，回复/分享/发帖仅提示；原 ArkWeb 仍可进入，Stage ArkWeb 与 overlay 字节一致。16 项 Node 回归通过；E 盘工程 clean build 实际执行 `CompileArkTS` 与 `SignHap`，签名 HAP 已覆盖安装至手机模拟器。设备 UI 树确认窄屏首屏、设置面板开关切换与关闭后重开保留会话内状态、点赞 86→87→86→87；停止滚动后进入网页再返回，城市观察员、周末书架、夜归电台三帖坐标均保持一致。修复设置面板系统关闭图标与「完成」按钮命中范围重叠（关闭系统图标，保留明确「完成」按钮及拖动关闭入口；拖动关闭未在手机模拟器单独实测）。MatePad 真机随后对固定版 `893aa68d` 补齐签装、单双栏、设置拖动关闭和返回保读位，见 [SP18 回执](https://github.com/TvTjiesen/threads-harmony/blob/509c73774a6c15f06a9e40fd942cf76bae37083e/coordination/matepad-ui-smoke-893aa68.md)。真实 Threads 网页、Pura X View 折叠/手势、帧率和视觉审美仍未验收，不能将编译或 UI 树通过视为达到获奖水准。

**深色与大字号迭代（独立分支）**：原生时间线跟随系统深浅色；在大字号下，标题栏纳入滚动区、关注按钮移至独立一行，宽窗也优先单栏。手机模拟器已通过深浅色与标准／特大字号切换；MatePad 对固定版 `f8473a4` 另已通过深浅色即时切换和标准字号单双栏，但其系统字号档位未触发应用字体变化，动态大字号仍未测。详见 [MatePad 验收记录](coordination/matepad-theme-smoke-f8473a4.md)。不覆盖折叠真机或 ArkWeb 页面本身的主题与大字号布局。

**减少动效迭代（独立分支）**：原生时间线通过本机 Preferences 保存「减少动效」，开启和关闭都可跨进程重启恢复；只影响点赞弹跳，不改变点赞状态和计数。通过 SDK 公开无障碍接口读取并监听系统减动效状态；系统要求减动效时，应用开关关闭也不会触发点赞弹跳。ArkWeb 源码未改。

**阅读连续性迭代（累积减动效）**：有效窗口宽度或系统字号改变时，按重排前的帖子 ID 恢复阅读位置；卡片仍有可用尺寸时尽量保留已滚过的距离，重排过程中不播放定位动画。不承诺逐像素一致或退出应用后恢复。布局不变时，网页容器返回仍由原列表保位。手机模拟器已验证标准与特大字号之间往返时留在同一帖；真实折叠、物理返回手势和宽窄形态仍待验收。

**帖子详情迭代（累积阅读连续性）**：时间线的回复入口打开原生详情，可阅读本地示例回复、添加仅在此次运行中保存的回复；不联网、不发送。详情与时间线共用点赞、关注和本地回复计数；原列表不销毁，同尺寸返回保留读位。新增详情转场同样遵从应用和系统的减少动效偏好。真实网页、真机键盘和侧边返回手势仍需独立验证。

**写帖草稿迭代（累积帖子详情）**：时间线新增原生「写草稿」，一份正文仅在明确保存后写入本机；随时可继续编辑、放弃本次修改或确认清空已保存的内容。草稿不发布、不上传，与详情内仅在运行态保留的演示回复分开。复用既有原生导航栈和减动效偏好，ArkWeb 源码不变。

**本地发布预演（累积写帖草稿）**：可先预览草稿再返回编辑，或确认加入本地演示时间线并回到顶部。预演帖子有本地标签，只在本次运行中存在，不上传、不会更改已保存的草稿；原 ArkWeb 入口和源码不变。

> 历史背景（不代表当前阻塞）：`2d106031` 与代理修复候选 `5e4d5abf` 曾通过 MatePad 未签名构建；此后 Windows E 盘工程已完成新版签名、安装、启动，MatePad 也对 `2c07c5f` 完成真机验收。旧记录中“新版未签名/未安装”只适用于当时版本。详见 [跨端协作记录](AI-WORKFLOW.md)。

## 工作分工

- **Windows + DSH**：唯一产品/代码主责，维护 Git 真源，负责架构、ArkTS、审查、测试、错误修复和 MatePad 任务单。DevEco CLI 用于本地文档；常规 ArkTS 编译和打包由 Windows DevEco Studio 自带 Hvigor 执行，已对隔离工作树中的代理候选完成首轮实编。Windows 手机模拟器 `ThreadsHarmonyPhone` 通过 HDC `127.0.0.1:5555` 验证新版。仓库 Stage 工程不保存签名；签名和部署在独立的 E 盘工程执行。此前固定 SHA `56785d268d3f028dbe19d21a2c6736bcbb5990d2` 的未签名构建是历史记录，不是新版安装前置。
- **MatePad Edge + WorkBuddy**：设备侧作为构建/验收站。WorkBuddy 通过已验证的 MatePad 本机 CLT/Hvigor 能力执行固定 SHA 构建；最新回执记录 Node v24.18.1、Hvigor 7.26.11，构建 62,003 字节未签名 HAP。WorkBuddy 是否通过 DevEco CLI 调用不作为已知事实。低性能 HY4Flash 只承担固定 SHA 的构建、版本/错误行核对和经授权的单项截图，不写业务代码、不决策架构、不改依赖或 SDK。代理修复 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 已构建，回执分支 `matepad/build-proxy-state-5e4d`、提交 `f9603240237d91791f1923a9a035d638997da4ed` 已由 Windows 核验，构建源码 SHA 与回执分支起点有明确区分。定时自动触发未验证。早期独立工程通过 DevEco GUI 签名安装启动，非当前候选的证据。
- **Pura X View**：HarmonyOS 7.0.0.115 SP10（用户提供；SDK API level 待核实）；主折叠手机验收设备。网页登录 Threads 可用，App 内 ArkWeb 仍未测。
- **Android**：后续独立 UI/平台目标，尚无工程。

## 已完成

- `PLAN.md` 定义设备、离线工作方式、共享事实源、Android 路线和阶段验收。
- `TEST-MATRIX.md` 记录设备及五项核心功能矩阵；所有尚未实际验证的格子均为“未测”。
- `overlay/entry/src/main/ets/pages/Index.ets`：ArkWeb 原型代码。
- `README.md`：构建接入步骤及平台边界。
- `.gitignore`：忽略构建产物和签名材料。

## 工具链证据

- 2026-11-23：Windows winget 可查询到 `Huawei.DevEco`，清单版本 `223.8617.56.36.310501` 指向 DevEco Studio 3.1.0.501（2023 安装包）。未安装，不采用此旧版本。
- 用户设备信息（2026-11-23）：Pura X View 系统为 HarmonyOS 7.0.0.115 SP10；该系统 build 尚未映射到 Harmony SDK API level。CodeArts 核实报告将 MatePad Edge 系统记录为 QXS-W00 7.0.0.111(SP16C00E111R5P5) / OpenHarmony 7.0.0.111 / API 26；注意报告采集的是 MatePad，不是 Pura X。报告全文位于用户提供的 `C:\Users\杰森\Documents\xwechat_files\wxid_ilhkddulxklw22_4e1a\msg\file\2026-11\CodeArts-HarmonyOS-PC-能力核实报告.md`。
- **Windows DSH 主机（2026-11-25）**：已发现华为签名有效的 DevEco Studio、Hvigor 6.26.20、Node 24.14.1、ohpm 与 API 26 `26.0.1.120` Beta1 SDK。以固定候选 `5e4d5abf` 创建纯 ASCII 隔离工作树，仅将本地 `compileSdkVersion` 对齐为 `26.0.1` 后，Hvigor clean build 实际执行 `CompileArkTS` 并成功生成 61,814 字节未签名 HAP。HDC 3.2.0f 已连接 Windows 本地 `ThreadsHarmonyTablet`（HarmonyOS 7.0.0 Release），可读系统版本。仅验证模拟器连通，未部署或运行应用。原始固定提交不变；MatePad 使用的构建配置也未改。完整命令/哈希见 [华为工具记录](HUAWEI-TOOLS.md)。
- 从公开 OpenTwit 仓库核对的 Stage 样例：`compileSdkVersion` 6.1.1(24)、`compatibleSdkVersion` 5.0.0(12)、设备列 phone/tablet/2in1；仅作历史参考，不是本项目兼容性证据。当前 MatePad 原型基于本机 SDK API 26。
- 用户提供的早期 CodeArts 核实报告引用官方鸿蒙开发实践：DevEco 6.0.0+，运行环境 Windows 10/11 x64 或 macOS 12+；该报告当时只核验 CodeArts 应用沙箱。随后 CodeArts 已在 MatePad 工作区成功调用 CLT/Hvigor，详见下节；因此不能再用旧沙箱报告推断本机无法构建。

## MatePad 本机构建与 ArkWeb 原型（2026-11-23）

- **本机签名/安装/启动链路已打通（2026-11-23 21:48）**：DevEco Studio 运行目标为「此电脑」；在独立探针工程 `test`（包名 `com.example.myappl`，日志里 log label 显示为 `label`）启用自动签名后，日志出现 `bm install -p .../entry-default-signed.hap` 249 ms、`aa start -a EntryAbility -b com.example.myappl` 223 ms、`Launch com.example.myappl success in 504 ms`，设备上出现独立应用窗口。此前 `9568320 / no signature file` 已由自动签名消除。**这一步只证明本机签名安装可用，尚未涉及 Threads 原型。**
- CodeArts 报告实测工具：Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、codelinter 6.0.140；版本命令退出码均为 0。SDK API 26，CLT 内含 Hvigor 插件。
- 在 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe` 创建独立 Stage 工程；不依赖模板、不下载依赖，先后构建空白 Hello HarmonyOS 与 ArkWeb Threads 原型。命令 `hvigorw assembleHap --no-daemon -p product=default`，原型构建退出码 0。
- ArkWeb 原型只改 `entry/src/main/module.json5`（加 INTERNET 权限）与 `entry/src/main/ets/pages/Index.ets`；包名 `com.example.harmonylocalprobe`，版本 `1000000 / 1.0.0`，deviceTypes `tablet/2in1`；HAP `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe/entry/build/default/outputs/default/entry-default-unsigned.hap`，27,231 字节，MD5 `fb56cefbdbdf8a51443f067e9fe3437c`，未签名。CodeArts 只读核对称 `build-profile.json5` 的 signingConfigs 为空；当前 hdc targets 为 0（不证明 DevEco GUI 看不到目标）。
- 27,231 字节的未签名 HAP 是最初 CLI 产物；随后用户通过 DevEco 在「此电脑」签名、安装并启动同名探针，原生工具栏显示，Threads 内容白屏加载。登录与其他网页功能未验收。
- 2026-11-24 固定提交 `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 在 MatePad 独立目录重建：15 个文本文件按 blob SHA 校验一致，另复制两个原工程 PNG（未纳入该提交）。`hvigorw assembleHap --no-daemon -p product=default` 退出 0，`BUILD SUCCESSFUL in 15 s 616 ms`，生成 27,229 字节 `entry-default-unsigned.hap`。Windows 核验回执分支 `matepad/build-f0caae-20261124` 的提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 直接继承源提交、仅新增 `coordination/matepad-build-f0caae.md`，并读取其正文。未上传 HAP，未签名、安装、启动；自动任务接单尚未验证。

## 跨端接入方案（2026-11-23 22:39）

- **Host 插件已安装，未生效**：`ds-harness-remote@0.6.7` 已用官方 launcher 装进 `desktop` profile（`+ ds-harness-remote 0.6.7`、`Packages: +9 -54`、guard 校验通过）。`package.json` dependencies 31 项 / bundles 34 项，只新增该项，无删除。**必须重启 DSH 才生效。**
- 选型理由、已知限制（Windows Host 锁恢复待上游验证）、重启后自检清单、鸿蒙客户端构建命令，见 [REMOTE-ACCESS.md](REMOTE-ACCESS.md)。
- 自建桥 `tools/bridge/`（LAN HTTP + ntfy 分块中继 + 单文件 worker，端到端已验证）降级为兜底，不再作为主路径。

## 下一步

- DSH 主开发、本机完成静态检查、Node 回归、Windows Hvigor ArkTS clean build 与错误定位；MatePad WorkBuddy（HY4Flash）仅做固定版本本机验收/窄杂务。当前任务单见 [MatePad 下一项验收](coordination/MATEPAD-NEXT.md)。
- 下一步：在 Pura X View 使用覆盖该设备的调试签名部署，验证折叠、滚动、系统返回，并在同一设备与网络下对比系统浏览器和 ArkWeb 的 Threads 首屏。旧手机 smoke 任务单描述的是先前 ArkWeb 候选，不替代这轮验收。

1. 固定候选 `2d106031f2fa6d0bd8018b053abaf9e257f40513` 已由 MatePad Edge 本机 DevEco Command Line Tools 精确构建并三次复现，详见 [ArkWeb 构建回执](https://github.com/TvTjiesen/threads-harmony/blob/feat/arkweb-build-2d1060/coordination/arkweb-build-receipt.md)。回执提交 `40f34cec5c14da8abd16dbf465d385828fb2b665` 的父提交即固定候选；命令 `hvigorw assembleHap --no-daemon -p product=default`，exit 0、`BUILD SUCCESSFUL`、未签名 HAP 56,075 字节。未签名、未安装、未运行、未上传。新代理修复候选不由此回执覆盖。
2. 代理修复候选在 `fix/arkweb-proxy-state`，两处 ArkWeb 页面一致。应用/关闭代理同一时刻只发一个请求；等待 20 秒只提示，不解锁、不加载页面、不发反向请求。无效的旧偏好或启动代理报错/超时会尝试清除；启动超时后回调才到达时，须在设置中确认才能继续。手动设置在回调确认后才保存。此处“确认”指 ArkWeb 接收配置，不证明代理可连通。
3. 代理修复候选已提交并推送：`5e4d5abf46247fc5c6c5ee693b0f004d482d9d38`（分支 `fix/arkweb-proxy-state`）。Node 回归 11/11、`git diff --check` 通过；假时钟测试执行生产页代理切换方法，且已另行通过 Windows 隔离 SDK 对齐构建和 MatePad 固定 SHA 构建验证。MatePad WorkBuddy 已完成单项固定 SHA 构建；回执分支 `matepad/build-proxy-state-5e4d`、提交 `f9603240237d91791f1923a9a035d638997da4ed`，仅新增 `coordination/matepad-build-proxy-state-5e4d.md`。回执分支基于命名分支 `fix/arkweb-proxy-state` 的 HEAD `7d8c910c1409b0de5a89f89049eaf7a17925d7e3`，与构建源码 SHA 不同；回执中明确写明实际构建源码 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38`。旧回执只覆盖 `2d106031f2fa6d0bd8018b053abaf9e257f40513`，不得用于此版。
4. 新候选构建通过后，由用户在 MatePad DevEco 本机签名、安装和启动。第一轮不登录：先检查无代理时的提示/重试，再用用户自己的网络环境检查 Threads 首屏、公开内容、图片和返回。代理端点、账号、HAP 和签名材料不回传。
5. P0 首屏过关后再测试登录、发帖、回复、关注、消息。Pura X View 手机/折叠形态需独立验收。定时自动接单不是产品开发前置，保持未开启。
