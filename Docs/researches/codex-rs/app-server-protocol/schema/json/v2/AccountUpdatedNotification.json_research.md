# AccountUpdatedNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AccountUpdatedNotification` 是服务器向客户端发送的通知，用于告知客户端账户信息已发生变化。

**使用场景：**
- 用户切换认证方式（API Key ↔ ChatGPT OAuth）
- 用户登录或登出后
- 账户套餐类型发生变化时
- 外部认证令牌刷新后

**职责：**
- 实时同步账户认证模式 (`authMode`)
- 同步账户套餐类型 (`planType`)
- 触发客户端重新获取账户详情
- 驱动 UI 更新账户相关展示

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现账户状态的实时同步：

1. **认证状态同步**: 告知客户端当前使用的认证方式
2. **套餐信息同步**: 通知套餐类型变化（升级/降级）
3. **触发刷新**: 提示客户端重新获取完整账户信息
4. **UI 一致性**: 确保多设备/多窗口间账户状态一致

**字段说明：**
- `authMode` (`AuthMode` | null): 认证模式
  - `apikey`: OpenAI API Key 认证
  - `chatgpt`: ChatGPT OAuth 认证（Codex 管理）
  - `chatgptAuthTokens`: 外部管理的 ChatGPT 令牌（OpenAI 内部使用）
- `planType` (`PlanType` | null): 账户套餐类型
  - `free`, `go`, `plus`, `pro`, `team`, `business`, `enterprise`, `edu`, `unknown`

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountUpdatedNotification {
    pub auth_mode: Option<AuthMode>,
    pub plan_type: Option<PlanType>,
}

// AuthMode 定义在 common.rs
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
pub enum AuthMode {
    ApiKey,
    Chatgpt,
    #[serde(rename = "chatgptAuthTokens")]
    #[ts(rename = "chatgptAuthTokens")]
    #[strum(serialize = "chatgptAuthTokens")]
    ChatgptAuthTokens,
}

// PlanType 来自 codex_protocol::account
pub enum PlanType {
    Free, Go, Plus, Pro, Team, Business, Enterprise, Edu, Unknown
}
```

### 协议集成

在 `common.rs` 中注册：

```rust
server_notification_definitions! {
    AccountUpdated => "account/updated" (v2::AccountUpdatedNotification),
}
```

### 通知触发时机

1. 登录/登出操作完成后
2. 切换认证方式后
3. 账户套餐变更后
4. 外部令牌刷新后

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **通知定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- **AuthMode 定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (第 28-43 行)
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (第 874-941 行)

### 相关类型
- `GetAccountResponse`: 获取账户详情的响应
- `GetAccountParams`: 获取账户详情的参数
- `Account` 联合类型: `ApiKey` | `Chatgpt`

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AccountUpdatedNotification.json`

### 相关 API 方法
- `account/read`: 获取账户信息
- `account/login/start`: 开始登录
- `account/logout`: 登出

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `AuthMode`: 定义在 `common.rs` 的认证模式枚举
- `PlanType`: 来自 `codex_protocol::account`
- `strum_macros::Display`: 用于枚举的字符串表示

### 外部交互
- **认证系统**: OpenAI API Key 验证、ChatGPT OAuth
- **账户系统**: 获取套餐类型和账户元数据
- **客户端 UI**: 通过 WebSocket/SSE 推送通知

### 相关配置
- `forced_login_method`: 强制登录方式配置
- `config.model_provider`: 模型提供商配置

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **信息泄露**: 通知中包含敏感账户信息，需确保传输安全
2. **状态不一致**: 通知丢失可能导致客户端状态滞后
3. **竞态条件**: 快速连续的状态变更可能导致通知顺序问题

### 边界情况

1. **空值处理**: `authMode` 和 `planType` 都可能为 null
2. **未知套餐**: `planType: unknown` 的处理
3. **内部模式**: `chatgptAuthTokens` 模式仅限 OpenAI 内部使用
4. **多设备同步**: 同一账户多设备登录时的状态同步

### 改进建议

1. **添加时间戳**: 建议添加 `updated_at` 字段用于追踪变更时间
2. **变更原因**: 可添加 `reason` 字段说明变更原因（如"用户升级套餐"）
3. **完整信息**: 可考虑直接包含完整账户信息，避免客户端二次请求
4. **会话信息**: 可添加当前会话标识用于多会话管理

### 测试建议

1. 测试三种认证模式的通知
2. 测试各种套餐类型的通知
3. 测试字段为 null 的情况
4. 测试快速连续变更的场景
5. 验证多设备同步行为

### 客户端实现建议

1. 收到通知后应调用 `account/read` 获取完整信息
2. 实现本地状态缓存和对比逻辑
3. 认证模式变化时可能需要重新初始化某些功能
4. 套餐类型变化时可展示升级/降级提示
