# ThreadCompactStartResponse.ts 研究文档

## 场景与职责

`ThreadCompactStartResponse` 是 Codex App-Server Protocol v2 API 中 `thread/compact/start` 方法的响应类型。由于压缩启动是异步操作，该响应仅确认操作已启动，不包含压缩结果。

## 功能点目的

### 核心功能

该类型使用 `Record<string, never>` 表示空对象，确认压缩操作已成功启动。

### 设计特点

1. **异步确认**：仅表示压缩操作已启动，不等待完成
2. **空响应模式**：保持与协议其他空响应的一致性
3. **结果通过通知**：实际压缩结果通过通知发送

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadCompactStartResponse = Record<string, never>;
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2871-2874) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartResponse {}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2871-2874): Rust 类型定义

### 下游使用方
- 客户端接收 `thread/compact/start` RPC 响应

### 相关类型
- `ThreadCompactStartParams.ts`: 压缩启动参数

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadCompactStartResponse } from "./v2";

// 启动压缩
const response: ThreadCompactStartResponse = await client.request(
  "thread/compact/start", 
  { threadId: "thread_abc123" }
);

// 响应为空对象
console.log(response); // {}

// 监听压缩完成通知
client.onNotification("thread/compacted", (notification) => {
  console.log("Compaction completed");
});
```

## 风险、边界与改进建议

### 改进建议

1. **添加操作 ID**：返回压缩操作 ID，用于追踪和取消
2. **添加预计时间**：返回预计压缩完成时间
3. **状态查询**：添加压缩状态查询接口

### 注意事项

- 该文件为**自动生成**
- 空响应仅表示启动成功，不代表压缩完成
- 客户端需要通过通知监听压缩完成事件
