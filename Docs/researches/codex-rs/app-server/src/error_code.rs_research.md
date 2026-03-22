# error_code.rs 研究文档

## 场景与职责

`error_code.rs` 是 Codex App Server 中的错误码定义模块，负责定义 JSON-RPC 协议层面的标准错误码和业务特定的错误标识。该模块作为整个 App Server 错误处理的基础，为各类 API 错误响应提供统一的错误码常量。

## 功能点目的

### 1. JSON-RPC 标准错误码
遵循 JSON-RPC 2.0 规范定义标准错误码：
- `INVALID_REQUEST_ERROR_CODE` (-32600): 请求格式无效或解析失败
- `INVALID_PARAMS_ERROR_CODE` (-32602): 请求参数无效
- `INTERNAL_ERROR_CODE` (-32603): 服务器内部错误

### 2. 业务特定错误码
- `OVERLOADED_ERROR_CODE` (-32001): 服务器过载，属于 JSON-RPC 规范预留的自定义错误码范围
- `INPUT_TOO_LARGE_ERROR_CODE` ("input_too_large"): 输入数据过大，用于文件读取等场景的大小限制提示

## 具体技术实现

### 数据结构
```rust
pub(crate) const INVALID_REQUEST_ERROR_CODE: i64 = -32600;
pub const INVALID_PARAMS_ERROR_CODE: i64 = -32602;
pub(crate) const INTERNAL_ERROR_CODE: i64 = -32603;
pub(crate) const OVERLOADED_ERROR_CODE: i64 = -32001;
pub const INPUT_TOO_LARGE_ERROR_CODE: &str = "input_too_large";
```

### 可见性设计
- `pub(crate)`: 仅限 crate 内部使用（如 `INVALID_REQUEST_ERROR_CODE`）
- `pub`: 对外公开，供其他 crate 使用（如 `INVALID_PARAMS_ERROR_CODE`、`INPUT_TOO_LARGE_ERROR_CODE`）

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/error_code.rs`

### 使用位置
| 文件 | 使用方式 |
|------|----------|
| `fs_api.rs` | `INTERNAL_ERROR_CODE`, `INVALID_REQUEST_ERROR_CODE` |
| `external_agent_config_api.rs` | `INTERNAL_ERROR_CODE` |
| `outgoing_message.rs` | `INTERNAL_ERROR_CODE` |
| `transport.rs` | `INVALID_REQUEST_ERROR_CODE` |
| `bespoke_event_handling.rs` | `INVALID_PARAMS_ERROR_CODE` |
| `in_process.rs` | `INVALID_PARAMS_ERROR_CODE` |
| `message_processor.rs` | `INVALID_REQUEST_ERROR_CODE` |
| `codex_message_processor.rs` | `INTERNAL_ERROR_CODE`, `INVALID_PARAMS_ERROR_CODE`, `INPUT_TOO_LARGE_ERROR_CODE` |
| `command_exec.rs` | `INTERNAL_ERROR_CODE` |
| `config_api.rs` | `INTERNAL_ERROR_CODE`, `INVALID_REQUEST_ERROR_CODE` |

### 导出位置
- `lib.rs` 中重新导出：`pub use crate::error_code::INPUT_TOO_LARGE_ERROR_CODE;`
- `lib.rs` 中重新导出：`pub use crate::error_code::INVALID_PARAMS_ERROR_CODE;`

## 依赖与外部交互

### 协议层依赖
- 与 `codex_app_server_protocol::JSONRPCErrorError` 配合使用
- 错误码通过 `JSONRPCErrorError { code, message, data }` 结构传递给客户端

### 核心层依赖
- 被 `codex_core` 的多个模块通过 App Server 的公开导出使用

## 风险、边界与改进建议

### 当前风险
1. **混合错误码类型**: `INPUT_TOO_LARGE_ERROR_CODE` 使用字符串类型，与其他整数错误码不一致，可能导致类型混淆
2. **错误码分散**: 部分错误码定义在其他模块（如 `server_request_error.rs`），缺乏统一的管理中心

### 边界情况
1. JSON-RPC 规范预留了 -32768 到 -32000 的错误码范围供自定义使用，当前使用符合规范
2. `OVERLOADED_ERROR_CODE` (-32001) 位于规范推荐的自定义范围内

### 改进建议
1. **统一错误码类型**: 考虑将所有错误码统一为整数类型，或使用枚举封装
2. **添加文档注释**: 为每个错误码添加 Rustdoc 注释，说明使用场景和触发条件
3. **错误码分类**: 考虑按模块或功能分类组织错误码，如 `FS_ERROR_*`, `AUTH_ERROR_*` 等
4. **国际化支持**: 如未来需要多语言支持，错误码应关联可本地化的消息模板
