---
last-reviewed: 2026-08-08
---

# 项目简报

## 概览

FMO Companion 是服务于持证业余无线电爱好者的原生 iOS App。它把 iPhone 作为 FMO 盒子的局域网伴侣、GPS 来源、APRS 信息终端、远程控制器、QSO 日志工具和自建服务器运维入口。

项目坚持公开接口边界：使用官方 GEO WebSocket、FMO V4 APRS、官方 APRS 远控示例、用户导出的 QSO 文件及用户自建 HTTPS API，不逆向核心语音协议或设备私钥。

## 当前状态

- **阶段：** 0.1–0.6 已完成；下一阶段为 0.8 QSO 导入、查询、验签与 ADIF
- **已完成：** 0.1 局域网真机闭环；0.2 可靠定位真机闭环；0.3 设备仪表盘；0.4 只读 APRS-IS 与可信 FMO 网络；0.6 前台 APRS 消息、ACK 与 FMO 公网远控
- **发布前跟踪：** 官方信任锚独立许可证、完整官方 APRS CERT/SIG 字节向量与 Intermediate CRL 轮换；这些事项不回退已完成的 0.4 里程碑，但正式发布前必须关闭或明确处理
- **字段门槛：** 呼号、当前服务器、过滤距离、单一频率、QSO 日志数与本地讲话/历史已由 ADR-0005 批准进入 Release 白名单；延迟、管理员、在线人数、无服务器与重启事件语义继续延期

## 最近变更

| 日期 | 变更 | 参考 |
|---|---|---|
| 2026-08-08 | 用户复验 APRS 消息与远控真机链路通过；结合首轮 162 项单元测试、11 条 XCUITest、修正后源码兼容向量与测试目标编译，0.6 转为 Complete。收尾时测试宿主受同机其他 Xcode 测试任务影响未能再次启动，无代码断言失败 | `docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 修正后的 `APFMO0 + 60 字节 UTF-8` 普通消息已完成真机互发与 ACK 验收；0.6 消息、远控真机闭环均通过，剩余门槛为新增兼容向量的完整自动化回归 | `docs/architecture/modules/aprs.md`、`docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 0.6 远控真机链路通过；普通消息首轮互发失败定位到 FMO 兼容边界，已把 `APFMC0 + 7-bit ASCII/67` 修正为 `APFMO0 + 60 字节 UTF-8`，保留无效草稿并等待复验 | `docs/architecture/modules/aprs.md`、`docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 0.6 首轮实现通过 162 项单元测试与 11 条主流程 XCUITest；同时修复冷启动 ScenePhase 竞态，确保稍后配置身份后只读/写 APRS 会话均可进入前台连接 | `docs/architecture/modules/aprs.md`、`docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 完成 0.6 首轮原生实现：隔离验证写会话、自动 PASSCODE、标准消息/ACK、本机历史、按目标 Keychain SECRET、原子 Counter、三种远控与重启系统认证；进入测试和真机闭环 | `docs/adr/0006-isolated-aprs-write-session.md`、`docs/architecture/modules/aprs.md`、`docs/architecture/modules/remote-control.md` |
| 2026-08-07 | 顶层“首页”改名为“设备”；远控入口和按目标隔离的 SECRET 设置归入设备，FMO 网络只保留 APRS 身份与消息；PASSCODE 由基础呼号自动计算且不持久化 | `docs/design/ui-design-system.md`、`docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 冻结 0.6 产品范围：先消息/ACK 后远控；仅保证前台收发，本地历史、有限消息重试、远控禁止自动重发、按目标 SECRET 与产品化远控页面 | `docs/plans/0008-milestone-0.6-aprs-messaging-remote-control.md` |
| 2026-08-07 | 用户完成 0.4 真实 iPhone + APRS-IS 真机验收；146 项单元测试与 14 项 XCUITest 通过，里程碑转为 Complete | `docs/plans/0007-milestone-0.4-fmo-aprs.md` |
| 2026-08-07 | 修正 FMO 网络身份条在浅色 grouped background 上缺少层级的问题，改用系统语义卡片底色与轻描边并保持深色模式适配 | `docs/design/ui-design-system.md` |
| 2026-08-07 | FMO 网络本地展示范围默认改为 500 km；首次进入自动取得手机位置，失败则回退全网，定位依赖纳入正式组合根与 UI 测试替身 | `docs/spec/product-spec.md`、`docs/architecture/modules/aprs.md` |
| 2026-08-06 | FMO 网络增加右上角全网/公里范围过滤，统一裁剪地图、目录和事件；追踪移到地图左下，事件采用最近 24 小时且最多 200 条的双上限并在界面可见 | `docs/spec/product-spec.md`、`docs/architecture/modules/aprs.md` |
| 2026-08-06 | FMO 网络地图增加默认开启的自动追踪开关与一次性“我的位置”按钮；明确公网 `APFMO4` 数据不继承盒子距离过滤器，地图控件不改变事件范围或写入设备 | `docs/spec/product-spec.md`、`docs/architecture/modules/aprs.md` |
| 2026-08-06 | 按真机体验反馈隐藏 FMO 网络的可信、身份验证与 CRL 技术状态，地图、目录、事件和详情统一展示已通过内部准入的业务数据；底层证书链、签名、吊销与类型化拒绝保持不变 | `docs/design/prototype-implementation-guide.md`、`docs/architecture/modules/aprs.md` |
| 2026-08-06 | 真机联调修正 APRS 未压缩位置边界：FMO 注释紧跟 symbol code，不存在额外空格；公开完整 STATION 报文的解析、官方证书链与消息签名临时端到端验证通过，真实报文未写入仓库 | `docs/architecture/modules/aprs.md` |
| 2026-08-06 | 完成 0.4 可信网络主体：官方证书链与 CRL、严格 CBOR/Ed25519 验证、可信聚合、地图、目录搜索、事件筛选、信任详情及呼号/服务器收藏；完整单元测试新增覆盖已通过 | `docs/architecture/modules/aprs.md`、`docs/plans/0007-milestone-0.4-fmo-aprs.md` |
| 2026-08-06 | 官方 SAS 源码已公开 Root/Intermediate CA 与两类 CRL 的确定性 CBOR TBS；开发验证门槛解除，独立证书许可证链接和完整 APRS 字节向量仍为发布前事项 | `docs/references/fmo-aprs-v4-readiness.md` |
| 2026-08-06 | 完成 0.4 可测试身份/会话切片：手动优先与 FMO 呼号继承、前台生命周期、登录超时、自动重连、身份 Sheet 和真实连接状态；未验证帧继续隔离 | `docs/architecture/modules/aprs.md`、`docs/plans/0007-milestone-0.4-fmo-aprs.md` |
| 2026-08-06 | 完成 0.4 首个代码切片：只读 APRS-IS transport、身份/登录、CRLF/TNC2 与全部规划 FMO V4 未验证解析；30 项新增测试通过，可信验证与 UI 继续阻塞 | `docs/architecture/modules/aprs.md`、`docs/plans/0007-milestone-0.4-fmo-aprs.md` |
| 2026-08-06 | 完成 FMO V4 官方材料核对：解析格式可冻结，生产验签因 CRL、许可证、CA/CRL 签名规则和完整向量暂时阻塞 | `docs/references/fmo-aprs-v4-readiness.md` |
| 2026-08-06 | APRS 身份与“消息与远控”采用最多两层的关联 Sheet，移除重复 Hero 与实现文案，并固化产品化文案和轻量编辑原则 | `docs/design/ui-design-system.md`、`prototype/index.html` |
| 2026-08-06 | 确认 0.4 只读身份继承规则，补齐 APRS 身份原型并建立 0007 实施计划草案 | `docs/plans/0007-milestone-0.4-fmo-aprs.md`、`prototype/index.html` |
| 2026-08-06 | 冻结 0.4 为 APRS-IS `pass -1` 前台只读接收；公网消息/远控留到 0.6，局域网 WS 写操作继续由官方 Web UI 承担 | `docs/spec/technical-spec.md`、`docs/plans/0003-product-roadmap.md` |
| 2026-08-06 | 用户确认 0.3 真机体验达到阶段目标；20 个单元测试套件、93 项测试通过，里程碑转为 Complete | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-06 | 首页连接期间低频只读刷新当前服务器；事件动画收敛为“同人只换图标并渐灰、换人才整行切换” | `docs/architecture/modules/device-connectivity.md`、`docs/design/ui-design-system.md` |
| 2026-08-06 | 收紧仪表盘网格/过滤距离辅助信息；事件窗口增加固定图标槽位、历史呼号降灰和实时相对时间刷新 | `docs/design/ui-design-system.md`、`docs/architecture/modules/dashboard.md` |
| 2026-08-06 | 修复浅色模式下深色仪表盘文字对比度；设备选择按钮收敛为单行，网格/距离图标降为辅助层级 | `docs/design/ui-design-system.md`、`docs/architecture/modules/dashboard.md` |
| 2026-08-05 | 完成首页原生设备选择 Sheet、启动恢复上次成功设备与手动切换优先；主 App 解除实时活动扩展依赖和嵌入 | `docs/architecture/modules/device-connectivity.md`、`docs/architecture/modules/dashboard.md` |
| 2026-08-05 | 实时活动从 0.3 移除；首页原型改为启动恢复上次设备，设备列表收进呼号右侧按钮打开的选择 Sheet | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-03 | 创建 Xcode SwiftUI 工程 | `FMOc.xcodeproj` |
| 2026-08-03 | 使用 Loom 结构初始化文档与 Agent 环境 | `docs/plans/0001-project-bootstrap.md` |
| 2026-08-03 | 将研究阶段的功能规划写入仓库 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-03 | 通过初始单元测试与 UI 测试 | `docs/plans/0001-project-bootstrap.md` |
| 2026-08-03 | 将最低部署版本提高到 iOS 26.0，不维护旧系统兼容分支 | `docs/adr/0003-ios-26-minimum-deployment.md` |
| 2026-08-03 | 完成交互式 HTML 原型与 `#FF8800` UI 设计基线 | `docs/plans/0004-interactive-prototype-and-ui-design.md` |
| 2026-08-03 | 将原型扩展到全部规划规格并建立覆盖矩阵 | `docs/design/prototype-coverage-matrix.md` |
| 2026-08-03 | 将用户导航重构为四标签并重新归类功能 | `docs/design/ui-design-system.md` |
| 2026-08-03 | 移除可见评审层并新增面向 AI 的原型实现指南 | `docs/design/prototype-implementation-guide.md` |
| 2026-08-03 | 启动 0.1 开发，完成原生局域网连接首个可运行切片 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-03 | 采用 Swift 6 完整严格并发检查 | `docs/adr/0004-swift-6-strict-concurrency.md` |
| 2026-08-03 | 真机修正 Bonjour 地址作用域问题，改为持久化 `fmo.local` 稳定身份 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-03 | 修正 SwiftUI 整行条目留白无法点击，并固化全宽命中规范 | `docs/design/ui-design-system.md` |
| 2026-08-03 | 完成 Wi-Fi、主机端口、HTTP 与 GEO WebSocket 四步实时连接诊断 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-03 | 补齐权限拒绝的系统设置恢复入口与异常断线状态收敛覆盖 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-04 | 修正发现覆盖手动设备、补齐设备移除，并区分首页会话与独立诊断结果 | `docs/architecture/modules/device-connectivity.md` |
| 2026-08-05 | 曾确认启动扫描后首台一次性自动尝试；后续已由“只恢复上次成功设备”规则取代 | `docs/spec/product-spec.md` |
| 2026-08-04 | 设备删除改为系统原生左滑，并固化为所有可删除列表的 UI 规范 | `docs/design/ui-design-system.md` |
| 2026-08-04 | Johnson iPhone 13 Pro + 真实 FMO 完成 0.1 全流程真机验收 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-04 | 冻结 0.2 模式阈值、离网恢复与系统浏览器契约并启动开发 | `docs/plans/0005-milestone-0.2-reliable-location.md` |
| 2026-08-04 | 完成 0.2 定位策略、iOS 26 后台会话、授权映射、模式存储与工程配置 | `docs/architecture/modules/location-sync.md` |
| 2026-08-04 | 完成自动同步协调器、网络门控、离网恢复和可取消指数退避 | `docs/architecture/modules/location-sync.md` |
| 2026-08-04 | 接入位置自动化状态页、启动恢复、共享稳定端点与官方管理/QSO 系统浏览器入口 | `docs/plans/0005-milestone-0.2-reliable-location.md` |
| 2026-08-04 | 真实 iPhone + FMO 完成 0.2 后台、锁屏、离网恢复、停止与系统终止恢复验收 | `docs/plans/0005-milestone-0.2-reliable-location.md` |
| 2026-08-04 | 将首页设备仪表盘与锁屏实时活动纳入 0.3，先进入文档与原型评审 | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-04 | 收敛语音事件为图标化“最近活动”，并补齐收藏呼号与公共服务器的产品、技术和原型闭环 | `docs/spec/product-spec.md` |
| 2026-08-04 | 用户确认最终仪表盘原型；0.3 调整为先实现共享基础与 GEO 字段，其他设备状态等待公开接口 | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-04 | 完成 0.3 首个原生切片：共享 Dashboard 快照、Maidenhead 派生、断线过期与首页真实字段投影 | `docs/architecture/modules/dashboard.md` |
| 2026-08-05 | 分析用户本人设备后台 WebSocket：确认呼号、当前服务器、过滤枚举、单频率、QSO 日志数与本地讲话事件；原始敏感抓包不入库 | `docs/references/fmo-open-capabilities.md` |
| 2026-08-05 | 0.3 原型收敛为已观察字段语义，隐藏延迟、管理员与在线人数，并记录接口授权门槛和待补样本 | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-05 | 接受 ADR-0005 并实现严格白名单的本地只读状态/事件客户端；首页改为数据与图标优先，不显示实现解释文案 | `docs/adr/0005-user-authorized-local-read-only-status.md` |
| 2026-08-05 | 用户提供 IP 的脱敏真机探测确认 `/ws` 五个白名单路由；`/events` 握手成功但等待实际事件样本 | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |
| 2026-08-05 | 完成定稿三段式原生仪表盘；当时的首台自动连接策略后续已由上次设备恢复 + Sheet 切换取代 | `docs/architecture/modules/dashboard.md`、`docs/architecture/modules/device-connectivity.md` |
| 2026-08-05 | 用户确认修订后自动连接流程真机测试无问题，0.1 计划关闭 | `docs/plans/0002-milestone-0.1-local-connection.md` |
| 2026-08-05 | 完成 ActivityKit 生命周期、隐私投影、锁屏与 Dynamic Island Widget Extension；联合构建和完整单元测试通过 | `docs/architecture/modules/dashboard.md` |
| 2026-08-05 | 首轮真机未展示实时活动；补齐扩展声明、活动标识恢复与 ActivityKit 失败提示，等待真机复验 | `docs/plans/0006-milestone-0.3-device-dashboard-live-activity.md` |

## 领域术语

| 术语 | 定义 |
|---|---|
| FMO | NFM Over Internet；通过互联网连接的模拟窄带调频通联系统及硬件节点 |
| FMO 盒子 | 持有设备身份、负责发现、鉴权和语音处理的硬件终端 |
| GEO 接口 | 盒子在局域网开放的坐标读写 WebSocket 接口 |
| APRS-IS | APRS 互联网骨干；FMO 用于节点发现、事件和远程消息 |
| SAS | FMO Server Authorizer Service；为 MQTT Broker 提供证书鉴权与 ACL |
| STATION | FMO V4 中用于广播服务器地址、端口、覆盖范围和在线人数的报文 |
| CERT blob | FMO V4 报文携带的 CBOR 用户证书容器 |
| QSO | 两个业余无线电台之间的一次通联记录 |

## 核心业务规则

- 使用者必须自行具备合规的呼号、证书与 APRS 凭据；App 不代替资质认证。
- 设备私钥不得离开 FMO 盒子，App 不提取、不备份、不模拟。
- APRS-IS PASSCODE 由规范化基础呼号按需计算，不持久化；远控 SECRET 只保存在 Keychain，不进入日志或云端同步。
- `VOCAL` 只代表某呼号近期触发过语音活动，不等于实时通联、当前说话人或语音内容。
- iOS 后台定位不能承诺固定分钟级调度，只能基于系统位置更新做节流。
- 盒子设置仍通过官方 `fmo.local` Web UI 打开；ADR-0005 只允许类型化只读状态，不使用 DOM 注入、不提供通用命令代理。
- FMO 连接 iPhone 自身个人热点的反向访问能力必须实机验证，在验证前不作为保证场景。

## 关键决策

- [ADR-0001：原生 iOS 与公开协议边界](adr/0001-native-ios-public-protocol-boundary.md)
- [ADR-0002：采用 Loom 文档驱动的 Agent 工作流](adr/0002-loom-document-driven-development.md)
- [ADR-0003：最低部署版本采用 iOS 26](adr/0003-ios-26-minimum-deployment.md)
- [ADR-0004：采用 Swift 6 严格并发](adr/0004-swift-6-strict-concurrency.md)
- [ADR-0005：采用用户授权的本地只读状态接口](adr/0005-user-authorized-local-read-only-status.md)

## 本轮开发入口

1. 0.6 已关闭；下一阶段先为 0.8 建立独立计划，不直接沿用 0.6 实现计划。
2. 先取得用户从 `qso.html` 下载的脱敏 SQLite、签名及必要元数据样本，确认 schema、更新方式和验签输入。
3. 0.8 第一版仍按用户主动下载或 Files 导入设计；除非确认公开、稳定且授权的下载接口，否则不宣称与 FMO 实时同步。
4. 完成 QSO 文档与原型评审后，再实现只读导入、查询、地图、P-256 验签和 ADIF 导出。
