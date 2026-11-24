# 非程序员 AI 协作开发流程（MatePad Edge + Windows DSH）

## 目标

目标是尽量全自动：用户描述需求后，AI 能读取/修改同一份项目、调用 HarmonyOS 工具链构建、收集错误并迭代修复；用户不写代码，只在账号授权、签名、安装等敏感操作时介入。**MatePad 本机 CodeArts → 本机 Hvigor 构建链已在独立探针工程实测成功；MatePad CodeArts 通过认证 GitHub MCP 交接源码，并从固定提交在 MatePad 独立目录重建成功，结果经新分支回传且由 Windows 核验。远程触发执行与定时自动接单仍待验证。**

当前进度：CodeArts 26.9.501 报告可调用 MatePad 系统 CLT 工具；`hvigorw --version` 为 7.26.11、`ohpm -v` 为 6.0.1、`hdc -v` 为 3.2.0f，退出码均为 0。它在 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe` 创建了独立 Stage/API 26 工程，并先后构建空白 HAP 与 ArkWeb Threads 原型 HAP，构建命令 `hvigorw assembleHap --no-daemon -p product=default` 均成功。最初产物为未签名 HAP，27,231 字节；随后用户通过 DevEco Studio 将独立探针签名、安装并启动在「此电脑」。原生工具栏已显示，但 Threads 内容停留在白屏加载；联网与登录未通过验收。Windows 仓库中含代理面板的版本不是这个已运行的构建。

这不等于 Windows DSH 已连接 MatePad，也不等于两个工作区已同步。Windows DSH 仓库 `threads-harmony` 与 MatePad 的 HarmonyLocalProbe 是两份独立目录；建立唯一事实源前，不要双端并行改同一业务代码。

## 现实边界

- DevEco Studio 是 IDE/构建和调试入口；不要默认它自带 AI Agent。
- 当前 DSH 会话运行在 Windows，不能直接读写 MatePad 上 DevEco Studio 的本地文件。远程桌面能看见/控制界面，不代表两端文件系统共享；即使 Git 同步已建立，也只共享代码，不等于 DSH 能在 MatePad 执行命令。
- CodeArts MCP/Skill 是否能访问本机 DevEco 工具链已不是当前问题：本机 CodeArts 已实际调用 Hvigor 并构建原型。MCP 探针未配置，且无必要为了继续本机工作而先配置。
- 已验证手动触发的跨端协作：CodeArts 通过 GitHub MCP 读取指定提交、本机调用 Hvigor、另开分支写回结果，Windows 回读核验。尚不证明 CodeArts 能在无人操作时自动唤醒、领单或构建；当前不启任务桥。
- 任何后续桥接只开放项目目录和必要构建/测试命令，不开放任意 shell、账号凭据、个人文件与签名私钥；需用户明确授权。GitHub 私库认证由用户授权的 GitHub MCP 安全持有；不得索要或传递 PAT、Cookie、SSH 私钥，也不得把它们写进命令行、环境回报或仓库。
- 当前工程已过 Hello World 阶段；固定交接提交中的 `build-profile.json5` 为脱敏无签名配置，两个图标未随 MCP 交接。MatePad 构建已在独立目录临时补入本机图标；本仓库的 `app/` 是为继续开发准备的 Stage 工程副本，使用自制占位图，签名配置为空；不得把本地签名私钥或 HAP 提交。
- 不把华为账号、访问令牌、Cookie、私信内容、签名密钥或 `.p12/.pfx` 文件交给 AI，也不提交到仓库。

## 角色分工（2026-11-25 调整）

主原则：**DSH 主助手负责绝大多数产品与工程工作；WorkBuddy/CodeArts 只做远端设备专属、短小且可验收的任务。**原因是当前 WorkBuddy 使用 DeepSeek 4 Flash，适合按固定步骤执行，不适合作为主要架构/代码决策者。工具和安装始终服从最小权限；“允许下载华为工具”不等于允许改系统全局配置、自动登录或上传敏感材料。

| 参与者 | 主责 | 输出/禁止事项 |
|---|---|---|
| DSH 主助手（Windows） | 产品路线、架构、ArkTS 主实现、代码审查、测试、状态文档、Git 分支/提交/推送、构建错误分析与修复 | 不宣称本机未执行的 MatePad 构建/签名/运行已通过；不读取用户签名/凭据，不修改正在等待回执的固定 SHA |
| WorkBuddy（MatePad） | 只执行交给它的一条固定 SHA 工程任务：检查指定文件、按命令构建、采集最小脱敏错误/回执；有明确授权时可做设备截图/页面检查 | 不自行改产品代码、不改依赖或 SDK、不签名/安装/登录，除非用户单独授权；不上传 HAP、日志全集、签名、令牌、代理地址 |
| 用户 | 设备上的签名授权、安装/启动/账号登录等必须由本人掌控的操作；确认 WorkBuddy 能力与授权 | 不必写代码；只回传分支名、SHA、结果或第一条脱敏错误，勿发送凭据 |
| DevEco / Huawei 工具 | 提供编译器、ArkTS 检查、设备部署与开发文档能力，由 DSH 设计调用边界 | 仅采用官方来源；先局部安装/临时目录验证，避免覆盖现有 SDK/工程 |

任务按“设计/实现 → 静态与单元测试 → DSH 审查 → 固定 SHA → WorkBuddy 构建/设备杂务 → DSH 独立核验”串行交接。一次只让 WorkBuddy 做一个具体动作；完成即回传并停止，不派开放式“继续开发”。代理修复版的下一单只编译：用已认证方式取得指定完整 SHA 的工程，在独立目录执行既有 Hvigor 命令。回执另开分支，只报源 SHA、命令、退出码、未签名 HAP 字节数或第一条脱敏错误。不要签名、安装、启动、修改源码或上传 HAP。

## 已验证：MatePad 本机 CodeArts 构建链

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

- 项目私有远端：`https://github.com/TvTjiesen/threads-harmony`（私有；默认分支 `main`）。MatePad CodeArts 已通过认证 GitHub MCP 完成一次真实读写和源码交接提交；这不是 Git 实时同步，也不代表自动构建或自动接单。
- 交接单位是 Git commit：DSH 改动后推送分支/提交；CodeArts 在 MatePad 通过认证 GitHub MCP 读取固定 SHA，在独立工作区构建，并把脱敏结果关联到新分支/提交。已验收源码基线 `f0caae1554dfbe691be9b9690bd59e007e4a14e6`，构建结果提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 的父提交正是此 SHA，且只新增回执文件。
- Git 负责**共享已提交并推送的文件和版本**，不会实时同步未提交内容，也不负责唤醒对端 Agent 或执行命令。此次真实 MCP 往返只证明异步读写；Agent 自动接单需要另有受控任务通道。不要导出凭据供沙箱使用，也不要把 HAP 上传到 Git。

### 受限任务桥（尚未接通；不可连接公网裸 HTTP）

- `tools/bridge/server.mjs` 仅允许绑定回环地址 `127.0.0.1` 或 `::1`，必须提供至少 32 字符 `BRIDGE_TOKEN`；认证仅使用 `x-bridge-token`。服务端本身仍是本机回环实验，不支持网络暴露或私有隧道，切勿尝试转发到 LAN/公网。
- 仅有固定 `doctor`、`preflight`、`build` 三个任务 profile；服务端不接任意命令，MatePad worker 另有 profile 命令 allowlist。源码同步、远程写入、产物上传均关闭；构建结果仅回传状态与截断后的日志，不传 HAP。**不含签名/安装/启动**。目前 HTTPS 客户端配置和可验证的、经过身份认证的反向隧道仍未实现，因此代码不能用于跨设备连接。
- 不要用匿名 ntfy topic 传任意 shell 命令或源码。旧 `relay-hub.mjs` / `NtfyTransport` 仅作历史实验，未启用为生产通道。
- 下一阶段设想：待 MatePad 首次 Git 往返、经身份认证的 HTTPS 隧道和 worker 安全审查完成后，才评估持久 worker；不能视为当前实现能力。

### 实施状态

- 已创建 GitHub 私有仓库 `TvTjiesen/threads-harmony`。CodeArts 先前无 CLI git 且匿名网络探针失败，随后认证 GitHub MCP 实测读写成功。Windows 代交分支 `matepad/first-handoff` 不算 MatePad 证据。MatePad 源码交接 commit `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 的父提交 `6b5cdfac4315f9deb642bedacf69af8aa9dc8f9c`、15 个文件、脱敏配置均已核验。构建结果分支 `matepad/build-f0caae-20261124` 的提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf` 父提交正为上述源码 SHA，且只新增 `coordination/matepad-build-f0caae.md`。
- `ds-harness-remote` 是人类远程访问 DSH，不是 CodeArts Agent 自动接单协议。
- 受限任务桥的认证、固定任务、防任意 shell 及隔离队列测试已在 Windows 通过；服务仍未启动，也未配置为 CodeArts 自动接单。MatePad 通过 GitHub MCP 的源码交接、固定 SHA 本机构建与回执回传闭环已验证；无人触发或定时自动接单仍未验证。

## 自动化实施检查点（历史初始计划）

1. 用户已确认 DevEco Studio 已下载、打开并登录（2026-11-23）；登录只说明 IDE 账号状态，不说明 CLI/Agent/设备桥可用。
2. 对照 MatePad 本机 Agent 与 HarmonyOS 原生运行限制，选定可审计的本地执行方式；未验证前不要宣称自动化完成。
3. 取得用户明确授权后，先用无账号数据的空白探针工程验证：Agent 能读取项目、写一个无害文件、调用本机 CLI 查询/构建、回传实际退出码与日志。
4. 探针通过后再接入 Threads 仓库；测试设备安装/启动与账号交互需逐项确认，签名私钥仍留本机。
