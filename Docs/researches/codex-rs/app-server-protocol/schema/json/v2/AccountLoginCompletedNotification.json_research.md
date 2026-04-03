# AccountLoginCompletedNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AccountLoginCompletedNotification` 是 App-Server Protocol v2 中定义的服务器向客户端发送的通知类型，用于告知客户端账户登录流程的完成状态。

**使用场景：**
- 当用户通过 OAuth (ChatGPT) 或 API Key 方式完成登录认证后，服务器发送此通知
- 用于异步通知客户端登录结果，特别是在需要浏览器跳转的 OAuth 流程中
- 客户端通过监听此通知来更新 UI 状态（如从"登录中"切换到"已登录"）

**职责：**
- 传递登录成功或失败的状态
- 在成功时提供登录会话标识 (`loginId`)
- 在失败时提供错误信息 (`error`)

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现登录流程的异步完成通知机制：

1. **状态同步**：将服务器端的登录状态变化同步到客户端
2. **结果传递**：明确告知客户端登录是成功还是失败
3. **错误处理**：在登录失败时提供可展示的错误信息
4. **会话管理**：成功时返回 `loginId` 用于后续会话管理

**字段说明：**
- `success` (boolean, required): 登录是否成功
- `loginId` (string | null): 成功时的登录会话ID
- `error` (string | null): 失败时的错误描述

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountLoginCompletedNotification {
    pub success: bool,
    pub login_id: Option<String>,
    pub error: Option<String>,
}
```

### 协议集成

在 `common.rs` 中注册为服务器通知：

```rust
server_notification_definitions! {
    #[serde(rename = "account/login/completed")]
    #[ts(rename = "account/login/completed")]
    #[strum(serialize = "account/login/completed")]
    AccountLoginCompleted(v2::AccountLoginCompletedNotification),
}
```

### 通知流程

1. 客户端调用 `account/login/start` 方法启动登录
2. 服务器处理登录流程（OAuth 跳转或 API Key 验证）
3. 登录完成后，服务器发送 `account/login/completed` 通知
4. 客户端接收通知并更新状态

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`

### 相关类型
- `LoginAccountParams`: 登录请求参数（v2.rs 第 1568-1601 行）
- `LoginAccountResponse`: 登录响应（v2.rs 第 1603-1623 行）
- `CancelLoginAccountParams/Response`: 取消登录相关类型

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AccountLoginCompletedNotification.json`

### 使用位置
- App-Server 实现中处理登录完成的逻辑
- TUI/CLI 客户端中监听登录状态变化

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `schemars::JsonSchema`: 用于生成 JSON Schema
- `ts_rs::TS`: 用于生成 TypeScript 类型定义
- `serde`: 用于序列化/反序列化

### 外部交互
- **OAuth 流程**: 与 ChatGPT OAuth 服务交互
- **Token 管理**: 与内部 token 存储和管理系统交互
- **客户端 UI**: 通过 WebSocket/SSE 发送通知到客户端

### 相关配置
- 登录相关的配置在 `Config` 类型中定义
- `forced_login_method` 可强制指定登录方式

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **安全性**: `loginId` 是敏感信息，传输过程需要加密
2. **时序问题**: 客户端可能在通知到达前发起其他请求
3. **重复通知**: 网络重连可能导致重复接收登录完成通知

### 边界情况

1. **并发登录**: 多个登录请求同时进行的处理
2. **超时处理**: 登录流程超时后的通知处理
3. **连接中断**: 登录过程中连接中断的恢复机制

### 改进建议

1. **添加时间戳**: 建议添加 `completed_at` 字段用于追踪
2. **会话信息**: 可考虑添加更多会话元数据（如过期时间）
3. **设备信息**: 可考虑添加登录设备信息用于安全审计
4. **重试机制**: 客户端应有机制处理通知丢失的情况

### 测试建议

1. 测试登录成功和失败的各种场景
2. 测试网络中断和重连场景
3. 测试并发登录请求的处理
4. 验证通知的序列化和反序列化正确性
