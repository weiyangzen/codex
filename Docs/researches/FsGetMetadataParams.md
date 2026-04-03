# FsGetMetadataParams 调研文档

## 1. 场景与职责

### 使用场景
`FsGetMetadataParams` 是 Codex App-Server Protocol v2 中获取文件元数据操作（`fs/getMetadata`）的请求参数结构体。它用于查询文件或目录的元数据信息。

### 典型使用场景包括：
- **文件存在性检查**：在操作前确认文件是否存在
- **类型判断**：判断路径是文件还是目录
- **时间戳获取**：获取文件创建和修改时间
- **缓存验证**：比较修改时间判断缓存是否过期
- **同步检测**：检测文件是否被外部修改

### 职责
- 定义要查询的绝对路径
- 通过 `AbsolutePathBuf` 确保路径安全性

---

## 2. 功能点目的

### 核心功能
提供类型安全、结构化的方式来请求文件或目录的元数据。

### 设计目标
1. **安全性**：强制使用绝对路径，防止路径遍历攻击
2. **简洁性**：最小化参数，仅需要路径
3. **通用性**：同时支持文件和目录的元数据查询

### 字段说明
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `path` | `AbsolutePathBuf` | 是 | 要查询的绝对路径 |

---

## 3. 具体技术实现

### 数据结构定义（Rust）
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

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Request metadata for an absolute path.",
  "properties": {
    "path": {
      "allOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }],
      "description": "Absolute path to inspect."
    }
  },
  "required": ["path"],
  "title": "FsGetMetadataParams",
  "type": "object"
}
```

### TypeScript 类型生成
```typescript
export interface FsGetMetadataParams {
  path: string;
}
```

### 关键实现细节

#### AbsolutePathBuf 安全机制
- 使用 `codex_utils_absolute_path::AbsolutePathBuf` 类型
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard`）
- 支持 `~` 主目录展开（非 Windows 平台）

---

## 4. 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2171-2178)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsGetMetadataParams.json`

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

### 底层文件系统接口
- **接口定义**：`codex_environment::ExecutorFileSystem`
- **返回类型**：包含 `is_directory`, `is_file`, `created_at_ms`, `modified_at_ms`

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例：
  - `fs_get_metadata_returns_only_used_fields`：验证返回字段
  - `fs_methods_cover_current_fs_utils_surface`：基本元数据获取
  - `fs_methods_reject_relative_paths`：拒绝相对路径

---

## 5. 依赖与外部交互

### 依赖 crate
| crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts_rs` | TypeScript 类型生成 |
| `codex_utils_absolute_path` | 绝对路径类型 |
| `codex_environment` | 文件系统操作抽象 |

### 外部交互流程
```
客户端请求
    ↓
JSON-RPC 2.0 请求 (method: "fs/getMetadata")
    ↓
AbsolutePathBufGuard 设置基础路径
    ↓
FsGetMetadataParams 反序列化
    ↓
FsApi::get_metadata() 处理
    ↓
ExecutorFileSystem::get_metadata() 底层操作
    ↓
返回 FsGetMetadataResponse
```

### 错误处理
- **InvalidInput**：无效请求参数（如相对路径）
- **InternalError**：文件系统操作失败
- 常见错误场景：
  - 路径不存在
  - 权限不足（无法访问路径）

---

## 6. 风险、边界与改进建议

### 安全风险
1. **路径遍历**：已通过 `AbsolutePathBuf` 缓解
2. **信息泄露**：元数据可能泄露敏感信息（如文件存在性）
3. **时序攻击**：通过元数据查询时间差异推断文件存在性

### 边界情况
| 场景 | 行为 |
|------|------|
| 路径不存在 | 返回错误 |
| 路径是文件 | `isFile=true`, `isDirectory=false` |
| 路径是目录 | `isFile=false`, `isDirectory=true` |
| 路径是符号链接 | 跟随链接，返回目标元数据 |
| 路径是特殊文件（FIFO、设备等） | 取决于底层实现 |
| 时间戳不可用 | 返回 `0` |
| 相对路径 | 反序列化失败 |

### 改进建议

#### 短期改进
1. **添加跟随符号链接选项**：
   ```rust
   pub struct FsGetMetadataParams {
       pub path: AbsolutePathBuf,
       pub follow_symlinks: Option<bool>,  // 默认 true
   }
   ```

2. **批量查询**：支持一次查询多个路径
   ```rust
   pub struct FsGetMetadataParams {
       pub paths: Vec<AbsolutePathBuf>,
   }
   ```

#### 长期改进
3. **扩展元数据字段**：
   - 文件大小
   - 权限（Unix mode）
   - 所有者/组
   - 硬链接数
   - 访问时间

4. **添加元数据过滤器**：
   ```rust
   pub struct FsGetMetadataParams {
       pub path: AbsolutePathBuf,
       pub fields: Option<Vec<MetadataField>>,  // 只返回指定字段
   }
   ```

5. **支持通配符**：
   ```rust
   pub struct FsGetMetadataParams {
       pub pattern: String,  // 如 "/path/*.txt"
   }
   ```

### 兼容性考虑
- 添加可选字段是向后兼容的
- 扩展 `FsGetMetadataResponse` 字段需要客户端更新
- 可考虑添加 `fields` 参数控制返回字段

### 性能考虑
- 元数据查询通常很快（只需 stat 调用）
- 批量查询可减少 RPC 往返
- 缓存元数据可减少重复查询

### 与相关操作的关系
| 操作 | 用途 |
|------|------|
| `fs/getMetadata` | 获取单个路径元数据 |
| `fs/readDirectory` | 获取目录内容列表 |
| `fs/readFile` | 获取文件内容 |
| `fs/writeFile` | 修改文件内容（更新修改时间） |
