# GetAccountRateLimitsResponse.ts 研究文档

## 场景与职责

`GetAccountRateLimitsResponse.ts` 定义了获取账户速率限制响应的类型，用于返回用户的速率限制状态。这是账户管理 API 的重要组成部分，帮助客户端了解当前的使用限制和配额状态。

该类型在速率限制显示、使用监控、配额预警等场景中发挥作用。

## 功能点目的

1. **速率限制查询**: 获取当前账户的速率限制状态
2. **多桶视图**: 支持按 `limit_id` 分桶的速率限制视图
3. **向后兼容**: 保留传统的单桶视图

## 具体技术实现

### 数据结构定义

```typescript
export type GetAccountRateLimitsResponse = { 
  /**
   * Backward-compatible single-bucket view; mirrors the historical payload.
   */
  rateLimits: RateLimitSnapshot, 
  /**
   * Multi-bucket view keyed by metered `limit_id` (for example, `codex`).
   */
  rateLimitsByLimitId: { [key in string]?: RateLimitSnapshot } | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `rateLimits` | `RateLimitSnapshot` | 向后兼容的单桶速率限制视图 |
| `rateLimitsByLimitId` | `Record<string, RateLimitSnapshot> \| null` | 按 `limit_id` 分桶的多桶视图 |

### 依赖类型

```typescript
export type RateLimitSnapshot = {
  limitId: string | null;
  limitName: string | null;
  primary: RateLimitWindow | null;
  secondary: RateLimitWindow | null;
  credits: CreditsSnapshot | null;
  planType: PlanType | null;
};

export type RateLimitWindow = {
  usedPercent: number;           // 已使用百分比
  windowDurationMins: number | null;  // 窗口持续时间（分钟）
  resetsAt: number | null;       // 重置时间戳
};
```

### 使用示例

```typescript
const response: GetAccountRateLimitsResponse = await client.sendRequest('account/getRateLimits', {});

// 使用传统视图
const { rateLimits } = response;
console.log(`主限制: ${rateLimits.primary?.usedPercent}%`);

// 使用多桶视图
if (response.rateLimitsByLimitId) {
  for (const [limitId, snapshot] of Object.entries(response.rateLimitsByLimitId)) {
    console.log(`${limitId}: ${snapshot?.primary?.usedPercent}%`);
  }
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1686-1694)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GetAccountRateLimitsResponse {
    /// Backward-compatible single-bucket view; mirrors the historical payload.
    pub rate_limits: RateLimitSnapshot,
    /// Multi-bucket view keyed by metered `limit_id` (for example, `codex`).
    pub rate_limits_by_limit_id: Option<HashMap<String, RateLimitSnapshot>>,
}
```

### 速率限制快照

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<PlanType>,
}
```

### 速率限制窗口

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub struct RateLimitWindow {
    pub used_percent: f64,
    pub window_duration_mins: Option<u32>,
    pub resets_at: Option<i64>,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `RateLimitSnapshot` | 速率限制快照类型 |
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 状态栏**: 显示速率限制状态
- **VS Code 扩展**: 显示配额信息
- **监控工具**: 收集使用统计

## 风险、边界与改进建议

### 已知风险

1. **双视图冗余**: 同时维护两个视图增加复杂性
2. **null 处理**: `rateLimitsByLimitId` 可能为 null
3. **精度问题**: `usedPercent` 使用浮点数可能有精度问题

### 边界情况

1. **无限制**: 某些账户可能无速率限制
2. **多计划**: 用户可能有多个计划的不同限制
3. **时间同步**: `resetsAt` 依赖客户端时间同步

### 改进建议

1. **统一视图**: 逐步迁移到多桶视图，弃用单桶视图
2. **实时更新**: 支持速率限制的实时推送更新
3. **预警机制**: 接近限制时主动通知
4. **历史趋势**: 提供使用率历史趋势

### 扩展示例

```typescript
export type GetAccountRateLimitsResponse = {
  rateLimits: RateLimitSnapshot;
  rateLimitsByLimitId: Record<string, RateLimitSnapshot> | null;
  // 新增字段
  updatedAt: number;           // 更新时间
  nextResetAt: number;         // 下次全局重置时间
  warnings: string[];          // 警告信息
};
```
