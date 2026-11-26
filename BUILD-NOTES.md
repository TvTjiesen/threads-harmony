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

MatePad 已精确构建候选 `2d106031f2fa6d0bd8018b053abaf9e257f40513`，回执 `40f34cec5c14da8abd16dbf465d385828fb2b665` 记录三次未签名 HAP 56,075 字节。新代理修复 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 已由 MatePad 独立构建通过，回执 `f9603240237d91791f1923a9a035d638997da4ed` 记录 unsigned HAP 62,003 字节；尚未签名、安装或运行。旧结果不能代替新版回执。Windows 已通过 DevEco Studio 自带 Hvigor 编译 ArkTS 并打包：在纯 ASCII 工作树从同一 SHA 出发，仅本地覆盖 `compileSdkVersion` 为 `26.0.1`，保留 `compatibleSdkVersion` 和 `targetSdkVersion` 为 `26.0.0`。未签名、未部署；复现步骤见 [工具验证](HUAWEI-TOOLS.md)。Node 测试与实际 ArkTS 编译分别记录。

## 原生时间线首轮验证（2026-11-26）

- `app/entry/src/main/ets/pages/Timeline.ets` 是单独 ArkUI 页面，入口改为该页；ArkWeb 仍留在 `pages/Index`，顶部显示本地首页栈内回退按钮，系统/工具栏返回优先尝试网页历史，无可用历史时才回到模拟时间线。两页均注册在 `main_pages.json`。
- 时间线内为 8 条本地演示帖；点赞/关注只存组件状态，回复/分享/发帖只显示“未接入”提示。没有账户、网络供数或 Threads API。
- `node --test tools/arkweb-candidate.test.mjs tools/sync-overlay.test.mjs`：14/14 通过；`git diff --check` 通过；Stage ArkWeb 页与 overlay 字节一致。生产回退方法的回归用例覆盖设置面板优先、网页历史优先，以及无历史或控制器异常时回到时间线。
- E 盘已签名的独立开发工程执行 `clean assembleHap --no-daemon -p product=default` 成功，实际执行 `CompileArkTS`，35 tasks，产生 signed/unsigned HAP。存在 `getContext`、`router.getLength/back/pushUrl` API 弃用警告；无 ArkTS 编译错误。首次复制采用了模板工程 `$media:icon`，编译报 `The resource reference '$media:icon' is not defined.`，改回 E 盘原有 `$media:layered_image` / `$media:startIcon` 模板资源并保留其 backup ability 后重建成功；失败版本没有覆盖原工程备份。
- 修正回退逻辑后，E 盘最新版签名 HAP 已在手机模拟器 `127.0.0.1:5555` 覆盖安装并重启成功。`uitest dumpLayout` 确认首屏 `pages/Timeline`、第一帖点赞后显示 `♥` 和 `87`、关注后显示「已关注」。点「网页」进入 `pages/Index`，点「本地首页」回时间线；滚动到后续帖子后重做往返，两条帖子的布局坐标一致。`E:/threadsharmony/smoke-timeline.jpeg` 是较早的同版型首屏截图，最新版交互以设备 UI 树为证。最新版也通过模拟器系统返回键测试：没有网页历史时返回时间线。真实网页连通、触控返回手势与 Pura X View 真机未在本轮验证。

## 原型同步工具验证

`node tools/sync-overlay.mjs` 默认只预览；`--apply` 需 Stage 配置文件齐全，且目标页面已被 Git 跟踪并没有工作区/暂存改动。脚本只更新 `app/entry/src/main/ets/pages/Index.ets`，不会修改 module 权限。`node --test tools/sync-overlay.test.mjs`：4 项通过，覆盖模板缺失、预览无副作用、未提交与已暂存改动保护、目标范围及重复执行。
