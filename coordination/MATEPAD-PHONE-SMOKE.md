# 手机优先验收任务单

状态：Windows 手机模拟器此前已启动并通过 HDC 连通；当前是否在线未复核。手机候选工程已在 DevEco 打开。请用户本人完成本地调试签名授权后，DSH 再确认设备在线并继续安装/启动和无登录 smoke。Pura X View 真机验收另行安排。此任务单记录窄范围验收步骤，不要求用户复制长提示词。

## 已锁定代码

- 项目：`TvTjiesen/threads-harmony`
- 开发分支：`fix/arkweb-proxy-state`
- 新手机候选 SHA：`56785d268d3f028dbe19d21a2c6736bcbb5990d2`，声明 `phone`、`tablet`、`2in1`，Bundle Name `com.tvtjiesen.threadsharmony`；原候选 `da480b43c92fbf9d364ae84efaf63197d17205c7` 使用的旧包名不再使用。手机模拟器 `ThreadsHarmonyPhone`，上次 HDC serial `127.0.0.1:5555`，系统 `7.0.0.107(SP8DEVC00E999R4P11)`，当前尝试重新启动中。
- Windows 对固定 SHA 在隔离构建工作树仅把 compile SDK 对齐到 `26.0.1`，兼容/目标仍为 `26.0.0`。Hvigor clean build 实际执行 `CompileArkTS`，产出 61,850 字节未签名 HAP，SHA256 `aa6f33c540b4763fb1ee59ccc76457b12e63f2f1556b423cc58112601b33d74c`；安装、启动和布局尚未验证。
- 旧的 `5e4d5abf` MatePad 回执不作为手机支持证据。

## 用户本机 DevEco 操作（仅一次）

1. 在已打开的 `threads-harmony-phone-56785d26-local/app` 工程中（候选 SHA `56785d268d3f028dbe19d21a2c6736bcbb5990d2`），打开 **File > Project Structure... > Project > Signing Configs**。
2. 勾选 **Automatically generate signature** 和 **Support HarmonyOS**；若出现 **Sign In**，仅由你本人在 IDE 完成华为账号登录/授权，不要把账号信息发给 DSH。
3. 用户确认华为后台已有与 `com.tvtjiesen.threadsharmony` 完全一致的 HarmonyOS 应用记录。工程已据此更新 `app/AppScope/app.json5` 和 `app/build-profile.json5`，现需从更新后的新 SHA 重新验证构建；此前占位名 `com.example.threadsharmony` 的 HAP 不用于签名/安装。账号授权由用户本人完成。不要把生成的证书或 HAP 提交到 GitHub；完成关联和签名配置后告诉 DSH「签名已配好」。安装和启动由 DSH 使用已授权的本机模拟器流程继续。

## 手机 smoke 范围

1. 只用明确记录的固定 phone-capable SHA 构建；不得自行把平板回执当成手机验收。
2. 先以无代理启动检查网络失败提示及重试；仅用户自有网络环境可用时观察公开首屏、滚动、系统返回、刷新、图片。
3. 不登录、不发帖、不私信、不改代理设置；不回传 HAP、签名材料、账号资料、代理地址或完整日志。
4. 只回传固定源码 SHA、设备类型/API、构建结果与字节数、安装/启动是否成功、上述功能的通过/失败/未测、第一条脱敏错误。

真机 Pura X View 的折叠形态、系统集成和网络结果必须在该手机单独实测；模拟器通过不等于真机通过。
