# FsCopyResponse 调研文档

## 1. 场景与职责

### 使用场景
`FsCopyResponse` 是 Codex App-Server Protocol v2 中文件系统复制操作（`fs/copy`）的成功响应结构体。它表示复制操作已成功完成。

### 典型使用场景包括：
- **确认复制成功**：客户端收到响应表示文件/目录已复制
- **流程控制**：作为异步操作链的一环，确认复制完成后执行后续操作
- **错误处理区分**：空响应用于区分成功与失败（失败返回 JSON-RPC Error）

### 职责
- 表示 `fs/copy` 操作成功完成
- 提供类型安全的成功响应标识
- 遵循 v2 API 设计模式（空对象成功响应）

---

## 2. 功能点目的

### 核心功能
作为 `fs/copy` 请求的成功响应，确认复制操作已完成。

### 设计哲学
1. **简洁性**：空对象模式，无额外数据（操作结果可通过文件系统验证）
2. **一致性**：与其他 fs 操作（writeFile、createDirectory、remove）保持统一风格
3. **明确性**：空对象明确表示"成功且无额外信息"

### 为何是空响应？
- 复制操作的结果可以通过文件系统查询验证
- 减少不必要的网络传输
- 符合 JSON-RPC 2.0 规范的成功响应格式
- 失败情况通过 JSON-RPC Error 返回详细信息

---

## 3. 具体技术实现

### 数据结构定义（Rust）
```rust
/// Successful response for `fs/copy`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FsCopyResponse {}
```

### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Successful response for `fs/copy`.",
  "title": "FsCopyResponse",
  "type": "object"
}
```

### TypeScript 类型生成
```typescript
// 生成的 TypeScript 类型
export type FsCopyResponse = {};
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
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2263-2267)
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/FsCopyResponse.json`

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
    Ok(FsCopyResponse {})  // 返回空响应
}
```

### 响应生成流程
```rust
// 成功时
Ok(FsCopyResponse {})

// 序列化为 JSON
{"result": {}}
```

### 测试覆盖
- **测试文件**：`codex-rs/app-server/tests/suite/v2/fs.rs`
- 测试用例验证响应成功返回（通过读取响应消息确认）

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
文件系统复制操作成功
    ↓
FsApi::copy() 返回 Ok(FsCopyResponse {})
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

错误响应：
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32600,
    "message": "fs/copy requires recursive: true when sourcePath is a directory"
  }
}
```

---

## 6. 风险、边界与改进建议

### 当前限制
1. **无返回信息**：客户端无法从响应中获知复制的字节数或文件数
2. **无元数据**：不返回新文件的元数据（创建时间、大小等）
3. **无验证信息**：不确认目标路径的最终状态

### 边界情况
| 场景 | 响应行为 |
|------|----------|
| 复制成功 | 返回空对象 `{}` |
| 复制失败 | 返回 JSON-RPC Error |
| 部分成功（如某些文件失败） | 取决于底层实现，可能返回错误 |

### 改进建议

#### 短期改进
1. **添加版本字段**：为未来扩展预留空间
   ```rust
   pub struct FsCopyResponse {
       pub version: u32,  // 当前为 1
   }
   ```

#### 长期改进
2. **返回统计信息**：
   ```rust
   pub struct FsCopyResponse {
       pub files_copied: u64,
       pub bytes_copied: u64,
       pub directories_copied: u64,
   }
   ```

3. **返回目标元数据**：
   ```rust
   pub struct FsCopyResponse {
       pub destination_metadata: FsGetMetadataResponse,
   }
   ```

4. **支持部分成功**：
   ```rust
   pub struct FsCopyResponse {
       pub success: bool,
       pub copied_files: Vec<String>,
       pub failed_files: Vec<FailedCopy>,
   }
   ```

### 兼容性考虑
- 添加字段是向后兼容的（客户端可忽略未知字段）
- 当前空对象设计允许未来平滑扩展
- 如需重大变更，应通过 API 版本控制处理

### 替代方案评估
| 方案 | 优点 | 缺点 |
|------|------|------|
| 保持空对象 | 简单、一致 | 信息有限 |
| 返回目标路径 | 确认目标位置 | 客户端已知 |
| 返回元数据 | 减少后续查询 | 增加响应大小 |
| 返回统计信息 | 有用信息 | 计算开销 |
