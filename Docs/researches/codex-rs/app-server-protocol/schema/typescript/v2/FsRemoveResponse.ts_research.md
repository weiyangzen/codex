# FsRemoveResponse.ts 研究文档

## 场景与职责

`FsRemoveResponse.ts` 定义了删除文件或目录请求的响应类型，用于确认删除操作成功完成。这是文件系统操作 API 的响应结构，采用空对象模式表示成功。

该类型在文件删除、目录清理、批量操作等场景中发挥作用。

## 功能点目的

1. **成功确认**: 确认文件或目录已成功删除
2. **空响应优化**: 使用空对象减少不必要的数据传输
3. **错误指示**: 通过 RPC 错误响应指示失败

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Successful response for `fs/remove`.
 */
export type FsRemoveResponse = Record<string, never>;
```

### 说明

- 使用 `Record<string, never>` 表示空对象类型
- 不包含任何字段，仅表示操作成功
- 错误通过 RPC 错误响应返回

### 请求参数

```typescript
export type FsRemoveParams = {
  path: AbsolutePathBuf;      // 要删除的路径
  recursive?: boolean | null; // 是否递归删除目录，默认 true
  force?: boolean | null;     // 是否忽略不存在的路径，默认 true
};
```

### 使用示例

```typescript
// 删除文件
const params: FsRemoveParams = {
  path: '/home/user/old-file.txt',
  force: true  // 忽略不存在的文件
};

try {
  const response: FsRemoveResponse = await client.sendRequest('fs/remove', params);
  console.log('删除成功');
} catch (error) {
  console.error('删除失败:', error);
}

// 递归删除目录
const dirParams: FsRemoveParams = {
  path: '/home/user/old-project',
  recursive: true,
  force: true
};
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2243-2247)

```rust
/// Successful response for `fs/remove`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsRemoveResponse {}
```

### 请求参数

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2228-2241)

```rust
pub struct FsRemoveParams {
    pub path: AbsolutePathBuf,
    #[ts(optional = nullable)]
    pub recursive: Option<bool>,
    #[ts(optional = nullable)]
    pub force: Option<bool>,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **文件系统 API**: `fs/remove` RPC 方法
- **清理操作**: 临时文件清理
- **批量删除**: 批量文件删除确认

## 风险、边界与改进建议

### 已知风险

1. **误删除**: 删除操作不可逆，可能误删重要文件
2. **权限问题**: 可能无权限删除某些文件
3. **非空目录**: 非递归模式下删除非空目录会失败

### 边界情况

1. **路径不存在**: `force: true` 时不报错
2. **只读文件**: 只读文件可能无法删除
3. **打开的文件**: 正在使用的文件可能无法删除

### 改进建议

1. **确认机制**: 重要删除操作增加二次确认
2. **回收站**: 支持移动到回收站而非永久删除
3. **删除信息**: 返回删除的文件列表
4. **进度通知**: 大目录删除支持进度通知
5. **撤销支持**: 支持撤销删除操作

### 扩展示例

```typescript
export type FsRemoveResponse = {
  deleted: boolean;
  path: AbsolutePathBuf;
  // 新增字段
  deletedItems?: string[];      // 递归删除时返回所有删除的项目
  movedToTrash?: boolean;       // 是否移动到回收站
  trashPath?: string;           // 回收站路径
};
```
