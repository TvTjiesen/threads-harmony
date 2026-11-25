# 华为开发工具验证记录（2026-11-25）

## 已验证：DevEco CLI 稳定版

- 为避免污染项目依赖，使用 npm 将 `@deveco/deveco-cli@1.3.0-stable` 安装到 Windows 临时隔离目录 `C:/Users/杰森/AppData/Local/Temp/threads-deveco-tools/cli-stable-20261125/`；未向项目添加依赖或 lock 文件。首次安装时参数传递有误，不能确认已禁用 postinstall（该脚本会后台启动文档初始化进程），因此不宣称安装期间无后台初始化。Node 为 `v24.14.0`，符合包的 Node `>=22` 要求。
- npm metadata 给出的稳定 tag 为 `1.3.0-stable`；`latest` 是 `1.3.13-alpha`，本轮不采用 alpha。
- 已验证 CLI 版本输出 `1.3.0-stable`；通过 `docs search ProxyController --limit 3` 与 `docs read ...ProxyController...` 搜索并读取本地鸿蒙文档。官方文档明确：ProxyController API 从 API 15 起支持；`applyProxyOverride` 和 `removeProxyOverride` 都应在回调触发后才加载页面，且代理变化“不保证网络连接后会立即使用新的代理配置”。这支持页面当前先 await 回调、超时不能假装操作取消的设计；并不证明当前源码正确或设备行为通过。
- CLI `device list --format json` **失败**：`Failed to initialize device manager: DevEco Studio installation not found in default locations.` 因此 Windows 当前没有验证过的 DevEco Studio/SDK/Hvigor/设备调试路径；CLI 单独不是编译器或 SDK。HarmonyOS ArkTS 构建仍由 MatePad 本机 CLT 执行。
- CLI 文档提到 Windows 自动发现 DevEco Studio >=6.0.0 或显式 CLT 配置 >=26.0.0；但仅凭文档不代表本机存在这些安装。本轮只完成 CLI 验证，尚未下载完整 SDK，也未更改系统 PATH/注册表。用户已授权下载华为工具；后续建立 Windows 构建链时，先核实官方安装包来源、版本、磁盘空间和目标 SDK，再执行安装验证，不要求用户重复授权普通下载。
- 遥测：调用 CLI 时设置 `DEVECO_CLI_DISABLE_TELEMETRY=1` 与 `DEVECO_CLI_SKIP_VERSION_CHECK=1`。后者只关闭本次 CLI 版本检查；首次安装的脚本禁用参数未可靠生效，不能把调用时设置的环境变量外推到安装过程。工具未启用 DSH/HarmonyOS MCP，也没有替用户登录。

## 本轮效率勘察（2026-11-25）

- Windows DSH 所在机再次检查：Node `v24.14.0` 可用；`hvigorw`、`hvigor`、`ohpm`、`hdc`、`adb` 均不在 PATH，已知 `C:/Program Files` 下未发现 DevEco/HarmonyOS SDK 安装，未发现 DevEco 安装目录；C 盘可用空间约 128.9 GB。系统枚举到两个 `Android ADB Interface` 设备接口，但本机没有 adb 命令，无法识别设备型号或证明 HDC 可连接。
- 官方下载中心 `https://developer.huawei.com/consumer/cn/download/` 与 CLT 页面均只返回 Angular SPA 外壳。其公开前端 JS 声明下载 API，但匿名 POST 得到 nginx 404；页面下载流程涉及开发者联盟登录。没有取得可校验的 Windows 安装包 URL、版本或哈希，因此**没有下载/安装未知镜像，也没有尝试绕过登录**。官方入口可由已登录浏览器访问；当前这台 DSH 无可用的开发者联盟下载会话。
- CLI `devecocli build --project .` 返回 `error: unknown option '--project'`；该工具以当前工程目录自动探测项目。随后在 `app/` 目录直接执行 `devecocli build`，25 秒内未返回且命令 shell 超时，未获得退出码或构建产物。故本机 CLI 尚未构建成功。因为本机没有发现 SDK/CLT，这一试验不替代 Hvigor。后续应先通过官方下载中心取得 Studio 或 CLT，再校验安装包来源/版本/哈希并装入隔离路径；CLI 设置 `DEVECO_CLI_CLT_PATH` 或 `DEVECO_CLI_STUDIO_PATH` 后才有条件进行项目构建。API 26 工程需要相应 SDK。
- 在 `app/` 执行 CLI `check lint entry/src/main/ets/pages/Index.ets`，退出码 1：`Error: DevEco Studio installation not found in default locations.`。因此本轮也没有取得 ArkTS Lint 通过证据。
- DSH 的 GitHub 仓库现已由用户改为公开；提交、推送后的内容可在两端读取，但这只是版本共享，不是文件实时同步、Agent 对话共享或自动唤醒。当前 Remote Hosts 发现失败，且没有 WorkBuddy 的远程执行/调度接口。因此本轮可把一次性验收任务写进仓库并固定 SHA，不能在 DSH 中直接启动 MatePad WorkBuddy。用户已确认 MatePad WorkBuddy 使用 **HY4Flash**，不是此前文档误记的 DeepSeek 4 Flash。

## 归档仓库候选 CLT（只读核验，未安装）

- 为避免猜测文件名，从 `https://repo.huaweicloud.com/harmonyos/compiler/hvigor/26.0.0.621/` 的目录索引发现 `command-line-tools.tar` 及同名 `.sha256`。下载至 Windows 临时目录后，文件为 351,515,648 字节；随包校验值与本地重新计算的 SHA-256 一致：`83888fb65cb80d40f07af0bd27d76cae005551265a3b0cd437b8a4f0c93d13cc`。该地址属于公开 Huawei Cloud 镜像域名，但本轮未取得它与华为开发者下载中心发布记录的对应证明；因此只把它作为候选归档信息，不视为已确认的官方正式安装来源。
- TAR 内 `version.txt` 明确标注 `Command Line Tools(linux-x64)`、版本 `26.0.0.621`、`releaseType: beta`、Hvigor `6.26.2`、HarmonyOS SDK `26.0.0 Beta2`（API 26）。`sdk/` 在归档中只有空目录，没有 SDK 文件；该包目标平台也是 Linux x64，不能给当前 Windows 主机建立构建链，也不应安装或拿它拼接本机工具链。已删除下载的 351 MB 临时归档；不更改项目依赖或系统配置。
- 只读查询同一归档索引中的其他 CLT 条目：`26.0.1.290`（TAR，360,777,728 字节）、`6.26.1`（ZIP，77,819,058 字节）、`7.26.0-arkts1.2-0601-02`（TAR，327,954,944 字节）。对 `6.26.1` ZIP 使用 HTTP Range 读取中央目录和 `version.txt`，确认也是 `Command Line Tools(linux-x64)`、`26.0.0.461`、Beta1、API 26，且仅有空 `sdk/` 目录。并未下载或安装这些包；索引不是已确认的 Windows 发布源，其他两个条目的平台/版本未验证。
- 故此结果没有改变本机状态：Windows 仍缺已验证的 DevEco Studio/Windows CLT/HarmonyOS SDK；没有构建、Lint、HDC 或设备调试的新证据。官方开发者下载中心仍是推荐获取 Windows 包的入口；本轮未找到可公开、可验证的 Windows 安装包 URL 与版本/哈希组合。

## 工具边界与下一步

- DevEco CLI 可由 DSH 用于本地文档查询、静态 Lint（在能发现 Studio/CLT 的机器上）、设备列表/日志/截图/UI 检查等；每条命令仍按副作用审查。`device/run/signature` 可能访问设备或改变签名/安装状态，必须先取得本轮明确授权，默认不自动执行。
- 当前 Windows 仅验证本地文档能力；MatePad WorkBuddy 承担固定 SHA 构建与少量设备专属读数。签名、安装、运行、登录由用户掌控。
- 后续迭代：DSH 设计/实现 → 从生产页提取方法做回归和同步镜像 → 本机文档/Lint（如可用）→ 审查 diff 和安全边界 → 固定 SHA → WorkBuddy 单任务 MatePad 构建或用户批准的单项设备检查 → DSH 独立核对回执。失败由 DSH 根据脱敏错误修复；不让 WorkBuddy 自行改代码。
- 本机真实设备路径未验证；不能把 `device list` 的错误解释为设备坏或 HDC 不可用，只能说 CLI 找不到 DevEco Studio。
