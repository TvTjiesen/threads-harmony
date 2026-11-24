# 非程序员 AI 协作开发流程（MatePad Edge + Windows DSH）

## 目标

目标是尽量全自动：用户描述需求后，AI 能读取/修改同一份项目、调用 HarmonyOS 工具链构建、收集错误并迭代修复；用户不写代码，只在账号授权、签名、安装等敏感操作时介入。**MatePad 本机 CodeArts → 本机 Hvigor 构建链已在独立探针工程实测成功；MatePad CodeArts 也已通过认证 GitHub MCP 将固定源码交接提交到私库。Windows DSH 与 MatePad 的同源重建结果回传、远程执行与定时自动接单仍待验证。**

当前进度：CodeArts 26.9.501 报告可调用 MatePad 系统 CLT 工具；`hvigorw --version` 为 7.26.11、`ohpm -v` 为 6.0.1、`hdc -v` 为 3.2.0f，退出码均为 0。它在 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe` 创建了独立 Stage/API 26 工程，并先后构建空白 HAP 与 ArkWeb Threads 原型 HAP，构建命令 `hvigorw assembleHap --no-daemon -p product=default` 均成功。最初产物为未签名 HAP，27,231 字节；随后用户通过 DevEco Studio 将独立探针签名、安装并启动在「此电脑」。原生工具栏已显示，但 Threads 内容停留在白屏加载；联网与登录未通过验收。Windows 仓库中含代理面板的版本不是这个已运行的构建。

这不等于 Windows DSH 已连接 MatePad，也不等于两个工作区已同步。Windows DSH 仓库 `threads-harmony` 与 MatePad 的 HarmonyLocalProbe 是两份独立目录；建立唯一事实源前，不要双端并行改同一业务代码。

## 现实边界

- DevEco Studio 是 IDE/构建和调试入口；不要默认它自带 AI Agent。
- 当前 DSH 会话运行在 Windows，不能直接读写 MatePad 上 DevEco Studio 的本地文件。远程桌面能看见/控制界面，不代表两端文件系统共享；即使 Git 同步已建立，也只共享代码，不等于 DSH 能在 MatePad 执行命令。
- CodeArts MCP/Skill 是否能访问本机 DevEco 工具链已不是当前问题：本机 CodeArts 已实际调用 Hvigor 并构建原型。MCP 探针未配置，且无必要为了继续本机工作而先配置。
- MatePad 本机构建与 Windows DSH 协作是两项不同能力。前者已验证；后者已验证一次通过认证 GitHub MCP 的真实源码读写交接，尚缺同源构建结果回传和自动唤醒/接单。当前不要求启任务桥。
- 任何后续桥接只开放项目目录和必要构建/测试命令，不开放任意 shell、账号凭据、个人文件与签名私钥；需用户明确授权。GitHub 私库认证由用户授权的 GitHub MCP 安全持有；不得索要或传递 PAT、Cookie、SSH 私钥，也不得把它们写进命令行、环境回报或仓库。
- 当前工程已过 Hello World 阶段；固定交接提交中的 `build-profile.json5` 为脱敏无签名配置，两个图标未随 MCP 交接。构建验证须使用 MatePad 本机现有图标（仅复制到独立构建目录），不得把签名私钥、签名配置或未签名 HAP 当作已验收产品。
- 不把华为账号、访问令牌、Cookie、私信内容、签名密钥或 `.p12/.pfx` 文件交给 AI，也不提交到仓库。

## 角色分工

| 参与者 | 做什么 | 不做什么 |
|---|---|---|
| 用户 | DevEco Studio 图形操作；选择 SDK/设备/签名；点击构建/运行；授权账号；发截图和脱敏日志 | 不需要手写 ArkTS；不照抄未经确认的签名/终端命令 |
| Windows DSH | 拆需求；编辑项目代码；解释每个变更；准备测试清单；根据真实构建日志修复 | 不声称已经在 MatePad 构建、安装或验证；不读取 MatePad 私有文件 |
| MatePad DevEco Studio | 打开被同步的项目；使用本机已安装 SDK 构建；连接/运行本机目标（若该版本支持） | 不把预览器画面当作设备运行成功；不在没有同步方案时维护另一份“长期主代码” |
| CodeArts Agent（可选） | 可在 MatePad 本地项目上协助理解/编辑，前提是它对目录和 ArkTS 工程确有访问能力 | 与 DSH 不要同时编辑同一个分支/同一文件；其工具链能力逐项实测，不根据 IDE 名称推定 |

## 已验证：MatePad 本机 CodeArts 构建链

- CodeArts 26.9.501 在 MatePad 工作区可调用系统 CLT 的 Node、Hvigor、ohpm、hdc 与 codelinter；已报告版本分别为 Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、codelinter 6.0.140，版本查询退出码均为 0。**没有配置 pong-probe/MCP；本机直接工具调用已足以推进。**
- CodeArts 在独立 `HarmonyLocalProbe` 工程完成 API 26 Stage 空工程与 ArkWeb Threads 原型构建；命令 `hvigorw assembleHap --no-daemon -p product=default`，退出码 0。原型 HAP 路径 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe/entry/build/default/outputs/default/entry-default-unsigned.hap`，27,231 字节，未签名。
- 原型已声明 INTERNET 权限，并限制主框架导航为精确 Threads 域名 HTTPS。它只证明 ArkTS 编译/打包成功；页面联网、图片、登录、交互、折叠/平板适配与 HDC 安装均尚未真机验证。
- 下一步先由用户在 DevEco Studio 图形界面确认签名配置和设备授权；账号、证书、私钥只在本机 IDE 操作，绝不发给 DSH/CodeArts 或提交仓库。签名与安装未获用户确认前，不执行。
- GitHub MCP 已验证 MatePad 到 Windows 的一次真实源码交接；同源构建与结果回传仍待验证，且这不代表 Windows DSH 已能触发 MatePad 执行。不要双端并行改同一业务分支。
- 并发上限只约束**本 DSH 会话**：主 Agent + 最多 1 个子 Agent。用户在 MatePad 另外运行 CodeArts 不受此限制；同一工程的编辑、构建、部署依然应串行。

## 设备验收与跨端回传

1. **先确认本机运行目标（已完成）**：DevEco Studio 顶部目标显示为「此电脑」，探针工程 `test` 经自动签名后已在本机安装并启动成功（`bm install` → `aa start` → `Launch ... success`）。独立的 Threads 探针也已签名安装并启动；共享仓库中的新版仍需按同样流程验证。
2. **签名与安装**：本机目标确认后，用户在 DevEco 图形界面选择/配置调试签名并授权安装；CodeArts/DSH 不读取签名材料，用户不发送密码、证书或私钥。分别回报签名成功、安装成功、启动成功与否及脱敏错误原文。
3. **首轮不登录测试**：启动后检查 Threads 首页是否加载、页面滚动、图片、返回/刷新。不要先登录；公开内容/登录入口加载有结果后再单独处理认证跳转。
4. **Windows DSH ↔ MatePad 源码交接**：MatePad CodeArts 已用认证 GitHub MCP 从固定提交 `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 在独立目录重建源码的步骤已下发，禁止覆盖原 `HarmonyLocalProbe`。只交接 15 个文本源码/配置，PNG 图标由原工程复制到独立目录；签名配置在远端已脱敏，密钥材料绝不交接。构建结果应写入从该固定 SHA 创建的新分支。若失败，只回报步骤和第一条脱敏错误，不换认证方式或扩展操作。代码同步不提供远程执行。
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
- 交接单位是 Git commit：DSH 改动后推送分支/提交；CodeArts 在 MatePad 通过认证 GitHub MCP 读取固定 SHA，在独立工作区构建，并把脱敏结果关联到新分支/提交。源码交接基线为 `f0caae1554dfbe691be9b9690bd59e007e4a14e6`；结果分支必须以该提交为父提交，避免把 Windows 代交或 main 更新误认为同源构建。
- Git 负责**共享已提交并推送的文件和版本**，不会实时同步未提交内容，也不负责唤醒对端 Agent 或执行命令。此次真实 MCP 往返只证明异步读写；Agent 自动接单需要另有受控任务通道。不要导出凭据供沙箱使用，也不要把 HAP 上传到 Git。

### 受限任务桥（尚未接通；不可连接公网裸 HTTP）

- `tools/bridge/server.mjs` 仅允许绑定回环地址 `127.0.0.1` 或 `::1`，必须提供至少 32 字符 `BRIDGE_TOKEN`；认证仅使用 `x-bridge-token`。服务端本身仍是本机回环实验，不支持网络暴露或私有隧道，切勿尝试转发到 LAN/公网。
- 仅有固定 `doctor`、`preflight`、`build` 三个任务 profile；服务端不接任意命令，MatePad worker 另有 profile 命令 allowlist。源码同步、远程写入、产物上传均关闭；构建结果仅回传状态与截断后的日志，不传 HAP。**不含签名/安装/启动**。目前 HTTPS 客户端配置和可验证的、经过身份认证的反向隧道仍未实现，因此代码不能用于跨设备连接。
- 不要用匿名 ntfy topic 传任意 shell 命令或源码。旧 `relay-hub.mjs` / `NtfyTransport` 仅作历史实验，未启用为生产通道。
- 下一阶段设想：待 MatePad 首次 Git 往返、经身份认证的 HTTPS 隧道和 worker 安全审查完成后，才评估持久 worker；不能视为当前实现能力。

### 实施状态

- 已创建 GitHub 私有仓库 `TvTjiesen/threads-harmony`，Windows `main` 已 push，代码不含签名文件。Windows 曾在新克隆目录推送 `matepad/first-handoff`，回执明确标注由 Windows 代交，**不是** MatePad 往返证据。2026-11-24 MatePad CodeArts 只读探针未读取到私库：不能操作 DevEco 图形界面，命令行 `git: NOT FOUND`，匿名 `curl` 请求提交与 raw 内容均显示 HTTP `000`（未取得 HTTP 响应，未测试登录态）。未读取 SHA 或本文件，未写入或推送。该结果仅限 CodeArts 当前环境，不代表 MatePad 系统浏览器或 DevEco 图形 Git 经人工登录后也不可用。停止重复同一探针；若需先验证同一份源码构建，走 [纯源码 ZIP 交接](SOURCE-HANDOFF.md)，明确它不是自动同步。最近核实并发布的远端基线为 `6b5cdfac4315f9deb642bedacf69af8aa9dc8f9c`（2026-11-24）；有新的 Windows 本地提交时需先确认已 push，再给 MatePad 新 SHA。
- `ds-harness-remote` 是人类远程访问 DSH，不是 CodeArts Agent 自动接单协议。
- 受限任务桥的认证、固定任务、防任意 shell 及隔离队列测试已在 Windows 通过；服务仍未启动，也未配置为 CodeArts 自动接单。MatePad 通过 GitHub MCP 的异步读写已完成；下一步验证固定源码提交的 MatePad 重建和结果分支回传。

## 自动化实施检查点（历史初始计划）

1. 用户已确认 DevEco Studio 已下载、打开并登录（2026-11-23）；登录只说明 IDE 账号状态，不说明 CLI/Agent/设备桥可用。
2. 对照 MatePad 本机 Agent 与 HarmonyOS 原生运行限制，选定可审计的本地执行方式；未验证前不要宣称自动化完成。
3. 取得用户明确授权后，先用无账号数据的空白探针工程验证：Agent 能读取项目、写一个无害文件、调用本机 CLI 查询/构建、回传实际退出码与日志。
4. 探针通过后再接入 Threads 仓库；测试设备安装/启动与账号交互需逐项确认，签名私钥仍留本机。
