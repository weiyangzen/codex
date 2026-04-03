# FsWriteFileParams.ts 研究文档

## 场景与职责

`FsWriteFileParams.ts` 定义了写入文件请求的参数类型，用于通过 App Server API 在主机文件系统上写入文件。这是文件系统操作 API 的核心功能，支持文件创建和内容更新。

该类型在文件编辑、代码生成、配置写入等场景中发挥关键作用。

## 功能点目的

1. **文件写入**: 创建新文件或覆盖现有文件
2. **二进制支持**: 使用 base64 编码支持任意二进制内容
3. **安全控制**: 通过沙盒策略控制可写入的路径

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Write a file on the host filesystem.
 */
export type FsWriteFileParams = { 
  /**
   * Absolute path to write.
   */
  path: AbsolutePathBuf, 
  /**
   * File contents encoded as base64.
   */
  dataBase64: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `AbsolutePathBuf` | 要写入的文件绝对路径 |
| `dataBase64` | `string` | 文件内容的 base64 编码 |

### 使用示例

```typescript
// 写入文本文件
const text = 'Hello, World!';
const params: FsWriteFileParams = {
  path: '/home/user/greeting.txt',
  dataBase64: btoa(text)  // base64 编码
};

await client.sendRequest('fs/writeFile', params);

// 写入二进制文件
const binaryData = new Uint8Array([0x89, 0x50, 0x4E, 0x47]); // PNG 文件头
const base64Data = btoa(String.fromCharCode(...binaryData));
const binaryParams: FsWriteFileParams = {
  path: '/home/user/image.png',
  dataBase64: base64Data
};
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2136-2145)

```rust
/// Write a file on the host filesystem.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsWriteFileParams {
    /// Absolute path to write.
    pub path: AbsolutePathBuf,
    /// File contents encoded as base64.
    pub data_base64: String,
}
```

### 响应类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2147-2151)

```rust
/// Successful response for `fs/writeFile`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsWriteFileResponse {}
```

### 读取文件响应

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2128-2134)

```rust
pub struct FsReadFileResponse {
    pub data_base64: String,
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

- **文件系统 API**: `fs/writeFile` RPC 方法
- **代码生成**: 生成的代码写入文件
- **配置保存**: 保存配置文件

## 风险、边界与改进建议

### 已知风险

1. **覆盖风险**: 会覆盖现有文件，可能导致数据丢失
2. **大文件**: 大文件的 base64 编码会增加传输开销
3. **编码问题**: 文本文件的编码需要客户端正确处理

### 边界情况

1. **父目录不存在**: 父目录不存在时写入会失败
2. **磁盘空间不足**: 大文件写入可能因空间不足失败
3. **权限问题**: 可能无权限写入目标路径

### 改进建议

1. **原子写入**: 支持原子性写入（写入临时文件后重命名）
2. **追加模式**: 支持追加写入而非覆盖
3. **写入确认**: 返回写入的字节数
4. **编码选项**: 支持指定文本编码
5. **流式写入**: 大文件支持分块流式写入

### 扩展示例

```typescript
export type FsWriteFileParams = { 
  path: AbsolutePathBuf, 
  dataBase64: string,
  // 新增字段
  mode?: 'overwrite' | 'append' | 'create';  // 写入模式
  encoding?: 'utf8' | 'base64' | 'binary';   // 内容编码
  atomic?: boolean;                          // 是否原子写入
  createDirs?: boolean;                      // 自动创建父目录
};

export type FsWriteFileResponse = {
  bytesWritten: number;
  path: AbsolutePathBuf;
  created: boolean;  // 是否为新建文件
};
```
