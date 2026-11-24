# Threads for HarmonyOS · P0 原型

非官方 ArkTS/ArkUI + ArkWeb 原型，使用官方 Threads 网站，外层提供基础原生导航和错误提示。MatePad 上的独立探针曾编译出未签名 HAP，且单独通过 DevEco 签名安装运行；Threads 页面仍曾白屏。2026-11-24 MatePad 已通过 GitHub MCP 将 15 个无签名的 HarmonyLocalProbe 源文件交接到私有分支 `matepad/source-handoff-6b5c`（固定 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6`）。同日，CodeArts 在 MatePad 独立目录从该提交重建成功（15 个文本文件按 blob SHA 校验，另补两个原有 PNG）；Windows 核验了回执 `7bbe80b0ec74e393d9e690e71671db491c2239cf`。本次 HAP 未签名、未安装、未运行；Windows 仓库的独立代理面板 overlay 尚未构建。

## 设备与共享流程

MatePad 与 Windows DSH 的分工见 [AI-WORKFLOW.md](AI-WORKFLOW.md)，首次安全转交纯源码见 [SOURCE-HANDOFF.md](SOURCE-HANDOFF.md)，自动化备选路线见 [AUTOMATION-OPTIONS.md](AUTOMATION-OPTIONS.md)。已获用户授权创建私有 GitHub 仓库；Windows `main` 已推送。Windows 在独立新目录完成了 `matepad/first-handoff` 回执分支推送，但回执明确记载由 Windows 代交；MatePad CodeArts 已通过认证 GitHub MCP 实际完成固定提交源码读取、同源 CLT 构建和结果分支回写；Windows 已核验回执 `7bbe80b0ec74e393d9e690e71671db491c2239cf`，父提交为源码 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6`。任务桥仅本机安全测试，未启动；定时自动接单未验证。

- Windows DSH 维护主仓库，MatePad CodeArts 通过已认证 GitHub MCP 按固定 SHA 执行独立任务并回传结果。它不是实时同步：先提交并固定 SHA，MatePad 从该 SHA 工作，在独立分支写回验收记录；Windows 再核对父 SHA、差异文件及回执。不得两端同时编辑同一业务分支。
- CodeArts MCP 的手动任务已成功，未验证定时唤醒、后台驻留或无人自动接单；不应把它当作持续运行的 Git worker。
- 进度以 `STATUS.md` 和 `TEST-MATRIX.md` 为准；协作者不要记录账号凭据、cookie、私信原文或签名私钥。
- MatePad Edge 已验证旧独立探针可在 PC 本机 DevEco 形态签名、安装和启动；交接新版本尚未安装。Pura X View 是主要手机硬件验收设备；授权登录、真实消息、设备通知、折叠体验和性能必须留到手机测试。

## 当前开发工程（Stage）

已从 MatePad 验收的脱敏源码提交 `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 在 Windows 仓库准备 `app/` Stage 工程副本；15 个提交内文本文件经 Git blob SHA 校验后复制，两个图标用本地自制占位 PNG 替代。`app/entry/src/main/ets/pages/Index.ets` 来自 `overlay/`，WebView attach 后再应用已存代理并加载首页；代理改为回调成功后再持久化；20 秒无响应会停止请求并提示检查网络；明确拒绝网页权限和 TLS 错误，并捕获主框架 HTTP 错误。签名配置为空，构建产物、签名材料均被忽略。HarmonyOS SDK 尚未在 Windows 验证；请由 MatePad CodeArts 认证 GitHub MCP 读取此分支最新 SHA `77cf325267f7e094b8a1e978630e5513aa8fbd99`，在 MatePad 新建独立目录并仅运行 `hvigorw assembleHap --no-daemon -p product=default`。该工作区不含本机签名配置；构建通过后，回到 MatePad DevEco 打开 `app/` 并配置本机自动签名、安装运行。不要回传或提交 HAP、日志、签名材料。

## Windows 首次构建

1. 在[华为官方 DevEco Studio 页面](https://developer.harmonyos.com/cn/develop/deveco-studio)获取当前正式版本。CodeArts 鸿蒙开发实践文档要求 Windows 10/11 x64 或 macOS 12+、DevEco 6.0.0+、Python 3.x、Node 21+ 与 Git；本项目按 Windows 侧 DevEco 6.0.0+ 规划（先核实华为当前支持版本），再安装适配 Pura X View 系统/API 的 SDK。不要采用过期包管理器条目或照搬模板 `compileSdkVersion`。
2. 在本目录使用 DevEco 的 Stage/ArkTS 空应用模板创建 `app/` 工程，核对其 `compileSdkVersion`、`compatibleSdkVersion`、`runtimeOS` 是 SDK 安装器实际提供的版本。保留模板元信息；签名材料不可提交。
3. 模板创建后，先确认 `app/entry/src/main/module.json5` 声明了 `ohos.permission.INTERNET`。然后运行 `node tools/sync-overlay.mjs` 预览；检查 `git status`，提交新模板页面作为回退点，再运行 `node tools/sync-overlay.mjs --apply`。脚本只替换 `Index.ets`，拒绝未跟踪/未提交页面，不改权限或其他模板声明。
4. 在 DevEco 先构建空模板，再构建本原型。查看 ArkTS 编译器对于 ArkWeb 拦截事件签名、解析 URL、布局和事件回调的报告，按**当前安装 SDK**修正 API 兼容，不将静态推测记为通过。
5. Pura X View 开启开发者模式/USB 调试，连接主机并授权；设备可见后配置本地开发签名，运行应用。不要提交开发证书或 `.p12`。
6. 逐项填写 `TEST-MATRIX.md`。只通过 Threads/Instagram/Meta 官方页面登录；不记录任何密钥、Cookie 或消息正文。

## ArkWeb 原型限制

- 顶层导航只允许 `Index.ets` 中精确列出的 Threads、Instagram 和 Meta 登录主机，HTTPS、主框架、标准端口；离开站点的链接目前会拦截。登录若被拦，先核实官方跳转主机再小范围放行，不能无条件允许所有 URL。
- 子资源并非仅可加载这些主机；顶层 allowlist 不会代替 Android/iOS/ArkWeb 的完整 Web 安全边界。此原型未开放文件访问、混合内容或多窗口。
- 暂无外部浏览器转交、媒体上传/下载、系统分享、推送、角标或完整原生信息流。浏览器可用不等于嵌入后也可用。

## 其他平台

HarmonyOS 是第一平台，Android 是未来独立目标。ArkTS 与 Android Kotlin UI 不共享；项目初期先共享品牌/design tokens、公开模型和验收用例，不跨平台复制登录会话。Android 工程/API/minSdk 在实际 spike 后确定，避免现在选一个未经验证的跨端框架限制鸿蒙适配。
