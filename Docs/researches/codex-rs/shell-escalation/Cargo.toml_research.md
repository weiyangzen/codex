# codex-rs/shell-escalation/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust crate `codex-shell-escalation` 的清单文件，定义了 crate 的元数据、依赖项、构建配置和二进制目标。该 crate 实现了 Unix 平台的 shell-escalation 协议，允许在沙箱环境中拦截和升级 execve 调用。

## 功能点目的

1. **Crate 元数据定义**: 指定名称、版本、许可证和 Rust 版本
2. **二进制目标配置**: 定义 `codex-execve-wrapper` 可执行文件
3. **依赖管理**: 声明运行时和开发依赖
4. **特性配置**: 配置 Tokio 等库的特性标志

## 具体技术实现

### 包元数据

```toml
[package]
edition.workspace = true      # 使用工作区统一的 Rust 版本
license.workspace = true       # 使用工作区统一的许可证
name = "codex-shell-escalation"  # Crate 名称（kebab-case）
version.workspace = true       # 使用工作区统一的版本
```

### 二进制目标

```toml
[[bin]]
name = "codex-execve-wrapper"
path = "src/bin/main_execve_wrapper.rs"
```

- **名称**: `codex-execve-wrapper` - 作为 execve 拦截的包装器
- **入口**: `src/bin/main_execve_wrapper.rs`
- **作用**: 接收被拦截的 execve 调用参数，通过 escalation socket 与 server 通信决定执行策略

### 运行时依赖分析

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理和传播 |
| `async-trait` | 异步 trait 支持（`EscalationPolicy`） |
| `clap` | 命令行参数解析（execve wrapper CLI） |
| `codex-protocol` | 协议类型定义（`EscalationPermissions` 等） |
| `codex-utils-absolute-path` | 绝对路径处理工具 |
| `libc` | Unix 系统调用（`execv`, `dup2`, `kill` 等） |
| `serde`/`serde_json` | 协议消息序列化 |
| `socket2` | 底层 socket 操作（SCM_RIGHTS fd 传递） |
| `tokio` | 异步运行时（多线程、进程、信号、网络） |
| `tokio-util` | Tokio 工具库 |
| `tracing`/`tracing-subscriber` | 日志和追踪 |

### Tokio 特性配置

```toml
tokio = { workspace = true, features = [
    "io-std",        # 标准输入输出异步支持
    "net",           # 网络支持（Unix socket）
    "macros",        # 异步宏
    "process",       # 进程管理
    "rt-multi-thread", # 多线程运行时
    "signal",        # 信号处理
    "time",          # 定时器
] }
```

### 开发依赖

- `pretty_assertions`: 测试断言美化
- `tempfile`: 临时文件/目录创建（测试用）

## 关键代码路径与文件引用

### 模块结构

```
shell-escalation/
├── Cargo.toml
├── src/
│   ├── lib.rs                    # 库入口，条件导出 Unix 模块
│   ├── bin/
│   │   └── main_execve_wrapper.rs  # 二进制入口
│   └── unix/
│       ├── mod.rs                # Unix 模块聚合
│       ├── escalate_protocol.rs  # 协议消息定义
│       ├── escalate_client.rs    # 客户端实现（wrapper）
│       ├── escalate_server.rs    # 服务端实现
│       ├── escalation_policy.rs  # 升级策略 trait
│       ├── execve_wrapper.rs     # wrapper CLI 入口
│       ├── socket.rs             # 异步 socket 实现
│       └── stopwatch.rs          # 计时器实现
```

### 调用关系

```
codex-execve-wrapper (binary)
└── main_execve_wrapper.rs
    └── run_shell_escalation_execve_wrapper() [escalate_client.rs]
        ├── EscalateRequest -> escalate_server
        └── 处理 EscalateResponse (Run/Escalate/Deny)

EscalateServer [escalate_server.rs]
├── start_session() -> EscalationSession
└── escalate_task() 处理并发请求
    └── handle_escalate_session_with_policy()
        └── EscalationPolicy::determine_action()
```

## 依赖与外部交互

### 协议依赖

- **codex-protocol**: 使用 `approvals::EscalationPermissions` 和 `Permissions` 类型
- 这些类型定义了权限升级时的沙箱配置

### 系统交互

- **Bash Patch**: 需要 patched bash 支持 `EXEC_WRAPPER` 环境变量
- **Unix Socket**: 使用 `SOCK_DGRAM` 和 `SOCK_STREAM` Unix domain socket
- **SCM_RIGHTS**: 通过辅助消息传递文件描述符

### 消费者

- **codex-core**: 通过 `codex_shell_escalation` 依赖使用此 crate
  - `unix_escalation.rs`: 实现 `CoreShellActionProvider`（`EscalationPolicy`）
  - `zsh_fork_backend.rs`: 集成到 shell 和 unified exec 运行时

## 风险、边界与改进建议

### 风险点

1. **平台限制**: 整个 crate 仅在 Unix 平台有效，`#[cfg(not(unix))]` 下导出空实现
2. **Bash 依赖**: 功能依赖 patched bash，标准 bash 无法使用
3. **FD 泄漏风险**: socket 和文件描述符传递需要小心管理生命周期

### 边界条件

1. **并发处理**: `escalate_task` 使用 `tokio::spawn` 处理并发请求，但每个请求独立
2. **超时控制**: `Stopwatch` 实现支持暂停/恢复，用于用户提示时不计入超时
3. **FD 数量限制**: `MAX_FDS_PER_MESSAGE = 16`，单次消息最多传递 16 个文件描述符

### 改进建议

1. **文档增强**: 在 Cargo.toml 中添加更详细的注释说明各依赖的用途
2. **特性门控**: 考虑添加可选特性，如 `tracing` 可以设为可选以减少 release 构建体积
3. **版本约束**: 考虑为关键依赖（如 `socket2`）添加更具体的版本约束
4. **测试配置**: 添加 `[[test]]` 配置以更好地控制测试执行

### 安全考虑

1. **环境变量过滤**: `escalate_client.rs` 中过滤了 `ESCALATE_SOCKET_ENV_VAR`、`EXEC_WRAPPER_ENV_VAR` 等敏感变量
2. **FD 验证**: 接收 FD 时验证数量匹配，防止 FD 劫持
3. **路径解析**: 使用 `AbsolutePathBuf` 确保路径安全解析
