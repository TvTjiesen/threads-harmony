# 华为组件选型：写帖底栏与宽屏导航

## 采用什么

- 写帖编辑底部使用公开的 ArkUI `Button`：保存草稿是普通按钮（`NORMAL`），预览和预览页的「加入本机时间线」分别是各自页面的唯一强调按钮（`EMPHASIZED`）。文字始终可见，最小高度 48 vp；颜色由系统样式提供，不再覆写这三个按钮的前景色和背景色。保存、预览、退出确认、键盘避让和大字号／窄窗布局逻辑不变。
- 签装试过华为 `HdsActionBar`。标准字号下，手机模拟器实际键盘展开时两个操作都在键盘之上，预览可点；但公开 `startButtons` 槽只呈现图标，书签容易与应用已有的「收藏」混淆，不能拿读屏文案或悬停提示当作触屏上的可见文字。最终没有引入该组件，不用额外的自绘按钮弥补。
- 宽屏四个平级栏目继续用华为 `HdsTabs` 的竖向半屏居中布局，写帖仍是独立操作。官方竖向默认栏宽 96 vp，与独立写帖所在栏一致。`HdsSideBar` 适合折叠／覆盖面板，`HdsSideMenu` 适合菜单层级，不为换组件而替换已运行的栏目、读位和焦点机制。

[同一手机模拟器实拍：HdsActionBar 探针、最终标准字号、最终特大字号](screenshots/native-hds-design.jpg)

## 证据边界

- 设计规范插件用于检索与静态检查，选型补核本机 SDK；`R009` 的 4 个命中来自头像和摘要内部的装饰布局，非独立点击区。摘要原生按钮至少 48 vp。这不等于已通过系统读屏验收。
- 不改网页、代理、登录、数据格式或签名配置；没有新加系统沉浸光感接口或智感卧姿实现。既有 `HdsTabs` 自适应系统材质仍保留。模拟器不替代真机外屏、折展、短宽窗口、实体键鼠或帧性能结论。

官方参考：[华为按钮设计规范](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/button-0000001929683228.md)、[ArkUI Button](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-button)、[HdsTabs](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)、[HdsSideBar](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdssidebar)、[HdsSideMenu](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdssidemenu)。详细实测见[测试矩阵](../TEST-MATRIX.md)。
