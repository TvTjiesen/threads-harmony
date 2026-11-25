# 华为开发工具验证记录（2026-11-25）

## 已验证：DevEco CLI 稳定版

- 为避免污染项目依赖，使用 npm 将 `@deveco/deveco-cli@1.3.0-stable` 安装到 Windows 临时隔离目录 `C:/Users/杰森/AppData/Local/Temp/threads-deveco-tools/cli-stable-20261125/`；未向项目添加依赖或 lock 文件。首次安装时参数传递有误，不能确认已禁用 postinstall（该脚本会后台启动文档初始化进程），因此不宣称安装期间无后台初始化。Node 为 `v24.14.0`，符合包的 Node `>=22` 要求。
- npm metadata 给出的稳定 tag 为 `1.3.0-stable`；`latest` 是 `1.3.13-alpha`，本轮不采用 alpha。
- 已验证 CLI 版本输出 `1.3.0-stable`；通过 `docs search ProxyController --limit 3` 与 `docs read ...ProxyController...` 搜索并读取本地鸿蒙文档。官方文档明确：ProxyController API 从 API 15 起支持；`applyProxyOverride` 和 `removeProxyOverride` 都应在回调触发后才加载页面，且代理变化“不保证网络连接后会立即使用新的代理配置”。这支持页面当前先 await 回调、超时不能假装操作取消的设计；并不证明当前源码正确或设备行为通过。
- CLI `device list --format json` **失败**：`Failed to initialize device manager: DevEco Studio installation not found in default locations.` 因此 Windows 当前没有验证过的 DevEco Studio/SDK/Hvigor/设备调试路径；CLI 单独不是编译器或 SDK。HarmonyOS ArkTS 构建仍由 MatePad 本机 CLT 执行。
- CLI 文档提到 Windows 自动发现 DevEco Studio >=6.0.0 或显式 CLT 配置 >=26.0.0；但仅凭文档不代表本机存在这些安装。本轮只完成 CLI 验证，尚未下载完整 SDK，也未更改系统 PATH/注册表。用户已授权下载华为工具；后续建立 Windows 构建链时，先核实官方安装包来源、版本、磁盘空间和目标 SDK，再执行安装验证，不要求用户重复授权普通下载。
- 遥测：调用 CLI 时设置 `DEVECO_CLI_DISABLE_TELEMETRY=1` 与 `DEVECO_CLI_SKIP_VERSION_CHECK=1`。后者只关闭本次 CLI 版本检查；首次安装的脚本禁用参数未可靠生效，不能把调用时设置的环境变量外推到安装过程。工具未启用 DSH/HarmonyOS MCP，也没有替用户登录。

## 工具边界与下一步

- DevEco CLI 可由 DSH 用于本地文档查询、静态 Lint（在能发现 Studio/CLT 的机器上）、设备列表/日志/截图/UI 检查等；每条命令仍按副作用审查。`device/run/signature` 可能访问设备或改变签名/安装状态，必须先取得本轮明确授权，默认不自动执行。
- 当前 Windows 仅验证本地文档能力；MatePad WorkBuddy 承担固定 SHA 构建与少量设备专属读数。签名、安装、运行、登录由用户掌控。
- 后续迭代：DSH 设计/实现 → 从生产页提取方法做回归和同步镜像 → 本机文档/Lint（如可用）→ 审查 diff 和安全边界 → 固定 SHA → WorkBuddy 单任务 MatePad 构建或用户批准的单项设备检查 → DSH 独立核对回执。失败由 DSH 根据脱敏错误修复；不让 WorkBuddy 自行改代码。
- 本机真实设备路径未验证；不能把 `device list` 的错误解释为设备坏或 HDC 不可用，只能说 CLI 找不到 DevEco Studio。
