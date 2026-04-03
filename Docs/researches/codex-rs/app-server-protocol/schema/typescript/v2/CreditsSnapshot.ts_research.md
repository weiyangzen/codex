# CreditsSnapshot.ts 研究文档

## 场景与职责

`CreditsSnapshot.ts` 定义了账户积分快照类型，用于表示用户在特定时间点的积分状态。该类型是速率限制和账户状态管理的一部分，帮助客户端了解用户的积分余额和使用情况。

该类型在账户信息查询、速率限制通知、使用统计等场景中发挥作用。

## 功能点目的

1. **积分状态展示**: 告知客户端用户是否有可用积分
2. **无限积分标识**: 区分普通用户和无限积分用户（如企业账户）
3. **余额查询**: 提供精确的积分余额（字符串格式，避免浮点精度问题）

## 具体技术实现

### 数据结构定义

```typescript
export type CreditsSnapshot = { 
  hasCredits: boolean, 
  unlimited: boolean, 
  balance: string | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `hasCredits` | `boolean` | 用户是否有可用积分（包括无限积分） |
| `unlimited` | `boolean` | 是否为无限积分账户 |
| `balance` | `string \| null` | 积分余额的字符串表示（如 `"1000"`），无限积分时为 `null` |

### 使用场景

```typescript
// 检查用户是否有可用积分
if (credits.hasCredits) {
  if (credits.unlimited) {
    console.log('无限积分账户');
  } else {
    console.log(`剩余积分: ${credits.balance}`);
  }
} else {
  console.log('积分已用完');
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/protocol/src/protocol.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 速率限制快照

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1690-1694)

```rust
pub struct GetAccountRateLimitsResponse {
    pub rate_limits: RateLimitSnapshot,
    pub rate_limits_by_limit_id: Option<HashMap<String, RateLimitSnapshot>>,
}
```

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,  // 积分快照
    pub plan_type: Option<PlanType>,
}
```

### 事件处理

**文件**: `codex-rs/app-server/src/bespoke_event_handling.rs`

处理账户速率限制更新事件，包含积分信息。

### 客户端使用

**文件**: `codex-rs/tui/src/status/rate_limits.rs`
**文件**: `codex-rs/tui_app_server/src/status/rate_limits.rs`

TUI 客户端使用积分信息显示账户状态。

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `codex_protocol::protocol::CreditsSnapshot` | 核心协议定义 |
| `codex_protocol::account::PlanType` | 账户计划类型 |

### 下游消费者

- **TUI**: 在状态栏显示积分余额
- **后端客户端**: `codex-rs/backend-client/src/client.rs`
- **API 服务**: `codex-rs/codex-api/src/rate_limits.rs`

## 风险、边界与改进建议

### 已知风险

1. **字符串余额**: 余额使用字符串而非数字，客户端需要自行解析
2. **精度问题**: 大数字的字符串表示可能存在解析精度问题
3. **缓存延迟**: 积分信息可能有延迟，不保证实时性

### 边界情况

1. **空余额**: `balance` 为 `null` 时，需结合 `unlimited` 字段判断
2. **负余额**: 后端应确保余额非负，但客户端应做好防御性编程
3. **格式变化**: 字符串格式可能包含前缀/后缀（如货币符号）

### 改进建议

1. **数值类型**: 考虑使用 `number` 类型替代字符串，或提供辅助解析函数
2. **货币信息**: 增加积分单位/货币信息
3. **历史记录**: 提供积分使用历史查询接口
4. **预警阈值**: 增加低积分预警功能
