# MatePad 原型 → Windows 工程：首次源码交接

这份清单不要求先开 Git 远端或配置 MCP，也不授权推送。它适用于用户通过已有的私有文件传输方式把可构建的 MatePad 原型交给 Windows DSH。DevEco 的签名、安装和真机测试是独立验收，不由源码交接替代。

## MatePad 端：仅打包已知源文件

如果还没配置调试签名，可以先让 CodeArts 按下面的提示打包当前已编译的纯源码，不必等到真机验证；这能避免 IDE 后续将本机签名信息写入配置后再清理。这个包只作为当前编译基线，不声称已上机验证。原工程继续保留在 MatePad，不在两个端上同时继续改业务文件。

```text
请准备 HarmonyLocalProbe 的纯源码交接包。工程在 /storage/Users/currentUser/Download/aitest/HarmonyLocalProbe。不要用整个目录压缩，也不要改工程。
只复制工程级和 entry 模块的 build-profile.json5、hvigorfile.ts、oh-package.json5，工程的 hvigor/hvigor-config.json5、AppScope/app.json5、已知 AppScope 图标/字符串资源，以及 entry/src/main 下的 module.json5、EntryAbility.ets、Index.ets、页面配置和已知图标/字符串/颜色资源。保留相对路径；遇到符号链接不要跟随。先检查拟交接的文本配置是否含本机绝对路径、签名材料引用、密钥、凭据或账号数据；若发现，请停下，只报告文件名与问题类别，不输出具体值，也不要自行删改原文件。
不得包含 HAP、build、.hvigor、oh_modules、日志、IDE 本机设置、local.properties、.env、签名目录、证书、密钥或任何账号数据。若安全检查通过，在工程外当前工作区生成独立源码 ZIP；如果无法打包，先报告文件清单，不安装工具或上传文件。输出 ZIP 路径、实际文件清单；若本机已有可用工具，可附 ZIP 的 SHA-256。不要推送、公开、签名或部署。
```

## Windows 端：接收后的验收

1. 解包前核对归档条目；拒绝绝对路径、`..`、链接和清单外条目。先在临时目录拆包，检查源码与配置是否包含签名引用、凭据或本机专用配置。
2. 对比 MatePad 的 ArkWeb 页面和 Windows 仓库现有 overlay，保留已编译的版本和可验证的导航边界。检查 API 26、`INTERNET`、设备类型以及独立探针包名；不要默默把探针配置推定为正式包名或手机兼容。
3. 确认导入方式后才将源码纳入 Windows 项目。首次同步以 CodeArts 在 MatePad 对同一份源码重新构建并回传退出码、脱敏错误或产物大小为验收；只有取得远端授权后才配置 Git。Git 只同步代码，不触发 MatePad 构建。
4. 分开记录“源码已导入”“同源源码构建成功”“签名安装成功”“实机网页功能通过”。其中最后两项以设备实测为准。

当前状态：尚未收到源码包，尚未验证 Windows 与 MatePad 的源码同步。