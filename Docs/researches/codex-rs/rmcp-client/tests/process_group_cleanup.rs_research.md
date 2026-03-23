# process_group_cleanup.rs 研究文档

## 场景与职责

`process_group_cleanup.rs` 是 `codex-rmcp-client`  crate 的集成测试文件，专注于验证 **Unix 平台下 MCP (Model Context Protocol) 客户端在丢弃时是否正确清理子进程组**。该测试确保当 `RmcpClient` 被 drop 时，通过 stdio 传输启动的 MCP 服务器进程及其所有后代进程都被正确终止。

### 测试目标
- 验证 `RmcpClient::new_stdio_client` 创建的子进程在客户端丢弃时被清理
- 确保进程组级别的终止（而非仅终止直接子进程）
- 防止 MCP 服务器进程在客户端关闭后成为僵尸进程或孤儿进程

## 功能点目的

### 1. 进程组清理验证
测试的核心目的是验证 `ProcessGroupGuard` 机制的有效性。当使用 stdio 传输创建 MCP 客户端时：
- 子进程被放入独立的进程组（通过 `setpgid(0, 0)`）
- `ProcessGroupGuard` 在 `RmcpClient` 被 drop 时触发清理
- 清理操作发送 SIGTERM，并在宽限期后发送 SIGKILL

### 2. 跨平台兼容性
- 使用 `#![cfg(unix)]` 条件编译，仅在 Unix 平台编译和运行
- 非 Unix 平台的 `ProcessGroupGuard` 为空操作

## 具体技术实现

### 测试流程

```
测试启动
    │
    ▼
创建临时目录（用于 PID 文件）
    │
    ▼
启动 RmcpClient（通过 /bin/sh 启动后台进程）
    │
    ├─ shell 脚本: sleep 300 & child_pid=$!; echo "$child_pid" > "$CHILD_PID_FILE"; cat >/dev/null
    │
    ▼
等待 PID 文件写入（轮询 50 次，每次 100ms）
    │
    ▼
验证孙进程（sleep 300）正在运行
    │
    ▼
drop(client) ──触发──► ProcessGroupGuard::drop()
    │                      ├─ terminate_process_group() 发送 SIGTERM
    │                      └─ 2秒后发送 SIGKILL（如果需要）
    ▼
等待孙进程退出（轮询验证）
    │
    ▼
断言进程已终止
```

### 关键辅助函数

#### `process_exists(pid: u32) -> bool`
```rust
fn process_exists(pid: u32) -> bool {
    std::process::Command::new("kill")
        .arg("-0")
        .arg(pid.to_string())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}
```
- 使用 `kill -0` 检查进程是否存在（不实际发送信号）
- 返回 `true` 表示进程存在，`false` 表示不存在或无权限

#### `wait_for_pid_file(path: &Path) -> Result<u32>`
- 轮询等待 PID 文件创建（最多 5 秒）
- 解析文件内容获取进程 ID
- 处理文件不存在、解析错误等边界情况

#### `wait_for_process_exit(pid: u32) -> Result<()>`
- 轮询验证进程已退出（最多 5 秒）
- 使用 `process_exists` 检查进程状态

### 测试用例：`drop_kills_wrapper_process_group`

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn drop_kills_wrapper_process_group() -> Result<()> {
    let temp_dir = tempfile::tempdir()?;
    let child_pid_file = temp_dir.path().join("child.pid");
    
    // 创建客户端，启动 shell 脚本
    let client = RmcpClient::new_stdio_client(
        OsString::from("/bin/sh"),
        vec![
            OsString::from("-c"),
            OsString::from("sleep 300 & child_pid=$!; echo \"$child_pid\" > \"$CHILD_PID_FILE\"; cat >/dev/null"),
        ],
        Some(HashMap::from([(
            "CHILD_PID_FILE".to_string(),
            child_pid_file.to_string_lossy().into_owned(),
        )])),
        &[],
        None,
    ).await?;

    // 获取孙进程 PID 并验证其运行
    let grandchild_pid = wait_for_pid_file(&child_pid_file).await?;
    assert!(process_exists(grandchild_pid));

    // 丢弃客户端，触发清理
    drop(client);

    // 验证孙进程已终止
    wait_for_process_exit(grandchild_pid).await
}
```

## 关键代码路径与文件引用

### 被测试代码

| 文件 | 相关组件 | 说明 |
|------|----------|------|
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `ProcessGroupGuard` | 进程组守卫结构体，负责在 drop 时终止进程组 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `PendingTransport::ChildProcess` | 包含进程组守卫的传输层枚举变体 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `new_stdio_client()` | 创建 stdio 客户端的工厂方法 |
| `codex-rs/utils/pty/src/process_group.rs` | `terminate_process_group()` | 发送 SIGTERM 到进程组 |
| `codex-rs/utils/pty/src/process_group.rs` | `kill_process_group()` | 发送 SIGKILL 到进程组 |

### ProcessGroupGuard 实现细节

```rust
// codex-rs/rmcp-client/src/rmcp_client.rs 第 369-422 行
#[cfg(unix)]
struct ProcessGroupGuard {
    process_group_id: u32,
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        if cfg!(unix) {
            self.maybe_terminate_process_group();
        }
    }
}

#[cfg(unix)]
fn maybe_terminate_process_group(&self) {
    let process_group_id = self.process_group_id;
    // 1. 发送 SIGTERM
    let should_escalate = match terminate_process_group(process_group_id) {
        Ok(exists) => exists,
        Err(error) => { warn!(...); false }
    };
    // 2. 如果进程组仍存在，2秒后发送 SIGKILL
    if should_escalate {
        std::thread::spawn(move || {
            std::thread::sleep(PROCESS_GROUP_TERM_GRACE_PERIOD); // 2秒
            kill_process_group(process_group_id);
        });
    }
}
```

### 子进程创建流程

```rust
// codex-rs/rmcp-client/src/rmcp_client.rs 第 890-906 行
let mut command = Command::new(resolved_program);
command
    .kill_on_drop(true)
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .env_clear()
    .envs(envs)
    .args(args);
#[cfg(unix)]
command.process_group(0);  // 创建新进程组

let (transport, stderr) = TokioChildProcess::builder(command)
    .stderr(Stdio::piped())
    .spawn()?;
let process_group_guard = transport.id().map(ProcessGroupGuard::new);
```

## 依赖与外部交互

### 直接依赖

| 依赖 | 用途 |
|------|------|
| `tokio` | 异步运行时，提供 `tokio::test` 和进程管理 |
| `tempfile` | 创建临时目录存储 PID 文件 |
| `anyhow` | 错误处理和上下文 |
| `codex_rmcp_client::RmcpClient` | 被测试的 MCP 客户端 |

### 系统调用

| 调用 | 用途 |
|------|------|
| `kill -0 <pid>` | 检查进程是否存在 |
| `setpgid(0, 0)` | 创建新进程组（在子进程中） |
| `killpg(pgid, SIGTERM)` | 终止进程组（宽限期） |
| `killpg(pgid, SIGKILL)` | 强制终止进程组 |

### 测试环境要求

- **平台**: Unix-like 系统（Linux, macOS 等）
- **Shell**: `/bin/sh` 必须可用
- **权限**: 能够创建进程和发送信号

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**
   - PID 文件写入和读取之间的时间窗口
   - 进程终止检查和实际终止之间的时间窗口
   - 缓解：使用轮询和超时机制

2. **平台限制**
   - 测试仅在 Unix 平台运行，Windows 无覆盖
   - 不同 Unix 变体的信号行为可能略有差异

3. **资源泄漏**
   - 如果 `ProcessGroupGuard` 未正确创建（如 `transport.id()` 返回 `None`）
   - 子进程的 stderr 读取任务可能成为孤儿任务

### 边界情况

| 场景 | 当前处理 | 建议 |
|------|----------|------|
| 进程在 drop 前已自然退出 | 正常通过 | 无需处理 |
| 进程忽略 SIGTERM | 2秒后 SIGKILL | 可配置宽限期 |
| 权限不足无法发送信号 | 记录警告 | 考虑测试失败 |
| 大量并发客户端 | 每个客户端独立管理 | 考虑资源限制 |

### 改进建议

1. **可观测性增强**
   ```rust
   // 建议：添加更多诊断信息
   info!("Terminating MCP process group {}", process_group_id);
   ```

2. **配置化宽限期**
   - 当前硬编码 2 秒（`PROCESS_GROUP_TERM_GRACE_PERIOD`）
   - 建议：通过环境变量或配置参数允许调整

3. **测试覆盖扩展**
   - 添加测试：验证 SIGKILL 升级路径
   - 添加测试：验证多个嵌套子进程的清理
   - 添加测试：验证权限不足时的行为

4. **错误处理细化**
   ```rust
   // 当前：仅记录警告
   // 建议：区分可恢复和不可恢复错误
   if err.raw_os_error() == Some(libc::EPERM) {
       return Err(ClientError::PermissionDenied);
   }
   ```

5. **与 systemd/容器集成**
   - 在 systemd 或容器环境中，进程组管理可能需要特殊处理
   - 考虑检测 cgroup 存在并调整清理策略

### 相关测试文件

- `codex-rs/rmcp-client/tests/resources.rs` - 资源管理测试
- `codex-rs/rmcp-client/tests/streamable_http_recovery.rs` - HTTP 传输恢复测试
- `codex-rs/utils/pty/src/tests.rs` - 底层进程组工具测试
