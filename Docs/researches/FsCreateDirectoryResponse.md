# FsCreateDirectoryResponse 调研文档

## 1. 场景与职责

### 使用场景
`FsCreateDirectoryResponse` 是 Codex App-Server Protocol v2 中创建目录操作（`fs/createDirectory`）的成功响应结构体。它表示目录创建操作已成功完成。

### 典型使用场景包括：
- **确认创建成功**：客户端收到响应表示目录已创建
- **流程控制**：作为异步操作链的一环，确认目录创建完成后执行后续操作
- **错误处理区分**：空响应用于区分成功与失败（失败返回 JSON-RPC Error）

### 职责
- 表示 `fs/createDirectory` 操作成功完成
- 提供类型安全的成功响应标识
- 遵循 v2 API 设计模式（空对象成功响应）

---

## 2. 功能点目的

### 核心功能
作为 `fs/createDirectory` 请求的成功响应，确认目录创建操作已完成。

### 设计哲学
1. **简洁性**：空对象模式，无额外数据
2. **一致性**：与其他 fs 操作（writeFile、remove、copy）保持统一风格
3. **明确性**：空对象明确表示"成功且无额外信息"

### 为何是空响应？
- 目录创建的结果可以通过文件系统查询验证（`fs/getMetadata`）
- 减少不必要的网络传输
- 符合 JSON-RPC 2.0 规范的成功响应格式
- 失败情况通过 JSON-RPC Error 返回详细信息

---

## 3. 具体技术实现

### 数据结构定义（Rust）
```rust
/// Successful response for `fs/createDirectory`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCreateDirectoryResponse {}
```

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Successful response for `fs/createDirectory`.",
  "title": "FsCreateDirectoryResponse",
  "type": "object"
}
```

### TypeScript 类型生成
```typescript
// 生成的 TypeScript 类型
export type FsCreateDirectoryResponse = {};
```

### 关键实现细节

#### 派生宏说明
- `Serialize`/`Deserialize`：serde 序列化支持
- `Debug`：调试输出
- `Clone`：可复制
- `PartialEq`/`Eq`：相等性比较
- `JsonSchema`：JSON Schema 生成
- `TS`：TypeScript 类型生成

#### 序列化行为
- 使用 `camelCase` 命名规范
- 空对象 `{}` 序列化结果

---

## 4. 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2165-2169)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsCreateDirectoryResponse.json`

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
    Ok(FsCreateDirectoryResponse {})  // 返回空响应
}
```

### 响应生成流程
```rust
// 成功时
Ok(FsCreateDirectoryResponse {})

// 序列化为 JSON
{"result": {}}
```

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例验证响应成功返回

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
文件系统创建操作成功
    ↓
FsApi::create_directory() 返回 Ok(FsCreateDirectoryResponse {})
    ↓
序列化为 JSON-RPC 2.0 响应
    ↓
{
  "jsonrpc": "2.0",
  "id": <request_id>,
  "result": {}
}
    ↓
客户端接收并解析
```

### 错误响应对比
成功响应：
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {}
}
```

错误响应（示例）：
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32603,
    "message": "Permission denied"
  }
}
```

---

## 6. 风险、边界与改进建议

### 当前限制
1. **无返回信息**：客户端无法从响应中获知实际创建的目录数（当 recursive=true 时）
2. **无元数据**：不返回新目录的元数据（创建时间、权限等）
3. **无验证信息**：不确认目录的最终状态

### 边界情况
| 场景 | 响应行为 |
|------|----------|
| 目录创建成功 | 返回空对象 `{}` |
| 目录已存在 | 返回空对象 `{}`（幂等） |
| 创建失败 | 返回 JSON-RPC Error |
| 部分创建（如某些父目录失败） | 取决于底层实现，可能返回错误 |

### 改进建议

#### 短期改进
1. **添加版本字段**：为未来扩展预留空间
   ```rust
   pub struct FsCreateDirectoryResponse {
       pub version: u32,  // 当前为 1
   }
   ```

#### 长期改进
2. **返回创建统计**：
   ```rust
   pub struct FsCreateDirectoryResponse {
       pub directories_created: u64,
       pub path: AbsolutePathBuf,
   }
   ```

3. **返回目录元数据**：
   ```rust
   pub struct FsCreateDirectoryResponse {
       pub metadata: FsGetMetadataResponse,
   }
   ```

4. **支持存在状态**：
   ```rust
   pub struct FsCreateDirectoryResponse {
       pub created: bool,  // true = 新创建, false = 已存在
   }
   ```

### 兼容性考虑
- 添加字段是向后兼容的（客户端可忽略未知字段）
- 当前空对象设计允许未来平滑扩展
- 如需重大变更，应通过 API 版本控制处理

### 与相关操作的关系
| 操作 | 响应类型 | 说明 |
|------|----------|------|
| `fs/createDirectory` | `FsCreateDirectoryResponse` | 空对象 |
| `fs/writeFile` | `FsWriteFileResponse` | 空对象 |
| `fs/remove` | `FsRemoveResponse` | 空对象 |
| `fs/copy` | `FsCopyResponse` | 空对象 |
| `fs/readFile` | `FsReadFileResponse` | 包含数据 |
| `fs/getMetadata` | `FsGetMetadataResponse` | 包含元数据 |
| `fs/readDirectory` | `FsReadDirectoryResponse` | 包含条目列表 |
