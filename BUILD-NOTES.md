# 工程建立 / 构建记录

## DevEco 工程初始化来源

`app/` 已建立：来源为经 MatePad CLT 实编的脱敏 Stage 工程基线，包含自制占位图、API 26 配置，包名 `com.example.threadsharmony`，签名配置为空。不重新生成模板或擅自升级 SDK/依赖；编译以固定 Git SHA 为单位，在独立目录执行。SDK/CLT 安装本身不纳入项目 Git。

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

MatePad 已精确构建候选 `2d106031f2fa6d0bd8018b053abaf9e257f40513`，回执 `40f34cec5c14da8abd16dbf465d385828fb2b665` 记录三次未签名 HAP 56,075 字节。新代理修复 SHA `5e4d5abf46247fc5c6c5ee693b0f004d482d9d38` 已由 MatePad 独立构建通过，回执 `f9603240237d91791f1923a9a035d638997da4ed` 记录 unsigned HAP 62,003 字节；尚未签名、安装或运行。旧结果不能代替新版回执。Windows 已验证 DevEco CLI 1.3.0-stable 的文档检索/读取，但设备查询报找不到 DevEco Studio；无已验证 SDK/Hvigor 构建链。详见 [工具验证](HUAWEI-TOOLS.md)。Node 测试不等于 ArkTS 编译。

## 原型同步工具验证

`node tools/sync-overlay.mjs` 默认只预览；`--apply` 需 Stage 配置文件齐全，且目标页面已被 Git 跟踪并没有工作区/暂存改动。脚本只更新 `app/entry/src/main/ets/pages/Index.ets`，不会修改 module 权限。`node --test tools/sync-overlay.test.mjs`：4 项通过，覆盖模板缺失、预览无副作用、未提交与已暂存改动保护、目标范围及重复执行。
