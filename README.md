# Threads for HarmonyOS · 原生界面候选

这是非官方、手机优先的 HarmonyOS 工程。ArkUI 主界面包含**首页、搜索、发帖、动态、我的**：窄窗用底栏，宽窗设计为侧栏。「发帖」打开独立草稿流程；首页的「为你／关注中」各记阅读位置；「动态」按赞、收藏、回复展示本机互动；「我的」管理收藏和本机帖子，并可进入设置。参考 [HarmonyX 公开更新日志](https://github.com/haohaoai0/HarmonyX/blob/main/CHANGELOG.md) 中的导航与阅读体验，使用本项目的 ArkUI 实现和系统图标。

本机帖子、点赞、关注和收藏可在同一安装重启后恢复；本地回复只保留在当次运行。所有原生操作均不连接 Threads，也不会写入 Threads 账号。

**真实 Threads** 由独立 ArkWeb 页面打开官方站点，网络设置中可以把固定的官方首页链接交给系统处理。本项目不提供原生真实账号时间线、私有 API 或登录信息同步。应用本机状态不能和官方网页操作混为一谈。当前构建、设备与网页实测口径见 [测试矩阵](TEST-MATRIX.md)。

非官方 ArkTS/ArkUI + ArkWeb 原型，使用官方 Threads 网站，外层提供基础原生导航和错误提示。MatePad 上的独立探针曾编译出未签名 HAP，且单独通过 DevEco 签名安装运行；Threads 页面仍曾白屏。2026-11-24 MatePad 已通过 GitHub MCP 将 15 个无签名的 HarmonyLocalProbe 源文件交接到分支 `matepad/source-handoff-6b5c`（固定 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6`）。同日，CodeArts 在 MatePad 独立目录从该提交重建成功（15 个文本文件按 blob SHA 校验，另补两个原有 PNG）；Windows 核验了回执 `7bbe80b0ec74e393d9e690e71671db491c2239cf`。本次 HAP 未签名、未安装、未运行，与下文的完整 ArkWeb 候选是不同版本。

## 设备与共享流程

GitHub 仓库已由用户告知转为公开；MatePad 与 Windows DSH 的分工见 [AI-WORKFLOW.md](AI-WORKFLOW.md)，Windows 华为工具验证见 [HUAWEI-TOOLS.md](HUAWEI-TOOLS.md)，MatePad 当前小任务见 [coordination/MATEPAD-NEXT.md](coordination/MATEPAD-NEXT.md)，手机 smoke 验收范围见 [coordination/MATEPAD-PHONE-SMOKE.md](coordination/MATEPAD-PHONE-SMOKE.md)，首次安全转交纯源码见 [SOURCE-HANDOFF.md](SOURCE-HANDOFF.md)，自动化备选路线见 [AUTOMATION-OPTIONS.md](AUTOMATION-OPTIONS.md)。Windows 开发分支已推送。Windows 在独立新目录完成了 `matepad/first-handoff` 回执分支推送，但回执明确记载由 Windows 代交；MatePad CodeArts 曾通过认证 GitHub MCP 完成基线源码读取、构建和回写；随后 WorkBuddy 对 ArkWeb 固定候选精确构建成功，详见回执。任务桥仅本机安全测试，未启动；定时自动接单未验证。

- Windows DSH 主助手负责主仓库中的产品设计、ArkTS实现、代码审查、安全测试、Git 与错误修复。MatePad WorkBuddy 只按 DSH 固定的 SHA 执行一次一个的本机构建/窄设备核验并回传脱敏结果，不自行修改业务代码。它不是实时同步：先提交并固定 SHA，MatePad 从该 SHA 工作，在独立分支写回验收记录；Windows DSH 再核对父 SHA、差异文件及回执。不得两端同时编辑同一业务分支。
- MatePad 上已验证手动构建与结果回写；未验证定时唤醒、后台驻留或无人自动接单，不应把它当作持续运行的 Git worker。
- 进度以[项目状态](STATUS.md)和[测试矩阵](TEST-MATRIX.md)为准；协作者不要记录账号凭据、Cookie、私信原文或签名私钥。
- MatePad 已对先前固定版提供窗口布局、详情和交互证据；这些不能替代本候选验收。Pura X View 是主要手机硬件验收设备；登录、当前版折叠与实际帧率需分别验证。

## 当前开发工程（Stage）

已从 MatePad 验收的脱敏源码提交 `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 在 Windows 仓库准备 `app/` Stage 工程副本；15 个提交内文本文件经 Git blob SHA 校验后复制，两个图标用本地自制占位 PNG 替代。`app/entry/src/main/ets/pages/Index.ets` 来自 `overlay/`，WebView attach 后再应用已存代理并加载首页；代理改为回调成功后再持久化；20 秒无响应会停止请求并提示检查网络；明确拒绝网页权限和 TLS 错误，并捕获主框架 HTTP 错误。签名配置为空，构建产物、签名材料均被忽略。Windows 已用 DevEco SDK API 26 `26.0.1.120` Beta1 对同一代理修复版做本地编译验证，仅在隔离副本覆盖 `compileSdkVersion`。**历史构建记录（不是当前阻塞）**：固定候选 `2d106031f2fa6d0bd8018b053abaf9e257f40513` 曾由 MatePad WorkBuddy 对精确源码 SHA 构建通过，三次 unsigned HAP 均为 56,075 字节；回执详见分支 `feat/arkweb-build-2d1060` 的 `coordination/arkweb-build-receipt.md`。代理状态修复版 `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 也曾由 WorkBuddy 编译并回传，历史回执 `f9603240237d91791f1923a9a035d638997da4ed`。这些回执不覆盖目前原生时间线；现有当前版本构建、签名与模拟器验收状态见本文件顶部及 [测试矩阵](TEST-MATRIX.md)。

## 开发与构建流程

1. 当前 Stage 工程 `app/` 已在仓库中，Bundle Name 为 `com.tvtjiesen.threadsharmony`（由用户确认华为后台已有对应 HarmonyOS 应用记录），签名配置为空，图标为自制占位图。Windows 仓库副本保持可复现配置；本机 Beta SDK 构建需在临时副本对齐 `compileSdkVersion`，不要把这个差异提交或擅自改仓库设置。
2. 主开发在 Windows DSH 工作区进行：ArkUI 时间线维护在 `app/entry/src/main/ets/pages/Timeline.ets`，ArkWeb 页面维护在 `overlay/entry/src/main/ets/pages/Index.ets`；只有改 ArkWeb 时才运行 `node tools/sync-overlay.mjs` 预览并审阅，再按脚本保护条件同步 Stage 镜像。运行 Node 回归、检查 `git diff --check` 和安全差异。
3. Windows DSH 使用 DevEco Studio 自带 Hvigor 在纯 ASCII 的隔离工作树编译 ArkTS。因本机 SDK `26.0.1.120` 为 Beta1，固定 SHA 构建时可能仅在副本将 `compileSdkVersion` 从 `26.0.0` 对齐到 `26.0.1`；该补丁不进入提交。可重复入口为 `tools/build-windows-arkts.ps1 -SourceSha <40位SHA>`，会检查精确 HEAD、构建 unsigned HAP、输出 SHA256 并清理临时工作树，不签名、不部署。具体限制见 [华为工具验证](HUAWEI-TOOLS.md)。实际安装使用独立的 E 盘 DevEco 工程及本机调试签名；该路径已验证当前版手机模拟器。签名配置和本地 HAP 不进入仓库。
4. 构建通过后用户在 MatePad DevEco GUI 自行签名、安装、启动；签名材料不可提交或交给 DSH。先不登录，检查代理提示、Threads 首页、公开内容、图片和返回。
5. Pura X View 连接、签名、安装、登录、发帖/消息和折叠适配均需用户亲自授权并分项验收；按 `TEST-MATRIX.md` 记录，不把构建成功当作实机功能通过。

## ArkWeb 原型限制

- 顶层导航只允许 `Index.ets` 中精确列出的 Threads、Instagram 和 Meta 登录主机，HTTPS、主框架、标准端口；离开站点的链接目前会拦截。登录若被拦，先核实官方跳转主机再小范围放行，不能无条件允许所有 URL。
- 子资源并非仅可加载这些主机；顶层 allowlist 不会代替 Android/iOS/ArkWeb 的完整 Web 安全边界。此原型未开放文件访问、混合内容或多窗口。
- 网络设置中的系统转交仅打开固定官方 HTTPS 首页，不携带应用代理、会话或拦截到的 URL；能否由浏览器处理取决于设备。媒体上传/下载、系统分享、推送、角标和真实账号原生信息流不在本候选范围。

## 其他平台

HarmonyOS 是第一平台，Android 是未来独立目标。ArkTS 与 Android Kotlin UI 不共享；项目初期先共享品牌/design tokens、公开模型和验收用例，不跨平台复制登录会话。Android 工程/API/minSdk 在实际 spike 后确定，避免现在选一个未经验证的跨端框架限制鸿蒙适配。
