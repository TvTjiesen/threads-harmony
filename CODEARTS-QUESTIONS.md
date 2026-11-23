# 给 HarmonyOS PC 上 CodeArts 的能力核实提示词（已由用户完成；归档参考）

请根据你**当前实际运行的产品/环境**回答以下问题；不确定的项目请标记“不知道/无法验证”，不要根据通用 CodeArts 文档推测。请优先报告产品名称、版本/构建号，以及每项能力的验证步骤或官方文档链接。不要输出账号密码、Access Token、私钥、开发证书、设备序列号或 Threads 登录信息。

我准备在 MatePad Edge 的 HarmonyOS PC 系统上开发一个个人使用的 HarmonyOS Threads 客户端。主代码目前保存在 Windows 工作区，目标设备包括 MatePad Edge 和运行 HarmonyOS 7.0.0.115 SP10 的 Pura X View。我希望尽量优先使用 Education 权益下的 CodeArts，但可以让 Windows DevEco 承担必要的构建/签名/设备安装工作。

1. 你是什么产品？请给出准确产品名、版本、运行位置：MatePad 本机 HarmonyOS PC 应用，还是远程云桌面/浏览器 IDE/Windows 客户端？
2. Education 权益具体包含哪些 CodeArts 服务/额度？可访问的官方能力说明链接是什么？
3. 能否创建/导入普通 Git 仓库，运行 Git clone/commit/push？是否支持 SSH/HTTPS 私有远端、分支、PR？能否在 MatePad 本地文件系统访问工作区？
4. 是否支持 HarmonyOS 应用开发：ArkTS、ArkUI、Stage 模型、hvigor、ohpm？可以执行自定义命令或本地终端吗？具体执行位置是 MatePad 本机、云容器还是远程 Windows？
5. 能否安装/选择 HarmonyOS SDK、指定 `compileSdkVersion` 和 `compatibleSdkVersion`，执行 hvigor build 并导出 `.hap`/App Pack？有没有官方教程或实际成功的最小样例？
6. 能否创建/调用签名配置？签名私钥存在哪里、是否支持本地密钥？如果不支持，能否无签名构建后下载到 Windows DevEco 签名？请只说明流程，禁止显示密钥内容。
7. 能否部署到 MatePad Edge 本机、Pura X View 或 HarmonyOS 模拟器？能否运行/集成 `hdc`、发现 USB/Wi-Fi 设备、查看设备日志？跨设备调试有哪些限制？
8. 能否使用官方模拟器？模拟器运行在云端、Windows 主机还是 MatePad 本机？支持 phone、foldable、tablet、2in1 中哪些形态？
9. 能否访问本地编辑器、文件上传下载、剪贴板和外设（键盘/鼠标/触控笔）？能否与 Windows DSH 工作区共享同一目录，还是必须经 Git/制品上传同步？
10. 对这个项目，建议什么最小可行工作流：哪些步骤留在 MatePad CodeArts，哪些必须在 Windows DevEco 与真实 Pura X View 完成？请列出已验证步骤、前置条件和不能完成的环节。

请用表格回答：问题 / 支持状态（已验证、文档确认、未确认、不支持）/ 具体证据与版本 / 限制。最后给出一个不含真实凭证的最小 Hello World 验证流程。