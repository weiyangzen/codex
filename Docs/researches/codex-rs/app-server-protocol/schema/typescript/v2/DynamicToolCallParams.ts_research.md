# DynamicToolCallParams.ts 研究文档

## 场景与职责

`DynamicToolCallParams.ts` 定义了动态工具调用请求的参数类型，用于客户端向服务器发起动态工具调用。动态工具是 Codex 的扩展机制，允许在运行时注册和使用自定义工具。

该类型在工具执行、扩展集成、自定义工作流等场景中发挥关键作用。

## 功能点目的

1. **工具标识**: 指定要调用的工具名称
2. **参数传递**: 传递工具执行所需的参数
3. **调用关联**: 通过 `callId` 关联调用请求和响应

## 具体技术实现

### 数据结构定义

```typescript
export type DynamicToolCallParams = { 
  threadId: string, 
  turnId: string, 
  callId: string, 
  tool: string, 
  arguments: JsonValue, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 当前线程 ID，用于上下文关联 |
| `turnId` | `string` | 当前回合 ID，用于定位调用时机 |
| `callId` | `string` | 调用唯一标识，用于匹配响应 |
| `tool` | `string` | 工具名称 |
| `arguments` | `JsonValue` | 工具参数（任意 JSON 值） |

### 使用示例

```typescript
// 调用自定义搜索工具
const params: DynamicToolCallParams = {
  threadId: 'thread-123',
  turnId: 'turn-456',
  callId: 'call-789',
  tool: 'web_search',
  arguments: {
    query: 'Rust programming language',
    limit: 10
  }
};

// 发送调用请求
client.sendRequest('dynamicTool/call', params);
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DynamicToolCallParams {
    pub thread_id: String,
    pub turn_id: String,
    pub call_id: String,
    pub tool: String,
    pub arguments: JsonValue,
}
```

### 服务器请求枚举

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
pub enum ServerRequest {
    // ...
    DynamicToolCall {
        request_id: RequestId,
        params: DynamicToolCallParams,
    },
    // ...
}
```

### 请求处理

**文件**: `codex-rs/app-server/src/outgoing_message.rs`

处理动态工具调用请求的接收和分发。

**文件**: `codex-rs/app-server/src/bespoke_event_handling.rs`

处理动态工具调用的事件转换。

### TUI 应用服务器

**文件**: `codex-rs/tui_app_server/src/app/app_server_requests.rs`

TUI 应用服务器处理动态工具调用请求。

### 测试用例

**文件**: `codex-rs/app-server/tests/suite/v2/dynamic_tools.rs`

动态工具调用的集成测试。

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde_json::Value` (`JsonValue`) | 任意 JSON 值类型 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **动态工具系统**: `codex-rs/app-server/src/dynamic_tools.rs`
- **TUI 客户端**: 发起工具调用请求
- **VS Code 扩展**: 集成自定义工具

## 风险、边界与改进建议

### 已知风险

1. **参数验证**: `arguments` 为任意 JSON，缺乏类型安全
2. **工具不存在**: 调用的工具可能未注册
3. **超时处理**: 长时间运行的工具调用需要超时机制

### 边界情况

1. **空参数**: `arguments` 可能为 `null` 或 `{}`
2. **无效工具名**: 工具名称可能不存在或拼写错误
3. **并发调用**: 同一回合可能有多个并发工具调用

### 改进建议

1. **参数校验**: 增加 JSON Schema 参数校验
2. **工具发现**: 提供工具列表查询接口
3. **进度通知**: 长时间运行的工具支持进度通知
4. **取消机制**: 支持取消正在进行的工具调用
5. **超时配置**: 允许调用时指定超时时间
6. **结果缓存**: 支持工具调用结果缓存

### 扩展示例

```typescript
// 改进后的结构
export type DynamicToolCallParams = { 
  threadId: string, 
  turnId: string, 
  callId: string, 
  tool: string, 
  arguments: JsonValue,
  // 新增字段
  timeoutMs?: number,  // 超时时间
  cacheKey?: string,   // 缓存键
  streaming?: boolean, // 是否流式返回结果
};
```
