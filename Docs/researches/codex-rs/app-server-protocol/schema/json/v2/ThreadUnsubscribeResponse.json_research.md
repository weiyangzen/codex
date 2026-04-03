# ThreadUnsubscribeResponse.json 研究文档

## 场景与职责

`ThreadUnsubscribeResponse` 是 Codex App-Server Protocol v2 中定义的 `thread/unsubscribe` 请求的响应类型。当客户端请求取消订阅某个 Thread 后，服务器返回此响应，告知客户端取消订阅操作的结果状态。这是订阅管理生命周期中的关键反馈机制。

典型使用场景：
- 客户端请求取消订阅后接收操作结果
- 根据响应状态更新本地订阅状态
- 处理取消订阅失败的情况
- 确认资源释放完成

## 功能点目的

该响应类型的主要目的是：
1. **操作确认**：向客户端确认取消订阅请求已处理
2. **状态反馈**：告知客户端当前的订阅状态
3. **错误处理**：提供明确的错误状态以便客户端处理
4. **幂等性支持**：多次调用返回一致的状态

### ThreadUnsubscribeStatus 状态说明

| 状态 | 值 | 说明 |
|------|-----|------|
| `NotLoaded` | `"notLoaded"` | Thread 未在服务器上加载 |
| `NotSubscribed` | `"notSubscribed"` | Thread 已加载但客户端未订阅 |
| `Unsubscribed` | `"unsubscribed"` | 成功取消订阅 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ThreadUnsubscribeStatus": {
      "enum": ["notLoaded", "notSubscribed", "unsubscribed"],
      "type": "string"
    }
  },
  "properties": {
    "status": { "$ref": "#/definitions/ThreadUnsubscribeStatus" }
  },
  "required": ["status"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 2726-2740）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnsubscribeResponse {
    pub status: ThreadUnsubscribeStatus,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ThreadUnsubscribeStatus {
    NotLoaded,
    NotSubscribed,
    Unsubscribed,
}
```

### 状态转换图

```
                    thread/unsubscribe
    +-------------------> (请求)
    |
    v
+------------------+
|   NotLoaded      | <--- Thread ID 不存在
| (Thread 未加载)   |
+------------------+

+------------------+
|  NotSubscribed   | <--- Thread 已加载但未订阅
| (未订阅)          |
+------------------+

+------------------+
|   Unsubscribed   | <--- 成功取消订阅
| (已取消订阅)      |
+------------------+
```

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
client_request_definitions! {
    ThreadUnsubscribe => "thread/unsubscribe" {
        params: v2::ThreadUnsubscribeParams,
        response: v2::ThreadUnsubscribeResponse,
    },
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadUnsubscribeResponse.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 2726-2740） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（行 233-236） |

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `thread/unsubscribe` 请求
- 检查 Thread 是否存在（返回 `NotLoaded`）
- 检查客户端是否订阅了该 Thread（返回 `NotSubscribed`）
- 执行取消订阅操作（返回 `Unsubscribed`）

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_unsubscribe.rs` | 取消订阅功能测试 |

## 依赖与外部交互

### 上游依赖

1. **订阅管理服务**：管理客户端与 Thread 的订阅关系
2. **Thread 管理服务**：验证 Thread 是否存在和加载状态

### 下游消费者

1. **客户端应用**：根据响应状态更新本地订阅状态
2. **UI 组件**：可能根据状态显示不同的提示信息

### 相关类型

| 类型 | 说明 |
|------|------|
| `ThreadUnsubscribeParams` | 取消订阅请求参数 |
| `ThreadUnsubscribeStatus` | 状态枚举类型 |

## 风险、边界与改进建议

### 潜在风险

1. **状态竞争**：客户端和服务器之间的订阅状态可能短暂不一致
2. **通知延迟**：取消订阅后可能仍收到已排队的通知
3. **连接问题**：网络问题可能导致响应丢失

### 边界情况

1. **重复取消订阅**：多次取消订阅同一 Thread 应返回 `Unsubscribed`（幂等）
2. **并发取消订阅**：多个客户端同时取消订阅同一 Thread
3. **连接断开**：连接断开时服务器应自动清理订阅

### 改进建议

1. **添加时间戳**：记录取消订阅操作的时间
2. **订阅计数**：返回当前 Thread 的订阅者数量
3. **强制取消订阅**：支持强制取消所有客户端的订阅（管理员功能）
4. **订阅历史**：记录订阅/取消订阅的历史日志

### 客户端处理示例

```typescript
// 示例：客户端处理 ThreadUnsubscribeResponse
async function handleUnsubscribeResponse(
    threadId: string, 
    response: ThreadUnsubscribeResponse
): Promise<void> {
    switch (response.status) {
        case 'unsubscribed':
            // 成功取消订阅
            console.log(`已取消订阅 Thread: ${threadId}`);
            removeFromSubscribedThreads(threadId);
            updateUIState(threadId, 'unsubscribed');
            break;
            
        case 'notSubscribed':
            // 原本就没有订阅
            console.log(`Thread ${threadId} 原本就没有订阅`);
            // 同步本地状态
            removeFromSubscribedThreads(threadId);
            break;
            
        case 'notLoaded':
            // Thread 未加载
            console.warn(`Thread ${threadId} 未加载`);
            // 可能需要重新加载 Thread 列表
            await refreshThreadList();
            break;
            
        default:
            // 未知状态
            console.error('未知的取消订阅状态:', response.status);
    }
}
```

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 状态值为 camelCase（`notLoaded`, `notSubscribed`, `unsubscribed`）
- 与 v1 API 不兼容
