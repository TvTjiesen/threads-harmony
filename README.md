# Threads for HarmonyOS · P0 原型

非官方 ArkTS/ArkUI + ArkWeb 原型，使用官方 Threads 网站，外层提供基础原生导航和错误提示。MatePad 上的独立探针已编译出未签名 HAP；Windows 仓库的 overlay 尚未构建，两个版本尚未同步。签名、安装与真机运行均未验证。

## 设备与共享流程

MatePad 与 Windows DSH 的分工见 [AI-WORKFLOW.md](AI-WORKFLOW.md)，首次安全转交纯源码见 [SOURCE-HANDOFF.md](SOURCE-HANDOFF.md)，自动化备选路线见 [AUTOMATION-OPTIONS.md](AUTOMATION-OPTIONS.md)。已获用户授权创建私有 GitHub 仓库；Windows `main` 已推送。Windows 在独立新目录完成了 `matepad/first-handoff` 回执分支推送，但回执明确记载由 Windows 代交；MatePad 是否可登录、克隆和提交仍待实际验证。双端 Agent 的受控任务桥仅本机安全测试，未启动。

- 主仓库在 Windows，与 DSH 当前工作区同目录；MatePad Edge 白天通过用户已有远程桌面连接此 Windows 会话，编辑同一份文件、跑构建或模拟器并更新状态。
- 若 MatePad 的 CodeArts 是独立开发环境，不允许两端同时改同一分支；在确认 CodeArts 产品、账户和网络后，再用 Git 拉取/提交同步。
- 进度以 `STATUS.md` 和 `TEST-MATRIX.md` 为准；协作者不要记录账号凭据、cookie、私信原文或签名私钥。
- Pura X View 是主要硬件验收设备。手机不在时可做的任务：代码、文档、ArkTS 检查、模板构建、模拟器尺寸/API、非真实账号的离线 UI 检查。授权登录、真实消息、设备通知、折叠体验和性能必须留到手机测试。
- MatePad Edge 的 PC 环境能否运行 HarmonyOS 模拟器或侧载 HAP 未确认。PC 环境不等同 HarmonyOS app 运行时；在该设备实测前不把它登记为通过的鸿蒙运行端。

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
