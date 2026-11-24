# 全自动开发路径评估（2026-11-23）

## 目标与已知限制

目标是用户发自然语言需求后，AI 自动读取/修改工程、构建、收集日志并迭代。当前 DSH Host 在 Windows，DevEco Studio 在 MatePad Edge；尚无已验证的文件+命令执行桥。DevEco Studio 已登录，只代表其账号状态已完成，不代表 Agent、CLI 或 DSH 集成可用。

## 路线比较

### A. MatePad 本机 CodeArts + CLT/Hvigor（构建已验证）

当前不走下面的早期 MCP 探测计划：CodeArts 已直接调用 CLT 的 Hvigor 7.26.11 构建 API 26 原型，详见 [项目状态](STATUS.md)。以下保留为历史背景，仅在以后需要独立 MCP 集成时参考。

- 用户明确指出 MatePad 上已有 CodeArts。此前用户提供的报告确认 CodeArts 26.9.501 在 HarmonyOS PC 本地沙箱运行，并可读写其工作区目录；报告所测沙箱缺少 Node/Git/Java/DevEco SDK/Hvigor/ohpm/HDC，故暂不能把它当成构建环境，但系统级 DevEco Studio 已安装并登录，是不同事实。
- CodeArts 官方文档支持两条本地连接路线：[MCP](https://support.huaweicloud.com/usermanual-codeartsagent/codeartsagent_ug_0010.html) 文档明确 stdio MCP 执行环境为“本地”；SSE/Streamable HTTP 可本地或远程；本地 Skill 存储于项目 `./.codeartsdoer/skills/` 或用户 `%USERPROFILE%/.codeartsdoer/skills`，见 [Skill 文档](https://support.huaweicloud.com/usermanual-codeartsagent/codeartsagent_ug_0024.html)。但官方产品文档没有证明 MatePad HarmonyOS PC 的 26.9.501 可以启动 MCP stdio 子进程或 Skill 脚本越过应用沙箱访问系统级 DevEco/SDK。用户提供的本机报告反而显示 Agent 沙箱看不到 Node/Git/Java/SDK/Hvigor/ohpm/HDC。**确定结论：CodeArts 是最应先测的已有入口，但 CodeArts → 宿主命令 → DevEco 的链路未经设备实测。**
- OpenHarmony SIG `deveco-cli` 仓库 https://gitcode.com/openharmony-sig/deveco-cli（本地检出 HEAD `c17f89d6cbe3ae36625f8e5cab795be3092a2d2b`）目前只把 Qoder/Qoder CN 列为原生 HarmonyOS 插件宿主；其原生运行时采用 HiShell 交接。**这解释了为什么此前考虑 Qoder，但并不说明必须安装 Qoder；用户已有 CodeArts，应先核实 CodeArts MCP/Skill 能否接入 DevEco CLI。**
- 最小验证顺序（每步用户确认/实测，串行）：①在 CodeArts「设置 → MCP 工具」检查是否能配置**本地 stdio** 服务；若没有或 UI 报错即停，不改系统设置；②仅配置固定返回 `pong` 的只读探针，确认工具被发现且能调用（无需 Node、shell 或私有目录访问）；③再检查 CodeArts 本机 MCP/Skill 是否有受控脚本调用能力；④只在前几项可用后，用明确允许的只读查询确认 `node/git/java/hdc/hvigor/ohpm` 及 SDK/DevEco CLI 路径是否可见；⑤最后才在 `Documents/HarmonyLocalProbe` 的空白工程测试 AI 写一个无害文件、构建，并回传真实退出码与脱敏日志。失败即保留该阶段证据，不跳去安装/改 ACL/执行任意 shell。
- `stdio` 文档所称“本地”是产品支持的执行环境类型，不足以证明子进程位于 HarmonyOS 主机而不是 CodeArts 沙箱；要用第②步证据区分。远端 Streamable HTTP 只是传输协议，不能替代命令执行端，也不可把服务暴露在非本机网络。
- 如果 CodeArts 不能执行本机工具，再比较系统 DevEco CLI 的 HiShell 工作流与 Qoder；只有确认 CodeArts 本机能力不足且用户同意后，才考虑安装其他 Agent。

### B. DSH Windows 主控 + MatePad 本机受限执行桥

- 可用私有 Git 同步源代码，但 Git 不提供远程执行能力。
- 可设计仅暴露特定项目目录和固定 build/test/status 命令的本机 MCP 服务；不暴露通用 shell、私人目录、浏览器会话或签名密钥。
- 该设备是否允许安装并常驻运行自建 MCP 服务、DSH 是否能经可用网络连接该服务，目前均未经实测。不可提前让用户敲开放任意命令的脚本。

### C. 远控桌面/屏幕自动化

- 视觉点击可作为最后补充，不适合单独做可靠构建闭环：焦点、对话框、应用更新和屏幕状态易使操作漂移，也不提供健壮退出码/日志。远程桌面目前没有被证实接入 DSH 的计算机使用工具。

## 安全与确认边界

- AI 可对已授权项目文件执行普通编辑/构建；每轮单任务，同一工程编辑→构建→部署串行。
- 华为账号/Threads 授权、签名密钥导出或使用、发布、数据删除、消息发送、任何超出工程目录的访问均需要用户明确批准或亲自完成。
- 日志回传前排除 access token、Cookie、账号标识、私信内容、签名材料。
- 并发上限 2 只约束本 DSH 会话（主 Agent + 最多一个子 Agent），不约束 MatePad 上的 CodeArts。

## 本次状态

最新实测以 [项目状态](STATUS.md) 为准：2026-11-24，MatePad CodeArts 通过认证 GitHub MCP 读取固定提交，在独立目录用本机 Hvigor 生成未签名 HAP，并把结果写回私库；Windows 已核验回执正文与父提交。上文 A 节的探测方案仅是历史记录。执行桥未启动，不是当前前置条件。

## 定时轮询可行性（2026-11-24）

优先评估 **CodeArts 官方定时入口 + 现有 GitHub MCP**，不新增服务，也不开放 Windows 端口。CodeArts 先前报告 `cronList` 返回 `No scheduled tasks`，只证明能列任务，不证明定时任务会在无人操作时唤醒本机 Agent、继承已认证 MCP 或调用本机 CLT。华为的 MCP 文档只证明连接能力；Windows DSH 的定时任务也只能调度 DSH 会话，不能把它当作唤醒 MatePad 的工具。

建议验收分开做，未获明确授权不创建任何定时任务：

1. **一次性只读探针**：确认 CodeArts 是否有官方一次性调度入口。经用户授权后，在预定时间读取这个私库的固定提交及回执，只在任务结果中记录触发时刻、读到的 SHA 和成败；不访问工作区个人文件、不写 GitHub、不构建。首次只测正常开机联网、无人工操作；合盖、休眠、应用退出和跨网另测，不从首轮结果推定。
2. **无人回传探针**：只读通过后，另行授权让一次性任务在独立分支写一条无害结果，Windows 验证父提交和唯一新增文件。不做签名、安装或 HAP 上传。
3. **有限构建接单**：前两关通过后，只接受固定仓库、经确认的不可变 SHA 和预定义构建动作；任务记录不携带 shell 命令，校验项目/构建脚本后执行。每个任务 ID 只交付一次结果，失败回传首条脱敏错误，不循环重试或改主分支。

任一关不通过就保留已验证的手动触发流程；不以匿名中继或任意 shell 兜底。当前结论：方案可试验，尚不能承诺后台自动接单。
