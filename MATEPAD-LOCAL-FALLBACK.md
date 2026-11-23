# DevEco 无本机目标时：HiShell 备选核实

仅在 DevEco 的运行目标列表没有明确的 MatePad 本机目标时使用。CodeArts 沙箱内 `hdc list targets` 为 0 不能单独触发此分支。OpenHarmony SIG 的 [鸿蒙原生运行参考](https://atomgit.com/openharmony-sig/deveco-cli/blob/c17f89d6cbe3ae36625f8e5cab795be3092a2d2b/.plugin/references/harmonyos-native-runtime.md#L111) 在 Qoder 场景记录了由用户在 HiShell 安装已签名 HAP、安装成功后再启动应用的做法。这不证明本机可用，也不要求换用 Qoder。

## 复制给 CodeArts（只读）

```text
DevEco Studio 的运行目标列表没有明确的 MatePad 本机目标。请只读核实 HarmonyLocalProbe 的 HiShell 本机安装前置条件。工程目录 /storage/Users/currentUser/Download/aitest/HarmonyLocalProbe。

1. 从模块配置找出实际的可启动 Ability 名称，并确认包名与设备类型；不要猜默认 Ability。只报告这些非敏感值。
2. 区分目前已知的 unsigned HAP 和可能新增的 HAP。只列产物文件名、大小和构建结果中有无已签名的明确证据；没有证据就标为未确认，不要只凭文件名判断。不要读取签名配置或签名材料。
3. 根据能核实的官方/上游文档，说明该版本是否有不依赖运行目标的 IDE 调试签名构建入口，以及用户手动打开 HiShell 的方式；把文档说法与实机观察分开。公开文档不明确就标未知。不要探测端口或尝试无线自连。

不要修改工程、签名、安装、启动应用或开无线调试；不要索取或输出账号、证书、密钥、设备标识。最后只给：包名 / Ability / 设备类型 / 是否有签名产物证据 / 可核实的 GUI 入口 / 下一步需要用户确认什么。
```

只有确认产物已签名、包名与 Ability 来自该产物对应的工程、用户明确选择本机安装后，才准备单独的一次性 HiShell 操作。安装与启动各自记录结果；安装失败则不启动，不自动改调试设置或切换目标。
