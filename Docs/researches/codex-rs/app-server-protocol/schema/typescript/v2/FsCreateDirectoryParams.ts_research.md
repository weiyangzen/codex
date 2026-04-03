# FsCreateDirectoryParams.ts 研究文档

## 场景与职责

`FsCreateDirectoryParams.ts` 定义了创建目录请求的参数类型，用于通过 App Server API 在主机文件系统上创建目录。这是文件系统操作 API 的一部分，提供安全的目录创建功能。

该类型在目录创建、项目初始化、文件组织等场景中发挥作用。

## 功能点目的

1. **目录创建**: 在指定路径创建目录
2. **递归创建**: 支持自动创建父目录
3. **安全控制**: 通过沙盒策略控制可访问的路径

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Create a directory on the host filesystem.
 */
export type FsCreateDirectoryParams = { 
  /**
   * Absolute directory path to create.
   */
  path: AbsolutePathBuf, 
  /**
   * Whether parent directories should also be created. Defaults to `true`.
   */
  recursive?: boolean | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `AbsolutePathBuf` | 要创建的目录的绝对路径 |
| `recursive` | `boolean \| null` | 是否递归创建父目录，默认为 `true` |

### 使用示例

```typescript
// 创建单个目录
const params: FsCreateDirectoryParams = {
  path: '/home/user/project/src',
  recursive: false
};

// 递归创建目录树
const recursiveParams: FsCreateDirectoryParams = {
  path: '/home/user/project/src/components/button',
  recursive: true  // 会自动创建 project、src、components 等父目录
};

await client.sendRequest('fs/createDirectory', params);
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2153-2163)

```rust
/// Create a directory on the host filesystem.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCreateDirectoryParams {
    /// Absolute directory path to create.
    pub path: AbsolutePathBuf,
    /// Whether parent directories should also be created. Defaults to `true`.
    #[ts(optional = nullable)]
    pub recursive: Option<bool>,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2165-2169)

```rust
/// Successful response for `fs/createDirectory`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCreateDirectoryResponse {}
```

### 路径类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

使用 `AbsolutePathBuf` 类型确保路径为绝对路径：
- 来自 `codex_utils_absolute_path::AbsolutePathBuf`
- 自动验证路径格式
- 防止目录遍历攻击

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `AbsolutePathBuf` | 绝对路径类型 |
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **文件系统 API**: `fs/createDirectory` RPC 方法
- **TUI 客户端**: 目录创建功能
- **VS Code 扩展**: 文件资源管理器操作

## 风险、边界与改进建议

### 已知风险

1. **沙盒限制**: 受沙盒策略限制，可能无法创建某些目录
2. **权限问题**: 可能无权限在目标位置创建目录
3. **路径冲突**: 路径可能已存在文件而非目录

### 边界情况

1. **目录已存在**: 递归模式下，已存在的目录不应报错
2. **路径是文件**: 如果路径已存在且是文件，应报错
3. **父目录无权限**: 父目录无写入权限时的错误处理

### 改进建议

1. **返回信息**: 响应中返回创建的目录信息
2. **存在处理**: 明确处理目录已存在的情况
3. **原子操作**: 支持原子性目录创建
4. **权限设置**: 支持创建时设置目录权限
5. **元数据**: 返回创建时间等元数据

### 扩展示例

```typescript
export type FsCreateDirectoryParams = { 
  path: AbsolutePathBuf, 
  recursive?: boolean | null,
  // 新增字段
  mode?: number,  // 权限模式（Unix）
  ifNotExists?: boolean,  // 如果不存在才创建
};

export type FsCreateDirectoryResponse = {
  created: boolean;  // 是否实际创建
  path: AbsolutePathBuf;
  createdAt: number;
};
```
