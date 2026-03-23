# escalate_protocol.rs 研究文档

## 场景与职责

`escalate_protocol.rs` 是 Unix 平台 shell 权限提升机制的**协议定义层**，负责定义客户端与服务器之间通信的数据结构、枚举类型和环境变量常量。它是整个权限提升系统的契约基础，确保客户端（execve 包装器）和服务器（权限提升服务）之间的数据交换格式一致。

核心职责：
1. 定义环境变量常量（socket FD、包装器路径）
2. 定义请求/响应数据结构（`EscalateRequest`, `EscalateResponse`）
3. 定义权限提升决策枚举（`EscalationDecision`, `EscalationExecution`）
4. 定义序列化消息类型（`EscalateAction`, `SuperExecMessage`, `SuperExecResult`）
5. 提供决策类型的便捷构造方法

## 功能点目的

### 1. 环境变量常量

```rust
pub const ESCALATE_SOCKET_ENV_VAR: &str = "CODEX_ESCALATE_SOCKET";
pub const EXEC_WRAPPER_ENV_VAR: &str = "EXEC_WRAPPER";
pub const LEGACY_BASH_EXEC_WRAPPER_ENV_VAR: &str = "BASH_EXEC_WRAPPER";
```

- `CODEX_ESCALATE_SOCKET`：execve 包装器通过此环境变量获取与服务器通信的 socket FD
- `EXEC_WRAPPER`：打补丁的 shell 使用此变量找到 execve 包装器二进制文件
- `BASH_EXEC_WRAPPER`：兼容旧版打补丁的 bash 构建的别名

### 2. 请求/响应结构

**EscalateRequest**（客户端 → 服务器）：
```rust
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径（可能相对）
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf,// 工作目录（绝对路径）
    pub env: HashMap<String, String>, // 环境变量快照
}
```

**EscalateResponse**（服务器 → 客户端）：
```rust
pub struct EscalateResponse {
    pub action: EscalateAction,
}
```

### 3. 决策类型

**EscalationDecision**（服务器内部决策）：
```rust
pub enum EscalationDecision {
    Run,                                    // 本地执行
    Escalate(EscalationExecution),         // 提升权限执行
    Deny { reason: Option<String> },       // 拒绝执行
}
```

**EscalationExecution**（提升权限的执行方式）：
```rust
pub enum EscalationExecution {
    Unsandboxed,                           // 无沙箱执行
    TurnDefault,                           // 使用当前 turn 的沙箱配置
    Permissions(EscalationPermissions),    // 使用显式权限配置
}
```

### 4. 序列化消息类型

**EscalateAction**（网络传输的响应动作）：
```rust
pub enum EscalateAction {
    Run,                                   // 客户端本地执行
    Escalate,                              // 提升权限到服务器执行
    Deny { reason: Option<String> },       // 拒绝执行
}
```

**SuperExecMessage**（传递文件描述符）：
```rust
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,  // 目标 FD 编号（通常是 0,1,2）
}
```

**SuperExecResult**（执行结果）：
```rust
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

## 具体技术实现

### 序列化方案

所有消息类型使用 `serde` 进行序列化：
- `EscalateRequest`：`Serialize + Deserialize`
- `EscalateResponse`：`Serialize + Deserialize`
- `EscalateAction`：`Serialize + Deserialize`
- `SuperExecMessage`：`Serialize + Deserialize`
- `SuperExecResult`：`Serialize + Deserialize`

**注意**：`EscalationDecision` 和 `EscalationExecution` **没有**实现 `Serialize/Deserialize`，它们是服务器内部使用的类型，不直接在网络上传输。服务器将内部决策转换为 `EscalateAction` 后序列化发送。

### 决策构造方法

```rust
impl EscalationDecision {
    pub fn run() -> Self { Self::Run }
    pub fn escalate(execution: EscalationExecution) -> Self { Self::Escalate(execution) }
    pub fn deny(reason: Option<String>) -> Self { Self::Deny { reason } }
}
```

提供便捷的构造方法，使服务器代码更简洁：
```rust
// 而不是
EscalationDecision::Run
// 可以写
EscalationDecision::run()
```

### 外部类型依赖

```rust
use codex_protocol::approvals::EscalationPermissions;
use codex_utils_absolute_path::AbsolutePathBuf;
```

- `EscalationPermissions`：来自 `codex-protocol` crate，定义权限提升的权限配置
- `AbsolutePathBuf`：来自 `codex-utils-absolute-path` crate，保证路径为绝对路径

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 10-17 | 环境变量常量定义 | `ESCALATE_SOCKET_ENV_VAR`, `EXEC_WRAPPER_ENV_VAR`, `LEGACY_BASH_EXEC_WRAPPER_ENV_VAR` |
| 19-31 | `EscalateRequest` | 请求结构定义 |
| 33-37 | `EscalateResponse` | 响应结构定义 |
| 39-55 | `EscalationDecision`, `EscalationExecution` | 内部决策枚举 |
| 57-69 | `EscalationDecision` 构造方法 | `run()`, `escalate()`, `deny()` |
| 71-79 | `EscalateAction` | 可序列化的响应动作枚举 |
| 81-85 | `SuperExecMessage` | FD 传递消息 |
| 87-91 | `SuperExecResult` | 执行结果 |

### 依赖文件

- `codex-rs/protocol/src/approvals.rs`：`EscalationPermissions` 定义
- `codex-rs/utils/absolute-path/src/lib.rs`：`AbsolutePathBuf` 定义

### 被依赖文件

| 文件 | 用途 |
|------|------|
| `escalate_client.rs` | 使用 `EscalateRequest`, `EscalateResponse`, `SuperExecMessage`, `SuperExecResult`, 环境变量常量 |
| `escalate_server.rs` | 使用所有协议类型 |
| `escalation_policy.rs` | 使用 `EscalationDecision` |
| `mod.rs` | 重新导出所有公共类型 |
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` | 使用 `EscalationDecision`, `EscalationExecution`, `EscalationPermissions` |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `std::collections::HashMap` | 环境变量存储 |
| `std::os::fd::RawFd` | 文件描述符类型 |
| `std::path::PathBuf` | 文件路径 |
| `codex_protocol::approvals::EscalationPermissions` | 权限配置 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径 |
| `serde::Deserialize` | 反序列化 |
| `serde::Serialize` | 序列化 |

### 类型系统关系

```
EscalationDecision (内部)
    ├── Run
    ├── Escalate(EscalationExecution)
    │       ├── Unsandboxed
    │       ├── TurnDefault
    │       └── Permissions(EscalationPermissions)
    └── Deny { reason }

EscalateAction (可序列化)
    ├── Run
    ├── Escalate
    └── Deny { reason }

转换关系：
EscalationDecision::Run → EscalateAction::Run
EscalationDecision::Escalate(_) → EscalateAction::Escalate
EscalationDecision::Deny { reason } → EscalateAction::Deny { reason }
```

## 风险、边界与改进建议

### 已知风险

1. **类型分离的维护成本**：`EscalationDecision` 和 `EscalateAction` 几乎相同，但一个用于内部、一个用于网络传输。这种分离是有意为之（内部决策包含更多执行细节），但需要维护两个相似类型。

2. **大枚举变体**：`#[allow(clippy::large_enum_variant)]` 注释表明 `EscalationExecution` 的 `Permissions` 变体可能较大，但为了避免 Box 分配的开销，允许此警告。

### 边界情况

1. **相对路径处理**：`EscalateRequest.file` 可以是相对路径，服务器需要使用 `workdir` 解析为绝对路径

2. **环境变量大小**：`EscalateRequest.env` 包含完整环境变量快照，如果环境变量很大，可能导致消息过大

3. **FD 数量限制**：`SuperExecMessage.fds` 是 `Vec<RawFd>`，理论上可以传递任意数量，但底层 socket 实现有 `MAX_FDS_PER_MESSAGE` 限制（在 `socket.rs` 中定义为 16）

### 改进建议

1. **文档完善**：为 `EscalateRequest.file` 的相对路径行为添加更多文档

2. **验证增强**：可以为 `EscalateRequest` 添加验证方法，检查 `argv` 非空（至少包含 argv[0]）

3. **性能优化**：如果环境变量很大，可以考虑只传递差异或必要的环境变量

4. **类型安全**：考虑使用 `newtype` 模式包装 `RawFd`，防止 FD 编号的混淆

5. **版本协商**：协议目前没有版本号，未来如果需要不兼容的变更，需要添加版本协商机制

### 测试覆盖

本文件没有直接包含测试，测试分布在：
- `escalate_client.rs`：客户端协议交互测试
- `escalate_server.rs`：服务器端协议处理测试
- `socket.rs`：底层 socket 消息传输测试
