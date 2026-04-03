# GetAccountRateLimitsResponse 研究报告

## 1. 场景与职责

`GetAccountRateLimitsResponse` 是 Codex App Server Protocol v2 中用于返回账户速率限制信息的响应结构体。该结构体提供了用户当前 API 使用配额、计划类型以及多维度速率限制窗口的完整视图。

### 主要使用场景

- **配额监控**：客户端实时显示用户的剩余配额和使用百分比，帮助用户了解当前资源状况
- **使用预警**：当配额接近上限时，向用户发出警告提示
- **计划类型展示**：显示用户当前的订阅计划（Free、Plus、Pro、Team 等）
- **多桶配额管理**：支持按不同限制 ID（如 `codex`）查看独立的配额桶
- **计费透明度**：向用户展示积分余额、无限使用权限等计费相关信息

### 职责边界

- 作为服务器到客户端的响应数据，承载完整的速率限制快照信息
- 提供向后兼容的单桶视图和新的多桶视图两种数据呈现方式
- 不包含敏感的个人身份信息，仅关注配额和限制状态

---

## 2. 功能点目的

### 2.1 速率限制快照（RateLimitSnapshot）

#### 核心功能

提供用户在特定时间点的完整配额使用状态：

| 字段 | 类型 | 说明 |
|------|------|------|
| `limitId` | `string \| null` | 限制标识符（如 `codex`） |
| `limitName` | `string \| null` | 限制的人类可读名称 |
| `planType` | `PlanType \| null` | 用户订阅计划类型 |
| `credits` | `CreditsSnapshot \| null` | 积分余额信息 |
| `primary` | `RateLimitWindow \| null` | 主限制窗口 |
| `secondary` | `RateLimitWindow \| null` | 次限制窗口 |

#### 设计意图

- **分层限制支持**：通过 `primary` 和 `secondary` 支持多层级速率限制（如每分钟 + 每天）
- **灵活标识**：`limitId` 和 `limitName` 支持按产品或功能细分的配额管理
- **计划感知**：包含 `planType` 使客户端能够根据用户计划展示相应的功能和限制

### 2.2 积分快照（CreditsSnapshot）

| 字段 | 类型 | 说明 |
|------|------|------|
| `hasCredits` | `boolean` | 是否有可用积分 |
| `unlimited` | `boolean` | 是否拥有无限使用权限 |
| `balance` | `string \| null` | 积分余额（字符串格式，支持大数） |

#### 功能目的

- **精确计费**：使用字符串存储余额，避免浮点数精度问题
- **权限区分**：`unlimited` 标志区分真正的无限配额和有具体余额的配额
- **可用性检查**：`hasCredits` 提供快速的积分可用性判断

### 2.3 速率限制窗口（RateLimitWindow）

| 字段 | 类型 | 说明 |
|------|------|------|
| `usedPercent` | `integer` | 已使用配额百分比（0-100） |
| `resetsAt` | `integer \| null` | 窗口重置时间（Unix 时间戳，秒） |
| `windowDurationMins` | `integer \| null` | 窗口持续时间（分钟） |

#### 功能目的

- **可视化支持**：`usedPercent` 直接支持进度条等 UI 组件
- **时间感知**：`resetsAt` 允许客户端显示"配额将在 X 分钟后重置"
- **透明性**：`windowDurationMins` 帮助用户理解限制的时间范围

### 2.4 多桶视图（rateLimitsByLimitId）

| 属性 | 说明 |
|------|------|
| 类型 | `object \| null` |
| 键 | 限制 ID（如 `codex`） |
| 值 | `RateLimitSnapshot` |

#### 功能目的

- **产品扩展**：支持多个产品各自拥有独立的配额体系
- **向后兼容**：保留 `rateLimits` 单桶视图确保现有客户端正常工作
- **未来扩展**：为未来的产品（如 Code Interpreter、Browsing 等）预留配额展示能力

---

## 3. 具体技术实现

### 3.1 数据结构定义

#### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "CreditsSnapshot": { /* ... */ },
    "PlanType": { /* enum: free, go, plus, pro, team, business, enterprise, edu, unknown */ },
    "RateLimitSnapshot": { /* ... */ },
    "RateLimitWindow": { /* ... */ }
  },
  "properties": {
    "rateLimits": {
      "allOf": [{ "$ref": "#/definitions/RateLimitSnapshot" }],
      "description": "Backward-compatible single-bucket view; mirrors the historical payload."
    },
    "rateLimitsByLimitId": {
      "additionalProperties": { "$ref": "#/definitions/RateLimitSnapshot" },
      "description": "Multi-bucket view keyed by metered `limit_id` (for example, `codex`).",
      "type": ["object", "null"]
    }
  },
  "required": ["rateLimits"],
  "title": "GetAccountRateLimitsResponse",
  "type": "object"
}
```

#### Rust 结构体定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GetAccountRateLimitsResponse {
    /// Backward-compatible single-bucket view; mirrors the historical payload.
    pub rate_limits: RateLimitSnapshot,
    /// Multi-bucket view keyed by metered `limit_id` (for example, `codex`).
    pub rate_limits_by_limit_id: Option<HashMap<String, RateLimitSnapshot>>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<PlanType>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct RateLimitWindow {
    /// Percentage (0-100) of the window that has been consumed.
    pub used_percent: i32,
    /// Rolling window duration, in minutes.
    #[ts(type = "number | null")]
    pub window_duration_mins: Option<i64>,
    /// Unix timestamp (seconds since epoch) when the window resets.
    #[ts(type = "number | null")]
    pub resets_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 3.2 核心协议类型

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<crate::account::PlanType>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct RateLimitWindow {
    /// Percentage (0-100) of the window that has been consumed.
    pub used_percent: f64,
    /// Rolling window duration, in minutes.
    #[ts(type = "number | null")]
    pub window_minutes: Option<i64>,
    /// Unix timestamp (seconds since epoch) when the window resets.
    #[ts(type = "number | null")]
    pub resets_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 3.3 计划类型枚举

```rust
// codex-rs/protocol/src/account.rs
#[derive(Serialize, Deserialize, Copy, Clone, Debug, PartialEq, Eq, JsonSchema, TS, Default)]
#[serde(rename_all = "lowercase")]
#[ts(rename_all = "lowercase")]
pub enum PlanType {
    #[default]
    Free,
    Go,
    Plus,
    Pro,
    Team,
    Business,
    Enterprise,
    Edu,
    #[serde(other)]
    Unknown,
}
```

### 3.4 协议集成

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
client_request_definitions! {
    // ...
    GetAccountRateLimits => "account/rateLimits/read" {
        params: #[ts(type = "undefined")] #[serde(skip_serializing_if = "Option::is_none")] Option<()>,
        response: v2::GetAccountRateLimitsResponse,
    },
    // ...
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 协议定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 类型定义（第 1689-1694 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 请求方法注册（第 446-449 行） |
| `codex-rs/protocol/src/protocol.rs` | 核心协议类型定义（第 1868-1894 行） |
| `codex-rs/protocol/src/account.rs` | `PlanType` 定义 |

### 4.2 Schema 文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/GetAccountRateLimitsResponse.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/GetAccountRateLimitsResponse.ts` | TypeScript 类型定义 |

### 4.3 服务端实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/codex-api/src/rate_limits.rs` | 速率限制 API 实现 |
| `codex-rs/backend-client/src/types.rs` | 后端客户端类型定义 |
| `codex-rs/core/src/token_data.rs` | 令牌数据管理 |

### 4.4 消费端代码

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/status/rate_limits.rs` | TUI 速率限制显示 |
| `codex-rs/tui_app_server/src/status/rate_limits.rs` | TUI App Server 速率限制状态 |
| `codex-rs/tui_app_server/src/status/card.rs` | 状态卡片 UI |

### 4.5 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/rate_limits.rs` | 速率限制 API 集成测试 |
| `codex-rs/tui_app_server/src/status/tests.rs` | 状态显示测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
GetAccountRateLimitsResponse
├── RateLimitSnapshot
│   ├── RateLimitWindow (primary/secondary)
│   ├── CreditsSnapshot
│   └── PlanType (from codex_protocol::account)
└── rateLimitsByLimitId (HashMap<String, RateLimitSnapshot>)
```

### 5.2 外部服务交互

#### 速率限制数据获取流程

```
Client -> account/rateLimits/read
    -> App Server
        -> Backend Client
            -> OpenAI Backend API
                -> Rate Limit Service
            <- Rate Limit Status Payload
        <- RateLimitSnapshot (internal)
    <- GetAccountRateLimitsResponse
```

#### 后端 API 类型映射

```rust
// codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs
pub struct RateLimitStatusPayload {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub plan_type: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
}
```

### 5.3 数据流

1. **获取阶段**：从后端 API 获取原始速率限制数据
2. **转换阶段**：将后端模型转换为内部 `RateLimitSnapshot`
3. **响应阶段**：将内部模型转换为 v2 API 响应格式
4. **展示阶段**：客户端根据响应更新 UI

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 描述 | 影响 | 缓解措施 |
|--------|------|------|---------|
| 数据不一致 | `rateLimits` 和 `rateLimitsByLimitId` 中的同一限制 ID 数据不一致 | 客户端困惑 | 确保服务端使用统一数据源 |
| 精度丢失 | `usedPercent` 从 f64 转换为 i32 可能导致精度丢失 | 显示不准确 | 明确精度要求，考虑保留小数位 |
| 时区问题 | `resetsAt` 使用 Unix 时间戳，但客户端可能误解 | 显示错误重置时间 | 文档明确说明时间戳格式 |
| 空值处理 | 多个可选字段为 null 时的客户端处理 | UI 显示异常 | 提供默认值指导 |
| 并发更新 | 速率限制在请求过程中可能变化 | 显示过时数据 | 实现适当的缓存策略 |

### 6.2 边界情况

1. **无限制用户**
   - `unlimited: true` 时，`balance` 可能为 null
   - `usedPercent` 可能始终为 0

2. **多桶场景**
   - `rateLimits` 和 `rateLimitsByLimitId["codex"]` 应包含相同数据
   - 新的限制 ID 可能只出现在 `rateLimitsByLimitId` 中

3. **窗口类型差异**
   - `primary` 和 `secondary` 可能有不同的 `windowDurationMins`
   - 某些计划可能只有一个窗口（secondary 为 null）

4. **计划变更**
   - 用户在会话期间升级/降级计划
   - 需要实时反映新的限制

### 6.3 改进建议

#### 短期改进

1. **增强文档**
   ```rust
   /// 注意：usedPercent 为 0-100 的整数百分比
   /// 注意：resetsAt 为 Unix 时间戳（秒），非毫秒
   ```

2. **添加元数据字段**
   ```rust
   pub struct GetAccountRateLimitsResponse {
       // ... 现有字段
       /// 数据获取时间戳，用于客户端判断数据新鲜度
       pub fetched_at: i64,
   }
   ```

3. **一致性校验**
   - 在服务端添加断言，确保 `rateLimits` 和对应 `rateLimitsByLimitId` 条目一致

#### 中期改进

1. **细粒度限制类型**
   ```rust
   pub enum LimitType {
       RequestsPerMinute,
       TokensPerDay,
       ComputeUnitsPerHour,
       // ...
   }
   ```

2. **历史趋势数据**
   ```rust
   pub struct RateLimitHistory {
       pub timestamp: i64,
       pub used_percent: i32,
   }
   ```

3. **预警阈值配置**
   ```rust
   pub struct RateLimitAlertConfig {
       pub warning_threshold: i32,  // 如 80%
       pub critical_threshold: i32, // 如 95%
   }
   ```

#### 长期改进

1. **实时推送**
   - 当速率限制状态变化时，通过 WebSocket 推送 `AccountRateLimitsUpdated` 通知
   - 减少轮询，提高实时性

2. **预测性限制**
   - 基于使用模式预测何时会达到限制
   - 提前向用户发出警告

3. **限制策略建议**
   - 根据用户使用模式推荐合适的计划升级
   - 提供优化使用效率的建议

### 6.4 兼容性考虑

- **v1 API 弃用**：`GetAuthStatus` 已被标记为弃用，应引导用户迁移到 `GetAccountRateLimits`
- **字段演进**：新增字段应保持可选，避免破坏现有客户端
- **计划类型扩展**：新增 `PlanType` 变体时应使用 `#[serde(other)]` 处理未知值
