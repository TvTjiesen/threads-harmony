# Threads 公开内容 · 开发联调

这不是账号首页或关注流，也不是网页登录接管。只使用 [Meta 的 Threads API 官方集合](https://www.postman.com/meta/threads/collection/dht3nzz/threads-api) 中的 `/keyword_search`（按近期排序）和 `/profile_posts`（完整公开用户名）；以[固定的官方导出](https://github.com/fbsamples/threads_api/blob/dacb6b6b1aa123bc7a2ac805552cc01aeb93e488/postman/threads-api.postman_collection.json)为端点依据。关键词需要 `threads_basic` 和 `threads_keyword_search`；用户名查询需要 `threads_basic` 和 `threads_profile_discovery`。具体可用能力仍按 Meta 应用状态和批准权限决定。此次没有申请授权或领取凭据，也不读取网页登录会话。

## 本机调试

1. 在可访问 `https://graph.threads.com` 的受信 Windows 开发机上，从仓库根目录运行 `node tools/threads-data/dev-relay.mjs`。不提供令牌时，合法请求应收到 `503` 与 `{"error":"unconfigured"}`。
2. 只对自己的调试设备建立回环转发：`hdc -t <设备号> rport tcp:18948 tcp:18948`。打开应用「搜索 → Threads 公开内容 · 开发联调」，输入关键词发起请求。不需要令牌即可检查设备能否连到中转以及提示是否正确。
3. 真数据联调需要开发者在 **自己受信任的终端** 将官方授权的访问令牌注入中转进程的 `THREADS_ACCESS_TOKEN` 环境变量。不要把令牌放到聊天、命令历史、源码、安装包、截图或日志。只在受信开发机和设备上运行；同机本地程序可访问回环中转，Host 与来源检查不是用户身份认证。不要改为对局域网或公网监听，不要把中转当生产服务。
4. 结束后用 `hdc -t <设备号> fport rm tcp:18948 tcp:18948` 清理转发，并关闭中转进程。

## 已实现的范围

界面显示作者、正文、日期及可用的官方原帖链接；支持按页读取，原帖交给系统打开。没有媒体下载、帖子写入、账号同步，也不把官方结果存进本机时间线。中转只允许固定 Meta 端点和 GET，禁止重定向；向界面仅输出筛选过的数据和固定错误码。网络或授权不足时不使用示例帖冒充真实结果。

手机模拟器已通过回环转发看到未配置授权的提示。另用显式标注、完全离线的测试数据验证了关键词结果显示、分页和公开用户名查询；测试数据不包含在安装包中，也不是中转的默认行为。

下一页出错时保留已加载帖子和游标，重试入口在列表末尾；切换查询或模式会清除旧结果与错误，旧请求不会覆盖当前列表。

2026-11-28 较早的无凭据探测：本机 Windows 直连官网与 `graph.threads.com/me` 仍为 curl 28、HTTP 000；现有系统回环代理返回 CONNECT 200，但目标 TLS 随即失败（curl 35、HTTP 000）。同机直连 Microsoft 控制域返回 200。未修改系统或应用代理，未启动中转；这些结果只描述该次测试路径，不说明其他设备不可达或 Meta 授权失败。没有成功读取真实帖子。

后续使用已经存在的开发机回环代理重测：官网 HTTPS 为 200，`graph.threads.com/me` 无凭据返回 HTTP 400。这说明该出口可达官方服务，不说明 OAuth 成功或可读取授权范围；没有启动中转、登录、读取令牌或发起带授权查询。
