# 工程建立 / 构建记录

## DevEco 工程初始化来源

未在此仓库 vendoring SDK、DevEco/Hvigor wrapper 或外部项目的实现代码。使用 Windows DevEco 6.0.0+ 的当前官方 Stage/ArkTS 模板创建 `app/`；CodeArts 鸿蒙开发实践报告将 DevEco 6.0.0+、Windows 10/11 x64 或 macOS 12+、Python 3.x、Node 21+、Git 列为开发前置。模板负责生成与**本机安装 SDK 一致**的 profile、签名设置、资源 schema、hvigor/oh-package 版本锁定。初次生成后把 `app/` 非密钥工程源纳入 Git。

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

没有本机构建。没有生成 `app/`、HAP、签名配置或 DevEco 日志。Windows CLI 探测未找到 `hvigor`、`hvigorw`、`ohpm`、`hdc`；目前 `node` 可用。不要在状态汇报中把文件模板/静态检查说成编译成功。

## 原型同步工具验证

`node tools/sync-overlay.mjs` 默认只预览；`--apply` 需 Stage 配置文件齐全，且目标页面已被 Git 跟踪并没有工作区/暂存改动。脚本只更新 `app/entry/src/main/ets/pages/Index.ets`，不会修改 module 权限。`node --test tools/sync-overlay.test.mjs`：4 项通过，覆盖模板缺失、预览无副作用、未提交与已暂存改动保护、目标范围及重复执行。
