# 华为开发工具验证记录（2026-11-25）

## 历史记录：独立安装的 DevEco CLI 稳定版

- 为避免污染项目依赖，使用 npm 将 `@deveco/deveco-cli@1.3.0-stable` 安装到 Windows 临时隔离目录 `C:/Users/杰森/AppData/Local/Temp/threads-deveco-tools/cli-stable-20261125/`；未向项目添加依赖或 lock 文件。首次安装时参数传递有误，不能确认已禁用 postinstall（该脚本会后台启动文档初始化进程），因此不宣称安装期间无后台初始化。Node 为 `v24.14.0`，符合包的 Node `>=22` 要求。
- npm metadata 给出的稳定 tag 为 `1.3.0-stable`；`latest` 是 `1.3.13-alpha`，本轮不采用 alpha。
- 已验证 CLI 版本输出 `1.3.0-stable`；通过 `docs search ProxyController --limit 3` 与 `docs read ...ProxyController...` 搜索并读取本地鸿蒙文档。官方文档明确：ProxyController API 从 API 15 起支持；`applyProxyOverride` 和 `removeProxyOverride` 都应在回调触发后才加载页面，且代理变化“不保证网络连接后会立即使用新的代理配置”。这支持页面当前先 await 回调、超时不能假装操作取消的设计；并不证明当前源码正确或设备行为通过。
- CLI `device list --format json` **失败**：`Failed to initialize device manager: DevEco Studio installation not found in default locations.` 这是安装 Studio 前的记录，不适用于下述直接使用 Studio 自带 Hvigor 的构建。CLI 本身不是编译器或 SDK。
- 历史记录：CLI 文档提到 Windows 自动发现 DevEco Studio >=6.0.0 或显式 CLT 配置 >=26.0.0；当时未发现这些安装。用户后来确认 Studio 已安装，当前状态及实际构建以本文件上方“Windows DSH 主机工具链更新”为准。
- 遥测：调用 CLI 时设置 `DEVECO_CLI_DISABLE_TELEMETRY=1` 与 `DEVECO_CLI_SKIP_VERSION_CHECK=1`。后者只关闭本次 CLI 版本检查；首次安装的脚本禁用参数未可靠生效，不能把调用时设置的环境变量外推到安装过程。工具未启用 DSH/HarmonyOS MCP，也没有替用户登录。

## Windows DSH 主机工具链更新（2026-11-25）

可重复的隔离构建入口：`tools/build-windows-arkts.ps1 -SourceSha <40位源码SHA>`。脚本只接受固定 Git SHA，拒绝覆盖已存在工作树；检查 HEAD 后只在临时副本把唯一 `compileSdkVersion: 26.0.0` 改成 `26.0.1`，构建 unsigned HAP、输出 SHA256，并清理临时工作树。它不会签名或部署。

- 用户确认已安装 DevEco Studio 并安装 DSH 鸿蒙插件。通过 Windows 注册表和运行进程发现安装于 `C:\DevEco Studio`：`DisplayName=DevEco Studio`、`DisplayVersion=261.23567.138.36.2601290`；`devecostudio64.exe` 的 Authenticode 状态为 `Valid`，签名发布者为 Huawei Technologies Co., Ltd.，ProductVersion `261.23567.138.36.2601290-DS`。这纠正了本文件早先“Windows 没有 DevEco Studio”的旧状态。
- Studio 自带构建工具：`C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`，`C:\DevEco Studio\tools\node\node.exe`（`v24.14.1`），`C:\DevEco Studio\tools\ohpm\bin\ohpm.bat`；SDK 自带 `C:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`（`Ver: 3.2.0f`）。SDK 包元数据 `C:\DevEco Studio\sdk\default\sdk-pkg.json` 标记 API 26、platformVersion `26.0.1`、releaseType `Beta1`、版本 `26.0.1.120`；这是 Beta SDK，不应描述成稳定发行版。DSH 的 `@duke-dsh-plugins/dsh-deveco@0.10.0` 已启用，能提供工程检查、ArkWeb DOM/ArkTS 调试和 UI/日志工具；它依赖 Studio/CLT/HDC，本身不是 SDK。
- 构建验证使用独立 detached worktree `C:\tmp\threads-harmony-build-5e4d`，HEAD 固定为代码候选 `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38`，未改主工作区的已提交源代码。先以原样 `26.0.0` 构建，Hvigor 明确失败：`00303313 Configuration Error`，`compileSdkVersion 26.0.0` 与本机 DevEco/SDK `26.0.1` 不兼容。仅在临时 worktree 将 `app/build-profile.json5` 的 `compileSdkVersion` 改为 `26.0.1`（`compatibleSdkVersion` 和 `targetSdkVersion` 保持 `26.0.0`）后，执行 `hvigorw.bat clean assembleHap --no-daemon -p product=default` 成功：随后又从干净状态重复执行相同命令，`BUILD SUCCESSFUL in 5 s 651 ms`，35 tasks（34 executed、1 up-to-date）。产物 `entry-default-unsigned.hap` 为 61,814 bytes，SHA-256 `752600fdd706c4a06a62d06453d5f8927a2d27ba3fa96639808590094fe48b21`；另两次 clean build 同字节数，哈希分别为 `6b36c7437a35f05d0c8407aad920e88d1312b47e5d7ab78aa96e16fff31750c8` 与 `c8af50c3875d68ca4d967078c098cc5442b06a7790cffd904110562d36bb51ce`。新脚本再次验证 `BUILD SUCCESSFUL in 6 s 665 ms`。构建输出含 `No signingConfig found for product default`，所以未签名。此结果仅证明固定源码在**本地临时 SDK 对齐副本**可编译打包，不是原始已推送提交原样构建，也不是稳定 API 26 SDK/真机验证。
- Hvigor 首次在原 Windows 工作区路径构建时被 Harmony 工程路径校验拒绝（路径含中文用户目录）；后续使用纯 ASCII 的 `C:\tmp` worktree。该次失败在主工作区留下 `.hvigor/outputs/build-logs/build.log`；仓库现忽略根目录下的 `.hvigor/`，不提交生成日志。HDC 初次探测无目标；最新平板模拟器连通证据见下节。没有签名、部署或应用运行证据。

### Windows 模拟器与签名入口

**手机优先更新（2026-11-25）**：工程入口 `app/` 已在 `entry/src/main/module.json5` 声明 `phone`、`tablet`、`2in1`，因此下一编译/验收不再只有平板。手机候选 SHA `da480b43c92fbf9d364ae84efaf63197d17205c7` 执行了 `CompileArkTS` 并生成 61,838 字节 unsigned HAP（SHA-256 `97478d6efd05c7327562dcde2a51b25bbb5801f386d74a79e214c33986912963`）；只在临时工作树对齐 `compileSdkVersion`，兼容/目标仍 26.0.0。没有签名/安装/运行。

手机模拟器：在用户明确同意后，DevEco CLI 接受模拟器许可并下载官方 HarmonyOS 7.0.0(26.0.0) phone Release 7.0.0.107 镜像（2,090,038,765 字节）。新建 `ThreadsHarmonyPhone` 并启动成功，HDC `list targets` 返回 `127.0.0.1:5555`，读取系统版本为 `7.0.0.107(SP8DEVC00E999R4P11)`。这只证明官方手机模拟器/HDC 通道可用；应用尚未签名、安装或运行。旧 `Mate 90 Pro` 配置引用的 26.0.1 Beta1 镜像缺失，仍无法启动。

**DevEco 自动调试签名的实际界面**：从 Windows Studio 打开要验收的工程 `app/`（本轮隔离候选副本位于 `C:\tmp\threads-harmony-phone-da480b4-local\app`），菜单 **File > Project Structure... > Project > Signing Configs**。官方 DevEco FAQ 要求：手机/模拟器已连接后，在 **File > Project Structure... > Project > Signing Configs** 勾选 **Automatically generate signature**；HarmonyOS 工程还要勾选 **Support HarmonyOS**。若未登录，点击 **Sign In**，由用户本人在 DevEco Studio 完成账号授权。不要把密码、验证码或生成的证书发给 DSH；签名配置与 `.p12/.cer/.p7b` 材料只保存在本机，不提交/上传证书或 HAP。CLI 的 `auth status` 不决定 IDE 登录状态。

- 经用户此前同意接受模拟器许可后，下载官方 HarmonyOS 7.0.0（26.0.0）平板 Release 映像 `7.0.0.107`（1,930,878,514 字节），创建独立 `ThreadsHarmonyTablet`；曾启动并由 HDC 连接 `127.0.0.1:5555`。后续查询时该实例已停止；本文只记录历史 HDC 连通，不代表当前有设备在线。
- 用户要求手机优先后，发现官方 HarmonyOS 7.0.0（26.0.0）手机 Release `7.0.0.107` 可下载，但 DevEco CLI 因 emulator license 尚未接受而拒绝下载。本轮没有接受新许可或下载镜像。已有 `Mate 90 Pro` 模拟器属于 26.0.1 Beta1，镜像缺失、启动失败。需用户先查看/接受对应许可后再下载；手机镜像下载后要重新确认 `device list` 与 `hdc list targets`，再部署。
- 官方 DevEco 自动调试签名文档（本机 CLI 文档缓存的 `ide-signing-auto`）说明：在工程窗口选择 **File > Project Structure... > Project > Signing Configs**；对未关联注册应用，勾选 **Automatically generate signature**。若页面显示 **Sign In**，用户本人可从该界面登录华为开发者账号并确认签名授权；成功后 IDE 在本机生成 `.p12/.cer/.p7b` 等材料。DSH 不读取、导出或提交这些材料。模拟器应用签名/安装尚未进行。

### 固定 SHA 的本机构建方法（手工备用）

优先使用上述已执行验证的脚本 `tools/build-windows-arkts.ps1 -SourceSha <40位SHA>`。以下步骤用于脚本不可用时的人工复现；手动工作树需自行清理。

从主仓库 PowerShell 创建新的纯 ASCII 构建目录（不覆盖已有目录）：

```powershell
git worktree add --detach C:/tmp/threads-harmony-verify 5e4d5abf46247fc5c6c5ee693b0f004d482d9d38
```

仅在该副本的 `app/build-profile.json5` 将 `compileSdkVersion` 从 `26.0.0` 改为 `26.0.1`。先用 `git -C C:/tmp/threads-harmony-verify diff -- app/build-profile.json5` 确认只有这一行变更。不要提交这个本机补丁，也不要改原开发分支或 MatePad 固定版本。然后运行：

```powershell
Set-Location C:/tmp/threads-harmony-verify/app
$env:DEVECO_SDK_HOME = 'C:\DevEco Studio\sdk'
$env:NODE_HOME = 'C:\DevEco Studio\tools\node'
$env:PATH = "$env:NODE_HOME;C:\DevEco Studio\tools\ohpm\bin;$env:PATH"
& 'C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' clean assembleHap --no-daemon -p product=default
```

验收需看到 ArkTS 编译、Hvigor 退出码 0 和 `entry/build/default/outputs/default/entry-default-unsigned.hap`。不生成签名，不部署，也不把本地 HAP 当作 MatePad 回执中的制品。

## 本轮效率勘察（历史记录，2026-11-25 早些时候）

- 当时未发现 DevEco Studio 和 HarmonyOS SDK；本节及随后“仍缺 Studio/Windows SDK”的描述已被上方新实测取代。历史 CLI 调查见下文，切勿把旧环境状态当作当前状态。
- 官方下载中心 `https://developer.huawei.com/consumer/cn/download/` 与 CLT 页面均只返回 Angular SPA 外壳。其公开前端 JS 声明下载 API，但匿名 POST 得到 nginx 404；页面下载流程涉及开发者联盟登录。没有取得可校验的 Windows 安装包 URL、版本或哈希，因此**没有下载/安装未知镜像，也没有尝试绕过登录**。官方入口可由已登录浏览器访问；当前这台 DSH 无可用的开发者联盟下载会话。
- 历史 CLI 构建试验：`devecocli build --project .` 返回 `error: unknown option '--project'`；工具会从当前目录探测工程。随后直接执行 `devecocli build` 超过当时的 25 秒工具时限，未获构建结果。该历史 CLI 试验不等于 Hvigor 编译；当前 Windows 原生编译证据见上方。
- DevEco CLI Lint 后续复测：Studio 安装后可运行，但官方模板配置和显式文件/目录参数均返回 `Files checked: 0`（exit 0，`No defects found`）。生成的完整报告也确认 0 个文件被检查，因此**不计为源码 Lint 通过**。ArkTS 语法/类型编译证据来自 Hvigor 的 `CompileArkTS`，不是这次 Lint。仍需找出 CLI Lint 正确的工程配置/入口后再测。
- 模拟器部署授权已获用户明确同意，但 `devecocli auth status` 返回 `Not logged in`；`devecocli signature generate --product default` 因需先登录而失败（`Failed to automatically generate signatures.Run devecocli auth login to sign in.`）。未尝试登录、获取账号凭据或上传任何签名材料；尚无可用的本地调试签名配置，故未安装/运行 HAP。需要用户在 DevEco Studio 本机自行完成账号授权与调试签名配置，随后再由 DSH 执行获授权的模拟器安装/启动。
- DSH 的 GitHub 仓库现已由用户改为公开；提交、推送后的内容可在两端读取，但这只是版本共享，不是文件实时同步、Agent 对话共享或自动唤醒。当前 Remote Hosts 发现失败，且没有 WorkBuddy 的远程执行/调度接口。因此本轮可把一次性验收任务写进仓库并固定 SHA，不能在 DSH 中直接启动 MatePad WorkBuddy。用户已确认 MatePad WorkBuddy 使用 **HY4Flash**，不是此前文档误记的 DeepSeek 4 Flash。

## 归档仓库候选 CLT（只读核验，未安装）

- 为避免猜测文件名，从 `https://repo.huaweicloud.com/harmonyos/compiler/hvigor/26.0.0.621/` 的目录索引发现 `command-line-tools.tar` 及同名 `.sha256`。下载至 Windows 临时目录后，文件为 351,515,648 字节；随包校验值与本地重新计算的 SHA-256 一致：`83888fb65cb80d40f07af0bd27d76cae005551265a3b0cd437b8a4f0c93d13cc`。该地址属于公开 Huawei Cloud 镜像域名，但本轮未取得它与华为开发者下载中心发布记录的对应证明；因此只把它作为候选归档信息，不视为已确认的官方正式安装来源。
- TAR 内 `version.txt` 明确标注 `Command Line Tools(linux-x64)`、版本 `26.0.0.621`、`releaseType: beta`、Hvigor `6.26.2`、HarmonyOS SDK `26.0.0 Beta2`（API 26）。`sdk/` 在归档中只有空目录，没有 SDK 文件；该包目标平台也是 Linux x64，不能给当前 Windows 主机建立构建链，也不应安装或拿它拼接本机工具链。已删除下载的 351 MB 临时归档；不更改项目依赖或系统配置。
- 只读查询同一归档索引中的其他 CLT 条目：`26.0.1.290`（TAR，360,777,728 字节）、`6.26.1`（ZIP，77,819,058 字节）、`7.26.0-arkts1.2-0601-02`（TAR，327,954,944 字节）。对 `6.26.1` ZIP 使用 HTTP Range 读取中央目录和 `version.txt`，确认也是 `Command Line Tools(linux-x64)`、`26.0.0.461`、Beta1、API 26，且仅有空 `sdk/` 目录。并未下载或安装这些包；索引不是已确认的 Windows 发布源，其他两个条目的平台/版本未验证。
- 这些归档没有参与 Windows 构建；实编使用的是上文已安装的华为 DevEco Studio。官方开发者下载中心仍是推荐获取 Windows 包的入口；本轮未找到可公开、可验证的 Windows 安装包 URL 与版本/哈希组合。

## 工具边界与下一步

- DevEco CLI 可由 DSH 用于本地文档查询、静态 Lint（在能发现 Studio/CLT 的机器上）、设备列表/日志/截图/UI 检查等；每条命令仍按副作用审查。`device/run/signature` 可能访问设备或改变签名/安装状态，必须先取得本轮明确授权，默认不自动执行。
- Windows 承担常规编译与回归；MatePad WorkBuddy 仅负责确实需要设备或 MatePad 工具链的固定版本核验。签名、安装、运行、登录由用户掌控。
- 后续迭代：DSH 设计/实现 → 从生产页提取方法做回归和同步镜像 → 本机文档/Lint（如可用）→ 审查 diff 和安全边界 → 固定 SHA → WorkBuddy 单任务 MatePad 构建或用户批准的单项设备检查 → DSH 独立核对回执。失败由 DSH 根据脱敏错误修复；不让 WorkBuddy 自行改代码。
- HDC 已验证可连接本地平板模拟器；未验证华为真机调试。ArkUI Inspector、ArkTS 断点和 ArkWeb DOM 均尚未在本项目上验证。
