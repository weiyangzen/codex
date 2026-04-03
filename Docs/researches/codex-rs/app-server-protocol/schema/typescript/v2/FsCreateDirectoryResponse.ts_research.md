# FsCreateDirectoryResponse.ts 研究文档

## 场景与职责

`FsCreateDirectoryResponse.ts` 定义了创建目录请求的响应类型，用于确认目录已成功创建。这是文件系统操作 API 的响应结构，采用空对象模式表示成功。

该类型在目录创建确认、批量操作、错误处理等场景中发挥作用。

## 功能点目的

1. **成功确认**: 确认目录创建操作成功完成
2. **空响应优化**: 使用空对象减少不必要的数据传输
3. **错误指示**: 通过响应存在与否指示操作结果

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Successful response for `fs/createDirectory`.
 */
export type FsCreateDirectoryResponse = Record<string, never>;
```

### 说明

- 使用 `Record<string, never>` 表示空对象类型
- 不包含任何字段，仅表示操作成功
- 错误通过 RPC 错误响应返回

### 使用示例

```typescript
// 创建目录
const params: FsCreateDirectoryParams = {
  path: '/home/user/new-folder',
  recursive: true
};

try {
  const response: FsCreateDirectoryResponse = await client.sendRequest('fs/createDirectory', params);
  // 成功，response 为空对象 {}
  console.log('目录创建成功');
} catch (error) {
  // 失败，处理错误
  console.error('目录创建失败:', error);
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2165-2169)

```rust
/// Successful response for `fs/createDirectory`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCreateDirectoryResponse {}
```

### 类似空响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub struct FsWriteFileResponse {}     // 写文件响应
pub struct FsRemoveResponse {}        // 删除响应
pub struct FsCopyResponse {}          // 复制响应
pub struct CommandExecWriteResponse {} // 命令写入响应
pub struct CommandExecTerminateResponse {} // 命令终止响应
pub struct CommandExecResizeResponse {}    // 命令调整大小响应
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **文件系统 API**: `fs/createDirectory` RPC 方法
- **批量操作**: 批量目录创建的结果确认
- **错误处理**: 区分成功和失败状态

## 风险、边界与改进建议

### 已知风险

1. **信息不足**: 空响应不包含创建的目录信息
2. **幂等性**: 无法区分"创建成功"和"目录已存在"
3. **调试困难**: 缺乏上下文信息，调试时难以追踪

### 边界情况

1. **目录已存在**: 响应相同，无法区分
2. **部分成功**: 递归创建时部分父目录可能已存在
3. **并发创建**: 并发创建同一目录时的行为

### 改进建议

1. **返回元数据**: 返回创建的目录路径和时间
2. **创建状态**: 指示是新建还是已存在
3. **详细信息**: 递归创建时返回创建的所有目录

### 扩展示例

```typescript
export type FsCreateDirectoryResponse = {
  path: AbsolutePathBuf;
  created: boolean;  // true = 新建, false = 已存在
  createdAt?: number;  // 创建时间戳
  createdDirectories?: AbsolutePathBuf[];  // 递归创建的所有目录
};
```
