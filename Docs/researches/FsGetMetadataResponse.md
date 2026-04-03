# FsGetMetadataResponse 调研文档

## 1. 场景与职责

### 使用场景
`FsGetMetadataResponse` 是 Codex App-Server Protocol v2 中获取文件元数据操作（`fs/getMetadata`）的响应结构体。它返回文件或目录的元数据信息。

### 典型使用场景包括：
- **文件存在性确认**：验证文件/目录是否存在
- **类型判断**：确定路径是文件还是目录
- **时间戳分析**：获取创建和修改时间用于同步或缓存
- **变更检测**：比较修改时间判断文件是否被修改
- **UI 展示**：在文件浏览器中显示文件信息

### 职责
- 返回路径的类型信息（文件/目录）
- 提供时间戳信息（创建时间、修改时间）
- 作为 `fs/getMetadata` 请求的完整响应

---

## 2. 功能点目的

### 核心功能
返回文件或目录的元数据信息，支持客户端进行文件系统状态判断。

### 设计目标
1. **完整性**：覆盖最常用的元数据（类型、时间戳）
2. **简洁性**：只包含最必要的信息，避免过度设计
3. **可靠性**：时间戳不可用时返回 `0` 而非错误

### 字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `isDirectory` | `bool` | 路径是否为目录 |
| `isFile` | `bool` | 路径是否为普通文件 |
| `createdAtMs` | `i64` | 创建时间（Unix 毫秒），不可用为 `0` |
| `modifiedAtMs` | `i64` | 修改时间（Unix 毫秒），不可用为 `0` |

### 设计决策
- **不包含文件大小**：简化响应，大小可通过 `fs/readFile` 后计算
- **Unix 毫秒时间戳**：便于 JavaScript/TypeScript 处理
- **布尔类型标记**：明确区分文件和目录

---

## 3. 具体技术实现

### 数据结构定义（Rust）
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

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Metadata returned by `fs/getMetadata`.",
  "properties": {
    "createdAtMs": {
      "description": "File creation time in Unix milliseconds when available, otherwise `0`.",
      "format": "int64",
      "type": "integer"
    },
    "isDirectory": {
      "description": "Whether the path currently resolves to a directory.",
      "type": "boolean"
    },
    "isFile": {
      "description": "Whether the path currently resolves to a regular file.",
      "type": "boolean"
    },
    "modifiedAtMs": {
      "description": "File modification time in Unix milliseconds when available, otherwise `0`.",
      "format": "int64",
      "type": "integer"
    }
  },
  "required": ["createdAtMs", "isDirectory", "isFile", "modifiedAtMs"],
  "title": "FsGetMetadataResponse",
  "type": "object"
}
```

### TypeScript 类型生成
```typescript
export interface FsGetMetadataResponse {
  createdAtMs: number;
  isDirectory: boolean;
  isFile: boolean;
  modifiedAtMs: number;
}
```

### 关键实现细节

#### 时间戳处理
- 使用 `i64` 类型存储 Unix 毫秒时间戳
- TypeScript 生成时使用 `number` 类型（`#[ts(type = "number")]`）
- 时间戳不可用时返回 `0`

#### 类型标记
- `is_directory` 和 `is_file` 可以同时为 `false`（如符号链接、特殊文件）
- 但不会同时为 `true`（文件系统约束）

---

## 4. 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2180-2195)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsGetMetadataResponse.json`

### 协议注册
- **ClientRequest 注册**：`codex-rs/app-server-protocol/src/protocol/common.rs` (行 323-326)
```rust
FsGetMetadata => "fs/getMetadata" {
    params: v2::FsGetMetadataParams,
    response: v2::FsGetMetadataResponse,
}
```

### 服务端实现
- **实现文件**：`codex-rs/app-server/src/fs_api.rs` (行 89-104)
```rust
pub(crate) async fn get_metadata(
    &self,
    params: FsGetMetadataParams,
) -> Result<FsGetMetadataResponse, JSONRPCErrorError> {
    let metadata = self
        .file_system
        .get_metadata(&params.path)
        .await
        .map_err(map_fs_error)?;
    Ok(FsGetMetadataResponse {
        is_directory: metadata.is_directory,
        is_file: metadata.is_file,
        created_at_ms: metadata.created_at_ms,
        modified_at_ms: metadata.modified_at_ms,
    })
}
```

### 底层元数据结构
```rust
// codex_environment 返回的元数据
struct Metadata {
    is_directory: bool,
    is_file: bool,
    created_at_ms: i64,
    modified_at_ms: i64,
}
```

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例 `fs_get_metadata_returns_only_used_fields`：
  - 验证返回字段列表
  - 验证 `is_directory` 和 `is_file` 正确性
  - 验证时间戳大于 0

---

## 5. 依赖与外部交互

### 依赖 crate
| crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts_rs` | TypeScript 类型生成 |

### 响应流程
```
文件系统元数据查询成功
    ↓
FsApi::get_metadata() 构造 FsGetMetadataResponse
    ↓
序列化为 JSON-RPC 2.0 响应
    ↓
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "isDirectory": false,
    "isFile": true,
    "createdAtMs": 1699999999999,
    "modifiedAtMs": 1700000000000
  }
}
```

### 错误响应
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32603,
    "message": "No such file or directory"
  }
}
```

---

## 6. 风险、边界与改进建议

### 当前限制
1. **无文件大小**：无法直接获知文件大小
2. **无权限信息**：无法获知文件权限（Unix）
3. **无所有者信息**：无法获知文件所有者
4. **时间戳可能为 0**：某些文件系统不支持创建时间

### 边界情况
| 场景 | 响应行为 |
|------|----------|
| 普通文件 | `isFile=true`, `isDirectory=false` |
| 目录 | `isFile=false`, `isDirectory=true` |
| 符号链接 | 跟随链接，返回目标元数据 |
| 特殊文件（FIFO、设备等） | `isFile=false`, `isDirectory=false` |
| 创建时间不可用 | `createdAtMs=0` |
| 修改时间不可用 | `modifiedAtMs=0` |

### 改进建议

#### 短期改进
1. **添加文件大小**：
   ```rust
   pub struct FsGetMetadataResponse {
       // ... 现有字段
       pub size: i64,  // 文件大小（字节），目录为 0
   }
   ```

2. **添加路径类型枚举**：
   ```rust
   pub enum PathType {
       File,
       Directory,
       Symlink,
       Unknown,
   }
   ```

#### 长期改进
3. **扩展元数据**：
   ```rust
   pub struct FsGetMetadataResponse {
       // 基本字段
       pub is_directory: bool,
       pub is_file: bool,
       pub created_at_ms: i64,
       pub modified_at_ms: i64,
       // 扩展字段
       pub size: i64,
       pub accessed_at_ms: i64,
       #[cfg(unix)]
       pub mode: u32,
       #[cfg(unix)]
       pub uid: u32,
       #[cfg(unix)]
       pub gid: u32,
       pub hard_links: u64,
   }
   ```

4. **支持选择性返回**：
   ```rust
   pub struct FsGetMetadataParams {
       pub path: AbsolutePathBuf,
       pub include_size: Option<bool>,
       pub include_permissions: Option<bool>,
   }
   ```

### 兼容性考虑
- 添加字段是向后兼容的
- 平台特定字段（如 Unix 权限）需要条件编译
- 可考虑添加 `extended` 参数控制返回详细程度

### 与相关操作的关系
| 操作 | 返回信息 |
|------|----------|
| `fs/getMetadata` | 元数据（类型、时间戳） |
| `fs/readDirectory` | 目录条目列表（含类型） |
| `fs/readFile` | 文件内容 |
| `fs/writeFile` | 空（修改元数据） |

### 使用示例
```typescript
// TypeScript 使用示例
async function checkFileAge(path: string): Promise<string> {
  const response = await client.sendRequest('fs/getMetadata', { path });
  
  if (response.isDirectory) {
    return 'This is a directory';
  }
  
  const age = Date.now() - response.modifiedAtMs;
  const days = Math.floor(age / (1000 * 60 * 60 * 24));
  
  return `File modified ${days} days ago`;
}
```
