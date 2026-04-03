# AccountRateLimitsUpdatedNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AccountRateLimitsUpdatedNotification` 是服务器向客户端发送的实时通知，用于告知客户端账户的 API 速率限制状态已发生变化。

**使用场景：**
- 当用户的 API 调用接近或达到速率限制时
- 当速率限制窗口重置时
- 当用户升级/降级账户导致限制变化时
- 当多桶限流策略中的某个桶状态变化时

**职责：**
- 实时同步账户的速率限制状态
- 提供详细的配额使用情况（已使用百分比、重置时间等）
- 支持多桶限流模型（按 limit_id 分组）
- 帮助客户端实现前端限流提示和预警

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现速率限制状态的实时同步：

1. **配额监控**: 让客户端了解当前配额使用情况
2. **预警提示**: 在接近限制时提前通知用户
3. **多桶管理**: 支持不同 API 端点的独立限流统计
4. **用户体验**: 避免因突然达到限制而导致操作失败

**核心数据结构：**
- `RateLimitSnapshot`: 速率限制快照
  - `limitId`: 限制桶标识
  - `limitName`: 限制名称
  - `planType`: 账户套餐类型
  - `credits`: 积分信息（余额、是否无限等）
  - `primary`/`secondary`: 主次限制窗口
- `RateLimitWindow`: 限制窗口详情
  - `usedPercent`: 已使用百分比
  - `resetsAt`: 重置时间戳
  - `windowDurationMins`: 窗口持续时间

## 3. 具体技术实现 (Technical Implementation Details)

### 核心类型定义

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountRateLimitsUpdatedNotification {
    pub rate_limits: RateLimitSnapshot,
}

// RateLimitSnapshot 来自 codex_protocol::protocol
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub plan_type: Option<PlanType>,
    pub credits: Option<CreditsSnapshot>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
}

pub struct RateLimitWindow {
    pub used_percent: i32,
    pub resets_at: Option<i64>,
    pub window_duration_mins: Option<i64>,
}

pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 协议集成

在 `common.rs` 中注册：

```rust
server_notification_definitions! {
    AccountRateLimitsUpdated => "account/rateLimits/updated" (v2::AccountRateLimitsUpdatedNotification),
}
```

### 通知触发时机

1. 每次 API 调用后检查剩余配额
2. 速率限制窗口重置时
3. 账户状态变更时（升级/降级）
4. 定期心跳同步（可选）

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`
- **核心类型**: `codex_protocol::protocol::RateLimitSnapshot`
- **PlanType**: `codex_protocol::account::PlanType`

### 相关 API
- `GetAccountRateLimitsResponse`: 主动查询速率限制的响应类型
- `GetAccountRateLimits`: `account/rateLimits/read` 方法

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AccountRateLimitsUpdatedNotification.json`

### PlanType 枚举值
```rust
pub enum PlanType {
    Free,
    Go,
    Plus,
    Pro,
    Team,
    Business,
    Enterprise,
    Edu,
    Unknown,
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `codex_protocol::protocol::RateLimitSnapshot`: 核心速率限制数据结构
- `codex_protocol::account::PlanType`: 账户套餐类型
- `codex_protocol::protocol::CreditsSnapshot`: 积分信息
- `codex_protocol::protocol::RateLimitWindow`: 限制窗口

### 外部交互
- **计费系统**: 获取实时配额使用情况
- **账户系统**: 获取账户套餐类型
- **API 网关**: 监控 API 调用频率

### 相关配置
- 速率限制配置通常由服务端控制
- 客户端可通过配置控制是否显示限流提示

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **通知延迟**: 网络延迟可能导致客户端看到的限制状态滞后
2. **并发更新**: 多个通知的时序问题
3. **精度丢失**: `usedPercent` 是整数，可能不够精确

### 边界情况

1. **无限配额**: `unlimited: true` 时的特殊处理
2. **多桶策略**: 不同 `limit_id` 的独立管理
3. **窗口重置**: `resetsAt` 为 null 时的处理
4. **套餐变更**: 升级/降级时的平滑过渡

### 改进建议

1. **添加时间戳**: 建议添加 `updated_at` 字段
2. **更细粒度**: `usedPercent` 可改为浮点数提高精度
3. **历史趋势**: 可考虑添加近期使用率趋势
4. **预测提醒**: 基于使用趋势预测何时达到限制
5. **批量通知**: 多个 limit_id 变化时可合并通知

### 测试建议

1. 测试各种套餐类型的通知格式
2. 测试无限配额账户的通知
3. 测试多桶限流场景
4. 验证时间戳和时区处理
5. 测试高并发场景下的通知顺序

### 客户端实现建议

1. 实现本地缓存避免频繁刷新
2. 在 UI 中展示使用进度条
3. 接近限制时显示警告提示
4. 提供升级到更高套餐的入口
