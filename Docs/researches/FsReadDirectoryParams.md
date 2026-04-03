# FsReadDirectoryParams 调研文档

## 1. 场景与职责

### 使用场景
`FsReadDirectoryParams` 是 Codex App-Server Protocol v2 中读取目录操作（`fs/readDirectory`）的请求参数结构体。它用于列出目录中的直接子项。

### 典型使用场景包括：
- **文件浏览器**：实现文件浏览器的目录列表功能
- **项目导航**：列出项目目录结构
- **批量处理**：获取目录内容以进行批量文件操作
- **路径补全**：实现路径自动补全功能
- **文件搜索**：在特定目录中搜索文件

### 职责
- 定义要读取的目录绝对路径
- 通过 `AbsolutePathBuf` 确保路径安全性
- 提供最小化的参数接口（仅路径）

---

## 2. 功能点目的

### 核心功能
提供类型安全、结构化的方式来请求目录内容列表。

### 设计目标
1. **安全性**：强制使用绝对路径，防止路径遍历攻击
2. **简洁性**：最小化参数，仅需要目录路径
3. **效率**：只返回直接子项，不递归

### 字段说明
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `path` | `AbsolutePathBuf` | 是 | 要读取的目录绝对路径 |

### 设计决策
- **不递归**：只返回直接子项，递归由客户端控制
- **无过滤**：返回所有子项，过滤由客户端处理
- **无排序**：返回顺序取决于文件系统，客户端可自行排序

---

## 3. 具体技术实现

### 数据结构定义（Rust）
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

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "List direct child names for a directory.",
  "properties": {
    "path": {
      "allOf": [{ "$ref": "#/definitions/AbsolutePathBuf" }],
      "description": "Absolute directory path to read."
    }
  },
  "required": ["path"],
  "title": "FsReadDirectoryParams",
  "type": "object"
}
```

### TypeScript 类型生成
```typescript
export interface FsReadDirectoryParams {
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
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2197-2204)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsReadDirectoryParams.json`

### 协议注册
- **ClientRequest 注册**：`codex-rs/app-server-protocol/src/protocol/common.rs` (行 327-330)
```rust
FsReadDirectory => "fs/readDirectory" {
    params: v2::FsReadDirectoryParams,
    response: v2::FsReadDirectoryResponse,
}
```

### 服务端实现
- **实现文件**：`codex-rs/app-server/src/fs_api.rs` (行 106-125)
```rust
pub(crate) async fn read_directory(
    &self,
    params: FsReadDirectoryParams,
) -> Result<FsReadDirectoryResponse, JSONRPCErrorError> {
    let entries = self
        .file_system
        .read_directory(&params.path)
        .await
        .map_err(map_fs_error)?;
    Ok(FsReadDirectoryResponse {
        entries: entries
            .into_iter()
            .map(|entry| FsReadDirectoryEntry {
                file_name: entry.file_name,
                is_directory: entry.is_directory,
                is_file: entry.is_file,
            })
            .collect(),
    })
}
```

### 底层文件系统接口
- **接口定义**：`codex_environment::ExecutorFileSystem`
- **返回类型**：`Vec<DirectoryEntry>`，包含 `file_name`, `is_directory`, `is_file`

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例：
  - `fs_methods_cover_current_fs_utils_surface`：基本目录读取
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
JSON-RPC 2.0 请求 (method: "fs/readDirectory")
    ↓
AbsolutePathBufGuard 设置基础路径
    ↓
FsReadDirectoryParams 反序列化
    ↓
FsApi::read_directory() 处理
    ↓
ExecutorFileSystem::read_directory() 底层操作
    ↓
返回 FsReadDirectoryResponse（条目列表）
```

### 错误处理
- **InvalidInput**：无效请求参数（如相对路径）
- **InternalError**：文件系统操作失败
- 常见错误场景：
  - 路径不存在
  - 路径不是目录
  - 权限不足（无法读取目录）

---

## 6. 风险、边界与改进建议

### 安全风险
1. **路径遍历**：已通过 `AbsolutePathBuf` 缓解
2. **目录遍历攻击**：无法通过 `..` 访问父目录
3. **信息泄露**：可能泄露目录存在性和内容
4. **DoS 攻击**：超大目录可能导致响应过大

### 边界情况
| 场景 | 行为 |
|------|------|
| 空目录 | 返回空数组 `[]` |
| 路径不存在 | 返回错误 |
| 路径是文件 | 返回错误 |
| 路径是符号链接 | 跟随链接，读取目标目录 |
| 权限不足 | 返回错误 |
| 相对路径 | 反序列化失败 |
| 超大目录 | 返回所有条目（可能很大） |

### 改进建议

#### 短期改进
1. **添加分页支持**：
   ```rust
   pub struct FsReadDirectoryParams {
       pub path: AbsolutePathBuf,
       pub cursor: Option<String>,  // 分页游标
       pub limit: Option<u32>,      // 每页条目数
   }
   ```

2. **添加过滤选项**：
   ```rust
   pub struct FsReadDirectoryParams {
       pub path: AbsolutePathBuf,
       pub pattern: Option<String>,  // 通配符过滤，如 "*.txt"
       pub include_hidden: Option<bool>,  // 是否包含隐藏文件
   }
   ```

3. **添加排序选项**：
   ```rust
   pub enum SortBy {
       Name,
       ModifiedTime,
       CreatedTime,
   }
   
   pub struct FsReadDirectoryParams {
       pub path: AbsolutePathBuf,
       pub sort_by: Option<SortBy>,
       pub sort_descending: Option<bool>,
   }
   ```

#### 长期改进
4. **递归读取**：
   ```rust
   pub struct FsReadDirectoryParams {
       pub path: AbsolutePathBuf,
       pub recursive: Option<bool>,      // 递归读取
       pub max_depth: Option<u32>,       // 最大递归深度
   }
   ```

5. **包含元数据**：
   ```rust
   pub struct FsReadDirectoryParams {
       pub path: AbsolutePathBuf,
       pub include_metadata: Option<bool>,  // 同时返回每个条目的元数据
   }
   ```

6. **流式响应**：
   - 对于超大目录，使用流式响应分批返回条目
   - 减少内存占用和网络传输延迟

### 兼容性考虑
- 添加可选字段是向后兼容的
- 分页支持需要客户端适配
- 默认行为应保持不变

### 性能考虑
- 目录读取通常很快
- 超大目录可能导致性能问题
- 建议添加分页或限制条目数

### 与相关操作的关系
| 操作 | 用途 |
|------|------|
| `fs/readDirectory` | 列出目录内容 |
| `fs/getMetadata` | 获取单个路径元数据 |
| `fs/readFile` | 读取文件内容 |
| `fuzzyFileSearch` | 模糊搜索文件 |

### 使用示例
```typescript
// TypeScript 使用示例
async function listFiles(dirPath: string): Promise<void> {
  const response = await client.sendRequest('fs/readDirectory', { path: dirPath });
  
  for (const entry of response.entries) {
    const icon = entry.isDirectory ? '📁' : '📄';
    console.log(`${icon} ${entry.fileName}`);
  }
}
```
