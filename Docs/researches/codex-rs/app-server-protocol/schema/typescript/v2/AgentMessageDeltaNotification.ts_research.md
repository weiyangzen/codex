# AgentMessageDeltaNotification.ts 研究文档

## 1. 场景与职责

`AgentMessageDeltaNotification` 是服务器向客户端推送的**流式消息增量通知**，用于实时传输 AI Agent 生成的消息内容。这是实现打字机效果（逐字显示）的关键协议类型。

### 使用场景
- **实时消息流**: AI 生成回复时，逐字/逐段推送给客户端显示
- **长文本生成**: 大段内容分块传输，减少等待时间
- **多轮对话**: 在复杂对话中持续更新消息内容
- **协作编辑**: 多个用户同时查看时保持内容同步

### 职责
- 标识消息所属的线程（`threadId`）
- 标识消息所属的回合（`turnId`）
- 标识具体的消息项（`itemId`）
- 传递消息内容的增量（`delta`）

---

## 2. 功能点目的

### 2.1 流式内容传输

```typescript
export type AgentMessageDeltaNotification = { 
  threadId: string,   // 线程唯一标识
  turnId: string,     // 回合唯一标识
  itemId: string,     // 消息项唯一标识
  delta: string,      // 内容增量（UTF-8 文本）
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 消息所属的线程 ID |
| `turnId` | `string` | 消息所属的回合 ID（一轮对话） |
| `itemId` | `string` | 具体消息项的唯一标识 |
| `delta` | `string` | 新增的内容片段（可能是一个字符、单词或句子） |

### 2.3 设计意图

1. **增量更新**: 只传输新增内容，而非完整消息，减少带宽
2. **精确定位**: 三级 ID（thread → turn → item）确保内容更新到正确位置
3. **实时体验**: 支持低延迟的流式传输，提供流畅的用户体验
4. **可恢复性**: 通过 ID 可以在断开重连后恢复正确的消息状态

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AgentMessageDeltaNotification {
  threadId: string;  // UUID 格式
  turnId: string;    // UUID 格式
  itemId: string;    // UUID 格式
  delta: string;     // UTF-8 编码的文本增量
}
```

### 3.2 Rust 源类型

```rust
// common.rs 中注册通知
server_notification_definitions! {
    // ...
    AgentMessageDelta => "item/agentMessage/delta" (v2::AgentMessageDeltaNotification),
}

// v2.rs 中定义结构体（由 codex_protocol 导入）
// 实际定义在 codex_protocol::items 模块
```

### 3.3 通知方法名

- **Wire 格式**: `item/agentMessage/delta`
- **TypeScript 类型**: `AgentMessageDeltaNotification`

### 3.4 消息组装逻辑

```typescript
// 客户端消息组装示例
class MessageAssembler {
  private messages: Map<string, string> = new Map();

  handleDelta(notification: AgentMessageDeltaNotification): void {
    const { itemId, delta } = notification;
    const current = this.messages.get(itemId) || "";
    this.messages.set(itemId, current + delta);
    this.updateUI(itemId, this.messages.get(itemId)!);
  }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通知注册（约第 897 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AgentMessageDeltaNotification.ts` | 生成的 TypeScript 类型 |
| `codex-rs/protocol/src/items.rs` | 核心消息类型定义 |

### 4.2 类型依赖

此类型无外部类型依赖。

### 4.3 关联通知

| 通知 | 说明 |
|------|------|
| `item/started` | 消息项开始生成 |
| `item/agentMessage/delta` | 消息内容增量（本类型） |
| `item/completed` | 消息项生成完成 |
| `item/reasoning/textDelta` | 推理过程的增量 |
| `item/reasoning/summaryTextDelta` | 推理摘要的增量 |

### 4.4 流式传输流程

```
┌─────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────┐
│  OpenAI │────►│  App-Server │────►│   Client    │────►│   UI    │
│   API   │     │  (Buffer &  │     │  (Assemble  │     │ (Render │
│ (SSE)   │     │   Forward)  │     │   Message)  │     │  Text)  │
└─────────┘     └─────────────┘     └─────────────┘     └─────────┘
     │                  │                  │                  │
     │ "Hello"          │ delta: "Hello"   │ append("Hello")  │
     │----------------->│----------------->│----------------->│
     │                  │                  │                  │
     │ " world"         │ delta: " world"  │ append(" world") │
     │----------------->│----------------->│----------------->│
     │                  │                  │                  │
     │ "!"              │ delta: "!"       │ append("!")      │
     │----------------->│----------------->│----------------->│
```

---

## 5. 依赖与外部交互

### 5.1 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Message Streaming Flow                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │  LLM API    │───►│  App-Server │───►│  WebSocket/SSE  │ │
│  │  (OpenAI)   │    │  (Protocol  │    │  Connection     │ │
│  │             │    │   Gateway)  │    │                 │ │
│  └─────────────┘    └──────┬──────┘    └────────┬────────┘ │
│                            │                     │          │
│                            ▼                     ▼          │
│                   ┌─────────────────────────────────────┐  │
│                   │  AgentMessageDeltaNotification      │  │
│                   │  - threadId, turnId, itemId         │  │
│                   │  - delta (content chunk)            │  │
│                   └─────────────────────────────────────┘  │
│                            │                                │
│                            ▼                                │
│                   ┌─────────────────┐                       │
│                   │   Client App    │                       │
│                   │  (Message Assembly & UI Update)         │
│                   └─────────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 序列化示例

**单字增量:**
```json
{
  "method": "item/agentMessage/delta",
  "params": {
    "threadId": "thread-550e8400-e29b-41d4-a716",
    "turnId": "turn-446655440000-1111-2222",
    "itemId": "item-a1b2c3d4-e5f6-7890",
    "delta": "H"
  }
}
```

**单词增量:**
```json
{
  "method": "item/agentMessage/delta",
  "params": {
    "threadId": "thread-550e8400-e29b-41d4-a716",
    "turnId": "turn-446655440000-1111-2222",
    "itemId": "item-a1b2c3d4-e5f6-7890",
    "delta": "ello "
  }
}
```

**完整句子:**
```json
{
  "method": "item/agentMessage/delta",
  "params": {
    "threadId": "thread-550e8400-e29b-41d4-a716",
    "turnId": "turn-446655440000-1111-2222",
    "itemId": "item-a1b2c3d4-e5f6-7890",
    "delta": "world!"
  }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 乱序到达 | 网络延迟导致增量乱序 | 使用序列号或依赖 TCP 有序性 |
| 消息丢失 | 网络中断导致部分增量丢失 | 客户端检测到不连续时请求重传 |
| 内存膨胀 | 长消息累积大量增量 | 定期同步完整消息状态 |
| 编码问题 | 多字节字符被分割 | 确保增量在字符边界分割 |
| 高频更新 | 过多增量导致 UI 卡顿 | 客户端实现节流/防抖 |

### 6.2 边界情况

1. **空增量**: `delta: ""` 可能表示心跳或保持连接
2. **超大增量**: 单个增量可能包含大量文本
3. **多字节字符**: Unicode 字符（如 emoji）可能被分割
4. **并发消息**: 同一回合可能有多个消息项同时生成
5. **重连恢复**: 客户端重连后需要恢复正确的消息状态

### 6.3 改进建议

1. **添加序列号**: 支持乱序检测和重传
   ```typescript
   export type AgentMessageDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     delta: string;
     seq: number;  // 序列号，用于检测丢失
   };
   ```

2. **添加完成标记**: 明确标识最后一个增量
   ```typescript
   export type AgentMessageDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     delta: string;
     isFinal: boolean;  // 是否为最后一个增量
   };
   ```

3. **支持二进制内容**: 对于特殊内容类型
   ```typescript
   export type AgentMessageDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     delta: string;
     encoding?: "utf-8" | "base64";  // 内容编码
   };
   ```

4. **添加时间戳**: 用于性能分析和延迟监控
   ```typescript
   generatedAt: number;  // 服务器生成时间戳
   ```

5. **批量增量**: 减少高频小增量的开销
   ```typescript
   export type AgentMessageDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     deltas: string[];  // 批量增量
   };
   ```

### 6.4 性能优化建议

1. **客户端节流**: 使用 `requestAnimationFrame` 批量更新 UI
2. **虚拟滚动**: 长消息使用虚拟列表渲染
3. **增量合并**: 在服务器端合并短时间内的小增量
4. **压缩传输**: 对大量文本启用 WebSocket 压缩

### 6.5 测试建议

- 各种增量大小的传输
- Unicode 字符（包括 emoji）的正确处理
- 网络中断和重连后的消息恢复
- 高频增量的客户端性能
- 多并发消息的正确路由
- 大消息（如代码块）的完整性和顺序
