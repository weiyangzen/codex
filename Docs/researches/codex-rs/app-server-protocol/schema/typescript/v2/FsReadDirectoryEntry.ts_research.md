# FsReadDirectoryEntry.ts 研究文档

## 场景与职责

`FsReadDirectoryEntry.ts` 定义了目录条目类型，用于表示 `fs/readDirectory` 返回的单个目录项。这是文件系统操作 API 的基础类型，提供目录内容的基本信息。

该类型在文件浏览器、目录遍历、文件列表展示等场景中发挥作用。

## 功能点目的

1. **条目信息**: 提供目录中每个条目的名称和类型
2. **类型区分**: 区分文件和子目录
3. **列表构建**: 支持构建目录内容列表

## 具体技术实现

### 数据结构定义

```typescript
/**
 * A directory entry returned by `fs/readDirectory`.
 */
export type FsReadDirectoryEntry = { 
  /**
   * Direct child entry name only, not an absolute or relative path.
   */
  fileName: string, 
  /**
   * Whether this entry resolves to a directory.
   */
  isDirectory: boolean, 
  /**
   * Whether this entry resolves to a regular file.
   */
  isFile: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `fileName` | `string` | 条目名称（仅文件名，不含路径） |
| `isDirectory` | `boolean` | 是否为目录 |
| `isFile` | `boolean` | 是否为普通文件 |

### 使用示例

```typescript
// 读取目录并处理条目
const response: FsReadDirectoryResponse = await client.sendRequest('fs/readDirectory', {
  path: '/home/user/project'
});

for (const entry of response.entries) {
  if (entry.isDirectory) {
    console.log(`📁 ${entry.fileName}/`);
  } else if (entry.isFile) {
    console.log(`📄 ${entry.fileName}`);
  }
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2206-2217)

```rust
/// A directory entry returned by `fs/readDirectory`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsReadDirectoryEntry {
    /// Direct child entry name only, not an absolute or relative path.
    pub file_name: String,
    /// Whether this entry resolves to a directory.
    pub is_directory: bool,
    /// Whether this entry resolves to a regular file.
    pub is_file: bool,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2219-2226)

```rust
/// Directory entries returned by `fs/readDirectory`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsReadDirectoryResponse {
    /// Direct child entries in the requested directory.
    pub entries: Vec<FsReadDirectoryEntry>,
}
```

### 请求类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2197-2204)

```rust
pub struct FsReadDirectoryParams {
    pub path: AbsolutePathBuf,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **文件浏览器**: 显示目录内容
- **树形控件**: 构建文件树
- **文件选择器**: 文件选择对话框

## 风险、边界与改进建议

### 已知风险

1. **信息有限**: 不包含文件大小、修改时间等
2. **特殊条目**: 未明确处理 `.` 和 `..`
3. **隐藏文件**: 未明确是否包含隐藏文件

### 边界情况

1. **空目录**: 返回空数组
2. **符号链接**: 未明确是否跟随符号链接
3. **权限不足**: 某些条目可能无法访问

### 改进建议

1. **更多字段**: 添加大小、时间戳等元数据
2. **条目类型**: 明确标识符号链接、设备文件等
3. **隐藏属性**: 标识隐藏文件（以 `.` 开头）
4. **排序**: 支持按名称、时间等排序

### 扩展示例

```typescript
export type FsReadDirectoryEntry = { 
  fileName: string, 
  isDirectory: boolean, 
  isFile: boolean,
  isSymlink: boolean,        // 新增
  isHidden: boolean,         // 新增
  size: number,              // 新增
  modifiedAtMs: number,      // 新增
};
```
