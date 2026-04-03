# FsCreateDirectoryParams 调研文档

## 1. 场景与职责

### 使用场景
`FsCreateDirectoryParams` 是 Codex App-Server Protocol v2 中创建目录操作（`fs/createDirectory`）的请求参数结构体。它用于在主机文件系统上创建单个目录或目录树。

### 典型使用场景包括：
- **项目初始化**：创建项目目录结构
- **缓存目录创建**：创建临时/缓存目录
- **配置文件目录**：创建应用配置目录（如 `~/.config/app`）
- **嵌套目录创建**：一次性创建多级目录（如 `a/b/c/d`）

### 职责
- 定义创建目录的目标路径
- 控制是否递归创建父目录
- 通过 `AbsolutePathBuf` 确保路径安全性

---

## 2. 功能点目的

### 核心功能
提供类型安全、结构化的方式来请求目录创建操作。

### 设计目标
1. **安全性**：强制使用绝对路径，防止路径遍历攻击
2. **便利性**：支持递归创建，简化多级目录创建
3. **灵活性**：`recursive` 参数可选，默认行为合理

### 字段说明
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `path` | `AbsolutePathBuf` | 是 | 要创建的目录绝对路径 |
| `recursive` | `Option<bool>` | 否 | 是否递归创建父目录，默认为 `true` |

### 默认值设计
- `recursive` 默认为 `true`：这是最常见需求，减少调用方负担
- 如需严格单级创建，需显式设置 `recursive: false`

---

## 3. 具体技术实现

### 数据结构定义（Rust）
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

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Create a directory on the host filesystem.",
  "properties": {
    "path": {
      "allOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }],
      "description": "Absolute directory path to create."
    },
    "recursive": {
      "description": "Whether parent directories should also be created. Defaults to `true`.",
      "type": ["boolean", "null"]
    }
  },
  "required": ["path"],
  "title": "FsCreateDirectoryParams",
  "type": "object"
}
```

### 关键实现细节

#### TypeScript 可选参数
```typescript
export interface FsCreateDirectoryParams {
  path: string;
  recursive?: boolean | null;
}
```

#### 默认值处理（服务端）
```rust
CreateDirectoryOptions {
    recursive: params.recursive.unwrap_or(true),
}
```

---

## 4. 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2153-2163)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsCreateDirectoryParams.json`

### 协议注册
- **ClientRequest 注册**：`codex-rs/app-server-protocol/src/protocol/common.rs` (行 319-322)
```rust
FsCreateDirectory => "fs/createDirectory" {
    params: v2::FsCreateDirectoryParams,
    response: v2::FsCreateDirectoryResponse,
}
```

### 服务端实现
- **实现文件**：`codex-rs/app-server/src/fs_api.rs` (行 73-87)
```rust
pub(crate) async fn create_directory(
    &self,
    params: FsCreateDirectoryParams,
) -> Result<FsCreateDirectoryResponse, JSONRPCErrorError> {
    self.file_system
        .create_directory(
            &params.path,
            CreateDirectoryOptions {
                recursive: params.recursive.unwrap_or(true),
            },
        )
        .await
        .map_err(map_fs_error)?;
    Ok(FsCreateDirectoryResponse {})
}
```

### 底层文件系统接口
- **接口定义**：`codex_environment::ExecutorFileSystem`
- **CreateDirectoryOptions**：`codex_environment::CreateDirectoryOptions` { recursive: bool }

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例：
  - `fs_methods_cover_current_fs_utils_surface`：基本目录创建
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
JSON-RPC 2.0 请求 (method: "fs/createDirectory")
    ↓
AbsolutePathBufGuard 设置基础路径
    ↓
FsCreateDirectoryParams 反序列化
    ↓
FsApi::create_directory() 处理
    ↓
recursive.unwrap_or(true) 应用默认值
    ↓
ExecutorFileSystem::create_directory() 底层操作
    ↓
文件系统实际创建
```

### 错误处理
- **InvalidInput**：无效请求参数（如相对路径）
- **InternalError**：文件系统操作失败
- 常见错误场景：
  - 父目录不存在（当 recursive=false）
  - 权限不足
  - 路径已存在且为文件

---

## 6. 风险、边界与改进建议

### 安全风险
1. **路径遍历**：已通过 `AbsolutePathBuf` 缓解
2. **目录轰炸**：递归创建可能创建大量嵌套目录
3. **权限提升**：在敏感位置创建目录（如 `/etc`、`C:\Windows`）

### 边界情况
| 场景 | 行为 |
|------|------|
| 目录已存在 | 通常成功（幂等） |
| 路径已存在且为文件 | 返回错误 |
| 父目录不存在 + recursive=false | 返回错误 |
| 父目录不存在 + recursive=true | 递归创建所有父目录 |
| 权限不足 | 返回错误 |
| 相对路径 | 反序列化失败 |
| 磁盘已满 | 返回错误 |

### 改进建议

#### 短期改进
1. **添加模式参数**：支持设置目录权限（Unix）
   ```rust
   pub struct FsCreateDirectoryParams {
       pub path: AbsolutePathBuf,
       pub recursive: Option<bool>,
       pub mode: Option<u32>,  // Unix 权限模式
   }
   ```

2. **添加存在处理选项**：
   ```rust
   pub enum IfExists {
       Error,    // 默认，返回错误
       Ignore,   // 忽略，视为成功
       Update,   // 更新时间戳
   }
   ```

#### 长期改进
3. **批量创建**：支持一次创建多个目录
   ```rust
   pub struct FsCreateDirectoryParams {
       pub paths: Vec<AbsolutePathBuf>,
       pub recursive: Option<bool>,
   }
   ```

4. **模板创建**：支持从模板创建目录结构
   ```rust
   pub struct FsCreateDirectoryParams {
       pub path: AbsolutePathBuf,
       pub template: Option<String>,  // 预定义模板名称
   }
   ```

### 兼容性考虑
- 添加可选字段是向后兼容的
- 默认值 `recursive: true` 符合大多数使用场景
- 如需改变默认值，应通过 API 版本控制

### 最佳实践
1. 明确设置 `recursive` 参数以提高代码可读性
2. 创建后验证目录存在（通过 `fs/getMetadata`）
3. 处理可能的权限错误，提供用户友好的错误消息
