# 设备与测试矩阵

状态：未测 / 通过 / 失败 / 不支持。模拟器与硬件分别记录，不把“未测”标作支持。

## 设备能力

| 设备/环境 | 系统/API | 构建/安装 | ArkWeb 登录 | 功能验收 | 形态/输入 | 证据/说明 |
| --- | --- | --- | --- | --- | --- | --- |
| Windows 主机 | Windows，具体 build 待录 | DevEco Studio 未被 CLI 自动发现；Harmony SDK/Hvigor 构建未验证 | 不适用 | 不适用 | DSH/键鼠 | 唯一主仓库、代码主责与 Node 回归站；DevEco CLI 1.3.0-stable 本地文档查询已验证 |
| MatePad Edge / CodeArts | QXS-W00 7.0.0.111(SP16C00E111R5P5)（用户提供）；构建 SDK API 26 | 基线原型工程曾用本机 Hvigor 7.26.11 构建通过；候选 bundle `com.example.threadsharmony`，deviceTypes tablet/2in1；SHA `2d106031f2fa6d0bd8018b053abaf9e257f40513` 已由 WorkBuddy 构建；最新代理状态修复 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 待构建 | 未测 | 未测 | PC 形态及本机 HAP 运行已对旧独立工程验证；本次固定提交 HAP 未签名，安装与运行待测 | 2026-11-24 CodeArts MCP 交接提交 `f0caae1554dfbe691be9b9690bd59e007e4a14e6`，15 个白名单文本文件；MatePad 独立目录重建通过，结果提交 `7bbe80b0ec74e393d9e690e71671db491c2239cf`。两个 PNG 在本机补入构建目录。未签名 HAP 27,229 字节；详见 [项目状态](STATUS.md) |
| Pura X View | HarmonyOS 7.0.0.115 SP10（用户提供）；具体应用 API level 待核实 | 尚无 HAP | ArkWeb 未测 | 五项未测 | 折叠形态待试 | 用户确认系统浏览器可正常使用 Threads；版本号不自动等同 SDK compileSdk/API level |
| HarmonyOS phone emulator | SDK/API 待装 | 未配置 | 未测 | 未测 | 尺寸模拟 | 仅验证布局及可模拟 API |
| HarmonyOS tablet/2in1 emulator | SDK/API 待装 | 未配置 | 未测 | 未测 | 窗口尺寸/输入模拟 | 不等于 MatePad Edge 真实功能验证 |
| Android emulator/device | 尚未决策 | 无工程 | 未测 | 未测 | 后续扩展 | 先做平台技术 spike，再定最低版本/工具链 |

## 核心功能（同一测试账号）

| 功能 | 系统浏览器 | ArkWeb / Pura X View | MatePad 环境 | Android 未来版 |
| --- | --- | --- | --- | --- |
| 登录、冷启动续用 | 用户确认网页能用；具体步骤未记 | 未测 | 未测 | 未测 |
| 浏览、分页、返回位置 | 用户确认网页能用；细项未测 | 未测 | 未测 | 未测 |
| 回复 | 细项未测 | 未测 | 未测 | 未测 |
| 关注/取关 | 细项未测 | 未测 | 未测 | 未测 |
| 私信双向文本 | 细项未测 | 未测 | 未测 | 未测 |
| 群聊双向文本/建群 | 细项未测 | 未测 | 未测 | 未测 |
| 图片/视频 | 细项未测 | 未测 | 未测 | 未测 |
| 后台推送/锁屏提醒 | 细项未测 | 未测 | 未测 | 未测 |
| 深色、大字号、无障碍 | 未测 | 未测 | 未测 | 未测 |
| 折叠、窗口、键鼠、触控笔 | 不适用 | 未测 | 未测 | 未测 |

## 跨设备 Git 同步验证

| 步骤 | CodeArts MatePad | Windows DSH | 证据 |
| --- | --- | --- | --- |
| 私有仓库服务 | 认证 GitHub MCP 读写成功 | GitHub API/fetch 均已核验 | 仓库 `TvTjiesen/threads-harmony` 私有 |
| MatePad WorkBuddy/DevEco bridge 构建回写 | 已完成 | Windows 核验远端父提交、文件路径、回执正文 | 固定 ArkWeb SHA `2d106031f2fa6d0bd8018b053abaf9e257f40513`；回执提交 `40f34cec5c14da8abd16dbf465d385828fb2b665` |
| 源文件交接 | 已完成 | 已拉取 15 个文本文件并扫描 | PNG 图标因 MCP 不支持二进制写入而省略 |
| 固定提交重建、结果分支回传 | 旧基线 `f0caae1554dfbe691be9b9690bd59e007e4a14e6` 已验证：15 个文件按 blob SHA 核对无差异，补用两个本机原图标，独立目录构建退出 0 | GitHub API 核实回执正文、父提交和单文件范围 | 回执 `7bbe80b0ec74e393d9e690e71671db491c2239cf`；未签名 HAP 27,229 字节，未上传、未安装、未运行 |
| ArkWeb 候选 MatePad 重建 | **通过**：固定 SHA `2d106031f2fa6d0bd8018b053abaf9e257f40513` | 回执分支 `feat/arkweb-build-2d1060`，提交 `40f34cec5c14da8abd16dbf465d385828fb2b665` 的父提交精确匹配固定 SHA；回执文件 SHA `d42df8b572bebe5724de041a32401e5ca398650b`，记载三次构建 exit 0，指定命令含 `-p product=default`，HAP 均 56,075 B、unsigned | 仅构建通过；未签名、安装、运行；旧回执 `8fdfd93f...` 仍是旧 SHA 证据 |
| 合并冲突与分支协作 | 未确认 | 未测 | 两端禁止同时写同一分支，首次先串行交接 |

## 代理修复版验收（待 MatePad 实测）

| 检查项 | 预期 | 状态 |
| --- | --- | --- |
| 固定修复提交的 ArkTS 编译 | 独立目录、指定 SHA，产出本机未签名 HAP | 待 WorkBuddy 构建；固定 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38`；已有回执仅覆盖旧版 |
| 代理应用/关闭回调迟到 | 等待超时后不允许第二次切换，也不发起新的顶层加载；等原回调收敛 | Windows 假时钟与模拟 ArkWeb 验证，设备未测 |
| 旧启动代理超时 | 尝试清除保存值；晚回调不自动恢复导航，等待用户确认 | Windows 假时钟与模拟 ArkWeb 验证，设备未测 |
| 配置网络后不登录打开 Threads | 可见网页内容或官方公开登录入口，而非白屏、工具栏或错误提示 | 未测 |

## MatePad 首次实机验收（旧探针历史，不登录）

| 顺序 | 操作 | 记为通过的条件 | 目前 |
| --- | --- | --- | --- |
| 1 | 在 DevEco 打开项目结构 → default → 签名配置，检查签名菜单；再展开顶部运行目标列表 | 只记录实际菜单/目标。CodeArts 已报包名 `com.example.harmonylocalprobe`、版本 1000000/1.0.0、deviceTypes tablet/2in1、signingConfigs 为空；hdc targets=0 不等于 DevEco GUI 无目标 | **已确认**：运行目标显示为「此电脑」（本机），非模拟器 |
| 1b | （独立探针 `test` 工程，非 Threads）自动签名 → 安装 → 启动 | 日志出现 signed HAP 的 `bm install` 与 `aa start` 且 `Launch ... success` | **通过**（2026-11-23 21:48，包名 `com.example.myappl`，`entry-default-signed.hap`）；仅证明本机签名/安装/启动链路可用 |
| 2 | 用 DevEco 对当前工程生成调试签名构建 | 本轮构建成功且 IDE 确认已签名；之前的 unsigned HAP 不算 | **通过**（2026-11-23 22:00，HarmonyLocalProbe 日志 `entry-default-signed.hap`） |
| 3 | 将已签名构建装到 MatePad 本机 | 部署结果明确显示安装成功；单有签名产物不算 | **通过**（`bm install` 成功，随后 `aa start`） |
| 4 | 从本机启动应用 | MatePad 上实际出现应用窗口；Previewer 或模拟器不算 | **通过**（窗口标题 `HarmonyLocalProbe`，可见「返回/刷新」工具栏与 Threads 标题） |
| 5 | 在应用打开 Threads 首页 | 网页正文或官方公开登录入口可见；只有原生工具栏、持续白屏或错误页不算 | **未通过/未完成**：2026-11-23 22:00 截图显示白屏 + 「加载中…」转圈，页面正文未出现；新版本待测：WebView attach 后才加载；启动读取已保存代理并等待应用回调，未配置时直接加载；20 秒后显示提示并停止卡死的加载；主框架 HTTP/TLS 错误显示反馈。新页面尚未由 MatePad 编译/实测 |
| 6 | 浏览一条公开内容，滚动并查看图片 | 内容能滚动；选定的公开图片正常出现。如页面无公开图片则记未测 | 未测 |
| 7 | 如果能进入站内链接，先点返回，再点刷新 | 返回上一页；刷新后页面可用。不具备站内历史时将返回记未测 | 未测 |

若找不到本机运行目标，保存目标下拉菜单截图，不选模拟器冒充实机；若安装失败，先记 DevEco 的第一条错误或错误码；只有启动成功后才检查网页。回传只需一步一行，不包含设备标识、账号、完整跳转 URL 或会话信息。登录、登录态续用和 Pura X View 单独验收。

## 每次测试记录

- 日期/测试者：
- 设备具体型号、系统 build/API、形态：
- DevEco/SDK/Hvigor/Node 版本：
- 工程提交/commit、构建命令、结果、签名状态：
- 测试功能及逐步操作：
- 预期/实际结果，失败证据或缺陷编号：
- 结果：未测 / 通过 / 失败 / 不支持：
- 截图只保存遮蔽账号和消息内容的版本：
