# 工程建立 / 构建记录

## DevEco 工程初始化来源

`app/` 起始于经 MatePad CLT 实编的脱敏 Stage 工程基线，包含自制占位图与 API 26 配置；初始占位 Bundle Name `com.example.threadsharmony` 已在用户确认华为后台应用记录后替换为 `com.tvtjiesen.threadsharmony`，签名配置仍为空。不重新生成模板或擅自升级 SDK/依赖；编译以固定 Git SHA 为单位，在独立目录执行。SDK/CLT 安装本身不纳入项目 Git。

命名建议：应用显示名 `Threads Harmony`；bundle 使用个人/团队控制的反向域名（先检查是否与现有应用冲突），vendor 使用自己的项目标识。开发者签名只保存在 Windows/本机，不提交。

模板初始验收顺序：

1. 空 Stage 工程 Sync/构建成功并记录 DevEco、SDK、Hvigor、Node、系统 API 版本。
2. 真机/模拟器目标的 INTERNET 权限、EntryAbility 和 `main_pages.json` 正常。
3. 将 `overlay/entry/src/main/ets/pages/Index.ets` 移入模板后，按实际 API 完成类型检查。
4. 在远程桌面/DevEco 运行时记录 Hvigor 构建日志；模拟器登录不连接用户真实 Threads 账号。
5. 开发签名安装、保存安全日志；连接 Pura X View 重做真实 Web 流程。

## 参考而非兼容性承诺

公开 ArkTS Stage 仓库 OpenTwit 展示的 `build-profile.json5` 选择 `compileSdkVersion: 6.1.1(24)`、`compatibleSdkVersion: 5.0.0(12)`、`runtimeOS: HarmonyOS`，并声明 `phone/tablet/2in1`。这不是当前手机 SDK 建议值，也不是我们项目的设备矩阵结果；版本必须由目标系统及华为当前开发文档决定。

## 当前状态

## 历史构建（当前版本状态见下节）

MatePad 曾精确构建候选 `2d106031f2fa6d0bd8018b053abaf9e257f40513`，回执 `40f34cec5c14da8abd16dbf465d385828fb2b665` 记录三次未签名 HAP 56,075 字节。代理修复 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 也曾由 MatePad 独立构建通过，回执 `f9603240237d91791f1923a9a035d638997da4ed` 记录 unsigned HAP 62,003 字节。当时未签名/部署；该旧状态不代表目前。Windows 也曾在纯 ASCII 工作树从固定 SHA 出发，仅本地覆盖 `compileSdkVersion` 为 `26.0.1`，保留 `compatibleSdkVersion` 和 `targetSdkVersion` 为 `26.0.0`，实际编译 ArkTS 并打包；复现步骤见 [工具验证](HUAWEI-TOOLS.md)。

## 原生时间线与视觉首轮迭代（2026-11-26）

- `app/entry/src/main/ets/pages/Timeline.ets` 是单独 ArkUI 页面，入口改为该页；ArkWeb 仍留在 `pages/Index`，顶部显示本地首页栈内回退按钮，系统/工具栏返回优先尝试网页历史，无可用历史时才回到模拟时间线。两页均注册在 `main_pages.json`。
- 时间线内为 8 条本地演示帖；点赞/关注只存组件状态，回复/分享/发帖只显示“未接入”提示。没有账户、网络供数或 Threads API。
- `node --test tools/arkweb-candidate.test.mjs tools/sync-overlay.test.mjs`：**16/16** 通过；`git diff --check` 通过；Stage ArkWeb 页与 overlay 字节一致。生产代码方法测试覆盖点赞/取消、多帖状态隔离、快速反复点击、减少动效开关和清除旧触发值；ArkWeb 回退覆盖设置面板、网页历史、无历史及控制器异常。
- 设置页使用 ArkUI `bindSheet($$this.settingsVisible, ...)` 同步显隐，提供「完成」与拖动关闭。首次 UI 树发现系统关闭图标与「完成」按钮 bounds 重叠；关闭系统 X（`showClose: false`），保留显式完成按钮，避免同一区域双重命中。手机模拟器重复点击「设置」打开、切换减少动效、点击完成、重开并保留会话状态、再切回关闭均通过。设置仅在当前页面会话有效，不持久化、不跟随系统辅助功能设置。
- E 盘签名工程执行 `clean assembleHap --no-daemon -p product=default` 成功：35 tasks（34 executed），`CompileArkTS` 2.736 s、`SignHap` 1.423 s；生成签名 HAP 266,690 B，SHA-256 `39cc64f1b45cd6815f987aa5b5103ac88cb6f7b738f494d9e55bd81524ab0357`。真实 ArkTS 编译和签名均执行；仅保留 ArkWeb 路由/旧 `getContext` 弃用警告。
- 最新签名 HAP 覆盖安装至手机模拟器 `127.0.0.1:5555` 并启动成功；UI 树证据确认首屏、设置开关状态、重开保留和点赞数 `86→87→86→87`。新增网页往返读位实测：先两次读取静止布局，再打开 ArkWeb 并点「本地首页」返回，城市观察员、周末书架、夜归电台坐标三者完全一致；另一次未停稳采样曾见 40 px 偏移，静止基线复测未复现，因此未改滚动代码。MatePad 真机旧版回执仅覆盖基线 SHA `2c07c5f99aa7e0d647e30279e656b2107892706a`；回执 `254b3755a0f61e90890ceb6ebeeb8e76cd44d010` 只新增 `coordination/matepad-native-smoke-5e4d.md`。真实 Threads 网页连通、Pura X View 折叠与当前新版真机体验仍未验证。

## 原型同步工具验证

`node tools/sync-overlay.mjs` 默认只预览；`--apply` 需 Stage 配置文件齐全，且目标页面已被 Git 跟踪并没有工作区/暂存改动。脚本只更新 `app/entry/src/main/ets/pages/Index.ets`，不会修改 module 权限。`node --test tools/sync-overlay.test.mjs`：4 项通过，覆盖模板缺失、预览无副作用、未提交与已暂存改动保护、目标范围及重复执行。
