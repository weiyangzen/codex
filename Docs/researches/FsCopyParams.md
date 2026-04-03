# FsCopyParams 调研文档

## 1. 场景与职责

### 使用场景
`FsCopyParams` 是 Codex App-Server Protocol v2 中文件系统复制操作（`fs/copy`）的请求参数结构体。它用于在主机文件系统上复制文件或整个目录树。

### 典型使用场景包括：
- **文件备份**：将重要文件复制到备份位置
- **项目模板复制**：复制项目模板以创建新项目
- **文件迁移**：将文件从一个位置迁移到另一个位置
- **目录结构克隆**：递归复制整个目录树（如 node_modules、配置目录等）

### 职责
- 定义复制操作所需的源路径和目标路径
- 控制是否递归复制目录内容
- 通过 `AbsolutePathBuf` 确保路径安全性（只允许绝对路径）

---

## 2. 功能点目的

### 核心功能
提供类型安全、结构化的方式来请求文件系统复制操作。

### 设计目标
1. **安全性**：强制使用绝对路径，防止路径遍历攻击
2. **灵活性**：支持文件和目录复制
3. **可控性**：通过 `recursive` 参数明确控制目录复制行为

### 字段说明
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `sourcePath` | `AbsolutePathBuf` | 是 | 源文件或目录的绝对路径 |
| `destinationPath` | `AbsolutePathBuf` | 是 | 目标位置的绝对路径 |
| `recursive` | `bool` | 否 | 复制目录时必需；复制文件时忽略 |

---

## 3. 具体技术实现

### 数据结构定义（Rust）
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCopyParams {
    /// Absolute source path.
    pub source_path: AbsolutePathBuf,
    /// Absolute destination path.
    pub destination_path: AbsolutePathBuf,
    /// Required for directory copies; ignored for file copies.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub recursive: bool,
}
```

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Copy a file or directory tree on the host filesystem.",
  "properties": {
    "destinationPath": {
      "allOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }],
      "description": "Absolute destination path."
    },
    "recursive": {
      "description": "Required for directory copies; ignored for file copies.",
      "type": "boolean"
    },
    "sourcePath": {
      "allOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }],
      "description": "Absolute source path."
    }
  },
  "required": ["destinationPath", "sourcePath"],
  "title": "FsCopyParams",
  "type": "object"
}
```

### 关键实现细节

#### AbsolutePathBuf 安全机制
- 使用 `codex_utils_absolute_path::AbsolutePathBuf` 类型
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard`）
- 支持 `~` 主目录展开（非 Windows 平台）

#### 序列化行为
- 使用 `camelCase` 命名规范（`sourcePath`, `destinationPath`）
- `recursive` 字段使用 `skip_serializing_if = "std::ops::Not::not"`，仅在 `true` 时序列化

---

## 4. 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2250-2261)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsCopyParams.json`

### 协议注册
- **ClientRequest 注册**：`codex-rs/app-server-protocol/src/protocol/common.rs` (行 335-338)
```rust
FsCopy => "fs/copy" {
    params: v2::FsCopyParams,
    response: v2::FsCopyResponse,
}
```

### 服务端实现
- **实现文件**：`codex-rs/app-server/src/fs_api.rs` (行 144-159)
```rust
pub(crate) async fn copy(
    &self,
    params: FsCopyParams,
) -> Result<FsCopyResponse, JSONRPCErrorError> {
    self.file_system
        .copy(
            &params.source_path,
            &params.destination_path,
            CopyOptions {
                recursive: params.recursive,
            },
        )
        .await
        .map_err(map_fs_error)?;
    Ok(FsCopyResponse {})
}
```

### 底层文件系统接口
- **接口定义**：`codex_environment::ExecutorFileSystem`
- **CopyOptions**：`codex_environment::CopyOptions` { recursive: bool }

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例：
  - `fs_methods_cover_current_fs_utils_surface`：基本复制功能
  - `fs_copy_rejects_directory_without_recursive`：目录复制必须设置 recursive
  - `fs_copy_rejects_copying_directory_into_descendant`：防止循环复制
  - `fs_copy_preserves_symlinks_in_recursive_copy`：符号链接保留（Unix）
  - `fs_copy_ignores_unknown_special_files_in_recursive_copy`：特殊文件处理
  - `fs_copy_rejects_standalone_fifo_source`：FIFO 文件拒绝

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
JSON-RPC 2.0 请求 (method: "fs/copy")
    ↓
AbsolutePathBufGuard 设置基础路径
    ↓
FsCopyParams 反序列化
    ↓
FsApi::copy() 处理
    ↓
ExecutorFileSystem::copy() 底层操作
    ↓
文件系统实际复制
```

### 错误处理
- **InvalidInput**：无效请求参数（如相对路径）
- **InternalError**：文件系统操作失败
- 特定错误消息：
  - "fs/copy requires recursive: true when sourcePath is a directory"
  - "fs/copy cannot copy a directory to itself or one of its descendants"
  - "fs/copy only supports regular files, directories, and symlinks"

---

## 6. 风险、边界与改进建议

### 安全风险
1. **路径遍历**：已通过 `AbsolutePathBuf` 缓解，但仍需确保基础路径设置正确
2. **循环复制**：已实现检测（目录不能复制到自身或其子目录）
3. **符号链接攻击**：递归复制时保留符号链接，但需确保不跟随恶意链接

### 边界情况
| 场景 | 行为 |
|------|------|
| 源路径不存在 | 返回文件系统错误 |
| 目标路径已存在 | 覆盖（取决于底层实现） |
| 复制目录时 recursive=false | 返回错误 |
| 复制到自身子目录 | 返回错误 |
| FIFO/特殊文件作为源 | 返回错误（仅支持普通文件、目录、符号链接） |
| 相对路径 | 反序列化失败 |

### 改进建议
1. **原子性**：考虑添加原子复制选项，确保操作要么完全成功要么完全失败
2. **进度报告**：大文件/目录复制时支持进度通知
3. **保留元数据**：添加选项控制是否保留权限、时间戳等元数据
4. **冲突处理**：添加 `overwrite` 参数明确控制覆盖行为
5. **批量复制**：支持多文件/目录批量复制，减少 RPC 往返

### 测试建议
- 添加大文件复制性能测试
- 添加跨文件系统复制测试
- 添加权限不足场景测试
- 添加并发复制测试
