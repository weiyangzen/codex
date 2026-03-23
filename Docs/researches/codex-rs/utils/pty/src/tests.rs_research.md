# tests.rs 研究文档

## 场景与职责

`tests.rs` 是 `codex-utils-pty` crate 的集成测试模块，提供全面的测试覆盖，验证 PTY 和 Pipe 两种进程创建模式的功能正确性、跨平台兼容性和边界情况处理。

### 核心职责

1. **功能验证**：验证进程创建、I/O 通信、终止等基本功能
2. **跨平台测试**：支持 Unix（Linux/macOS）和 Windows 平台
3. **边界情况**：测试进程组管理、FD 继承、信号处理等复杂场景
4. **回归防护**：防止已修复问题的再次出现

### 测试分类

| 类别 | 测试数量 | 覆盖内容 |
|------|----------|----------|
| PTY 功能测试 | 5+ | Python REPL、进程组终止、FD 继承 |
| Pipe 功能测试 | 5+ | 标准输入输出、分离输出、终止 |
| 跨平台测试 | 全部 | 条件编译适配不同平台 |
| 边界情况 | 多个 | 超时、权限、资源清理 |

## 功能点目的

### 1. 测试工具函数

| 函数 | 用途 |
|------|------|
| `find_python()` | 查找可用的 Python 解释器 |
| `setsid_available()` | 检查 `setsid` 命令是否可用 |
| `shell_command()` | 生成平台特定的 shell 命令 |
| `echo_sleep_command()` | 生成带延迟的回显命令 |
| `split_stdout_stderr_command()` | 生成分离 stdout/stderr 的命令 |
| `collect_split_output()` | 收集 split 模式的输出 |
| `combine_spawned_output()` | 合并 stdout/stderr 为广播接收器 |
| `collect_output_until_exit()` | 收集输出直到进程退出 |
| `wait_for_output_contains()` | 等待输出包含特定字符串 |
| `wait_for_python_repl_ready()` | 等待 Python REPL 就绪 |
| `wait_for_python_repl_ready_via_probe()` | 通过探测命令等待就绪 |
| `process_exists()` | 检查进程是否存在 |
| `wait_for_marker_pid()` | 从输出中提取 PID |
| `wait_for_process_exit()` | 等待进程退出 |

### 2. 测试用例列表

| 测试函数 | 平台 | 验证内容 |
|----------|------|----------|
| `pty_python_repl_emits_output_and_exits` | 全平台 | PTY Python REPL 基本功能 |
| `pipe_process_round_trips_stdin` | 全平台 | Pipe 模式 stdin/stdout 往返 |
| `pipe_process_detaches_from_parent_session` | Unix | 进程会话分离 |
| `pipe_and_pty_share_interface` | 全平台 | 两种模式接口一致性 |
| `pipe_drains_stderr_without_stdout_activity` | 全平台 | stderr 独立读取 |
| `pipe_process_can_expose_split_stdout_and_stderr` | 全平台 | 分离 stdout/stderr 输出 |
| `pipe_terminate_aborts_detached_readers` | Unix (setsid) | 终止时中止 reader 任务 |
| `pty_terminate_kills_background_children_in_same_process_group` | Unix | 进程组终止 |
| `pty_spawn_can_preserve_inherited_fds` | Unix | FD 继承功能 |
| `pty_preserving_inherited_fds_keeps_python_repl_running` | Unix | FD 继承 + Python REPL |
| `pty_spawn_with_inherited_fds_reports_exec_failures` | Unix | FD 继承 + 执行失败 |
| `pty_spawn_with_inherited_fds_supports_resize` | Unix | FD 继承 + 终端调整大小 |
| `pipe_spawn_no_stdin_can_preserve_inherited_fds` | Unix | Pipe + FD 继承 |

## 具体技术实现

### 1. 测试基础设施

**平台抽象：**
```rust
fn shell_command(program: &str) -> (String, Vec<String>) {
    if cfg!(windows) {
        let cmd = std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string());
        (cmd, vec!["/C".to_string(), program.to_string()])
    } else {
        ("/bin/sh".to_string(), vec!["-c".to_string(), program.to_string()])
    }
}
```

**输出收集：**
```rust
async fn collect_output_until_exit(
    mut output_rx: tokio::sync::broadcast::Receiver<Vec<u8>>,
    exit_rx: tokio::sync::oneshot::Receiver<i32>,
    timeout_ms: u64,
) -> (Vec<u8>, i32) {
    let mut collected = Vec::new();
    let deadline = tokio::time::Instant::now() + tokio::time::Duration::from_millis(timeout_ms);
    tokio::pin!(exit_rx);

    loop {
        tokio::select! {
            res = output_rx.recv() => { ... }
            res = &mut exit_rx => {
                let code = res.unwrap_or(-1);
                // Windows 特殊处理：退出后可能仍有输出
                let (quiet_ms, max_ms) = if cfg!(windows) { (200, 2_000) } else { (50, 500) };
                // 额外 drain 一段时间
                ...
                return (collected, code);
            }
            _ = tokio::time::sleep_until(deadline) => {
                return (collected, -1);  // 超时
            }
        }
    }
}
```

### 2. 关键测试详解

#### PTY Python REPL 测试

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pty_python_repl_emits_output_and_exits() -> anyhow::Result<()> {
    // 1. 查找 Python
    let Some(python) = find_python() else {
        eprintln!("python not found; skipping");
        return Ok(());
    };

    // 2. 启动 Python REPL
    let ready_marker = "__codex_pty_ready__";
    let args = vec!["-i".to_string(), "-q".to_string(), "-c".to_string(), format!("print('{ready_marker}')")];
    let spawned = spawn_pty_process(&python, &args, ..., TerminalSize::default()).await?;
    
    // 3. 合并输出
    let (session, mut output_rx, exit_rx) = combine_spawned_output(spawned);
    let writer = session.writer_sender();
    
    // 4. 等待就绪
    let newline = if cfg!(windows) { "\r\n" } else { "\n" };
    let startup_timeout_ms = if cfg!(windows) { 10_000 } else { 5_000 };
    wait_for_python_repl_ready(&mut output_rx, startup_timeout_ms, ready_marker).await?;
    
    // 5. 发送命令
    writer.send(format!("print('hello from pty'){newline}").into_bytes()).await?;
    writer.send(format!("exit(){newline}").into_bytes()).await?;
    
    // 6. 收集输出并验证
    let (remaining_output, code) = collect_output_until_exit(output_rx, exit_rx, timeout_ms).await;
    assert!(text.contains("hello from pty"));
    assert_eq!(code, 0);
    
    Ok(())
}
```

**测试要点：**
- 使用多线程运行时（`worker_threads = 2`）
- 平台特定的超时（Windows 较慢）
- 平台特定的换行符（`\r\n` vs `\n`）
- 就绪标记确保 REPL 已启动

#### 进程组终止测试

```rust
#[cfg(unix)]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pty_terminate_kills_background_children_in_same_process_group() -> anyhow::Result<()> {
    // 1. 启动 shell，后台运行 sleep
    let marker = "__codex_bg_pid:";
    let script = format!("sleep 1000 & bg=$!; echo {marker}$bg; wait");
    let spawned = spawn_pty_process(&program, &args, ..., TerminalSize::default()).await?;
    let (session, mut output_rx, _exit_rx) = combine_spawned_output(spawned);
    
    // 2. 提取后台进程 PID
    let bg_pid = wait_for_marker_pid(&mut output_rx, marker, 2_000).await?;
    assert!(process_exists(bg_pid)?);
    
    // 3. 终止 PTY 会话
    session.terminate();
    
    // 4. 验证后台进程也被终止
    let exited = wait_for_process_exit(bg_pid, 3_000).await?;
    if !exited {
        let _ = unsafe { libc::kill(bg_pid, libc::SIGKILL) };  // 清理
    }
    assert!(exited, "background child pid {bg_pid} survived PTY terminate()");
    
    Ok(())
}
```

**测试要点：**
- 验证进程组级别的终止
- 使用 `libc::kill(pid, 0)` 检查进程存在
- 超时后强制清理，避免测试残留

#### FD 继承测试

```rust
#[cfg(unix)]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn pty_spawn_can_preserve_inherited_fds() -> anyhow::Result<()> {
    // 1. 创建管道
    let mut fds = [0; 2];
    let result = unsafe { libc::pipe(fds.as_mut_ptr()) };
    assert_eq!(result, 0);
    
    let mut read_end = unsafe { std::fs::File::from_raw_fd(fds[0]) };
    let write_end = unsafe { std::fs::File::from_raw_fd(fds[1]) };
    
    // 2. 设置环境变量传递 FD 编号
    let mut env_map: HashMap<String, String> = std::env::vars().collect();
    env_map.insert("PRESERVED_FD".to_string(), write_end.as_raw_fd().to_string());
    
    // 3. 启动进程，保留 write_end
    let script = "printf __preserved__ >\"/dev/fd/$PRESERVED_FD\"";
    let spawned = spawn_process_with_inherited_fds(
        "/bin/sh", &["-c".to_string(), script.to_string()], ...,
        &[write_end.as_raw_fd()],
    ).await?;
    
    drop(write_end);  // 父进程关闭写端
    
    // 4. 验证子进程可以通过保留的 FD 写入
    let mut pipe_output = String::new();
    read_end.read_to_string(&mut pipe_output)?;
    assert_eq!(pipe_output, "__preserved__");
    
    Ok(())
}
```

**测试要点：**
- 使用 `libc::pipe` 创建测试管道
- 通过环境变量传递 FD 编号
- 验证子进程可以通过保留的 FD 通信

### 3. 平台适配策略

**条件编译使用：**
```rust
#[cfg(unix)]          // Unix 特有测试
#[cfg(not(unix))]     // 非 Unix 平台
#[cfg(target_os = "linux")]  // Linux 特有
#[cfg(windows)]       // Windows 特有
#[cfg(not(target_os = "windows"))]  // 非 Windows
```

**运行时跳过：**
```rust
let Some(python) = find_python() else {
    eprintln!("python not found; skipping test");
    return Ok(());
};

if !setsid_available() {
    eprintln!("setsid not available; skipping test");
    return Ok(());
}
```

**平台特定值：**
```rust
let newline = if cfg!(windows) { "\r\n" } else { "\n" };
let startup_timeout_ms = if cfg!(windows) { 10_000 } else { 5_000 };
let (quiet_ms, max_ms) = if cfg!(windows) { (200, 2_000) } else { (50, 500) };
```

## 关键代码路径与文件引用

### 1. 文件依赖图

```
tests.rs
  ├── 外部依赖
  │   ├── std::collections::HashMap
  │   ├── std::path::Path
  │   ├── pretty_assertions::assert_eq
  │   └── tokio::test
  │
  ├── 内部依赖
  │   ├── lib.rs 导出
  │   │   ├── spawn_pipe_process, spawn_pipe_process_no_stdin
  │   │   ├── spawn_pty_process
  │   │   ├── combine_output_receivers
  │   │   ├── SpawnedProcess, TerminalSize
  │   │   └── spawn_process_no_stdin_with_inherited_fds (Unix)
  │   └── pty.rs 导出 (Unix)
  │       └── spawn_process_with_inherited_fds
  │
  └── 系统依赖 (Unix)
      └── libc
```

### 2. 关键代码位置

| 功能 | 行号 | 代码 |
|------|------|------|
| find_python | 17-29 | Python 解释器查找 |
| setsid_available | 31-40 | setsid 可用性检查 |
| shell_command | 42-52 | 平台 shell 命令生成 |
| echo_sleep_command | 54-60 | 延迟回显命令 |
| split_stdout_stderr_command | 62-70 | 分离输出命令 |
| collect_split_output | 72-78 | 分离输出收集 |
| combine_spawned_output | 80-98 | 输出合并辅助 |
| collect_output_until_exit | 100-140 | 退出时输出收集 |
| wait_for_output_contains | 142-176 | 内容等待辅助 |
| wait_for_python_repl_ready | 178-211 | REPL 就绪等待 |
| wait_for_python_repl_ready_via_probe | 213-263 | 探测式就绪等待 |
| process_exists | 265-278 | 进程存在检查 |
| wait_for_marker_pid | 280-326 | 标记 PID 提取 |
| wait_for_process_exit | 328-340 | 进程退出等待 |
| 测试用例 | 342-946 | 13 个测试函数 |

### 3. 测试执行流程

**典型 PTY 测试流程：**
```
1. 前置检查
   ├── 查找依赖（Python、setsid 等）
   └── 不满足则跳过

2. 准备环境
   ├── 构建命令参数
   ├── 设置环境变量
   └── 准备测试数据（管道、标记等）

3. 创建进程
   └── spawn_pty_process() / spawn_pipe_process()

4. 交互验证
   ├── 等待就绪标记
   ├── 发送输入
   ├── 收集输出
   └── 验证内容

5. 终止验证
   ├── 调用 terminate() / 自然退出
   ├── 等待退出
   └── 验证退出码

6. 清理验证
   ├── 检查进程是否存在
   └── 验证资源释放
```

## 依赖与外部交互

### 1. 外部依赖

```rust
use std::collections::HashMap;
use std::path::Path;

use pretty_assertions::assert_eq;

// 内部 crate 导入
use crate::combine_output_receivers;
use crate::spawn_pipe_process;
use crate::spawn_pipe_process_no_stdin;
use crate::spawn_pty_process;
use crate::SpawnedProcess;
use crate::TerminalSize;

#[cfg(unix)]
use crate::pipe::spawn_process_no_stdin_with_inherited_fds;
#[cfg(unix)]
use crate::pty::spawn_process_with_inherited_fds;
```

### 2. 系统依赖

| 依赖 | 用途 | 可选 |
|------|------|------|
| python3/python | Python REPL 测试 | 是（跳过） |
| /bin/sh | Unix shell 命令 | 否 |
| setsid | 会话分离测试 | 是（跳过） |
| cmd.exe | Windows 命令 | 否（Windows） |

### 3. 测试运行时

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```

**配置原因：**
- `multi_thread`：需要并发执行 I/O 任务
- `worker_threads = 2`：确保 reader/writer 任务可以并行运行

## 风险、边界与改进建议

### 1. 测试脆弱性

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 时间敏感 | 超时值可能因系统负载而失败 | 使用宽松超时，平台特定值 |
| 外部依赖 | Python 可能未安装 | 运行时检查并跳过 |
| 竞态条件 | 进程状态检查与实际操作之间 | 重试逻辑和超时 |
| 平台差异 | Windows/Unix 行为不同 | 平台特定代码路径 |
| 残留进程 | 测试失败可能留下孤儿进程 | 清理逻辑和超时强制终止 |

### 2. 边界情况处理

```rust
// 1. 超时处理
_ = tokio::time::sleep_until(deadline) => {
    return (collected, -1);  // 返回 -1 表示超时
}

// 2. 通道关闭处理
Ok(Err(tokio::sync::broadcast::error::RecvError::Closed)) => break,
Ok(Err(tokio::sync::broadcast::error::RecvError::Lagged(_))) => continue,

// 3. 进程不存在处理
Some(libc::ESRCH) => Ok(false),  // 进程不存在
Some(libc::EPERM) => Ok(true),    // 存在但无权限访问

// 4. 测试跳过
if !setsid_available() {
    eprintln!("setsid not available; skipping");
    return Ok(());
}
```

### 3. 改进建议

1. **测试并行化**
   ```rust
   // 当前：所有测试串行执行
   // 建议：使用 cargo-nextest 或独立进程隔离
   ```

2. **超时统一**
   ```rust
   // 当前：分散的硬编码超时
   // 建议：统一的超时配置结构
   struct TestTimeouts {
       startup: Duration,
       operation: Duration,
       cleanup: Duration,
   }
   ```

3. **资源清理增强**
   ```rust
   // 建议：使用 scopeguard 确保清理
   let _guard = scopeguard::guard(bg_pid, |pid| {
       let _ = unsafe { libc::kill(pid, libc::SIGKILL) };
   });
   ```

4. **日志增强**
   ```rust
   // 当前：简单的 eprintln 跳过信息
   // 建议：使用 tracing 或 log crate
   tracing::info!("Skipping test: python not found");
   ```

5. **模糊测试**
   ```rust
   // 建议：添加 property-based 测试
   // 验证各种输入大小、特殊字符等
   ```

6. **覆盖率提升**
   - Windows 特有代码的测试覆盖
   - 错误路径的测试（权限不足、无效命令等）
   - 大负载和压力测试

### 4. 测试数据外部化

```rust
// 当前：硬编码的测试脚本
let script = "sleep 1000 & bg=$!; echo {marker}$bg; wait";

// 建议：外部化到 fixtures 文件
let script = std::fs::read_to_string("tests/fixtures/bg_sleep.sh")?;
```

### 5. 持续集成建议

| 平台 | 优先级 | 特殊考虑 |
|------|--------|----------|
| Linux | 必须 | 完整测试套件 |
| macOS | 必须 | Unix 特有测试 |
| Windows | 必须 | ConPTY 测试，较长超时 |
| 容器环境 | 建议 | 验证 FD 继承在受限环境 |
