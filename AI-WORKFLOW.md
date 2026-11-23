# 非程序员 AI 协作开发流程（MatePad Edge + Windows DSH）

## 目标

目标是尽量全自动：用户描述需求后，AI 能读取/修改同一份项目、调用 HarmonyOS 工具链构建、收集错误并迭代修复；用户不写代码，只在账号授权、签名、安装等敏感操作时介入。**MatePad 本机 CodeArts → 本机 Hvigor 构建链已在独立探针工程实测成功；Windows DSH 与 MatePad 仍未打通同一份工程/远程执行/日志自动回传闭环。**

当前进度：CodeArts 26.9.501 报告可调用 MatePad 系统 CLT 工具；`hvigorw --version` 为 7.26.11、`ohpm -v` 为 6.0.1、`hdc -v` 为 3.2.0f，退出码均为 0。它在 `/storage/Users/currentUser/Download/aitest/HarmonyLocalProbe` 创建了独立 Stage/API 26 工程，并先后构建空白 HAP 与 ArkWeb Threads 原型 HAP，构建命令 `hvigorw assembleHap --no-daemon -p product=default` 均成功。最初产物为未签名 HAP，27,231 字节；随后用户通过 DevEco Studio 将独立探针签名、安装并启动在「此电脑」。原生工具栏已显示，但 Threads 内容停留在白屏加载；联网与登录未通过验收。Windows 仓库中含代理面板的版本不是这个已运行的构建。

这不等于 Windows DSH 已连接 MatePad，也不等于两个工作区已同步。Windows DSH 仓库 `threads-harmony` 与 MatePad 的 HarmonyLocalProbe 是两份独立目录；建立唯一事实源前，不要双端并行改同一业务代码。

## 现实边界

- DevEco Studio 是 IDE/构建和调试入口；不要默认它自带 AI Agent。
- 当前 DSH 会话运行在 Windows，不能直接读写 MatePad 上 DevEco Studio 的本地文件。远程桌面能看见/控制界面，不代表两端文件系统共享；即使 Git 同步已建立，也只共享代码，不等于 DSH 能在 MatePad 执行命令。
- CodeArts MCP/Skill 是否能访问本机 DevEco 工具链已不是当前问题：本机 CodeArts 已实际调用 Hvigor 并构建原型。MCP 探针未配置，且无必要为了继续本机工作而先配置。
- MatePad 本机构建与 Windows DSH 协作是两项不同能力。前者已验证；后者仍缺经用户批准的源码交接/同步和持续构建结果回传流程。第一次可用源码 ZIP 交接验证，不要求立即创建远端或执行桥。
- 任何后续桥接只开放项目目录和必要构建/测试命令，不开放任意 shell、账号凭据、个人文件与签名私钥；需用户明确授权。私有 Git 若用户选择，再以其授权方式配置。
- 当前工程已过 Hello World 阶段；在 MatePad 完成独立探针签名/安装/真机验收之前，不要把未签名探针 HAP 当作可运行产品。
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
- Windows DSH 与 MatePad 的代码/结果同步仍未验证；不能把 CodeArts 本机能构建说成 Windows DSH 已能触发。未建立唯一事实源前，不要双端并行改业务代码。
- 并发上限只约束**本 DSH 会话**：主 Agent + 最多 1 个子 Agent。用户在 MatePad 另外运行 CodeArts 不受此限制；同一工程的编辑、构建、部署依然应串行。

## 设备验收与跨端回传

1. **先确认本机运行目标（已完成）**：DevEco Studio 顶部目标显示为「此电脑」，探针工程 `test` 经自动签名后已在本机安装并启动成功（`bm install` → `aa start` → `Launch ... success`）。独立的 Threads 探针也已签名安装并启动；共享仓库中的新版仍需按同样流程验证。
2. **签名与安装**：本机目标确认后，用户在 DevEco 图形界面选择/配置调试签名并授权安装；CodeArts/DSH 不读取签名材料，用户不发送密码、证书或私钥。分别回报签名成功、安装成功、启动成功与否及脱敏错误原文。
3. **首轮不登录测试**：启动后检查 Threads 首页是否加载、页面滚动、图片、返回/刷新。不要先登录；公开内容/登录入口加载有结果后再单独处理认证跳转。
4. **Windows DSH 同步**：MatePad `HarmonyLocalProbe` 与 Windows `threads-harmony` 不是同一个目录。私有远端已获授权并建立；先在 MatePad 将远端克隆到新目录，不覆盖已跑通的 `HarmonyLocalProbe`。确认 Git 同步后，按 `SOURCE-HANDOFF.md` 审核并导入独立探针的纯源码；同一个提交能否在 MatePad 重建，要另行验收。代码同步不提供远程执行。
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

## 双端 Agent 共享与交接（2026-11-23）

### 唯一共享事实源

- 项目私有远端：`https://github.com/TvTjiesen/threads-harmony`（私有；默认分支 `main`）。Windows 本地分支已推送到远端。MatePad 端是否能登录、克隆和推送仍待实测；不要把远端存在当成两台机器已经同步。
- 交接单位是 Git commit：DSH 改动后推送分支/提交；CodeArts 在 MatePad 拉取该提交，在自己的工作区构建，并把脱敏日志、构建结果和可分享产物关联回同一个提交。禁止同时改同一分支；建议 CodeArts 建 `matepad/<task>` 分支、提交后 PR 或合并，由 DSH 复核。
- Git 负责**共享已提交并推送的文件和版本**，不会实时同步未提交内容，也不负责唤醒对端 Agent 或执行命令。Agent 自动接单需要另有受控任务通道。首次往返的验收条件：MatePad 自己读取指定远端提交的 SHA 与 `AI-WORKFLOW.md`，在独立 `matepad/<task>` 分支提交不含设备路径、账号、日志、签名或凭据的结果说明并 push；Windows 再 fetch 并核对回执提交的父提交与目标 SHA。只有双方读到相同 commit，才算工作区共享打通。

### 受限任务桥（尚未接通；不可连接公网裸 HTTP）

- `tools/bridge/server.mjs` 仅允许绑定回环地址 `127.0.0.1` 或 `::1`，必须提供至少 32 字符 `BRIDGE_TOKEN`；认证仅使用 `x-bridge-token`。当前实现不支持网络暴露或私有隧道，切勿尝试将其转发到 LAN/公网。
- 仅有固定 `doctor`、`preflight`、`build` 三个任务 profile；服务端不接任意命令，MatePad worker 另有 profile 命令 allowlist。源码同步、远程写入、产物上传均关闭；构建结果仅回传状态与截断后的日志，不传 HAP。**不含签名/安装/启动**。目前 HTTPS 客户端配置和可验证的、经过身份认证的反向隧道仍未实现，因此代码不能用于跨设备连接。
- 不要用匿名 ntfy topic 传任意 shell 命令或源码。旧 `relay-hub.mjs` / `NtfyTransport` 仅作历史实验，未启用为生产通道。
- 用户在 MatePad CodeArts 的工作区里启动持久 worker 后，桥可轮询固定任务、执行本机 CLT 构建并回报状态；worker 是否能在 CodeArts 的工作区终端持续运行、MatePad 到 Windows 私有隧道是否可达，尚未实测。

### 实施状态

- 已创建 GitHub 私有仓库 `TvTjiesen/threads-harmony`，Windows `main` 已 push，代码包括 ArkWeb 原型、工具脚本及文档；不含签名文件。Windows 已在新克隆目录完成并 push `matepad/first-handoff`（回执明确标注由 Windows 代交），所以这**不是** MatePad 端往返证据；MatePad 尚未接入。最近 Windows `main` 安全修复已在提交 `5a696dee472c69c8cae2e2f70a41d21ea4cd88af` 推送，MatePad 首次拉取应以该 SHA 为准。
- `ds-harness-remote` 是人类远程访问 DSH，不是 CodeArts Agent 自动接单协议。
- 受限任务桥的认证、固定任务、防任意 shell 及隔离队列测试已在 Windows 通过；服务仍未启动，CodeArts 未配置，MatePad 也未回执，因此两 Agent 尚未实时协作。下一步先完成 Git 首次往返，再验证同一提交在 MatePad 构建。

## 自动化实施检查点（历史初始计划）

1. 用户已确认 DevEco Studio 已下载、打开并登录（2026-11-23）；登录只说明 IDE 账号状态，不说明 CLI/Agent/设备桥可用。
2. 对照 MatePad 本机 Agent 与 HarmonyOS 原生运行限制，选定可审计的本地执行方式；未验证前不要宣称自动化完成。
3. 取得用户明确授权后，先用无账号数据的空白探针工程验证：Agent 能读取项目、写一个无害文件、调用本机 CLI 查询/构建、回传实际退出码与日志。
4. 探针通过后再接入 Threads 仓库；测试设备安装/启动与账号交互需逐项确认，签名私钥仍留本机。
