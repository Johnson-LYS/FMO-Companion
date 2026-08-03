---
last-reviewed: 2026-08-03
status: accepted
---

# ADR-0004：采用 Swift 6 严格并发

**日期：** 2026-08-03

## 背景

FMO Companion 从零开始，首个里程碑就包含 Bonjour、WebSocket、定位、超时、取消和 App 生命周期等并发边界。若先在 Swift 5 兼容模式下积累实现，再切换严格并发，会把数据隔离和 `Sendable` 问题推迟到模块已经互相依赖之后。

## 决策

- App、单元测试和 UI 测试统一采用 Swift 6 语言模式。
- 开启完整严格并发检查；不使用警告降级或大范围 `@unchecked Sendable` 逃避隔离设计。
- UI 状态归属 `MainActor`；网络、协议和定位服务通过 Actor、值类型和 `Sendable` 协议隔离。
- 新异步 API 必须支持取消；超时使用结构化并发或可注入策略，不使用裸线程与阻塞等待。
- 仅当 Apple SDK 类型缺少正确并发标注且边界已被局部同步保护时，才允许最小范围使用 `@unchecked Sendable`，并说明原因。

## 结果

### 正面影响

- 数据竞争和跨 Actor 误用更早在编译期暴露。
- WebSocket、Bonjour、定位和测试替身共享统一的并发模型。
- 后续不需要进行一次高风险的全项目 Swift 6 迁移。

### 负面影响

- 初期需要更严格地设计 Delegate 桥接和系统框架边界。
- 某些旧式回调 API 需要包装为 AsyncSequence、continuation 或 Actor。
