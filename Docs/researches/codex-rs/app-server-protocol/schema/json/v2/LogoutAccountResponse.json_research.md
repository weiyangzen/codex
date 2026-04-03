# LogoutAccountResponse.json 研究文档

## 场景与职责

`LogoutAccountResponse` 是 Codex App-Server Protocol v2 中账户登出流程的响应类型，用于 `account/logout` 方法。这是一个空响应类型，表示登出操作成功完成，无需返回额外数据。

## 功能点目的

1. **简单确认**：作为 RPC 方法的响应占位符，确认登出操作已执行
2. **协议一致性**：保持请求-响应模式的完整性，即使无实际数据返回
3. **未来扩展**：空结构体为未来可能的扩展预留空间（如登出详情、会话清理状态等）

## 具体技术实现

### 数据结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct LogoutAccountResponse {}
```

### JSON Schema 特征

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "LogoutAccountResponse",
  "type": "object"
}
```

- 无 `properties` 定义
- 无 `required` 字段
- 接受任何空对象 `{}` 或仅包含额外字段的对象

### 协议映射

- **ClientRequest**: `LogoutAccount => "account/logout"`
- **请求参数**: `Option<()>`（空参数，可省略）
- **响应类型**: `LogoutAccountResponse`

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 1651)

### 协议注册
- `codex-rs/app-server-protocol/src/protocol/common.rs` (line 441-443):
```rust
LogoutAccount => "account/logout" {
    params: #[ts(type = "undefined")] #[serde(skip_serializing_if = "Option::is_none")] Option<()>,
    response: v2::LogoutAccountResponse,
}
```

### 使用位置
- `codex-rs/app-server/src/codex_message_processor.rs`：处理登出请求
- `codex-rs/app-server/tests/suite/v2/account.rs`：账户相关测试

## 依赖与外部交互

### 上游依赖
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `serde`：序列化/反序列化

### 下游消费者
- App-Server 客户端（TUI、VS Code 扩展等）

### 登出流程
1. 客户端发送 `LogoutAccount` 请求（无参数或空参数）
2. 服务器执行登出逻辑（清理认证状态、令牌等）
3. 服务器返回 `LogoutAccountResponse`（空对象）
4. 客户端确认登出完成

## 风险、边界与改进建议

### 风险点
1. **无错误详情**：当前设计无法携带登出失败的具体原因
2. **状态同步**：登出后客户端和服务器的状态同步依赖于后续通知或重新初始化

### 边界情况
1. **幂等性**：多次调用登出应该产生相同效果
2. **并发登出**：需要处理并发登出请求的场景

### 改进建议
1. **添加状态字段**：考虑添加 `success` 或 `status` 字段明确表示操作结果
2. **会话清理详情**：如有需要，可添加清理的会话数量、令牌失效状态等信息
3. **错误信息**：考虑在失败场景下返回错误详情（虽然当前为空结构体，但可通过 Result 类型处理）
