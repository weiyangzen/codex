# ThreadSortKey 类型研究报告

## 场景与职责

`ThreadSortKey` 是 Codex App-Server Protocol v2 中的枚举类型，用于指定线程列表的排序方式。该类型在 `ThreadListParams` 中使用，控制 `thread/list` 查询结果的排序顺序。

**主要使用场景：**
- 获取线程列表时指定排序字段
- 客户端展示线程列表的排序控制
- 支持按创建时间或更新时间排序

**职责范围：**
- 定义支持的排序字段
- 提供类型安全的排序键选择
- 与 `ThreadListParams` 配合实现排序功能

## 功能点目的

该类型的核心目的是为线程列表查询提供标准化的排序选项：

1. **时间排序**: 支持按创建时间或更新时间排序
2. **类型安全**: 通过枚举限制有效的排序键
3. **API 一致性**: 为列表查询提供统一的排序参数接口

**使用方式：**
```typescript
// 在 ThreadListParams 中使用
const params: ThreadListParams = {
  cursor: undefined,
  limit: 20,
  sortKey: "updated_at",  // 使用 ThreadSortKey
  archived: false,
};
```

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadSortKey = "created_at" | "updated_at";
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub enum ThreadSortKey {
    CreatedAt,
    UpdatedAt,
}
```

### 字段/变体说明

| TypeScript 值 | Rust 变体 | 说明 |
|---------------|-----------|------|
| `"created_at"` | `CreatedAt` | 按线程创建时间排序 |
| `"updated_at"` | `UpdatedAt` | 按线程最后更新时间排序 |

### 序列化规则

- **Rust 到 JSON**: 使用 `snake_case` 命名规则
  - `CreatedAt` → `"created_at"`
  - `UpdatedAt` → `"updated_at"`

- **TypeScript 表示**: 字符串字面量联合类型
  - `"created_at" | "updated_at"`

### 相关类型

- **ThreadListParams**: 使用 `ThreadSortKey` 作为可选参数
  ```typescript
  export type ThreadListParams = {
    cursor?: string | null,
    limit?: number | null,
    sortKey?: ThreadSortKey | null,  // 使用 ThreadSortKey
    // ... 其他字段
  };
  ```

- **Thread**: 包含 `createdAt` 和 `updatedAt` 字段
  ```typescript
  export type Thread = {
    // ...
    createdAt: number,  // Unix timestamp
    updatedAt: number,  // Unix timestamp
    // ...
  };
  ```

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadSortKey.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2981-2987

### 相关上下文
```rust
// ThreadSortKey 定义（2981-2987）
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub enum ThreadSortKey {
    CreatedAt,
    UpdatedAt,
}

// ThreadListParams 中的使用（2932-2961）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadListParams {
    // ...
    /// Optional sort key; defaults to created_at.
    #[ts(optional = nullable)]
    pub sort_key: Option<ThreadSortKey>,
    // ...
}
```

### 依赖类型文件
| 类型 | 路径 |
|------|------|
| ThreadListParams | `codex-rs/app-server-protocol/schema/typescript/v2/ThreadListParams.ts` |
| Thread | `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts` |

## 依赖与外部交互

### 内部依赖

1. **ThreadListParams**: 排序键的使用上下文
2. **Thread**: 提供排序依据的字段（`createdAt`、`updatedAt`）

### 外部交互

1. **与 ThreadListParams 的交互**:
   ```typescript
   const params: ThreadListParams = {
     sortKey: "updated_at",  // 指定排序方式
   };
   ```

2. **与 ThreadListResponse 的交互**:
   - 服务端根据 `sortKey` 对线程排序
   - 返回排序后的线程列表

3. **默认值行为**:
   - 如果 `sortKey` 为 `null` 或未指定
   - 默认按 `"created_at"` 排序

### 排序方向

当前类型**不包含排序方向**（升序/降序），可能的实现方式：

1. **约定降序**: 默认按时间倒序（最新的在前）
2. **单独字段**: 可能的扩展
   ```typescript
   export type ThreadListParams = {
     sortKey?: ThreadSortKey | null,
     sortDirection?: "asc" | "desc" | null,  // 可能的扩展
   };
   ```

### 与其他排序类型的对比

| 类型 | 用途 | 值 |
|------|------|-----|
| ThreadSortKey | 线程排序 | `"created_at"`, `"updated_at"` |
| （其他排序类型） | ... | ... |

## 风险、边界与改进建议

### 潜在风险

1. **排序方向不明确**:
   - 类型只定义了排序字段，未定义方向
   - 客户端无法指定升序或降序
   - 不同客户端可能对默认方向有不同假设

2. **扩展性限制**:
   - 当前仅支持两个时间字段
   - 无法按名称、状态等其他字段排序
   - 每次新增排序字段都需要协议变更

3. **时区问题**:
   - 时间戳是 Unix 秒（UTC）
   - 客户端显示时可能需要转换
   - 排序基于 UTC，与用户本地时间可能有差异

### 边界情况

1. **相同时间戳**: 多个线程具有相同的 `createdAt` 或 `updatedAt`
2. **null 值处理**: 虽然时间戳理论上不为 null
3. **性能考虑**: 大量线程排序的性能影响
4. **与分页的交互**: 排序稳定性对分页的重要性

### 改进建议

1. **添加排序方向**:
   ```rust
   #[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, JsonSchema, TS)]
   #[serde(rename_all = "snake_case")]
   #[ts(export_to = "v2/")]
   pub enum ThreadSortDirection {
       Asc,
       Desc,
   }
   
   #[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
   #[serde(rename_all = "camelCase")]
   #[ts(export_to = "v2/")]
   pub struct ThreadListParams {
       // ...
       #[ts(optional = nullable)]
       pub sort_key: Option<ThreadSortKey>,
       #[ts(optional = nullable)]
       pub sort_direction: Option<ThreadSortDirection>,
       // ...
   }
   ```

2. **扩展排序字段**:
   ```typescript
   export type ThreadSortKey = 
     | "created_at" 
     | "updated_at"
     | "name"           // 按名称排序
     | "status"         // 按状态排序
     | "preview";       // 按预览文本排序
   ```

3. **复合排序**:
   ```typescript
   export type ThreadSortKey = {
     primary: "created_at" | "updated_at" | "name",
     secondary?: "created_at" | "updated_at" | "name",
   };
   ```

4. **自定义排序**:
   ```typescript
   export type ThreadListParams = {
     sortKey?: ThreadSortKey | null,
     customSort?: {
       field: string,
       direction: "asc" | "desc",
     } | null,
   };
   ```

5. **服务端排序提示**:
   ```typescript
   export type ThreadListResponse = {
     data: Thread[],
     nextCursor: string | null,
     sortInfo: {
       key: ThreadSortKey,
       direction: "asc" | "desc",
       totalCount: number,
     },
   };
   ```

6. **索引优化建议**:
   - 为 `created_at` 和 `updated_at` 字段建立数据库索引
   - 考虑复合索引（如 `updated_at` + `id`）确保排序稳定性

7. **向后兼容扩展**:
   ```typescript
   // 当前
   export type ThreadSortKey = "created_at" | "updated_at";
   
   // 未来扩展
   export type ThreadSortKey = 
     | "created_at" 
     | "updated_at"
     | "name_asc"
     | "name_desc";
   ```
