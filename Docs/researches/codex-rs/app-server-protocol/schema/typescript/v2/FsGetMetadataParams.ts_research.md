# FsGetMetadataParams.ts 研究文档

## 场景与职责

`FsGetMetadataParams.ts` 定义了获取文件元数据请求的参数类型，用于查询文件或目录的元数据信息。这是文件系统操作 API 的基础功能，支持文件管理、状态检查等操作。

该类型在文件信息查询、存在性检查、时间戳获取等场景中发挥作用。

## 功能点目的

1. **元数据查询**: 获取文件的类型、时间戳等信息
2. **存在性检查**: 检查路径是否存在及类型
3. **时间信息**: 获取文件创建和修改时间

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Request metadata for an absolute path.
 */
export type FsGetMetadataParams = { 
  /**
   * Absolute path to inspect.
   */
  path: AbsolutePathBuf, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `AbsolutePathBuf` | 要查询的绝对路径 |

### 响应类型

```typescript
export type FsGetMetadataResponse = { 
  isDirectory: boolean,      // 是否为目录
  isFile: boolean,           // 是否为文件
  createdAtMs: number,       // 创建时间（Unix 毫秒）
  modifiedAtMs: number,      // 修改时间（Unix 毫秒）
};
```

### 使用示例

```typescript
// 获取文件元数据
const params: FsGetMetadataParams = {
  path: '/home/user/document.txt'
};

const metadata: FsGetMetadataResponse = await client.sendRequest('fs/getMetadata', params);

if (metadata.isFile) {
  console.log('文件大小:', metadata.size);
  console.log('修改时间:', new Date(metadata.modifiedAtMs));
} else if (metadata.isDirectory) {
  console.log('这是一个目录');
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2171-2178)

```rust
/// Request metadata for an absolute path.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsGetMetadataParams {
    /// Absolute path to inspect.
    pub path: AbsolutePathBuf,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2180-2195)

```rust
/// Metadata returned by `fs/getMetadata`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsGetMetadataResponse {
    /// Whether the path currently resolves to a directory.
    pub is_directory: bool,
    /// Whether the path currently resolves to a regular file.
    pub is_file: bool,
    /// File creation time in Unix milliseconds when available, otherwise `0`.
    #[ts(type = "number")]
    pub created_at_ms: i64,
    /// File modification time in Unix milliseconds when available, otherwise `0`.
    #[ts(type = "number")]
    pub modified_at_ms: i64,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `AbsolutePathBuf` | 绝对路径类型 |
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **文件系统 API**: `fs/getMetadata` RPC 方法
- **文件浏览器**: 显示文件信息
- **同步工具**: 比较文件时间戳

## 风险、边界与改进建议

### 已知风险

1. **路径不存在**: 路径不存在时的行为未明确
2. **权限问题**: 可能无权限访问某些路径的元数据
3. **符号链接**: 未明确是否跟随符号链接

### 边界情况

1. **路径不存在**: 应返回错误还是特定响应
2. **特殊文件**: 设备文件、管道等特殊文件的处理
3. **时间不可用**: 某些文件系统可能不支持创建时间

### 改进建议

1. **不存在处理**: 明确路径不存在时的响应
2. **更多元数据**: 增加文件大小、权限、所有者等
3. **符号链接**: 支持查询符号链接本身的信息
4. **错误详情**: 提供更详细的错误信息

### 扩展示例

```typescript
export type FsGetMetadataParams = { 
  path: AbsolutePathBuf,
  // 新增字段
  followSymlinks?: boolean;  // 是否跟随符号链接
};

export type FsGetMetadataResponse = {
  exists: boolean;           // 路径是否存在
  isDirectory: boolean;
  isFile: boolean;
  isSymlink: boolean;        // 是否为符号链接
  size: number;              // 文件大小（字节）
  createdAtMs: number;
  modifiedAtMs: number;
  accessedAtMs: number;      // 最后访问时间
  permissions: {             // 权限信息
    mode: number;
    owner: string;
    group: string;
  };
};
```
