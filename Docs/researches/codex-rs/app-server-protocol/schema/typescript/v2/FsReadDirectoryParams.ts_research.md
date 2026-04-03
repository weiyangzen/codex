# FsReadDirectoryParams.ts 研究文档

## 场景与职责

`FsReadDirectoryParams.ts` 定义了读取目录请求的参数类型，用于获取目录中的文件和子目录列表。这是文件系统操作 API 的核心功能，支持文件浏览、目录遍历等操作。

该类型在文件浏览器、项目导航、批量操作等场景中发挥作用。

## 功能点目的

1. **目录读取**: 获取指定目录的内容列表
2. **路径安全**: 使用绝对路径防止目录遍历攻击
3. **沙盒控制**: 受沙盒策略限制，只能访问允许的路径

## 具体技术实现

### 数据结构定义

```typescript
/**
 * List direct child names for a directory.
 */
export type FsReadDirectoryParams = { 
  /**
   * Absolute directory path to read.
   */
  path: AbsolutePathBuf, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `AbsolutePathBuf` | 要读取的目录的绝对路径 |

### 响应类型

```typescript
export type FsReadDirectoryResponse = {
  entries: FsReadDirectoryEntry[];
};

export type FsReadDirectoryEntry = {
  fileName: string;
  isDirectory: boolean;
  isFile: boolean;
};
```

### 使用示例

```typescript
// 读取目录内容
const params: FsReadDirectoryParams = {
  path: '/home/user/project'
};

const response: FsReadDirectoryResponse = await client.sendRequest('fs/readDirectory', params);

console.log(`目录包含 ${response.entries.length} 个条目:`);
for (const entry of response.entries) {
  console.log(`- ${entry.fileName} (${entry.isDirectory ? '目录' : '文件'})`);
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2197-2204)

```rust
/// List direct child names for a directory.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsReadDirectoryParams {
    /// Absolute directory path to read.
    pub path: AbsolutePathBuf,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2219-2226)

```rust
pub struct FsReadDirectoryResponse {
    pub entries: Vec<FsReadDirectoryEntry>,
}
```

### 条目类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2206-2217)

```rust
pub struct FsReadDirectoryEntry {
    pub file_name: String,
    pub is_directory: bool,
    pub is_file: bool,
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

- **文件系统 API**: `fs/readDirectory` RPC 方法
- **文件浏览器**: 显示目录内容
- **项目导航**: 遍历项目结构

## 风险、边界与改进建议

### 已知风险

1. **大目录**: 大目录可能返回大量条目，影响性能
2. **权限问题**: 可能无权限读取某些目录
3. **符号链接循环**: 未处理符号链接循环

### 边界情况

1. **空目录**: 返回空数组
2. **非目录路径**: 路径不是目录时应报错
3. **隐藏文件**: 是否包含隐藏文件未明确

### 改进建议

1. **分页支持**: 大目录支持分页返回
2. **过滤选项**: 支持按模式过滤条目
3. **排序选项**: 支持按名称、时间等排序
4. **递归选项**: 支持递归读取子目录
5. **元数据**: 返回条目的基本元数据

### 扩展示例

```typescript
export type FsReadDirectoryParams = { 
  path: AbsolutePathBuf,
  // 新增字段
  pattern?: string;          // 过滤模式（glob）
  includeHidden?: boolean;   // 是否包含隐藏文件
  sortBy?: 'name' | 'time' | 'size';
  sortOrder?: 'asc' | 'desc';
  recursive?: boolean;       // 是否递归
  maxDepth?: number;         // 递归最大深度
};
```
