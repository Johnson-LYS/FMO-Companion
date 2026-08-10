---
last-reviewed: 2026-08-09
---

# 模块：QSO

## 目的

QSO 模块让用户连接自己选择的 FMO 后，在 App 前台自动看到盒子日志，并在设备离线时继续浏览最后缓存。它只实现 ADR-0007 固定的分页摘要和逐条详情读取，不代理官方后台的删除、恢复、备份、签名、密钥或设备端 ADIF 操作。

模块把“来自所选 FMO 的日志”与“经过签名数据库归档验证”严格区分。普通界面只展示接口实际提供的呼号、网格、时间、模式、频率、服务器和备注，不显示虚构时长、精确轨迹或验签状态。

## 公共接口

```swift
protocol FmoQSOReading: Sendable {
    func connect(to endpoint: FmoDeviceEndpoint) async throws
    func list(page: Int, pageSize: Int) async throws -> FmoQSOListPage
    func detail(logID: Int64) async throws -> FmoQSODetail
    func disconnect() async
}

struct FmoQSOListPage: Equatable, Sendable {
    let totalCount: Int
    let page: Int
    let pageSize: Int
    let summaries: [FmoQSOSummary]
}

@MainActor @Observable
final class QSOModel {
    func configure(modelContext: ModelContext)
    func setDevice(endpoint: FmoDeviceEndpoint?, isConnected: Bool) async
    func setActive(_ active: Bool) async
    func setVisible(_ visible: Bool) async
    func refresh() async
    func loadDetail(logID: Int64) async
    func makeADIF() async -> String?
}
```

`FmoQSOReading` 没有通用 `send(type:subType:)`，因此调用层无法构造白名单外命令。`QSOModel` 是 SwiftUI 唯一状态入口；页面不直接接触 WebSocket、JSON 或 SwiftData 实体。

## 内部结构

- `FmoQSOProtocol` 只生成 `qso/getList(page,pageSize)` 与 `qso/getDetail(logId)`。当前固件的列表负载为 `data.list`，详情负载为 `data.log`；解码器验证该固定嵌套、响应路由、错误码、请求分页回显、ID、时间、文本上限、页内重复 ID 和 Maidenhead 格式，未知字段被丢弃。
- `FmoQSOReadClient` 使用独立 `/ws` 会话、5 秒响应超时和 512 KiB 帧上限。由于协议没有请求 ID，内部交换槽保证 Actor 重入时仍严格串行；超时、取消或畸形响应会关闭会话。
- `QSOModel` 将设备连接/切换、App 前台、QSO 页面出现、页面可见低频检查和手动刷新合并到每台设备最多一个同步任务。进入后台或设备切换会取消旧任务；页面离开停止轮询，并在同步空闲时关闭会话。
- 每次同步先读取全部摘要页。摘要按 `deviceID + logID` upsert，并比较摘要指纹；同一 ID 的时间、对端呼号或网格变化时清除旧详情，防止日志清空或固件复用 ID 后串数据。
- 页面可在首批摘要落库后展示内容；最近 20 条详情优先串行补齐，旧详情在用户打开或导出时按需读取。
- `FmoQSORecord` 和 `FmoQSOSyncMetadata` 使用 SwiftData。缓存按 `FmoDeviceEndpoint.id` 隔离，不静默合并多台盒子；只有全部摘要页成功且计数一致后才删除本轮未出现的旧记录。
- 部分分页失败只合并已经确认的新摘要，不执行删除对账；离线、部分失败和完整失败均保留最后内容与最后完整同步时间。
- 单次同步上限 10,000 条、单页上限 100 条。Debug 自动化的 10,000 条摘要基线约 4.5 秒，避免无界设备请求和缓存增长。
- `MaidenheadGrid` 只把 4/6/8 位网格换算成区域中心供 MapKit 定位，界面明确提示这是大致区域，不绘制虚构通联轨迹。
- `QSOADIFEncoder` 从规范化详情生成 UTF-8 ADIF，包含标准呼号、UTC 日期时间、模式、频率和网格；服务器、管理员与本地日志 ID 使用 `APP_FMO_*` 扩展。缺详情时先可取消地补齐，再交给系统文件导出。

## 数据流

```text
selected FMO + App active
→ FmoQSOReadClient（独立 /ws、严格串行）
→ qso/getList 全部分页
→ deviceID + logID + summary fingerprint
→ SwiftData summary cache
→ recent / on-demand qso/getDetail
→ SwiftData detail hydration
→ QSOModel projection
→ list / search / filter / Maidenhead map / ADIF
```

## 依赖与边界

- URLSession WebSocket：用户所选 FMO 的明文局域网只读会话。
- SwiftData：按设备隔离的摘要、详情与最后完整同步时间。
- MapKit：双方网格区域展示。
- SwiftUI / UniformTypeIdentifiers：浏览、搜索、筛选与系统文件导出。
- 不使用 APRS-IS、FMO 网络快照、官方网页 DOM、Cookie、数据库下载或第三方依赖。
- 不记录原始帧、真实呼号、端点、网格、备注或导出内容；自动化只使用人工脱敏数据。

## 错误与降级

- 没有选择设备：显示去“设备”连接的空状态，不尝试猜测其他缓存来源。
- 已选择设备但离线：显示该设备缓存和最后同步时间；没有缓存时显示离线空状态。
- 列表协议错误、总数在分页中变化、跨页重复 ID、超过 10,000 条、超时或断线：结束本轮，不删除旧缓存。
- 最近详情失败：摘要同步仍可完成，状态标为部分更新；列表可浏览，详情稍后按需重试。
- 详情不存在或与请求 ID 不一致：拒绝写入缓存，不把其他响应挂到当前记录。
- ADIF 所需详情无法补齐：不生成不完整且容易误导的文件，并给出产品化错误。
- 详情响应缺少 `data.log`：按协议错误关闭当前会话；不得退回到错误的 `data.{fields}` 夹具结构。

## 关键文件

- `FMOc/Features/QSO/FmoQSOProtocol.swift`
- `FMOc/Features/QSO/FmoQSOReadClient.swift`
- `FMOc/Features/QSO/FmoQSORecord.swift`
- `FMOc/Features/QSO/QSOModel.swift`
- `FMOc/Features/QSO/QsoViews.swift`
- `FMOc/Features/QSO/QSOADIFEncoder.swift`
- `FMOc/Features/QSO/MaidenheadGrid.swift`

## 测试

- 固定只读请求结构、`data.list`/`data.log` 嵌套、未知字段丢弃、错误路由/错误码、畸形字段、重复 ID 与帧上限。
- 全分页、最近详情、跨设备缓存切换、完整同步删除对账、ID 复用清详情。
- 部分页失败保留旧缓存、离线展示最后成功时间和 10,000 条摘要基线。
- Maidenhead 区域中心、UTF-8 ADIF 字节长度、频率与 `APP_FMO_*` 扩展。
- XCUITest 以 DEBUG 注入读取器验证连接设备后自动出现记录、整行进入详情、网格与服务器字段，并确认普通 UI 不出现验签/SQLite 文案；全量回归为 177 项单元测试与 16 项 XCUITest。
