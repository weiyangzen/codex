# errors.rs 深度研究文档

## 场景与职责

`errors.rs` 定义了 Unified Exec 模块的错误类型 `UnifiedExecError`，统一处理进程执行各阶段的失败场景，为调用方提供结构化的错误信息。

## 功能点目的

### 错误类型设计

| 错误变体 | 场景 | 用户可见信息 |
|---------|------|-------------|
| `CreateProcess` | PTY/进程创建失败 | "Failed to create unified exec process: {message}" |
| `UnknownProcessId` | 操作不存在的进程 | "Unknown process id {process_id}" |
| `WriteToStdin` | 写入 stdin 失败 | "failed to write to stdin" |
| `StdinClosed` | 向已关闭 stdin 写入 | 提示使用 `tty=true` 重新运行 |
| `MissingCommandLine` | 命令行为空 | "missing command line for unified exec request" |
| `SandboxDenied` | 沙箱拒绝执行 | 包含详细原因和输出片段 |

### 辅助方法

```rust
impl UnifiedExecError {
    // 便捷构造 CreateProcess 错误
    pub(crate) fn create_process(message: String) -> Self
    
    // 便捷构造 SandboxDenied 错误，包含 ExecToolCallOutput 上下文
    pub(crate) fn sandbox_denied(message: String, output: ExecToolCallOutput) -> Self
}
```

## 具体技术实现

### 错误类型定义

```rust
#[derive(Debug, Error)]
pub(crate) enum UnifiedExecError {
    #[error("Failed to create unified exec process: {message}")]
    CreateProcess { message: String },
    
    #[error("Unknown process id {process_id}")]  // 注意：对外显示 session_id
    UnknownProcessId { process_id: i32 },
    
    #[error("failed to write to stdin")]
    WriteToStdin,
    
    #[error("stdin is closed for this session; rerun exec_command with tty=true to keep stdin open")]
    StdinClosed,
    
    #[error("missing command line for unified exec request")]
    MissingCommandLine,
    
    #[error("Command denied by sandbox: {message}")]
    SandboxDenied {
        message: String,
        output: ExecToolCallOutput,  // 包含 exit_code、stdout、stderr
    },
}
```

### 关键设计决策

1. **session_id vs process_id**：注释说明模型训练使用 `session_id`，但内部使用 `process_id`，保持术语一致性
2. **SandboxDenied 包含完整输出**：便于调用方分析拒绝原因，支持自动重试策略
3. **thiserror 派生**：自动实现 `Display` 和 `Error` trait

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `thiserror::Error` | 错误类型派生宏 |
| `ExecToolCallOutput` | 沙箱拒绝时携带的执行结果上下文 |

### 使用场景

```rust
// process.rs: 进程创建失败
UnifiedExecError::create_process(err.to_string())

// process.rs: 检测到沙箱拒绝
UnifiedExecError::sandbox_denied(message, exec_output)

// process_manager.rs: 写入已关闭进程
UnifiedExecError::UnknownProcessId { process_id }

// process_manager.rs: 非 TTY 模式写入 stdin
UnifiedExecError::StdinClosed
```

## 风险、边界与改进建议

### 当前局限

1. **错误分类粒度**：`CreateProcess` 过于笼统，无法区分权限不足、命令不存在、资源不足等
2. **无错误链**：丢失底层错误上下文（如 `std::io::Error`）
3. **国际化**：错误消息硬编码为英文

### 改进建议

1. **细化 CreateProcess**：
   ```rust
   pub(crate) enum CreateProcessError {
       PermissionDenied { path: PathBuf },
       NotFound { path: PathBuf },
       Io { source: std::io::Error },
   }
   ```

2. **保留错误链**：
   ```rust
   #[error("failed to create process")]
   CreateProcess {
       #[source]
       source: Box<dyn std::error::Error + Send + Sync>,
   }
   ```

3. **添加错误代码**：便于程序化判断错误类型，而非依赖字符串匹配
