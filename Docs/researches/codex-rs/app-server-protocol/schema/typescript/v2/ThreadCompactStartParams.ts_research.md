# ThreadCompactStartParams.ts 研究文档

## 场景与职责

`ThreadCompactStartParams` 是 Codex App-Server Protocol v2 API 中 `thread/compact/start` 方法的请求参数类型，用于触发线程的上下文压缩操作。当对话历史过长时，压缩操作可以减小上下文窗口，同时保留关键信息。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 要压缩的线程 ID |

### 设计特点

1. **简洁接口**：仅需线程 ID 即可触发压缩
2. **后台操作**：压缩通常在后台异步执行
3. **上下文管理**：帮助管理长对话的上下文窗口限制

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadCompactStartParams = { threadId: string, };
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2864-2869) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartParams {
    pub thread_id: String,
}
```

### 在 ClientRequest 中的注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
ThreadCompactStart => "thread/compact/start" {
    params: v2::ThreadCompactStartParams,
    response: v2::ThreadCompactStartResponse,
},
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2864-2869): Rust 类型定义

### 下游使用方
- 客户端调用 `thread/compact/start` RPC 方法

### 相关类型
- `ThreadCompactStartResponse.ts`: 压缩启动响应
- `ContextCompactedNotification.ts`: 压缩完成通知（已废弃，推荐使用 `ContextCompaction` item 类型）

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadCompactStartParams } from "./v2";

// 启动线程压缩
const params: ThreadCompactStartParams = {
  threadId: "thread_abc123"
};

const response = await client.request("thread/compact/start", params);
// 响应为空对象
```

### 压缩流程

1. 客户端发送 `thread/compact/start` 请求
2. 服务器开始异步压缩操作
3. 压缩完成后，服务器发送 `ContextCompactedNotification`（或添加 `ContextCompaction` item）
4. 客户端更新线程历史显示

## 风险、边界与改进建议

### 边界情况

1. **压缩中状态**：同一线程多次调用压缩操作的处理
2. **压缩失败**：压缩过程中出现错误的处理
3. **数据丢失**：压缩可能导致部分历史信息丢失

### 改进建议

1. **压缩策略**：添加可选的压缩策略参数（如保留最近 N 轮、摘要生成等）
2. **进度通知**：添加压缩进度通知
3. **预览模式**：添加预览模式，显示压缩后的效果而不实际执行

### 注意事项

- 该文件为**自动生成**
- 压缩操作不可逆，执行前应考虑用户确认
- 压缩后的历史可能无法完全恢复到原始状态
