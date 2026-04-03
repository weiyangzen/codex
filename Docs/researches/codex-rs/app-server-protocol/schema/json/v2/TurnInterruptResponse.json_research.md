# TurnInterruptResponse.json 研究文档

## 场景与职责

`TurnInterruptResponse` 是 Codex App-Server Protocol v2 中定义的 `turn/interrupt` 请求的响应类型。当客户端请求中断正在进行的 Turn 后，服务器返回此响应，确认中断请求已被接收。这是一个空对象响应，表示请求已被接受，实际的中断结果通过 `TurnCompletedNotification` 异步通知。

典型使用场景：
- 客户端发送中断请求后接收确认
- 确认服务器已收到中断指令
- 作为中断流程的第一步确认

## 功能点目的

该响应类型的主要目的是：
1. **请求确认**：确认服务器已收到中断请求
2. **异步处理**：表示中断将在后台异步执行
3. **错误隔离**：区分请求接收错误和中断执行错误
4. **协议完整性**：提供完整的请求-响应协议模式

### 响应语义

```rust
TurnInterruptResponse {}
```

空对象表示：
- 请求格式正确
- Thread 和 Turn 存在
- 中断指令已传递给核心引擎
- 客户端应等待 `TurnCompletedNotification` 获取最终结果

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TurnInterruptResponse",
  "type": "object"
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 3967-3970）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnInterruptResponse {}
```

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
client_request_definitions! {
    TurnInterrupt => "turn/interrupt" {
        params: v2::TurnInterruptParams,
        response: v2::TurnInterruptResponse,
    },
    // ...
}
```

### 完整中断流程

```
Client -> Server: turn/interrupt (TurnInterruptParams)
Server -> Client: TurnInterruptResponse {} (确认接收)

... (服务器处理中断) ...

Server -> Client: TurnCompletedNotification {
    threadId: "...",
    turn: {
        id: "...",
        status: "interrupted",
        items: [],
        error: null
    }
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/TurnInterruptResponse.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 3967-3970） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（行 360-363） |

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 验证 `TurnInterruptParams`
- 调用核心引擎的中断方法
- 返回 `TurnInterruptResponse`（空对象）
- 异步处理中断并发送 `TurnCompletedNotification`

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs` | Turn 中断功能测试 |

## 依赖与外部交互

### 上游依赖

1. **Turn 管理服务**：验证 Turn 是否存在且可中断
2. **核心 Codex 引擎**：执行中断操作

### 下游消费者

1. **客户端应用**：接收确认并等待最终通知
2. **通知系统**：发送 `TurnCompletedNotification`

### 相关类型

| 类型 | 说明 |
|------|------|
| `TurnInterruptParams` | 中断请求参数 |
| `TurnCompletedNotification` | 中断完成通知 |
| `TurnStatus::Interrupted` | 中断状态 |

## 风险、边界与改进建议

### 潜在风险

1. **响应与通知顺序**：响应可能在通知之后到达（网络延迟）
2. **空响应语义**：空对象可能让客户端困惑
3. **错误延迟**：某些错误可能只在通知中体现

### 边界情况

1. **Turn 已完成**：如果 Turn 在请求到达前已完成，仍返回空响应
2. **Turn 不存在**：返回错误响应（非空）
3. **重复中断**：多次中断返回相同的空响应

### 改进建议

1. **添加请求 ID**：在响应中包含请求 ID 以便关联通知
2. **添加时间戳**：记录请求接收时间
3. **预期等待时间**：估计中断完成所需时间
4. **状态指示**：返回当前 Turn 状态的快照

### 设计考虑

#### 为什么选择空对象响应？

1. **异步处理**：中断是异步操作，无法立即返回结果
2. **简化协议**：避免在响应和通知中重复信息
3. **错误分离**：请求错误立即返回，执行错误通过通知返回

#### 替代设计方案

```rust
// 方案 A：同步等待结果（不推荐，可能超时）
pub struct TurnInterruptResponse {
    pub success: bool,
    pub turn: Turn,
}

// 方案 B：包含请求 ID
pub struct TurnInterruptResponse {
    pub request_id: String,
}

// 方案 C：当前方案（空对象）
pub struct TurnInterruptResponse {}
```

### 客户端处理示例

```typescript
// 示例：客户端处理 TurnInterruptResponse
async function interruptTurn(threadId: string, turnId: string): Promise<void> {
    // 发送中断请求
    const response = await sendRequest('turn/interrupt', { threadId, turnId });
    
    // 验证响应（虽然是空对象，但可以验证结构）
    if (response !== undefined && Object.keys(response).length !== 0) {
        console.warn('意外的响应内容:', response);
    }
    
    console.log('中断请求已发送，等待完成通知...');
    
    // 设置超时
    const timeout = setTimeout(() => {
        console.warn('中断操作超时');
        showTimeoutWarning();
    }, 30000);
    
    // 等待完成通知
    try {
        const notification = await waitForNotification('turn/completed',
            n => n.turnId === turnId,
            30000
        );
        
        clearTimeout(timeout);
        
        if (notification.turn.status === 'interrupted') {
            console.log('Turn 已成功中断');
        } else {
            console.warn('Turn 未按预期中断:', notification.turn.status);
        }
    } catch (error) {
        clearTimeout(timeout);
        throw error;
    }
}
```

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 响应为空对象 `{}`
- 与 v1 API 不兼容
