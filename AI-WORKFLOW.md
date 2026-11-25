# 非程序员 AI 协作开发流程（Pura X View + Windows DSH）

## 目标

**手机优先（2026-11-25）**：Pura X View 是主验收设备，Windows 手机模拟器先做窄屏/启动路径验证，MatePad 只做平板与2in1补充。当前 `deviceTypes` 应包含 `phone`、`tablet`、`2in1`。

目标是尽量全自动：用户描述需求后，AI 能读取/修改同一份项目、调用 HarmonyOS 工具链构建、收集错误并迭代修复；用户不写代码，只在账号授权、签名、安装等敏感操作时介入。**Windows DSH 已能用 DevEco Studio 自带 Hvigor 本机编译；MatePad CodeArts 也已通过认证 GitHub MCP 交接源码、在固定提交的独立目录构建并回写结果。无人值守触发、定时自动接单与 Windows 物理设备调试仍待验证。**

当前进度：MatePad 侧 CodeArts 26.9.501/WorkBuddy 已报告可调用系统 CLT 工具；`hvigorw --version` 为 7.26.11、`ohpm -v` 为 6.0.1、`hdc -v` 为 3.2.0f，退出码均为 0。Windows DSH 已用华为 DevEco Studio 自带 Hvigor clean 编译 ArkTS 并生成未签名 HAP（仅在隔离工作树将 compileSdkVersion 对齐到已安装的 Beta SDK）；本地平板模拟器已通过 HDC 连通；应用尚未部署或运行。DevEco CLI 1.3.0-stable 仍用于本地 API 文档。MatePad 在 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe` 创建独立 Stage/API 26 工程，并先后构建空白 HAP 与 ArkWeb Threads 原型 HAP，构建命令 `hvigorw assembleHap --no-daemon -p product=default` 均成功。最初产物为未签名 HAP，27,231 字节；随后用户通过 DevEco Studio 将独立探针签名、安装并启动在「此电脑」。原生工具栏已显示，但 Threads 内容停留在白屏加载；联网与登录未通过验收。Windows 仓库中含代理面板的版本不是这个已运行的构建。

这不等于 Windows DSH 已连接 MatePad，也不等于两个工作区已同步。Windows DSH 仓库 `threads-harmony` 与 MatePad 的 HarmonyLocalProbe 是两份独立目录；建立唯一事实源前，不要双端并行改同一业务代码。

## 现实边界

- DevEco Studio 是 IDE/构建和调试入口；不要默认它自带 AI Agent。
- 当前 DSH 会话运行在 Windows，不能直接读写 MatePad 上 DevEco Studio 的本地文件。远程桌面能看见/控制界面，不代表两端文件系统共享；即使 Git 同步已建立，也只共享代码，不等于 DSH 能在 MatePad 执行命令。
- CodeArts MCP/Skill 是否能访问本机 DevEco 工具链已不是当前问题：本机 CodeArts 已实际调用 Hvigor 并构建原型。MCP 探针未配置，且无必要为了继续本机工作而先配置。
- 已验证手动触发的跨端协作：CodeArts 通过 GitHub MCP 读取指定提交、本机调用 Hvigor、另开分支写回结果，Windows 回读核验。尚不证明 CodeArts 能在无人操作时自动唤醒、领单或构建；当前不启任务桥。
- 任何后续桥接只开放项目目录和必要构建/测试命令，不开放任意 shell、账号凭据、个人文件与签名私钥；需用户明确授权。GitHub 私库认证由用户授权的 GitHub MCP 安全持有；不得索要或传递 PAT、Cookie、SSH 私钥，也不得把它们写进命令行、环境回报或仓库。
- 当前工程已过 Hello World 阶段；固定交接提交中的 `build-profile.json5` 为脱敏无签名配置，两个图标未随 MCP 交接。MatePad 构建已在独立目录临时补入本机图标；本仓库的 `app/` 是为继续开发准备的 Stage 工程副本，使用自制占位图，签名配置为空；不得把本地签名私钥或 HAP 提交。
- 不把华为账号、访问令牌、Cookie、私信内容、签名密钥或 `.p12/.pfx` 文件交给 AI，也不提交到仓库。

## 角色分工（2026-11-25 调整与工具验证）

主原则：**DSH 主助手是唯一的产品与代码主责；WorkBuddy（MatePad）只承担少量、本机专属、边界清楚且可核验的杂务。**用户确认 MatePad WorkBuddy 当前使用 HY4Flash，适合照步骤跑构建/检查并回报，不承担架构决策或跨文件功能开发。华为官方 DevEco CLI/CLT 是工具，不是另一个代码 Agent；Windows 已建立隔离 Hvigor 编译链，但使用 Beta1 SDK 与仅本地 SDK 对齐补丁。用户已授权下载华为工具，但仍遵循最小权限：优先项目本地或用户目录，不做无关系统级变更，不自动登录，不上传敏感材料。

| 参与者 | 主责 | 输出/禁止事项 |
|---|---|---|
| DSH 主助手（Windows） | 唯一产品负责人：需求拆分、路线/架构、ArkTS 与 UI 主实现、代码审查、安全与测试设计、静态/Node 回归、Windows Hvigor 实编、Git 真源和发布分支、WorkBuddy 任务书、错误诊断与修复、状态/测试矩阵维护 | 不冒充设备实测，不处理用户签名密钥/凭据，不把代理端点或 HAP 放进仓库；不改变已发布的 MatePad 固定 SHA；本机 SDK 是 Beta；HarmonyOS phone 模拟器此前已通过 HDC 连通；该模拟器是否仍在线未做本轮复核。签名仅由用户在 IDE 的 Project Structure > Signing Configs 界面操作。DSH 不请求或代填凭据 |
| WorkBuddy（MatePad） | 低性能 HY4Flash 执行员：一次一个小任务，如固定 SHA 的本机 Hvigor 构建、指定错误行/版本/文件核对、用户授权后的单张脱敏截图；按模板提交最小回执 | 不做架构或开放式开发、不改业务代码/依赖/SDK、不自行选 SHA；未单独获用户授权时不签名、安装、启动、登录；绝不上传 HAP、完整日志、令牌、签名材料或代理地址 |
| 用户 | 设备上的身份授权、DevEco 调试签名、安装/启动及登录等必须由本人掌控的动作；在 MatePad 上运行 WorkBuddy 的明确小任务；提供真实设备现象 | 不必写代码；只回传分支/commit、退出码、产物字节数或第一条脱敏错误，不发送凭据/代理地址 |
| 华为官方工具（DevEco Studio、HarmonyOS CLT/Hvigor、DevEco CLI、hdc 等） | DSH 使用 Studio 自带 Hvigor 在 Windows 本机做 ArkTS 编译；CLI 用于补充文档检索；MatePad 工具链留给 WorkBuddy 的设备专属核验 | Windows SDK 为 API 26 `26.0.1.120` Beta1；固定版本编译仅在临时副本对齐 `compileSdkVersion`；HarmonyOS 7.0.0 phone 模拟器此前由 HDC 连通，但本轮未复核在线状态；未验证物理设备 |

任务按“DSH 设计/实现 → DSH 本地文档、Node 回归与 Hvigor 编译 → DSH 审查 → 固定 SHA → WorkBuddy 一项 MatePad 专属设备/环境核验 → DSH 独立核验 → DSH 修复下一轮”串行交接。一次只让 WorkBuddy 做一个具体动作；完成即回传并停止，不派开放式“继续开发”。代理修复版已从完整固定 SHA 在独立目录构建通过；回执另开分支，只报源 SHA、命令、退出码、未签名 HAP 字节数或第一条脱敏错误。回执分支可从命名分支创建，但必须在回执里区分构建源码 SHA 与分支起点，不能误称父提交就是构建源码。不要签名、安装、启动、修改源码或上传 HAP。每轮实施差异仍由 DSH 主写；WorkBuddy 不负责合并、重构或排错。Windows 本地工具证据与限制见 [华为工具验证](HUAWEI-TOOLS.md)。

## 已验证：MatePad 本机 CLT 构建链

- CodeArts 26.9.501 在 MatePad 工作区可调用系统 CLT 的 Node、Hvigor、ohpm、hdc 与 codelinter；已报告版本分别为 Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、codelinter 6.0.140，版本查询退出码均为 0。**没有配置 pong-probe/MCP；本机直接工具调用已足以推进。**
- CodeArts 在独立 `HarmonyLocalProbe` 工程完成 API 26 Stage 空工程与 ArkWeb Threads 原型构建；命令 `hvigorw assembleHap --no-daemon -p product=default`，退出码 0。原型 HAP 路径 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe/entry/build/default/outputs/default/entry-default-unsigned.hap`，27,231 字节，未签名。
- 原型已声明 INTERNET 权限，并限制主框架导航为精确 Threads 域名 HTTPS。它只证明 ArkTS 编译/打包成功；页面联网、图片、登录、交互、折叠/平板适配与 HDC 安装均尚未真机验证。
- 下一步先由用户在 DevEco Studio 图形界面确认签名配置和设备授权；账号、证书、私钥只在本机 IDE 操作，绝不发给 DSH/CodeArts 或提交仓库。签名与安装未获用户确认前，不执行。
- GitHub MCP 已验证 MatePad 到 Windows 的源码交接，并完成同源构建和结果回传：源 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6`，结果提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 的父提交正是源 SHA；回执仅新增 `coordination/matepad-build-f0caae.md`。构建命令 `hvigorw assembleHap --no-daemon -p product=default` 退出码 0，产物 `entry-default-unsigned.hap` 27,229 字节，使用了 MatePad 原有两个图标；未签名、未安装、未运行。这证明异步源码交接→本机构建→结果回传闭环，不代表 Windows DSH 能远程触发 MatePad。不要双端并行改同一业务分支。
- 并发上限只约束**本 DSH 会话**：主 Agent + 最多 1 个子 Agent。用户在 MatePad 另外运行 CodeArts 不受此限制；同一工程的编辑、构建、部署依然应串行。

## 设备验收与跨端回传

1. **先确认本机运行目标（已完成）**：DevEco Studio 顶部目标显示为「此电脑」，探针工程 `test` 经自动签名后已在本机安装并启动成功（`bm install` → `aa start` → `Launch ... success`）。独立的 Threads 探针也已签名安装并启动；共享仓库中的新版仍需按同样流程验证。
2. **签名与安装**：本机目标确认后，用户在 DevEco 图形界面选择/配置调试签名并授权安装；CodeArts/DSH 不读取签名材料，用户不发送密码、证书或私钥。分别回报签名成功、安装成功、启动成功与否及脱敏错误原文。
3. **首轮不登录测试**：启动后检查 Threads 首页是否加载、页面滚动、图片、返回/刷新。不要先登录；公开内容/登录入口加载有结果后再单独处理认证跳转。
4. **Windows DSH ↔ MatePad 源码交接**：MatePad 基线 SHA `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 已重建通过。ArkWeb 候选 `feat/arkweb-reliability` 固定提交 `2d106031f2fa6d0bd8018b053abaf9e257f40513` 含 Stage 工程与 ArkWeb 页面。MatePad WorkBuddy 通过 HarmonyOS DevEco Command Line Tools 对该精确 SHA 构建成功：回执分支 `feat/arkweb-build-2d1060`，提交 `40f34cec5c14da8abd16dbf465d385828fb2b665` 的父提交等于固定 SHA；回执 `coordination/arkweb-build-receipt.md` 记录指定命令 `hvigorw assembleHap --no-daemon -p product=default` exit 0、`BUILD SUCCESSFUL`、三次 unsigned HAP 均 56,075 字节。Windows 已核对分支、父提交和回执文件内容。此为构建证据，不代表已签名、安装、运行或完成 Threads 页面验收。旧回执 `8fdfd93febb2d17a67179107573a3d6967a32465` 对应更早 SHA `fd9f9cf3c4d1f79bdd65f28b39b0405c86be43dc`，不能代替本次记录。
5. **收尾记录**：每一项分别记录“源码交接”“本机重建”“签名”“安装/启动”“页面功能”状态到 `STATUS.md`/`TEST-MATRIX.md`。没有实机证据的功能标记“未测”。

## 每轮给 DSH 的反馈模板

```text
当前任务：<一句话>
DevEco Studio 版本：<关于页面显示的版本>
项目路径：<本机路径；不含账号或个人文件名更好>
当前阶段：<欢迎页/项目已打开/构建中/运行中>
操作：<我刚才点了什么>
结果：<成功状态，或第一条错误及后续错误>
附件：<截图；先遮挡账号、邮箱、二维码、通知和个人内容>
```

## 双端 Agent 共享与交接（2026-11-24）

### 唯一共享事实源

- 项目远端：`https://github.com/TvTjiesen/threads-harmony`（用户已改为公开；默认分支 `main`）。当前一次性 MatePad 验收任务见 `coordination/MATEPAD-NEXT.md`。本任务单代替复制完整提示词；用户在 WorkBuddy 中只需指示按文件执行。MatePad CodeArts 已通过认证 GitHub MCP 完成一次真实读写和源码交接提交；这不是 Git 实时同步，也不代表自动构建或自动接单。
- 交接单位是 Git commit：DSH 改动后推送分支/提交；CodeArts 在 MatePad 通过认证 GitHub MCP 读取固定 SHA，在独立工作区构建，并把脱敏结果关联到新分支/提交。已验收源码基线 `f0caae1554dfbe691be9b9690bd59e007e4a14e6`，构建结果提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 的父提交正是此 SHA，且只新增回执文件。
- Git 负责**共享已提交并推送的文件和版本**，不会实时同步未提交内容，也不负责唤醒对端 Agent 或执行命令。此次真实 MCP 往返只证明异步读写；Agent 自动接单需要另有受控任务通道。不要导出凭据供沙箱使用，也不要把 HAP 上传到 Git。

### 无需复制提示词的交接（仓库任务单）

- 项目根目录的 `coordination/MATEPAD-NEXT.md` 是当前给 MatePad WorkBuddy 的固定小任务；代码已锁定 SHA，任务只含本机无登录验收及脱敏回执。
- 你无需在两个 Agent 之间复制长提示词：让 MatePad WorkBuddy 读取该仓库文件即可。它不需要改代码或选择版本；只按任务单执行并提交最小回执。DSH 再读取回执并继续主开发。
- 这减少人工复制，但**不是实时共享、也不会自动唤醒**。DSH 当前无法启动 MatePad 上的 WorkBuddy；Remote host discovery 未连接，官方下载/API 亦未证明存在可用的自动执行回调。WorkBuddy 只有在用户打开它并要求读取该任务单时才会执行。用户不必复制全文，只需告诉它按仓库文件执行。

### 受限任务桥（尚未接通；不可连接公网裸 HTTP）

- `tools/bridge/server.mjs` 仅允许绑定回环地址 `127.0.0.1` 或 `::1`，必须提供至少 32 字符 `BRIDGE_TOKEN`；认证仅使用 `x-bridge-token`。服务端本身仍是本机回环实验，不支持网络暴露或私有隧道，切勿尝试转发到 LAN/公网。
- 仅有固定 `doctor`、`preflight`、`build` 三个任务 profile；服务端不接任意命令，MatePad worker 另有 profile 命令 allowlist。源码同步、远程写入、产物上传均关闭；构建结果仅回传状态与截断后的日志，不传 HAP。**不含签名/安装/启动**。目前 HTTPS 客户端配置和可验证的、经过身份认证的反向隧道仍未实现，因此代码不能用于跨设备连接。
- 不要用匿名 ntfy topic 传任意 shell 命令或源码。旧 `relay-hub.mjs` / `NtfyTransport` 仅作历史实验，未启用为生产通道。
- 下一阶段设想：待 MatePad 首次 Git 往返、经身份认证的 HTTPS 隧道和 worker 安全审查完成后，才评估持久 worker；不能视为当前实现能力。

### 实施状态

- GitHub 仓库 `TvTjiesen/threads-harmony` 已由用户转为公开。CodeArts 先前无 CLI git 且匿名网络探针失败，随后认证 GitHub MCP 实测读写成功。Windows 代交分支 `matepad/first-handoff` 不算 MatePad 证据。MatePad 源码交接 commit `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 的父提交 `6b5cdfac4315f9deb642bedacf69af8aa9dc8f9c`、15 个文件、脱敏配置均已核验。构建结果分支 `matepad/build-f0caae-20261124` 的提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 父提交正为上述源码 SHA，且只新增 `coordination/matepad-build-f0caae.md`。
- `ds-harness-remote` 是人类远程访问 DSH，不是 CodeArts Agent 自动接单协议。
- 受限任务桥的认证、固定任务、防任意 shell 及隔离队列测试已在 Windows 通过；服务仍未启动，也未配置为 CodeArts 自动接单。MatePad 通过 GitHub MCP 的源码交接、固定 SHA 本机构建与回执回传闭环已验证；无人触发或定时自动接单仍未验证。

## 自动化实施检查点（历史初始计划；本轮能力见 HUAWEI-TOOLS.md）

1. 用户已确认 DevEco Studio 已下载、打开并登录（2026-11-23）；登录只说明 IDE 账号状态，不说明 CLI/Agent/设备桥可用。
2. 对照 MatePad 本机 Agent 与 HarmonyOS 原生运行限制，选定可审计的本地执行方式；未验证前不要宣称自动化完成。
3. 取得用户明确授权后，先用无账号数据的空白探针工程验证：Agent 能读取项目、写一个无害文件、调用本机 CLI 查询/构建、回传实际退出码与日志。
4. 探针通过后再接入 Threads 仓库；测试设备安装/启动与账号交互需逐项确认，签名私钥仍留本机。
