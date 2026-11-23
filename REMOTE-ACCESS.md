# 跨端接入：选 ds-harness-remote，自建桥降为兜底

> 结论日期 2026-11-23。目的是解决「用户不想在 Windows DSH 和 MatePad 之间来回粘贴」。
> 自建桥实现见 `tools/bridge/`，**保留但不作为主路径**。

## 决策

主路径改用开源 `liguobao/ds-harness-remote`（MIT，3622★，v0.6.7）。理由：

1. 它正好覆盖本项目两台设备：Host 插件跑在本机 DSH，客户端有 `phone / tablet / 2in1` 三形态鸿蒙原生 App。
2. 不需要公网 IP、端口映射或梯子：优先 WebRTC（LAN/P2P/TURN），失败回落中继 + Noise 认证，双向端到端加密。
3. 版本对得上：本机 DSH `0.2.2-rc.5`、Node `v24.14.0`；上游基线 `dsh-v0.2.2-rc.1`、Node ≥ 24.9。
4. 能力覆盖用户的实际诉求：看进度、发文字/图片、回答提问、处理权限请求、开工作区、只读预览、本机终端。

自建 `tools/bridge/` 的唯一优势是零依赖、可直接在 MatePad 的 CLT Node 上跑、不依赖任何账号或服务端。
仅在 ds-harness-remote 的 Windows Host 出问题时启用。

## 已知限制（上游自述，非本机故障）

- `docs/compatibility.md`：「Windows Harness Host 的锁恢复仍待目标平台验证。Windows 上不明 PID 状态会保留锁。」
- Release 里的 `dsh-remote-harmony-v0.6.7-unsigned.hap` **未签名，不能直接装真机**，必须本地重编并签名。
- 鸿蒙客户端的 WebRTC 数据通道由本地 ArkWeb 页面承载，身份/Noise 握手/RPC 在 ArkTS 层；不是把网页塞进 WebView。

## 已完成：Host 插件安装（2026-11-23 22:39）

用官方 launcher 装进 `desktop` profile，走 `handbook/config-guard.mjs wrap` 护栏：

```
node handbook/config-guard.mjs wrap -- C:/tmp/bin/dsh.cmd plugin --profile desktop add -w ds-harness-remote@0.6.7
```

- 结果：`+ ds-harness-remote 0.6.7`，`Packages: +9 -54`，退出码 0，guard 校验通过（未新增断言失败）。
- `~/.dsh/profiles/desktop/package.json`：dependencies 31 项、`dsh.profile.bundles` 34 项，新增的都是 `ds-harness-remote`，**没有删除任何既有条目**。
- `node_modules/ds-harness-remote` 存在，`dsh-plugin.json` 的 `id` 为 `com.r2049.ds-harness-remote`，`facets.host.entry = dist/index.js`。
- 插件自带 `cordis.patch.yml` 插入行 `id: ds-harness-remote`，默认配置：`enabled: true`、`role: host`、`serverUrl: https://dsh.r2049.cn`、`codex.enabled: true`、`binary: codex`。
- 备份（`~/.dsh/profiles/desktop/`）：`package.json.bak-guard-20261123-223701-pre-remote`、`pnpm-lock.yaml.bak-guard-20261123-223701-pre-remote`、`cordis.patch.yml.bak-guard-20261123-223701-pre-remote`、`pnpm-workspace.yaml.bak-guard-20261123-223701-pre-remote`、`compatibility.json.bak-guard-20261123-223701-pre-remote`；另有 guard 自建的 `cordis.patch.yml.bak-guard-20261123-223942-wrap-pre-change`。

**尚未生效**：deps/bundles 是启动时快照，必须重启 DSH。

## 重启后自检清单

1. DSH 重启后新开一个会话，确认主回合正常（不是 401 / 不是空白）。
2. 打开「扩展 / 插件管理 → ds-harness-remote」，确认版本 0.6.7、状态已启用。
3. 在 Remote 面板按提示登录（`https://dsh.r2049.cn` 实测 HTTP 200、`/api/v1/devices` 无 token 返回 401 `AUTH_REQUIRED`，服务在线）。
4. 记录本机 Host 的设备名与 workspace，供平板端选择。

## 客户端路线（下一步）

鸿蒙 App 需要本地重编 + 签名，材料已在平板上齐备：

- 工具链：Node 24.18.1、Hvigor 7.26.11、ohpm 6.0.1、hdc 3.2.0f、SDK API 26（均由 CodeArts 工作区实测，退出码 0）。
- 签名：DevEco 公测版在「此电脑」目标上自动签名已跑通（`bm install` + `aa start` 成功）。

构建命令（上游 `docs/harmony-client.md`）：

```
node packages/app-core/scripts/build-terminal.mjs apps/harmony/entry/src/main/resources/rawfile/terminal.html
ohpm install --all
node scripts/inject-signing.mjs --unsigned
hvigorw --no-daemon assembleHap -p product=default -p buildMode=release
```

`--unsigned` 只用于编译验证；要装机必须用 DevEco 配好的自动签名重编。签名材料不入库。
