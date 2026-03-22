# fs_api.rs 研究文档

## 场景与职责

`fs_api.rs` 实现了文件系统相关的 JSON-RPC API，为客户端提供受控的文件系统访问能力。该模块作为 App Server 的文件系统操作接口，通过 `ExecutorFileSystem` trait 抽象底层文件系统实现，支持本地文件系统和潜在的远程文件系统。

## 功能点目的

### 1. 文件读写操作
- **read_file**: 读取文件内容，返回 Base64 编码的数据
- **write_file**: 写入 Base64 编码的数据到文件

### 2. 目录操作
- **create_directory**: 创建目录，支持递归创建
- **read_directory**: 读取目录内容，返回文件/目录条目列表

### 3. 元数据操作
- **get_metadata**: 获取文件或目录的元数据（类型、创建时间、修改时间）

### 4. 文件管理
- **remove**: 删除文件或目录，支持递归删除和强制删除
- **copy**: 复制文件或目录

## 具体技术实现

### 核心结构
```rust
#[derive(Clone)]
pub(crate) struct FsApi {
    file_system: Arc<dyn ExecutorFileSystem>,
}

impl Default for FsApi {
    fn default() -> Self {
        Self {
            file_system: Arc::new(Environment.get_filesystem()),
        }
    }
}
```

### API 方法详情

#### read_file
```rust
pub(crate) async fn read_file(
    &self,
    params: FsReadFileParams,
) -> Result<FsReadFileResponse, JSONRPCErrorError>
```
- 使用 `base64::STANDARD` 编码返回文件内容
- 错误通过 `map_fs_error` 映射

#### write_file
```rust
pub(crate) async fn write_file(
    &self,
    params: FsWriteFileParams,
) -> Result<FsWriteFileResponse, JSONRPCErrorError>
```
- 解码 Base64 输入数据，失败返回 `INVALID_REQUEST_ERROR_CODE`
- 写入文件系统

#### create_directory
```rust
pub(crate) async fn create_directory(
    &self,
    params: FsCreateDirectoryParams,
) -> Result<FsCreateDirectoryResponse, JSONRPCErrorError>
```
- `recursive` 参数默认为 `true`

#### get_metadata
```rust
pub(crate) async fn get_metadata(
    &self,
    params: FsGetMetadataParams,
) -> Result<FsGetMetadataResponse, JSONRPCErrorError>
```
- 返回 `is_directory`, `is_file`, `created_at_ms`, `modified_at_ms`

#### read_directory
```rust
pub(crate) async fn read_directory(
    &self,
    params: FsReadDirectoryParams,
) -> Result<FsReadDirectoryResponse, JSONRPCErrorError>
```
- 返回 `FsReadDirectoryEntry` 列表，包含文件名和类型信息

#### remove
```rust
pub(crate) async fn remove(
    &self,
    params: FsRemoveParams,
) -> Result<FsRemoveResponse, JSONRPCErrorError>
```
- `recursive` 默认为 `true`
- `force` 默认为 `true`（文件不存在时不报错）

#### copy
```rust
pub(crate) async fn copy(
    &self,
    params: FsCopyParams,
) -> Result<FsCopyResponse, JSONRPCErrorError>
```
- 支持递归复制

### 错误处理
```rust
fn invalid_request(message: impl Into<String>) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: message.into(),
        data: None,
    }
}

fn map_fs_error(err: io::Error) -> JSONRPCErrorError {
    if err.kind() == io::ErrorKind::InvalidInput {
        invalid_request(err.to_string())
    } else {
        JSONRPCErrorError {
            code: INTERNAL_ERROR_CODE,
            message: err.to_string(),
            data: None,
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/fs_api.rs`

### 协议层类型定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `FsReadFileParams`, `FsReadFileResponse`
  - `FsWriteFileParams`, `FsWriteFileResponse`
  - `FsCreateDirectoryParams`, `FsCreateDirectoryResponse`
  - `FsGetMetadataParams`, `FsGetMetadataResponse`
  - `FsReadDirectoryParams`, `FsReadDirectoryResponse`, `FsReadDirectoryEntry`
  - `FsRemoveParams`, `FsRemoveResponse`
  - `FsCopyParams`, `FsCopyResponse`

### 文件系统抽象
- `codex-rs/environment/src/fs.rs`: `ExecutorFileSystem` trait
- `codex-rs/environment/src/lib.rs`: `Environment` 类型

### 使用位置
- `codex-rs/app-server/src/message_processor.rs`: 通过 `FsApi` 处理客户端请求

## 依赖与外部交互

### 外部依赖
```rust
use codex_app_server_protocol::{FsCopyParams, FsCopyResponse, ...};
use codex_environment::{CopyOptions, CreateDirectoryOptions, Environment, ExecutorFileSystem, RemoveOptions};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
```

### ExecutorFileSystem Trait
```rust
#[async_trait]
pub trait ExecutorFileSystem: Send + Sync {
    async fn read_file(&self, path: &AbsolutePathBuf) -> FileSystemResult<Vec<u8>>;
    async fn write_file(&self, path: &AbsolutePathBuf, contents: Vec<u8>) -> FileSystemResult<()>;
    async fn create_directory(&self, path: &AbsolutePathBuf, options: CreateDirectoryOptions) -> FileSystemResult<()>;
    async fn get_metadata(&self, path: &AbsolutePathBuf) -> FileSystemResult<FileMetadata>;
    async fn read_directory(&self, path: &AbsolutePathBuf) -> FileSystemResult<Vec<ReadDirectoryEntry>>;
    async fn remove(&self, path: &AbsolutePathBuf, options: RemoveOptions) -> FileSystemResult<()>;
    async fn copy(&self, source_path: &AbsolutePathBuf, destination_path: &AbsolutePathBuf, options: CopyOptions) -> FileSystemResult<()>;
}
```

### LocalFileSystem 实现
- 基于 `tokio::fs` 的异步文件系统操作
- 文件大小限制：`MAX_READ_FILE_BYTES = 512 * 1024 * 1024` (512MB)

## 风险、边界与改进建议

### 当前风险
1. **无路径校验**: 未对 `params.path` 进行路径遍历攻击防护
2. **大文件处理**: 512MB 限制在 `LocalFileSystem` 中实现，但 `FsApi` 层无感知
3. **并发写入**: 无文件锁机制，并发写入可能导致数据损坏
4. **Base64 开销**: 大文件传输时 Base64 编码增加约 33% 的数据量

### 边界情况
1. **符号链接**: `LocalFileSystem` 使用 `symlink_metadata`，正确处理符号链接
2. **强制删除**: `force=true` 时，文件不存在返回成功，可能掩盖问题
3. **递归默认值**: 大多数操作默认递归，可能意外操作大量文件

### 改进建议
1. **路径安全**: 添加路径规范化，防止 `../` 等路径遍历攻击
2. **流式传输**: 大文件支持分片读写，避免内存压力
3. **校验和**: 添加文件校验和验证，确保传输完整性
4. **进度通知**: 大文件操作支持进度通知
5. **原子写入**: 文件写入使用临时文件+重命名，保证原子性
6. **配额限制**: 添加用户级存储配额检查和限制
