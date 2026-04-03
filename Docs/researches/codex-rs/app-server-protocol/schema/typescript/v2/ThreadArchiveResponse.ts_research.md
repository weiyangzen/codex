# ThreadArchiveResponse.ts 研究文档

## 场景与职责

`ThreadArchiveResponse` 是 Codex App-Server Protocol v2 API 中 `thread/archive` 方法的响应类型。由于归档操作是简单的状态变更且无需返回额外数据，该响应类型设计为空对象。

## 功能点目的

### 核心功能

该类型使用 TypeScript 的 `Record<string, never>` 表示一个空对象，即：
- 不接受任何属性
- 任何属性赋值都会导致类型错误

### 设计特点

1. **空响应模式**：对于无需返回数据的操作，使用空对象保持协议一致性
2. **类型安全**：使用 `Record<string, never>` 而非 `{}` 或 `object`，确保严格的空对象语义
3. **协议完整性**：即使无数据返回，也有明确的响应类型定义

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadArchiveResponse = Record<string, never>;
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2714-2717) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchiveResponse {}
```

### 在 ClientRequest 中的注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
ThreadArchive => "thread/archive" {
    params: v2::ThreadArchiveParams,
    response: v2::ThreadArchiveResponse,
},
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2714-2717): Rust 类型定义

### 下游使用方
- 客户端接收 `thread/archive` RPC 响应时使用

### 相关类型
- `ThreadArchiveParams.ts`: 归档请求参数

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadArchiveResponse } from "./v2";

// RPC 调用归档操作
const response: ThreadArchiveResponse = await client.request("thread/archive", {
  threadId: "thread_abc123"
});

// 响应为空对象
console.log(response); // {}

// 以下代码会导致类型错误
// response.anyField = "value"; // Error: Type 'string' is not assignable to type 'never'
```

### 空对象类型的优势

```typescript
// Record<string, never> 与 {} 的区别

// {} 允许任意属性赋值（宽松）
const loose: {} = { any: "thing" }; // OK

// Record<string, never> 严格禁止任何属性
const strict: Record<string, never> = {}; // OK
// const strict2: Record<string, never> = { any: "thing" }; // Error
```

## 风险、边界与改进建议

### 边界情况

1. **序列化结果**：空对象序列化为 JSON `{}`
2. **与其他空响应的区别**：需要确保所有空响应类型保持一致

### 改进建议

1. **添加成功标志**：考虑添加 `success: boolean` 字段以明确操作结果
2. **添加时间戳**：`archivedAt: number` 记录归档时间
3. **统一空响应类型**：考虑所有空响应使用统一的 `EmptyResponse` 类型

### 注意事项

- 该文件为**自动生成**
- 空响应用于确认操作完成，实际状态变更通过 `ThreadArchivedNotification` 通知
