# 鸿蒙设备性能证据：采集与离线汇总

**本仓库工具不连设备，不启动应用，不联网，不安装依赖。** [离线工具](../tools/device-performance.mjs) 只读本地文件：它能从一份受支持的 HiDumper 进程内存表提取一个 PSS 值，或验证手工整理的数值并汇总。真实首帧、帧时间线和主线程证据来自设备上的 DevEco Profiler 会话，不来自这个脚本。没有对应会话或泳道缺失，应记为**未测**，不能拿宿主计时补位。

## 先固定复测条件

- 使用已授权的同一台设备或同一个模拟器实例、同一系统完整构建及 API、折叠姿态/分屏尺寸、方向、分辨率、固定且核实过的刷新率、系统动画及省电状态。模拟器还须保持同一主机负载与分配；模拟器数据不能代表 Pura X View 或 MatePad 真机。
- 使用明确的源码 Git revision 和对应已安装 HAP；同一 build mode、编译配置、签名类型和 Profiler 设置。不要把源码 revision 当作已确认的安装制品；在本地实验记录里保存制品核对结果。性能测试不要附加断点或混用不同探针配置。
- 只用安全的本机演示数据，不测试真实账号。固定同一初始种子、页面/媒体、缓存状态、手势轨迹与时长、等待时长、录制泳道和窗口边界。每次先恢复起点状态，按预先约定的次数重放；前后两版都做，建议每组至少 20 个独立试次。不要将同一次运行的重复读数当独立试次，不挑最快结果；崩溃、`No Data` 或漏操作单独计数和说明，不填零。
- 可共享的结果只保留必要数值和公开的构建元数据。原始 trace、导出会话和 dump 放在本机私有目录，不提交；它们可能含 PID、进程列表、路径、画面或输入数据。不可分享设备号、HDC 地址、账号、日志、证书、签名材料和原始截图。

| 场景 | 固定起点、操作和终点 |
| --- | --- |
| `cold-launch` | 确认应用进程不在（仅退到桌面不等于冷启），从桌面图标手动点入演示首页。固定应用数据/缓存条件；每次只取同一对首帧端点。 |
| `home-idle` | 打开同一默认演示流且不交互，在预先约定的等待时长结束后取一次 PSS。 |
| `post-scroll` | 在同一演示流从同一滚动锚点执行同一组快速滚动；Frame 选固定交互窗口，PSS 在约定的滚动后检查点读取。 |
| `gallery-page-four` | 打开同一四图帖子，依次翻到第 4 张；Frame 覆盖同一翻页区间，PSS 在约定的第 4 张停留时间处读取。 |
| `video-playing` | 播放同一本地演示视频，固定清晰度、片段及进度；Frame 选相同操作窗口，PSS 取相同播放检查点。 |
| `post-resume` | 从同一页面进入后台，等待同一时长后恢复；区分原进程恢复和被系统重新创建，PSS 取同一恢复后检查点。 |

## 首帧、卡顿与主线程：优先用 DevEco Profiler

1. 打开 **DevEco Profiler**，选设备和正确的应用/进程，创建 **Launch** 会话。选择手动启动，采集设置里勾选 **Hitrace > multimodalinput**。开始录制，等工具提示后再手动点设备桌面的应用图标；冷启结束且泳道有数据后停止，等解析完成。
2. 首帧指标 `cold-first-present`：起点取 `mmi_service` 收到该桌面点击离手的 `H:service report touchId:…, type: up`（或相应 `button-up`），可用桌面 `H:DispatchTouchEvent` 的 `type=1` 反查。跟踪应用首个 `H:ReceiveVsync`、事务发送、Render Service 的 `H:RSMainThread::ProcessCommandUni`、`H:CommitLayers` 和对应 `H:Waiting for PresentFence`，终点取该 PresentFence 切片的**结束**。只在两个端点都能关联到该次冷启时，把选区时长以 `ms` 填入 `samples`。应用首个 VSync 是开始绘制，不能代替提交/显示结束；如系统版本改变标记、缺失或无法关联，记为未测。
3. `cold-first-present` 是**桌面抬手到应用首帧完成上屏**，不是内容完全可读/可交互的 TTFD。没有独立、可信的内容就绪标记和同一设备时间基准就不报 TTFD。`hdc shell aa start` 的往返、宿主秒表、日志出现、UI 树轮询、截图抓取都不是首帧端点。
4. 用 **Frame** 模板分别录制快速滚动、四图翻页、视频、恢复。选定实际操作区间和目标进程，在 **Frame / Statistics / Frame List** 核对 App Frame 与 RS Frame 的实际/期望结束时间、总帧数、Jank Count 和类型（`AppDeadlineMissed` / `RenderDeadlineMissed`）。有 Lost Frames 或 Hitch Time 泳道时可分别记录。不要将平均 FPS 当丢帧数，亦不要将 App/RS 数据混为一组。对异常帧查看目标进程主线程 Trace / ArkTS Callstack / Callstack（主线程线程号等于进程号）；结论应区分 ArkUI 布局、解码、业务工作和渲染连续性，不能仅凭耗时判因。帧数据留在 Profiler 会话中核对，本脚本不导入通用帧格式。
5. 分析随时间变化的内存峰值用 **Allocation** 模板；在同一目标进程、相同窗口和泳道设置读取采样高点。官方文档的 Allocation **Memory** 泳道为 `PSS + GL + Graph`，**不可**与下文 HiDumper PSS Total 混作同一指标。静态 PSS 最大值也不等于运行期间的内存峰值，更不能证明泄漏。
6. 解析完成后用会话区导出按钮本地保存，另一次可在 **Open File** 导回；文档列出的兼容格式包括 `.insight`、`.htrace`、`.ftrace`。以实际会话和安装版本支持为准，不把所有格式视为等价。不要启用需要联网、且与采集无关的分析功能。

如果专项测试已具备受支持硬件和安装包，也可用官方 **HiSmartPerf Device**：本机文档给出设备侧 `SP_daemon --help`，并说明 `-f` 为应用刷新 FPS、jitter、刷新率，`-r` 含进程和整机内存，且 daemon 执行要求连接硬件设备。先由操作者核对本机目标支持和指标定义；不假定模拟器有这个能力，不把其 RAM、响应/完成时间或 FPS 替代本指南的 PSS/首帧/Jank。安装的 DevEco CLI `1.3.0-stable` README 未给出 `devecocli profiler`；这里不提供未经核实的捕获命令。Studio 同捆的 Windows `trace_streamer.exe --help`（本机版本输出 `4.3.7`）只说明 bytrace/htrace 的**事后**分析，例如 `FILE -e sqlite_out.db`。它不是录制器，且本流程没有验证通用 SQL schema 或解析实际 trace；不需要它即可做下文的 PSS 汇总。

## 可独立采集：同一进程的 HiDumper PSS 快照

下面只是供**已获授权且独占设备的操作者**手动采样；离线工具本身不会执行这些命令。官方 HiDumper 文档给出 `hidumper --mem <pid>`（不是整机 `hidumper --mem`），本项目操作者也在手机模拟器上核对了 `hidumper -h` 和对应表形。先手动把应用带到约定的检查点，再在宿主 PowerShell 7 对一次试次执行：

```powershell
$hdc = 'C:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$target = '<仅本机使用的 HDC 目标>'
$bundle = '<已安装应用的 bundle name>'
$outFile = '<私有本地临时目录>\run01.txt'  # 每个试次用新的文件名

$before = ((& $hdc -t $target shell pidof $bundle) -join "`n").Trim()
if ($LASTEXITCODE -ne 0 -or $before -notmatch '^[1-9][0-9]*$') { throw 'Expected one PID before sampling' }
$dump = & $hdc -t $target shell hidumper --mem $before
if ($LASTEXITCODE -ne 0) { throw 'HiDumper failed' }
$after = ((& $hdc -t $target shell pidof $bundle) -join "`n").Trim()
if ($LASTEXITCODE -ne 0 -or $after -cne $before) { throw 'Process changed during sampling' }
if (Test-Path -LiteralPath $outFile) { throw 'Use a new file for each trial' }
$dump | Set-Content -LiteralPath $outFile -Encoding utf8
```

`pidof` 缺失、出现多个 PID、PID 不一致、进程不在、权限不足或输出格式不符，均不采信，不能猜进程。PID 前后一致只用来排除明显重启，并非进程身份的独立证明。每份 dump 来自一个试次的一个检查点。用已安装的 Node.js 22+ 从仓库根目录执行（参数换成自己的本地 UTF-8 文件）：

```powershell
node tools/device-performance.mjs pss 'C:\private-perf\run01.txt' 'C:\private-perf\run02.txt'
```

它按参数顺序只输出数值数组，来源是 `[memory]` 的标准 10 列进程明细表内 `Total` 行的 `Pss / Total (kB)`。不读 SwapPss、堆分类、整机总量或尾部扩展；不支持的表及歧义会报错，不输出部分结果。无法从本地文本验证原始命令是否确实运行、PID 是否稳定，或读数是否来自独立试次；这些由采集人核对。

## 数值导入、汇总与比较

每个 JSON 文件是一组同条件样本。PSS 把数值数组填入 `samples`；Launch 从每个已核对的 Profiler 会话手工转录 `ms`。以下是**虚构示例**，不是性能实测：

```json
{
  "schemaVersion": 1,
  "metric": "process-pss",
  "source": "hidumper-process",
  "unit": "kB",
  "scenario": "home-idle",
  "deviceClass": "phone-emulator",
  "osBuild": "7.0.0.107",
  "refreshHz": 60,
  "buildMode": "debug",
  "collectorVersion": "os-bundled",
  "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "samples": [124000, 128000, 125000, 126000]
}
```

| 字段 | 规则 |
| --- | --- |
| 指标、来源、单位、场景、采集器 | `process-pss` / `hidumper-process` / `kB` / 上表除 `cold-launch` 外的任一场景 / `os-bundled`。或 `cold-first-present` / `deveco-launch` / `ms` / `cold-launch` / Studio 数字版本，如 `26.0.1.290`。禁止混合其它单位、来源或端点。 |
| `deviceClass` / `osBuild` | 类别 `phone-emulator`、`tablet-emulator`、`phone`、`foldable`、`tablet`；系统构建只写数字版本，不写硬件标识、完整序列号或附加私有字段。完整系统构建一致性另在本地核对。 |
| `refreshHz` / `buildMode` / `revision` | 实际确认的固定整数 Hz；`debug` 或 `release`；对应应用源码的 40 位小写 Git SHA。不要用默认值补未知条件。 |
| `samples` | 至少一个有限的正数；PSS 必须是整数 kB，Launch 允许小数 ms。不接受额外字段、字符串数字、零、负数或缺测值。 |

```powershell
node tools/device-performance.mjs summarize 'C:\private-perf\baseline.json'
node tools/device-performance.mjs compare --matched-setup 'C:\private-perf\baseline.json' 'C:\private-perf\candidate.json'
node --test tools/device-performance.test.mjs
```

汇总输出样本数、中位数（偶数个取中间两项平均）和 nearest-rank P95（排序后第 `ceil(0.95 × n)` 项）。少于 20 项标记 `smallSample: true`，此时 P95 就是最大观测值，不代表稳定尾部；即使满 20 项也不是显著性检验。比较要求 schema、指标、来源、单位、场景、设备类别、系统数字构建、刷新率、build mode、采集器版本、样本数全相同，输出候选值减基线值。`--matched-setup` 表示操作者已核对工具无法检测的**同一物理目标、完整系统构建、同一采样协议、相同演示数据及运行条件**；它不是自动证明。不同设备（即便同类）或同设备的不同设置只做独立汇总，不报对照差值。

## 本机核对依据

- Windows 安装元数据：`C:\DevEco Studio\product-info.json`（Studio `26.0.1.290`）、`C:\DevEco Studio\sdk\default\sdk-pkg.json`（API 26，`26.0.1.120` Beta1）。SDK 版本不是设备系统版本。安装与历史连通背景见 [华为开发工具验证记录](../HUAWEI-TOOLS.md)。
- 文档来自本机已安装的 `@deveco/deveco-cli@1.3.0-stable` 附带的 `docs.zip`，离线核对以下文档条目：`deep-recording.md`（性能问题定位：深度录制）、`ide-profiler-session.md`（会话区）、`ide-profiler-launch-case.md`（应用冷启动首帧完成时延）、`ide-insight-session-frame.md`（Frame 分析）、`ide-frame-case.md`（使用 Frame 模板分析卡顿）、`ide-insight-session-allocations-memory.md`（内存分析介绍）、`hidumper.md`（查询进程内存）、`bpta-retrieve-process-memory-info.md`（获取进程内存信息）、`smartperf-guidelines.md`（HiSmartPerf Device 性能使用指导）。
- 这些依据支持命令、界面及定义，不证明在每个目标上可采；本工具的测试仅验证文本提取、导入校验与统计。把实测结果按**平台、场景、指标、样本数**说明；没有验证过的设备和缺失数据保持未测。
