# Coordination 回执 · ArkWeb 候选构建核验

- 回执类型：构建核验（coordination receipt）
- 目标候选（用户指定固定提交）：`2d106031f2fa6d0bd8018b053abaf9e257f40513`
- 回执生成时间：2026-11-24T15:14Z（UTC）
- 执行环境：MatePad Edge 本机 DevEco Command Line Tools（经 `harmonyos-deveco-bridge` MCP 工具调用）

## 源码来源与 HEAD 核验

- 源码取得方式：`codeload.github.com` 按精确提交 SHA 导出 tar.gz（本沙箱无 git，非 `git checkout`）。
- 归档字节数：69326 字节。
- 固定提交核验：`get_commit(2d1060…)` 成功，message=`docs: pin ArkWeb candidate MatePad handoff`，作者 Jason `<jason@local>`，时间 `2026-11-24T12:32:29Z`。
- 构建根定位：`app/`（含 `hvigorfile.ts`、`build-profile.json5`、`oh-package.json5`）。
- 关键 ArkTS 源：`app/entry/src/main/ets/pages/Index.ets`、`app/entry/src/main/ets/entryability/EntryAbility.ets` 均存在。

## 构建命令（最终以逐字一致的指定命令为准）

- 用户指定命令：`hvigorw assembleHap --no-daemon -p product=default`
- **最终采用命令（逐字一致，主记录）**：`hvigorw assembleHap --no-daemon -p product=default`
  - 执行方式：bridge 的 `deveco_build` 工具只拼 `task + --no-daemon`、不接受 `-p` 参数，故直接用其 `env()` 中同一套环境变量（`NODE_HOME` / `DEVECO_SDK_HOME` / `OHOS_BASE_SDK_HOME` / `PATH`，并 `unset NODE_OPTIONS`）调用同一 hvigorw 二进制，加上 `-p product=default` 执行。
  - 工作目录：`.../threads-harmony-verify-2d1060/app`
  - 日志：`coordination/build-exact-command.log`
  - 结果：exit 0、`BUILD SUCCESSFUL in 9 s 153 ms`、0 ERROR、`CompileArkTS` 4 s 681 ms、HAP 56075 字节。
- 补充：此前两次经 `deveco_build` 工具执行的是 `hvigorw assembleHap --no-daemon`（工具固定参数，不含 `-p`）；工程仅一个 `default` 产品、产物落 `outputs/default/`，与指定命令构建对象一致。三次产物字节数均为 56075。

## 构建结果（来自 `deveco_build` 真实输出）

- 退出码（exitCode）：0
- 结果标记：`BUILD SUCCESSFUL`
- ERROR 计数：0 个 `ERROR:`
- 任务统计：34 tasks，34 executed，0 up-to-date
- `CompileArkTS` 耗时：6 s 718 ms（真实编译，非缓存命中）
- 总耗时：`BUILD SUCCESSFUL in 12 s 196 ms`
- HAP 产物：`app/entry/build/default/outputs/default/entry-default-unsigned.hap`
  - 字节数：56075
  - 产物时间：2026-11-24T15:14:24.829Z
  - 签名状态：unsigned（`WARN: No signingConfig found for product default`，未配置签名，符合"不签名"要求）

## 可复现性（干净重建二次确认）

- 第 1 次（`deveco_build` 工具，无 `-p`）：exit 0、`BUILD SUCCESSFUL in 12 s 196 ms`、34/34 executed、HAP 56075 字节（15:14:24.829Z）。
- 第 2 次（`deveco_clean` 后重建，无 `-p`）：exit 0、`BUILD SUCCESSFUL in 10 s 242 ms`、33 tasks（32 executed / 1 up-to-date）、HAP 56075 字节（15:17:06.577Z）。
- 第 3 次（`deveco_clean` 后，逐字一致的指定命令含 `-p product=default`）：exit 0、`BUILD SUCCESSFUL in 9 s 153 ms`、33 tasks（17 executed / 16 up-to-date）、HAP 56075 字节。
- 三次产物字节数均为 56075，确认可复现，非缓存假象；最终以第 3 次（命令原文与用户指定一致）为准。

## 与旧回执的区别（关键）

- 仓库现有回执分支 `matepad/build-arkweb-reliability`（提交 `8fdfd93febb2d17a67179107573a3d6967a32465`）记录：
  - 实际构建 commit：`fd9f9cf3c4d1f79bdd65f28b39b0405c86be43dc`（旧提交）
  - HAP 字节数：54421
- 本回执针对 `2d1060…`，产物 56075 字节，与旧回执 54421 字节不同——构造不同，不能互证。
- 结论：本回执是固定提交 `2d1060…` 的首份可核验构建证明；旧回执不得作为本候选的构建证据。

## 未做的事（边界）

- 未签名、未安装、未运行、未上传 HAP。
- 未修改任何业务源码（ArkTS / 配置均未改动）。
- 未触碰三项代理逻辑风险（代理超时状态不一致、坏代理偏好反复失败、关闭代理缺回调超时处理）。

## 工具链版本（`deveco_doctor` 实测）

- toolchain root：`/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`
- hvigorw：7.26.11（exit 0）
- node：v24.18.1（exit 0）
- hdc：`.../sdk/default/openharmony/toolchains/hdc`（存在；设备连接另测）
