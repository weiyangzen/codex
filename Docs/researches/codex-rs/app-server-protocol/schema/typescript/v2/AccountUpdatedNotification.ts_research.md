# AccountUpdatedNotification.ts 研究文档

## 1. 场景与职责

`AccountUpdatedNotification` 是服务器向客户端推送的**账户状态变更通知**，用于在账户的关键属性发生变化时通知客户端更新。

### 使用场景
- **认证模式变更**: 用户从 API Key 切换到 ChatGPT 登录，或反之
- **套餐升级/降级**: 用户的 PlanType 发生变化时
- **登录状态变更**: 用户登出或切换账户时
- **配置同步**: 确保多设备间的账户状态一致

### 职责
- 通知客户端账户的认证模式（`authMode`）变化
- 通知客户端账户套餐类型（`planType`）变化
- 触发客户端重新获取完整的账户信息

---

## 2. 功能点目的

### 2.1 账户状态变更通知

```typescript
export type AccountUpdatedNotification = { 
  authMode: AuthMode | null,   // 认证模式
  planType: PlanType | null,   // 套餐类型
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `authMode` | `AuthMode \| null` | 当前认证模式：`"apikey"`, `"chatgpt"`, `"chatgptAuthTokens"` |
| `planType` | `PlanType \| null` | 当前套餐类型：`"free"`, `"plus"`, `"pro"` 等 |

### 2.3 设计意图

1. **轻量通知**: 仅传递关键变更字段，完整信息通过 `account/read` 获取
2. **可选字段**: 使用 `null` 表示该字段未变更或未知
3. **触发刷新**: 通知的主要目的是触发客户端刷新账户信息

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AccountUpdatedNotification {
  authMode: AuthMode | null;
  planType: PlanType | null;
}
```

### 3.2 依赖类型

**AuthMode** (`../AuthMode`):
```typescript
export type AuthMode = "apikey" | "chatgpt" | "chatgptAuthTokens";
```

**PlanType** (`../PlanType`):
```typescript
export type PlanType = "free" | "go" | "plus" | "pro" | "team" | "business" | "enterprise" | "edu" | "unknown";
```

### 3.3 Rust 源类型

```rust
// common.rs 中注册通知
server_notification_definitions! {
    // ...
    AccountUpdated => "account/updated" (v2::AccountUpdatedNotification),
}

// v2.rs 中定义结构体
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountUpdatedNotification {
    pub auth_mode: Option<AuthMode>,
    pub plan_type: Option<PlanType>,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通知注册（约第 908 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AccountUpdatedNotification.ts` | 生成的 TypeScript 类型 |

### 4.2 类型依赖图

```
AccountUpdatedNotification.ts
  ├── AuthMode.ts (../AuthMode)
  └── PlanType.ts (../PlanType)
```

### 4.3 关联方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `account/read` | Client → Server | 获取完整账户信息 |
| `account/updated` | Server → Client | 账户变更通知（本类型） |
| `account/login/completed` | Server → Client | 登录完成通知 |

### 4.4 触发场景

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  User Action    │     │   App-Server    │     │     Client      │
├─────────────────┤     ├─────────────────┤     ├─────────────────┤
│ Login/Logout    │────►│ Detect Change   │────►│ account/updated │
│ Upgrade Plan    │────►│ Emit Notification│────►│ Refresh UI      │
│ Switch Account  │────►│                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { AuthMode } from "../AuthMode";
import type { PlanType } from "../PlanType";
```

### 5.2 外部系统交互

```
┌─────────────────┐
│   Client App    │
│  (UI Update)    │
└────────┬────────┘
         │ account/updated notification
         ▼
┌─────────────────┐
│   App-Server    │
│  (Event Emit)   │
└────────┬────────┘
         │ Auth/Subscription Events
         ▼
┌─────────────────┐
│  External APIs  │
│ (OpenAI Auth,   │
│  Billing)       │
└─────────────────┘
```

### 5.3 序列化示例

**认证模式变更:**
```json
{
  "method": "account/updated",
  "params": {
    "authMode": "chatgpt",
    "planType": null
  }
}
```

**套餐升级:**
```json
{
  "method": "account/updated",
  "params": {
    "authMode": null,
    "planType": "plus"
  }
}
```

**完全变更:**
```json
{
  "method": "account/updated",
  "params": {
    "authMode": "apikey",
    "planType": "pro"
  }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 信息不完整 | 仅传递部分字段，客户端需额外查询 | 客户端收到通知后调用 `account/read` |
| 重复通知 | 短时间内多次变更可能导致通知风暴 | 服务器端实现防抖 |
| 竞态条件 | 通知与主动查询结果可能不一致 | 以查询结果为准，通知仅作为触发器 |
| 空值歧义 | `null` 可能表示"未变更"或"已清除" | 文档明确语义 |

### 6.2 边界情况

1. **未登录状态**: 两个字段都可能为 `null`
2. **部分变更**: 仅一个字段有值，另一个为 `null`
3. **快速切换**: 用户快速切换账户时的通知顺序
4. **离线恢复**: 客户端离线期间的通知丢失

### 6.3 改进建议

1. **添加变更原因**: 帮助客户端决定如何处理
   ```typescript
   export type AccountUpdatedNotification = { 
     authMode: AuthMode | null,
     planType: PlanType | null,
     reason?: "login" | "logout" | "upgrade" | "downgrade" | "switch";
   };
   ```

2. **添加时间戳**: 便于排序和去重
   ```typescript
   updatedAt: number;  // Unix timestamp
   ```

3. **完整账户信息**: 可选直接包含完整账户信息，减少往返
   ```typescript
   export type AccountUpdatedNotification = { 
     authMode: AuthMode | null,
     planType: PlanType | null,
     account?: Account;  // 可选完整信息
   };
   ```

4. **变更详情**: 对于套餐变更，提供前后对比
   ```typescript
   planChange?: {
     from: PlanType;
     to: PlanType;
     effectiveAt: number;
   };
   ```

### 6.4 测试建议

- 各种字段组合的序列化/反序列化
- 通知触发的时机验证
- 客户端刷新逻辑
- 多设备同步场景
- 离线恢复后的状态一致性
