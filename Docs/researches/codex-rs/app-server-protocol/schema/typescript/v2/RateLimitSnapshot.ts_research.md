# RateLimitSnapshot.ts 研究文档

## 场景与职责

`RateLimitSnapshot.ts` 定义了 API 速率限制快照的数据结构，用于在客户端和服务器之间传递账户级别的速率限制状态信息。这是 Codex 配额管理系统的重要组成部分，让用户能够实时了解其 API 使用情况。

## 功能点目的

该类型用于：
1. **速率限制监控**：追踪用户当前 API 配额的使用百分比和重置时间
2. **多层级限制支持**：支持主要(primary)和次要(secondary)两个限制窗口
3. **积分系统集成**：关联 CreditsSnapshot 显示账户积分状态
4. **计划类型标识**：关联 PlanType 区分不同订阅层级

## 具体技术实现

### 数据结构定义

```typescript
export type RateLimitSnapshot = { 
  limitId: string | null,      // 限制ID标识符
  limitName: string | null,    // 人类可读的限制名称
  primary: RateLimitWindow | null,    // 主要限制窗口
  secondary: RateLimitWindow | null,  // 次要限制窗口
  credits: CreditsSnapshot | null,    // 积分快照
  planType: PlanType | null,   // 订阅计划类型
};
```

### 关键依赖类型

- `RateLimitWindow`: 定义限制窗口的使用百分比、持续时间和重置时间
- `CreditsSnapshot`: 积分余额信息（has_credits, unlimited, balance）
- `PlanType`: 订阅计划类型枚举

### 服务端解析实现

在 `codex-rs/codex-api/src/rate_limits.rs` 中实现了从 HTTP 响应头解析速率限制：

```rust
pub fn parse_rate_limit_for_limit(
    headers: &HeaderMap,
    limit_id: Option<&str>,
) -> Option<RateLimitSnapshot> {
    // 解析 x-codex-primary-used-percent 等头部
    // 支持多限制家族（如 codex, codex_secondary）
}
```

解析的头部包括：
- `x-{limit}-primary-used-percent`: 主要窗口使用百分比
- `x-{limit}-primary-window-minutes`: 主要窗口持续时间
- `x-{limit}-primary-reset-at`: 主要窗口重置时间戳
- `x-{limit}-secondary-*`: 次要窗口对应头部
- `x-codex-credits-*`: 积分相关头部

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/RateLimitSnapshot.ts`
- 生成工具：ts-rs (Rust 到 TypeScript 的类型生成)

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs` 中的 `RateLimitSnapshot`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs` 导入 `CoreRateLimitSnapshot`

### 服务端实现
- 头部解析：`codex-rs/codex-api/src/rate_limits.rs`
- 事件处理：`codex-rs/app-server/src/bespoke_event_handling.rs`
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 状态显示：`codex-rs/tui/src/status/rate_limits.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/status/rate_limits.rs`

### 测试覆盖
- 集成测试：`codex-rs/app-server/tests/suite/v2/rate_limits.rs`
- 单元测试：`codex-rs/codex-api/src/rate_limits.rs` (mod tests)

## 依赖与外部交互

### 上游依赖
- HTTP 响应头：从 Codex 后端 API 获取速率限制信息
- 后端模型：`codex-backend-openapi-models/src/models/rate_limit_window_snapshot.rs`

### 下游消费
- TUI 状态栏：显示当前速率限制状态
- App Server：通过 `AccountRateLimitsUpdatedNotification` 通知客户端
- 聊天组件：在 UI 中展示配额警告

### 通知机制
```rust
// AccountRateLimitsUpdatedNotification 包含 RateLimitSnapshot
pub struct AccountRateLimitsUpdatedNotification {
    pub rate_limits: Vec<RateLimitSnapshot>,
}
```

## 风险、边界与改进建议

### 边界情况
1. **空快照处理**：当所有字段为 null 时，表示无可用限制信息
2. **多限制家族**：支持多个 limit_id（如 codex, codex_other）同时存在
3. **时间戳解析**：resets_at 使用 Unix 时间戳（秒级）

### 潜在风险
1. **头部大小写**：解析逻辑使用小写头部名称，但某些代理可能修改大小写
2. **浮点精度**：usedPercent 使用 f64，可能存在精度问题
3. **时区问题**：resets_at 时间戳假设客户端/服务器时钟同步

### 改进建议
1. **缓存策略**：考虑在客户端缓存限制信息，避免频繁请求
2. **预警机制**：在接近限制阈值时提前警告用户
3. **多租户支持**：当前设计已支持多 limit_id，但 UI 展示可能需要优化
4. **类型安全**：考虑将 limitId 从 string | null 改为更严格的联合类型
