# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-utils-pty` crate 的公共 API 入口点，提供了跨平台的进程创建和管理功能。该 crate 的核心职责是：

1. **统一抽象 PTY 和 Pipe 两种进程创建模式**：为调用者提供一致的接口，无论底层使用伪终端（PTY）还是普通管道（pipe）
2. **跨平台支持**：支持 Unix（Linux/macOS）和 Windows 平台，自动适配不同操作系统的进程管理机制
3. **向后兼容**：维护 `ExecCommandSession` 和 `SpawnedPty` 等类型别名，确保现有代码的兼容性

## 功能点目的

### 1. 模块导出结构

| 模块 | 可见性 | 用途 |
|------|--------|------|
| `pipe` | `pub` | 非交互式管道进程创建 |
| `process` | `private` | 进程句柄和共享逻辑 |
| `process_group` | `pub` | 进程组管理工具 |
| `pty` | `pub` | PTY 交互式进程创建 |
| `tests` | `#[cfg(test)]` | 单元测试 |
| `win` | `#[cfg(windows)]` | Windows 特定实现 |

### 2. 核心常量

```rust
pub const DEFAULT_OUTPUT_BYTES_CAP: usize = 1024 * 1024; // 1MB 输出缓冲区上限
```

### 3. 公共 API 导出

**进程创建函数：**
- `spawn_pipe_process` - 创建带标准输入的管道进程
- `spawn_pipe_process_no_stdin` - 创建无标准输入的管道进程
- `spawn_pty_process` - 创建 PTY 交互式进程

**进程管理类型：**
- `ProcessHandle` - 进程操作句柄（写入、终止、调整大小等）
- `SpawnedProcess` - 包含句柄、输出接收器和退出接收器的完整结构
- `TerminalSize` - 终端尺寸配置（行数/列数）
- `ExecCommandSession` / `SpawnedPty` - 向后兼容的类型别名

**工具函数：**
- `combine_output_receivers` - 合并 stdout/stderr 为单一广播接收器
- `conpty_supported` - 检测 Windows ConPTY 支持（Windows 专用）
- `RawConPty` - Windows 原始 ConPTY 句柄（Windows 专用）

## 具体技术实现

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                        lib.rs (API 层)                       │
├─────────────────────────────────────────────────────────────┤
│  spawn_pipe_process()      spawn_pty_process()               │
│       │                           │                         │
│       ▼                           ▼                         │
│  ┌─────────┐                ┌─────────┐                     │
│  │  pipe   │                │  pty    │                     │
│  │ 模块    │                │ 模块    │                     │
│  └────┬────┘                └────┬────┘                     │
│       │                           │                         │
│       └───────────┬───────────────┘                         │
│                   ▼                                         │
│            ┌──────────┐                                     │
│            │ process  │  共享：ProcessHandle, SpawnedProcess│
│            │ 模块     │                                     │
│            └────┬─────┘                                     │
│                 │                                           │
│       ┌─────────┴─────────┐                                 │
│       ▼                   ▼                                 │
│  ┌──────────┐        ┌──────────┐                          │
│  │process_  │        │   win    │  (Windows 专用)           │
│  │group     │        │  模块    │                          │
│  └──────────┘        └──────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

### 平台抽象策略

**Unix 平台：**
- 使用 `libc` 进行系统调用
- 进程组管理通过 `setpgid`, `setsid`, `killpg`
- PTY 通过 `openpty` 系统调用创建

**Windows 平台：**
- 使用 `winapi` 进行 Windows API 调用
- ConPTY（Console Pseudo Terminal）支持
- 进程终止通过 `TerminateProcess`

## 关键代码路径与文件引用

### 1. 进程创建流程

**PTY 进程创建：**
```
lib.rs:spawn_pty_process()
  └── pty.rs:spawn_process()
      ├── pty.rs:spawn_process_portable()  [无继承 FD]
      └── pty.rs:spawn_process_preserving_fds()  [Unix + 继承 FD]
```

**Pipe 进程创建：**
```
lib.rs:spawn_pipe_process()
  └── pipe.rs:spawn_process()
      └── pipe.rs:spawn_process_with_stdin_mode()
```

### 2. 进程终止流程

```
ProcessHandle::terminate()
  ├── ProcessHandle::request_terminate()
  │   └── ChildTerminator::kill()
  │       ├── pipe.rs:PipeChildTerminator::kill()
  │       │   ├── Unix: process_group.rs:kill_process_group()
  │       │   └── Windows: pipe.rs:kill_process()
  │       └── pty.rs:PtyChildTerminator::kill()
  │           └── process_group.rs:kill_process_group()
  └── 中止 reader/writer/wait 任务
```

### 3. 文件依赖关系

```rust
// lib.rs 内部依赖
pub mod pipe;           // 依赖: process, process_group
mod process;            // 依赖: portable-pty
pub mod process_group;  // 依赖: libc (unix)
pub mod pty;            // 依赖: process, process_group, portable-pty

#[cfg(windows)]
mod win;                // Windows 特定实现
```

## 依赖与外部交互

### 1. 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `portable-pty` | 跨平台 PTY 实现基础 |
| `tokio` | 异步运行时（进程管理、通道、任务） |
| `anyhow` | 错误处理 |
| `libc` | Unix 系统调用（Unix 平台） |
| `winapi` | Windows API（Windows 平台） |

### 2. 内部模块交互

```
lib.rs
  ├── re-exports pipe::spawn_process → spawn_pipe_process
  ├── re-exports pipe::spawn_process_no_stdin → spawn_pipe_process_no_stdin
  ├── re-exports process::combine_output_receivers
  ├── re-exports process::ProcessHandle, SpawnedProcess, TerminalSize
  ├── re-exports pty::spawn_process → spawn_pty_process
  ├── re-exports pty::conpty_supported
  └── re-exports win::conpty::RawConPty (Windows)
```

### 3. 调用方（Upstream Consumers）

主要调用方位于 `codex-rs/app-server/src/command_exec.rs`：

```rust
// command_exec.rs 使用示例
codex_utils_pty::spawn_pty_process(...)   // TTY 模式
codex_utils_pty::spawn_pipe_process(...) // 流式 stdin 模式
codex_utils_pty::spawn_pipe_process_no_stdin(...) // 无 stdin 模式
```

## 风险、边界与改进建议

### 1. 已知风险

| 风险点 | 描述 | 缓解措施 |
|--------|------|----------|
| 进程泄漏 | 子进程可能成为孤儿进程 | `process_group.rs` 使用进程组 + `killpg` 确保整组终止 |
| 资源泄漏 | PTY 句柄未正确关闭 | `PtyHandles` 在 `ProcessHandle` 中保持存活直到 Drop |
| 竞态条件 | fork/exec 期间父进程退出 | `set_parent_death_signal` 确保子进程收到 SIGTERM |
| Windows 终止逻辑 | 原 WezTerm 代码中 `TerminateProcess` 返回值判断错误 | 已修复（见 `win/mod.rs` 注释） |

### 2. 边界情况

1. **空程序名**：`spawn_process_with_stdin_mode` 会检查 `program.is_empty()` 并返回错误
2. **PID 获取失败**：`child.id()` 可能返回 `None`，会转换为错误
3. **PTY 调整大小**：仅对 PTY 进程有效，pipe 进程调用 `resize()` 会返回错误
4. **跨平台 FD 继承**：`inherited_fds` 仅在 Unix 平台有效，Windows 上被忽略

### 3. 改进建议

1. **错误处理细化**：当前使用 `anyhow` 进行通用错误处理，可考虑为常见错误（如程序未找到、权限拒绝）定义特定错误类型

2. **文档完善**：`RawConPty` 的公共接口缺少文档注释

3. **测试覆盖**：
   - Windows 平台的测试覆盖可能不足
   - 大规模并发进程创建的压力测试缺失

4. **性能优化**：
   - 考虑使用 `tokio::process` 的 `kill_on_drop` 功能
   - 评估 `spawn_blocking` 的使用场景是否适合

5. **API 演进**：
   - 考虑统一 `spawn_pipe_process` 和 `spawn_pty_process` 的接口（通过配置结构体）
   - 添加异步流式输出 API（`Stream<Item = Vec<u8>>`）

### 4. 安全考虑

- **命令注入**：调用方负责转义参数，本 crate 不处理 shell 注入防护
- **环境变量泄漏**：`env_clear()` 确保子进程不继承父进程环境，但调用方提供的 `env` HashMap 可能包含敏感信息
- **FD 继承风险**：`inherited_fds` 功能需谨慎使用，避免意外泄漏敏感文件描述符
