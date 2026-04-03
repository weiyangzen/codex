# Account.ts 研究文档

## 1. 场景与职责

`Account` 类型定义了 Codex App-Server Protocol v2 中的账户信息表示，用于在客户端和服务器之间传递用户身份认证和账户状态信息。

### 使用场景
- **账户信息查询**: 当客户端调用 `account/read` 方法获取当前登录账户信息时，服务器返回此类型的数据
- **登录流程**: 在 OAuth 登录流程完成后，服务器通过通知将账户信息推送给客户端
- **身份验证状态同步**: 在会话期间，当账户状态发生变化时，用于更新客户端的账户视图

### 职责
- 统一表示不同类型的账户身份（API Key 或 ChatGPT OAuth）
- 提供账户类型标签（`type` 字段）以支持类型区分和序列化
- 封装账户相关的元数据（如邮箱、套餐类型等）

---

## 2. 功能点目的

### 2.1 账户类型抽象

```typescript
export type Account = 
  | { "type": "apiKey" } 
  | { "type": "chatgpt", email: string, planType: PlanType };
```

该类型是一个**带标签的联合类型（Tagged Union）**，支持两种账户形态：

| 类型 | 用途 | 字段 |
|------|------|------|
| `apiKey` | 开发者使用 OpenAI API Key 直接认证 | 无额外字段 |
| `chatgpt` | 终端用户通过 ChatGPT OAuth 登录 | `email`: 用户邮箱<br>`planType`: 套餐类型 |

### 2.2 设计意图

1. **类型安全**: 使用 TypeScript 的 Discriminated Union 模式，通过 `type` 字段进行类型收窄
2. **向后兼容**: 新账户类型可以无缝添加为新的联合成员
3. **序列化友好**: 与 Rust 的枚举类型（`#[serde(tag = "type")]`）完美映射

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
// 简化表示
interface ApiKeyAccount {
  type: "apiKey";
}

interface ChatgptAccount {
  type: "chatgpt";
  email: string;        // 用户邮箱地址
  planType: PlanType;   // 套餐类型枚举
}

type Account = ApiKeyAccount | ChatgptAccount;
```

### 3.2 Rust 源类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum Account {
    #[serde(rename = "apiKey", rename_all = "camelCase")]
    #[ts(rename = "apiKey", rename_all = "camelCase")]
    ApiKey {},

    #[serde(rename = "chatgpt", rename_all = "camelCase")]
    #[ts(rename = "chatgpt", rename_all = "camelCase")]
    Chatgpt { email: String, plan_type: PlanType },
}
```

### 3.3 关键注解说明

| 注解 | 作用 |
|------|------|
| `#[serde(tag = "type")]` | 使用 `"type"` 字段作为枚举变体的标签 |
| `#[serde(rename_all = "camelCase")]` | 字段序列化为 camelCase |
| `#[ts(tag = "type")]` | TypeScript 生成时使用 tagged union |
| `#[ts(export_to = "v2/")]` | 输出到 `v2/` 目录 |

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 源类型定义（约第 1554-1566 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/Account.ts` | 生成的 TypeScript 类型 |

### 4.2 相关类型依赖

```
Account.ts
  └── PlanType.ts (../PlanType)
```

### 4.3 使用位置

| 文件/模块 | 使用方式 |
|-----------|----------|
| `GetAccountResponse` | `account: Option<Account>` 字段 |
| `AccountUpdatedNotification` | 通知推送账户变更 |
| 客户端 UI | 显示账户信息、套餐状态 |

### 4.4 协议方法关联

- **`account/read`**: 返回 `GetAccountResponse`，其中包含 `Account` 信息
- **`account/login/start`**: 登录响应 `LoginAccountResponse` 可能包含账户信息

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { PlanType } from "../PlanType";
```

`PlanType` 定义：
```typescript
export type PlanType = "free" | "go" | "plus" | "pro" | "team" | "business" | "enterprise" | "edu" | "unknown";
```

### 5.2 外部系统交互

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Client    │◄────►│  App-Server  │◄────►│  Auth API   │
│  (Account)  │      │  (Account)   │      │ (OAuth/Key) │
└─────────────┘      └──────────────┘      └─────────────┘
```

### 5.3 序列化格式

**API Key 账户:**
```json
{
  "type": "apiKey"
}
```

**ChatGPT 账户:**
```json
{
  "type": "chatgpt",
  "email": "user@example.com",
  "planType": "plus"
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 类型扩展 | 新增账户类型需要修改联合类型 | 使用开放接口模式预留扩展点 |
| 空对象模式 | `ApiKey` 使用空对象 `{}` 可能导致序列化歧义 | 确保 serde 配置正确处理空对象 |
| 套餐类型同步 | `PlanType` 需要与后端服务保持一致 | 建立类型变更通知机制 |

### 6.2 边界情况

1. **未登录状态**: `GetAccountResponse.account` 可能为 `null`
2. **套餐类型未知**: `planType` 可能为 `"unknown"`
3. **邮箱缺失**: 某些 ChatGPT 账户可能无法获取邮箱（理论上不应发生）

### 6.3 改进建议

1. **类型收窄辅助函数**
   ```typescript
   export function isChatgptAccount(account: Account): account is { type: "chatgpt"; email: string; planType: PlanType } {
     return account.type === "chatgpt";
   }
   ```

2. **空账户处理**: 考虑添加 `Anonymous` 变体表示未登录状态，而非使用 `null`

3. **元数据扩展**: 为未来扩展预留字段，如 `createdAt`, `lastLoginAt` 等

4. **类型文档**: 添加 JSDoc 注释说明各变体的使用场景

### 6.4 测试建议

- 验证两种变体的序列化/反序列化
- 测试类型收窄逻辑
- 验证与 Rust 端的互操作性
- 测试 `PlanType` 枚举的完整性
