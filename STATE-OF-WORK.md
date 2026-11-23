# 跨设备工作约定

## 唯一事实源

代码、文档、运行日志索引均以本目录 Git 仓库为准。Windows DSH 和 MatePad Edge 远程桌面应连到同一 Windows 用户会话和同一工作目录；会话切换后先读取 `STATUS.md`、`TEST-MATRIX.md` 与 Git 状态。不要用截图、聊天摘要或另一份 CodeArts 副本覆盖较新的文件。

MatePad Edge 上若打开的是独立 CodeArts workspace：先将本仓库 clone/pull 到其受支持的 Git 工作区，工作前检查分支和未提交修改；工作后提交一个有意义的 commit，再由 Windows pull。两端不可同时改同一文件/同一分支。远程托管 Git 仅在用户提供并授权远程地址后添加。远程同步前核实私钥、签名配置、日志、测试数据都在 ignore 列表中；禁止上传口令、Meta cookie、私信内容。

## 白天手机不在身边时的任务

可以完成：页面/组件、ArkUI 布局、静态检查、hvigor 构建、资源/依赖审查、单元测试、模拟器的手机/平板/2in1尺寸、窗口 resize、键鼠焦点、无障碍扫描、文档和缺陷分类。

必须等 Pura X View 在手：手机开发者桥接和安装、官方登录/续期、真实账户的五项核心功能、折叠铰链/转屏行为、真实媒体选择、后台/锁屏推送、功耗/内存/真实机性能。模拟器通过不替代真机通过。

## MatePad Edge PC 环境首轮检查

分别记录：系统名称和版本；是否是完整 Windows VM/远程桌面还是本机 PC 模式；能否访问 `C:\Users\杰森\Documents\deepseek-harness\default-workspace\threads-harmony`；DevEco 与 HDC 能否运行；能否创建并启动 HarmonyOS phone/tablet/2in1 emulator；MatePad 自身是否能安装华为 HAP、是否能授权安装第三方开发签名应用、ArkWeb 实际版本和 Threads 登录能否工作。结果填入 `TEST-MATRIX.md`。

未实测前，把 MatePad Edge 作为远程 Windows 客户端、代码阅读/工作站，而不是承诺其 PC 环境可原生安装鸿蒙 HAP。即使能侧载到 MatePad，也只能验证相应的大屏设备配置，不能代替 Pura X View 手机验收。
