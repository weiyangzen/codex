# README.md 研究文档

## 场景与职责

`README.md` 是 `codex-utils-pty` crate 的公共 API 文档，面向使用该库的开发者。它提供了：
- 高层功能概述
- 完整的公共 API 列表
- 使用示例代码
- 测试运行指南

该 crate 是 Codex 项目的底层基础设施，为需要执行外部命令的组件提供统一的进程管理抽象。

## 功能点目的

### 1. 核心功能定位
```markdown
Lightweight helpers for spawning interactive processes either under a PTY 
(pseudo terminal) or regular pipes.
```

提供两种进程启动模式：
| 模式 | 适用场景 | 特点 |
|------|----------|------|
| **PTY 模式** | 交互式程序（REPL、编辑器、彩色输出） | 模拟终端，支持 TTY 检测、窗口大小调整 |
| **Pipe 模式** | 非交互式程序（脚本、批处理） | 标准管道 I/O，支持 stdout/stderr 分离 |

### 2. 公共 API 表面

#### 进程启动函数
```rust
// PTY 模式
spawn_pty_process(program, args, cwd, env, arg0, size) → SpawnedProcess

// Pipe 模式（标准输入）
spawn_pipe_process(program, args, cwd, env, arg0) → SpawnedProcess

// Pipe 模式（无输入）
spawn_pipe_process_no_stdin(program, args, cwd, env, arg0) → SpawnedProcess
```

#### 输出处理
```rust
combine_output_receivers(stdout_rx, stderr_rx) → broadcast::Receiver<Vec<u8>>
```
将分离的 stdout/stderr 通道合并为单一广播接收器。

#### 平台检测
```rust
conpty_supported() → bool  // Windows only; always true elsewhere
```
检测 Windows ConPTY 支持（需要 Windows 10 1809+）。

#### 数据结构
```rust
TerminalSize { rows, cols }  // PTY 尺寸（字符单元）
```

#### ProcessHandle 操作
```rust
writer_sender() → mpsc::Sender<Vec<u8>>  // 写入 stdin
resize(TerminalSize)                      // 调整终端大小
close_stdin()                            // 关闭输入
has_exited() → bool                      // 检查是否退出
exit_code() → Option<i32>               // 获取退出码
terminate()                              // 强制终止
```

#### SpawnedProcess 结构
```rust
SpawnedProcess {
    session: ProcessHandle,              // 进程控制句柄
    stdout_rx: mpsc::Receiver<Vec<u8>>, // 标准输出接收器
    stderr_rx: mpsc::Receiver<Vec<u8>>, // 标准错误接收器
    exit_rx: oneshot::Receiver<i32>,    // 退出码接收器（一次性）
}
```

### 3. 使用示例分析

```rust
use codex_utils_pty::{spawn_pty_process, TerminalSize, combine_output_receivers};

// 1. 启动 bash 进程
let spawned = spawn_pty_process(
    "bash",
    &["-lc".into(), "echo hello".into()],
    Path::new("."),
    &env_map,
    &None,
    TerminalSize::default(),  // 24x80
).await?;

// 2. 获取写入句柄
let writer = spawned.session.writer_sender();
writer.send(b"exit\n".to_vec()).await?;

// 3. 合并输出流
let mut output_rx = combine_output_receivers(spawned.stdout_rx, spawned.stderr_rx);

// 4. 收集输出
let mut collected = Vec::new();
while let Ok(chunk) = output_rx.try_recv() {
    collected.extend_from_slice(&chunk);
}

// 5. 等待退出
let exit_code = spawned.exit_rx.await.unwrap_or(-1);
```

### 4. 模式切换说明
```markdown
Swap in `spawn_pipe_process` for a non-TTY subprocess; 
the rest of the API stays the same.
```
关键设计：**API 一致性**——切换 PTY/Pipe 模式只需更换启动函数，其他代码不变。

## 具体技术实现

### API 设计模式

#### 1. 统一的 SpawnedProcess 返回类型
无论 PTY 还是 Pipe 模式，都返回相同的 `SpawnedProcess` 结构：
```rust
// src/process.rs
pub struct SpawnedProcess {
    pub session: ProcessHandle,
    pub stdout_rx: mpsc::Receiver<Vec<u8>>,
    pub stderr_rx: mpsc::Receiver<Vec<u8>>,
    pub exit_rx: oneshot::Receiver<i32>,
}
```

#### 2. 内部句柄抽象
`ProcessHandle` 封装了不同后端（PTY/Pipe）的差异：
```rust
// src/process.rs
pub struct ProcessHandle {
    writer_tx: StdMutex<Option<mpsc::Sender<Vec<u8>>>>,
    killer: StdMutex<Option<Box<dyn ChildTerminator>>>,
    // ... 其他字段
    _pty_handles: StdMutex<Option<PtyHandles>>,  // PTY 特有
}
```

#### 3. 平台抽象
```rust
// src/pty.rs
#[cfg(windows)]
pub fn conpty_supported() -> bool { crate::win::conpty_supported() }

#[cfg(not(windows))]
pub fn conpty_supported() -> bool { true }
```

### 关键实现文件

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 公共 API 导出、模块声明 |
| `src/pty.rs` | PTY 模式实现（481 行） |
| `src/pipe.rs` | Pipe 模式实现（294 行） |
| `src/process.rs` | ProcessHandle、SpawnedProcess 定义（265 行） |
| `src/process_group.rs` | 进程组管理（184 行） |
| `src/win/` | Windows ConPTY 实现（vendored from WezTerm） |
| `src/tests.rs` | 集成测试（946 行） |

### 输出合并实现
```rust
// src/process.rs
pub fn combine_output_receivers(
    mut stdout_rx: mpsc::Receiver<Vec<u8>>,
    mut stderr_rx: mpsc::Receiver<Vec<u8>>,
) -> broadcast::Receiver<Vec<u8>> {
    let (combined_tx, combined_rx) = broadcast::channel(256);
    tokio::spawn(async move {
        let mut stdout_open = true;
        let mut stderr_open = true;
        loop {
            tokio::select! {
                stdout = stdout_rx.recv(), if stdout_open => { ... }
                stderr = stderr_rx.recv(), if stderr_open => { ... }
                else => break,
            }
        }
    });
    combined_rx
}
```

## 关键代码路径与文件引用

### 使用示例的完整调用链
```
README 示例
    ↓
spawn_pty_process (src/lib.rs 导出)
    ↓
pty::spawn_process (src/pty.rs)
    ↓
spawn_process_portable / spawn_process_preserving_fds
    ↓
platform_native_pty_system()
    ↓
#[cfg(windows)] win::ConPtySystem
#[cfg(unix)] portable_pty::native_pty_system
```

### 实际调用方
| 调用方 | 文件 | 使用模式 |
|--------|------|----------|
| `codex-core` | `src/unified_exec/process.rs` | `SpawnedPty` + `combine_output_receivers` |
| `codex-core` | `src/spawn.rs` | `process_group::detach_from_tty` |
| `codex-app-server` | `src/command_exec.rs` | 命令执行 |
| `codex-rmcp-client` | `src/rmcp_client.rs` | MCP 工具调用 |

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `portable-pty` | 跨平台 PTY 抽象 |
| `tokio` | 异步通道、任务调度 |
| `anyhow` | 错误处理 |
| `libc` / `winapi` | 系统调用 |

### 与调用方的契约
1. **Tokio 运行时依赖**：所有异步函数必须在 Tokio 运行时中执行
2. **缓冲区限制**：`DEFAULT_OUTPUT_BYTES_CAP = 1MB`（输出截断阈值）
3. **进程组语义**：Unix 上自动创建新进程组，确保清理时杀死整个进程树

### 平台兼容性
| 平台 | PTY 支持 | Pipe 支持 | 备注 |
|------|----------|-----------|------|
| Linux | ✓ | ✓ | 使用 `openpty()` |
| macOS | ✓ | ✓ | 使用 `openpty()` |
| Windows 10+ | ✓ | ✓ | 使用 ConPTY |
| Windows <10 | ✗ | ✓ | ConPTY 不可用 |

## 风险、边界与改进建议

### 风险

#### 1. API 文档与实现不同步
README 中的示例代码需要定期验证：
```bash
cargo test -p codex-utils-pty --doc  # 文档测试
```

#### 2. 平台差异隐藏
`conpty_supported()` 在 Windows 上动态检测，但 README 未说明：
- 检测依据：Windows build number >= 17763
- 失败回退：无（调用方需自行处理）

#### 3. 缓冲区溢出
`broadcast::channel(256)` 在输出量大时可能丢弃数据（`RecvError::Lagged`）。

### 边界

#### 1. 输入大小限制
```rust
// src/pty.rs
let (writer_tx, mut writer_rx) = mpsc::channel::<Vec<u8>>(128);
```
stdin 写入通道容量为 128 条消息，背压处理依赖调用方。

#### 2. 输出合并的广播语义
`combine_output_receivers` 使用广播通道：
- 优势：多消费者可独立接收
- 限制：消费者必须及时处理，否则触发 `Lagged`

#### 3. 进程终止语义
```rust
pub fn terminate(&self) {
    self.request_terminate();  // 发送 SIGKILL/SIGTERM
    // 然后中止所有辅助任务
    handle.abort();
}
```
终止是**尽力而为**，不保证子进程立即退出。

### 改进建议

#### 1. README 增强
添加以下章节：
```markdown
## Platform Support
- Linux: PTY via `openpty()`
- macOS: PTY via `openpty()`  
- Windows: PTY via ConPTY (Windows 10 1809+)

## Error Handling
All spawn functions return `anyhow::Result<SpawnedProcess>`.

## Buffer Limits
- Stdin channel: 128 messages
- Output broadcast: 256 messages  
- Default output cap: 1MB
```

#### 2. 添加文档测试
```rust
#[doc = include_str!("../README.md")]
#[cfg(doctest)]
pub struct ReadmeDoctests;
```

#### 3. 特性门控文档
```rust
#[cfg_attr(docsrs, doc(cfg(windows)))]
pub fn conpty_supported() -> bool;
```

#### 4. 示例代码改进
当前示例使用 `try_recv()` 轮询，建议改为异步：
```rust
// 改进版示例
while let Ok(chunk) = output_rx.recv().await {
    collected.extend_from_slice(&chunk);
}
```

#### 5. 添加架构图
```markdown
## Architecture
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  spawn_pty_...  │────→│  ProcessHandle │←──│  spawn_pipe_... │
└─────────────────┘     └──────────────┘     └─────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ↓                    ↓                    ↓
    ┌──────────┐        ┌──────────┐         ┌──────────┐
    │  Writer  │        │  Reader  │         │  Waiter  │
    │  (mpsc)  │        │(blocking)│         │(blocking)│
    └──────────┘        └──────────┘         └──────────┘
```
```

#### 6. 版本兼容性说明
添加 `CHANGELOG.md` 或版本兼容性表格：
| 版本 | 变更 |
|------|------|
| 0.1.0 | 初始版本，支持 Unix PTY |
| 0.2.0 | 添加 Windows ConPTY 支持 |
| 0.3.0 | 添加 `inherited_fds` 支持 |
