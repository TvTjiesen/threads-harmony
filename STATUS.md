# 项目状态

## 当前阶段

P0：MatePad 已构建并在 DevEco 本机签名、安装、启动过独立 `HarmonyLocalProbe`；Threads 网页曾停在白屏加载。2026-11-24 CodeArts 经认证 GitHub MCP 完成源码交接，并在 MatePad 独立目录从固定源提交重建成功。源 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6`；构建回执 SHA `7bbe80b0ec74e393d9e690e71671db491c2239cf`，其父提交正是源 SHA。命令退出码 0，生成未签名 HAP 27,229 字节；未安装、未运行。详见 [跨端协作记录](AI-WORKFLOW.md)。

## 工作分工

- **Windows + DSH**：主 Git 仓库、唯一源代码事实源、DevEco/SDK/构建与手机连接后安装签名。
- **MatePad Edge + CodeArts**：CodeArts 26.9.501 在工作区能调用系统 CLT。Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、codelinter 6.0.140 的版本查询均退出码 0；MatePad CodeArts 已通过认证 GitHub MCP 完成源码交接、固定提交重建和脱敏结果回传；定时自动触发仍未验证。独立工程此前已通过 DevEco GUI 签名、安装和启动，非此交接版本的证据。
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
- **Windows DSH 主机**未发现 DevEco、HarmonyOS SDK 或 `hdc`。USB 清单中能看到 Android ADB 接口，但尚未识别连接的是哪台设备；ADB 可见不能证明 HarmonyOS HDC 可用。此结论只描述 Windows 主机，不适用于 MatePad。
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

1. 已收到但不接受为当前候选验收的回执：`matepad/build-arkweb-reliability` 的 `8fdfd93febb2d17a67179107573a3d6967a32465` 只新增回执，正文证明实际构建 SHA 是旧版 `fd9f9cf3c4d1f79bdd65f28b39b0405c86be43dc`（成功，54,421 字节）。当前待验收源码是 `2d106031f2fa6d0bd8018b053abaf9e257f40513`；两提交之间 `app/entry/src/main/ets/pages/Index.ets` 有 ArkTS 变更。请从精确 SHA 重建后回传新回执，详情见 AI-WORKFLOW.md；不签名、安装或上传 HAP。
2. 仅当 MatePad 构建通过后，在 MatePad DevEco 打开该独立 `app/`、本机调试签名并安装启动。签名材料留本机；记录与旧 HarmonyLocalProbe 分开。
3. 首先无代理启动，检查错误提示/重试；再配置有效代理观察 Threads 首屏。代理端点不要写入 Git 或回执。
4. P0 网络门槛通过后，继续验返回/刷新、公开内容和图片；再单独测登录、发帖、回复、关注、消息。Pura X View 手机/折叠形态仍需独立验收。
4. 定时自动接单不是产品开发前置；保持未启用，等客户端有明确价值后再单独授权探针。
5. 当前分支 `feat/arkweb-reliability` 的 `overlay/` 已改进加载超时、重试看门狗和代理偏好设置持久化；并准备 `app/` Stage 工程以便 MatePad 接手构建。其两个图标是自制占位图，工程未签名；ArkTS 改动尚未由 HarmonyOS SDK 编译。使用 `about:blank` 初始化 WebView，等待 `onControllerAttached` 后再加载；已保存代理须等待 ArkWeb 回调才加载 Threads，代理回调也有 20 秒超时恢复，页面加载超时会停止请求并提示重试。候选固定 commit `2d106031f2fa6d0bd8018b053abaf9e257f40513`；Windows Node 回归 9/9 通过，ArkTS 尚未由 MatePad 编译。通过 MatePad CodeArts 实测前不得标为可用产品。
6. 只读代理流程审查（2026-11-24）发现待后续处理项，当前冻结候选不修改：代理应用等待超时后本地作废回调但未撤销可能迟到的 ArkWeb override，UI 状态可能与底层代理不一致；已保存代理启动失败仅清空输入、未清理持久化值，可能重启重复失败；关闭代理没有回调 watchdog，回调不来时状态/偏好可能悬挂。必须先取得精确 SHA 的构建回执，再另开修复提交、测试并重新构建，不能直接签装本候选绕过这些风险。
7. 本 DSH 会话并发上限为主 Agent + 最多 1 个子 Agent；同一工程编辑、构建、部署依次串行。
