# AccountLoginCompletedNotification.ts 研究文档

## 1. 场景与职责

`AccountLoginCompletedNotification` 是服务器向客户端推送的**异步通知类型**，用于告知 OAuth 登录流程的最终结果。

### 使用场景
- **OAuth 登录完成**: 当用户通过浏览器完成 ChatGPT OAuth 授权后，服务器通过 WebSocket/长连接推送此通知
- **登录状态同步**: 在多设备/多窗口场景下，通知所有连接的客户端更新登录状态
- **登录错误处理**: 当登录流程失败（用户取消、授权超时、网络错误）时传递错误信息

### 职责
- 传递登录操作的唯一标识（`loginId`）
- 明确指示登录成功或失败（`success` 布尔值）
- 在失败时提供可读的的错误信息（`error` 字段）

---

## 2. 功能点目的

### 2.1 异步通知设计

```typescript
export type AccountLoginCompletedNotification = { 
  loginId: string | null,   // 登录请求的唯一标识
  success: boolean,         // 登录是否成功
  error: string | null,     // 失败时的错误信息
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `loginId` | `string \| null` | 关联到原始登录请求的标识符，用于匹配请求-响应 |
| `success` | `boolean` | `true` 表示登录成功，`false` 表示失败 |
| `error` | `string \| null` | 失败时的可读错误信息，成功时为 `null` |

### 2.3 设计意图

1. **请求-响应关联**: 通过 `loginId` 将异步通知与原始登录请求关联
2. **明确的成功/失败状态**: 避免仅通过 `error` 是否存在来判断状态
3. **可扩展性**: 未来可添加 `account` 字段直接传递账户信息，减少额外查询

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AccountLoginCompletedNotification {
  loginId: string | null;  // UUID 格式的字符串
  success: boolean;        // 成功标志
  error: string | null;    // 错误描述
}
```

### 3.2 Rust 源类型

在 `common.rs` 中通过宏定义（约第 936-939 行）：

```rust
server_notification_definitions! {
    // ...
    #[serde(rename = "account/login/completed")]
    #[ts(rename = "account/login/completed")]
    #[strum(serialize = "account/login/completed")]
    AccountLoginCompleted(v2::AccountLoginCompletedNotification),
}
```

实际结构体定义在 `v2.rs`：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountLoginCompletedNotification {
    pub login_id: String,
    pub success: bool,
    pub error: Option<String>,
}
```

### 3.3 通知方法名

- **Wire 格式**: `account/login/completed`
- **TypeScript 类型**: `AccountLoginCompletedNotification`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通知注册（约第 936-939 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AccountLoginCompletedNotification.ts` | 生成的 TypeScript 类型 |

### 4.2 相关类型

```
AccountLoginCompletedNotification.ts
  └── ServerNotification (common.ts)
```

### 4.3 协议流程

```
┌─────────┐                    ┌─────────────┐                    ┌──────────┐
│ Client  │ ──account/login/start──►│ App-Server  │───OAuth URL──►│ Browser  │
│         │◄────LoginAccountResponse─┤             │                │          │
│         │                    │             │◄──Auth Callback──┤          │
│         │◄──account/login/completed──┤             │                │          │
└─────────┘                    └─────────────┘                    └──────────┘
```

### 4.4 关联方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `account/login/start` | Client → Server | 启动登录流程，返回 `loginId` 和 `authUrl` |
| `account/login/cancel` | Client → Server | 取消进行中的登录 |
| `account/login/completed` | Server → Client | 登录完成通知（本类型） |

---

## 5. 依赖与外部交互

### 5.1 类型依赖

此类型无外部类型依赖，是独立的结构体。

### 5.2 外部系统交互

```
┌─────────────────┐
│   Client App    │
│  (TypeScript)   │
└────────┬────────┘
         │ WebSocket/SSE
         ▼
┌─────────────────┐
│   App-Server    │
│    (Rust)       │
└────────┬────────┘
         │ OAuth 2.0 / OIDC
         ▼
┌─────────────────┐
│  ChatGPT Auth   │
│   (OpenAI)      │
└─────────────────┘
```

### 5.3 序列化示例

**成功场景:**
```json
{
  "method": "account/login/completed",
  "params": {
    "loginId": "550e8400-e29b-41d4-a716-446655440000",
    "success": true,
    "error": null
  }
}
```

**失败场景:**
```json
{
  "method": "account/login/completed",
  "params": {
    "loginId": "550e8400-e29b-41d4-a716-446655440000",
    "success": false,
    "error": "User denied authorization"
  }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 通知丢失 | WebSocket 断开可能导致通知丢失 | 客户端在重连后主动查询登录状态 |
| 重复通知 | 网络重连可能导致重复推送 | 客户端根据 `loginId` 去重 |
| 时序问题 | 通知可能在客户端处理响应前到达 | 确保 `loginId` 匹配机制健壮 |
| 空 loginId | 某些异常情况下 `loginId` 可能为 `null` | 客户端处理 `null` 情况 |

### 6.2 边界情况

1. **超时处理**: 登录流程可能因用户未操作而超时，此时 `error` 应包含超时信息
2. **并发登录**: 多个登录请求同时进行时，需确保 `loginId` 正确匹配
3. **已登录状态**: 用户已登录时再次登录，应返回相应错误
4. **网络中断**: OAuth 回调成功但通知发送失败，客户端需能恢复状态

### 6.3 改进建议

1. **添加账户信息**: 成功时直接包含 `Account` 信息，减少额外查询
   ```typescript
   export type AccountLoginCompletedNotification = { 
     loginId: string | null,
     success: boolean,
     error: string | null,
     account?: Account,  // 成功时可选返回
   };
   ```

2. **错误码标准化**: 使用枚举替代字符串错误，便于客户端国际化
   ```typescript
   export type LoginErrorCode = 
     | "user_cancelled" 
     | "timeout" 
     | "network_error" 
     | "server_error";
   ```

3. **添加时间戳**: 便于调试和过期检测
   ```typescript
   completedAt: number;  // Unix timestamp
   ```

4. **重试机制**: 服务器端实现通知重试，确保至少一次送达

### 6.4 测试建议

- 成功登录的通知接收
- 失败登录的错误处理
- `loginId` 匹配逻辑
- 网络断开重连后的状态恢复
- 并发登录请求的处理
- 通知去重机制
