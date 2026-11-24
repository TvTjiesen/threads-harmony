# 项目状态

## 当前阶段

P0：MatePad 已构建、签名、安装并启动独立的 `HarmonyLocalProbe`；原生工具栏已显示，Threads 网页仍停在白屏加载。Windows 仓库中的新版尚未在 MatePad 用同一份源码构建。CodeArts 私库只读探针未读到提交或文件，见 [跨端协作记录](AI-WORKFLOW.md)。

## 工作分工

- **Windows + DSH**：主 Git 仓库、唯一源代码事实源、DevEco/SDK/构建与手机连接后安装签名。
- **MatePad Edge + CodeArts**：CodeArts 26.9.501 在工作区能调用系统 CLT。Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、codelinter 6.0.140 的版本查询均退出码 0；它已在独立 HarmonyLocalProbe（API 26）实际构建空白工程和 ArkWeb Threads 原型。此证据更新了早期沙箱报告中“CodeArts 不能构建”的初步判断（先前探测的应用沙箱与本轮工作区/CLT 调用能力不同）。MCP 未配置且非当前必要。DevEco 签名配置、安装/部署、GUI Git clone/push 均未验证；优先考虑私有 Git 同步，但尚未建立。
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
- 上述未签名 HAP 是最初 CLI 产物；随后用户通过 DevEco 在「此电脑」签名、安装并启动同名探针，原生工具栏显示，Threads 内容白屏加载。登录与其他网页功能未验收。MCP 未配置；无需为了本地构建先做 pong 探针。
- 私有远端已创建；Windows `threads-harmony` 与 MatePad `HarmonyLocalProbe` 尚未同步，也没有自动回传。不要双端并行改业务代码。

## 跨端接入方案（2026-11-23 22:39）

- **Host 插件已安装，未生效**：`ds-harness-remote@0.6.7` 已用官方 launcher 装进 `desktop` profile（`+ ds-harness-remote 0.6.7`、`Packages: +9 -54`、guard 校验通过）。`package.json` dependencies 31 项 / bundles 34 项，只新增该项，无删除。**必须重启 DSH 才生效。**
- 选型理由、已知限制（Windows Host 锁恢复待上游验证）、重启后自检清单、鸿蒙客户端构建命令，见 [REMOTE-ACCESS.md](REMOTE-ACCESS.md)。
- 自建桥 `tools/bridge/`（LAN HTTP + ntfy 分块中继 + 单文件 worker，端到端已验证）降级为兜底，不再作为主路径。

## 下一步

1. 用户已从 CodeArts 获得只读核对：bundleName `com.example.harmonylocalprobe`；versionCode/versionName `1000000 / 1.0.0`；deviceTypes `tablet/2in1`；工程 signingConfigs 为空；`hdc list targets` 返回 0 个目标。该结果不代表 DevEco GUI 不能识别同机目标。
2. **运行目标已确认是本机「此电脑」**，且独立探针工程已用自动签名成功安装并启动。接下来把同样的自动签名用到 Threads 原型工程：DevEco 里打开 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe`（当前打开的是 `test`，不是它），运行一次，确认日志中 HAP 名变为 `entry-default-signed.hap` 且 `Launch com.example.harmonylocalprobe success`。若签名配置未继承，点日志里的 `Open signing configs` 勾选自动生成签名即可。
3. 若 Threads 工程在 DevEco 里打开后无运行目标或模板报错，再按 [HiShell 备选核实提示词](MATEPAD-LOCAL-FALLBACK.md) 处理；本机目标已在 `test` 工程验证可用，不再是首要疑点。反馈时区分签名、安装、启动三步。
4. 真机先测首页加载、图片、滚动、返回/刷新及失败提示；记录脱敏日志和设备系统，之后再测试登录/身份验证跳转。未测能力仍标“未测”。
5. 源码交接独立于真机验收：若尚未配置签名，可让 CodeArts 先按 [纯源码 ZIP 交接](SOURCE-HANDOFF.md) 导出当前编译基线，用户私下传给 DSH。未收到源码包；导入前先检查归档与本机配置，暂不设置远端，不双端同时修改业务源码。
6. 本 DSH 会话的并发上限为主 Agent + 最多 1 个子 Agent；不限制用户在 MatePad 另外运行 CodeArts。工程内改动与构建/部署依次串行。系统 build 到 SDK API level 映射仍待核实。
