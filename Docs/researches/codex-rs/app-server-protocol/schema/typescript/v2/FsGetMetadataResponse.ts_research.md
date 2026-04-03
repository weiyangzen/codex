# FsGetMetadataResponse.ts 研究文档

## 场景与职责

`FsGetMetadataResponse.ts` 定义了获取文件元数据请求的响应类型，用于返回文件或目录的元数据信息。这是文件系统操作 API 的核心响应类型，提供文件类型、时间戳等关键信息。

该类型在文件管理、状态检查、同步操作等场景中发挥关键作用。

## 功能点目的

1. **类型识别**: 区分文件和目录
2. **时间信息**: 提供创建和修改时间戳
3. **存在性确认**: 确认路径存在且可访问

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Metadata returned by `fs/getMetadata`.
 */
export type FsGetMetadataResponse = { 
  /**
   * Whether the path currently resolves to a directory.
   */
  isDirectory: boolean, 
  /**
   * Whether the path currently resolves to a regular file.
   */
  isFile: boolean, 
  /**
   * File creation time in Unix milliseconds when available, otherwise `0`.
   */
  createdAtMs: number, 
  /**
   * File modification time in Unix milliseconds when available, otherwise `0`.
   */
  modifiedAtMs: number, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `isDirectory` | `boolean` | 路径是否为目录 |
| `isFile` | `boolean` | 路径是否为普通文件 |
| `createdAtMs` | `number` | 创建时间（Unix 时间戳，毫秒），不可用时为 0 |
| `modifiedAtMs` | `number` | 修改时间（Unix 时间戳，毫秒），不可用时为 0 |

### 使用示例

```typescript
// 获取并处理文件元数据
const response: FsGetMetadataResponse = await client.sendRequest('fs/getMetadata', {
  path: '/home/user/project'
});

if (response.isDirectory) {
  console.log('目录');
} else if (response.isFile) {
  console.log('文件');
}

// 时间戳处理
if (response.modifiedAtMs > 0) {
  const modifiedDate = new Date(response.modifiedAtMs);
  console.log('最后修改:', modifiedDate.toLocaleString());
}
```

## 关键代码路径与文件引用

### Rust 源码定义

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

### 请求类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2171-2178)

```rust
pub struct FsGetMetadataParams {
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

- **文件浏览器**: 显示文件信息
- **同步工具**: 比较文件时间戳
- **构建系统**: 检查文件修改时间

## 风险、边界与改进建议

### 已知风险

1. **信息有限**: 不包含文件大小、权限等重要信息
2. **时间精度**: 毫秒精度在某些场景可能不足
3. **时区问题**: Unix 时间戳无时区信息

### 边界情况

1. **时间不可用**: 某些文件系统可能不支持创建时间，返回 0
2. **同时满足**: `isDirectory` 和 `isFile` 理论上互斥，但需验证
3. **特殊文件**: 符号链接、设备文件等的识别

### 改进建议

1. **增加字段**: 添加文件大小、权限、所有者等
2. **符号链接**: 明确标识符号链接
3. **错误处理**: 路径不存在时返回明确的错误码
4. **纳秒精度**: 支持更高精度的时间戳

### 扩展示例

```typescript
export type FsGetMetadataResponse = { 
  isDirectory: boolean, 
  isFile: boolean,
  isSymlink: boolean,        // 新增：是否为符号链接
  size: number,              // 新增：文件大小
  createdAtMs: number, 
  modifiedAtMs: number,
  accessedAtMs: number,      // 新增：访问时间
  permissions: {             // 新增：权限信息
    mode: number;
    ownerRead: boolean;
    ownerWrite: boolean;
    ownerExecute: boolean;
    groupRead: boolean;
    groupWrite: boolean;
    groupExecute: boolean;
    otherRead: boolean;
    otherWrite: boolean;
    otherExecute: boolean;
  },
};
```
