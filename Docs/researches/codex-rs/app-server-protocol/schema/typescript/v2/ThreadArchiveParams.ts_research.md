# ThreadArchiveParams.ts 研究文档

## 场景与职责

`ThreadArchiveParams` 是 Codex App-Server Protocol v2 API 中 `thread/archive` 方法的请求参数类型，用于将指定线程标记为归档状态。归档后的线程不会出现在默认的线程列表中，但可以通过特定过滤器访问。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 要归档的线程 ID |

### 设计特点

1. **简洁设计**：仅需线程 ID 即可执行归档操作
2. **软删除语义**：归档不等于删除，数据仍然保留
3. **可逆操作**：通过 `thread/unarchive` 可以恢复归档线程

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadArchiveParams = { threadId: string, };
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2707-2712) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchiveParams {
    pub thread_id: String,
}
```

### 在 ClientRequest 中的注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为 RPC 方法：

```rust
ThreadArchive => "thread/archive" {
    params: v2::ThreadArchiveParams,
    response: v2::ThreadArchiveResponse,
},
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2707-2712): Rust 类型定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: RPC 方法注册

### 下游使用方
- 客户端调用 `thread/archive` RPC 方法时使用

### 相关类型
- `ThreadArchiveResponse.ts`: 归档操作的响应类型（空对象）
- `ThreadArchivedNotification.ts`: 归档完成通知
- `ThreadUnarchiveParams.ts`: 取消归档参数

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadArchiveParams } from "./v2";

// 归档线程请求
const params: ThreadArchiveParams = {
  threadId: "thread_abc123"
};

// RPC 调用
const response = await client.request("thread/archive", params);
// 响应为 ThreadArchiveResponse，即空对象 {}
```

### 相关通知

归档操作完成后，服务器会发送 `ThreadArchivedNotification`：

```typescript
export type ThreadArchivedNotification = { 
  threadId: string 
};
```

## 风险、边界与改进建议

### 边界情况

1. **线程不存在**：请求不存在的线程 ID 时的错误处理
2. **重复归档**：对已归档线程再次执行归档操作的行为
3. **权限检查**：是否有权限归档特定线程的验证

### 改进建议

1. **批量归档**：支持一次归档多个线程
2. **归档原因**：添加可选的归档原因字段
3. **自动归档**：支持基于时间的自动归档策略配置

### 注意事项

- 该文件为**自动生成**
- 归档是逻辑操作，不会删除线程数据
- 归档后的线程可以通过 `ThreadListParams.archived = true` 过滤器查询
