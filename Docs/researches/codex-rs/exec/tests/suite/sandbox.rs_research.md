# sandbox.rs 深度研究文档

## 场景与职责

`sandbox.rs` 是 `codex-exec` CLI 工具的沙箱机制核心测试模块，专门验证不同操作系统（macOS Seatbelt 和 Linux Landlock）下的沙箱功能。这是安全关键代码的测试套件。

**核心场景**：
- 验证沙箱能够正确限制进程的文件系统访问
- 测试 Python 等多进程程序在沙箱中的行为
- 验证命令 CWD 和策略 CWD 的区分
- 测试 Unix socket 等 IPC 机制在沙箱中的可用性

## 功能点目的

### 1. Python 多进程锁测试 (`python_multiprocessing_lock_works_under_sandbox`)
验证 Python 的 `multiprocessing.Lock` 在沙箱中能够正常工作。

**背景**: Linux 的命名信号量存储在 `/dev/shm`，需要显式允许访问。

### 2. Python 用户信息测试 (`python_getpwuid_works_under_sandbox`)
验证 Python 的 `pwd.getpwuid()` 在沙箱中能够正常工作。

### 3. CWD 区分测试 (`sandbox_distinguishes_command_and_policy_cwds`)
验证沙箱能够区分命令执行目录和策略应用目录。

### 4. Unix Socket 测试 (`allow_unix_socketpair_recvfrom`)
验证 Unix domain socket 在沙箱中可用。

## 具体技术实现

### 平台特定沙箱实现

#### macOS Seatbelt
```rust
#[cfg(target_os = "macos")]
async fn spawn_command_under_sandbox(
    command: Vec<String>,
    command_cwd: PathBuf,
    sandbox_policy: &SandboxPolicy,
    sandbox_cwd: &Path,
    stdio_policy: StdioPolicy,
    env: HashMap<String, String>,
) -> std::io::Result<Child> {
    use codex_core::seatbelt::spawn_command_under_seatbelt;
    spawn_command_under_seatbelt(...).await
}
```

#### Linux Landlock
```rust
#[cfg(target_os = "linux")]
async fn spawn_command_under_sandbox(
    command: Vec<String>,
    command_cwd: PathBuf,
    sandbox_policy: &SandboxPolicy,
    sandbox_cwd: &Path,
    stdio_policy: StdioPolicy,
    env: HashMap<String, String>,
) -> std::io::Result<Child> {
    use codex_core::landlock::spawn_command_under_linux_sandbox;
    let codex_linux_sandbox_exe = codex_utils_cargo_bin::cargo_bin("codex-exec")?;
    spawn_command_under_linux_sandbox(
        codex_linux_sandbox_exe,  // 使用自身作为沙箱启动器
        ...
    ).await
}
```

### Linux 沙箱能力探测

```rust
#[cfg(target_os = "linux")]
async fn linux_sandbox_test_env() -> Option<HashMap<String, String>> {
    // 尝试运行简单命令验证 Landlock 是否可用
    if can_apply_linux_sandbox_policy(&policy, &command_cwd, ...).await {
        return Some(HashMap::new());
    }
    eprintln!("Skipping test: Landlock is not enforceable on this host.");
    None
}
```

### 沙箱策略类型

```rust
SandboxPolicy::WorkspaceWrite {
    writable_roots: Vec<AbsolutePathBuf>,      // 可写根目录
    read_only_access: ReadOnlyAccess,          // 只读访问级别
    network_access: bool,                      // 网络访问权限
    exclude_tmpdir_env_var: bool,              // 是否排除 TMPDIR
    exclude_slash_tmp: bool,                   // 是否排除 /tmp
}
```

### 测试执行框架

```rust
const IN_SANDBOX_ENV_VAR: &str = "IN_SANDBOX";

pub async fn run_code_under_sandbox<F, Fut>(
    test_selector: &str,
    policy: &SandboxPolicy,
    child_body: F,
) -> io::Result<Option<ExitStatus>>
where
    F: FnOnce() -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    if std::env::var(IN_SANDBOX_ENV_VAR).is_err() {
        // 父进程：启动子进程在沙箱中运行
        let mut child = spawn_command_under_sandbox(...).await?;
        let status = child.wait().await?;
        Ok(Some(status))
    } else {
        // 子进程：执行测试体
        child_body().await;
        Ok(None)
    }
}
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **Seatbelt 实现**: `codex-rs/core/src/seatbelt.rs`
   - macOS 沙箱配置文件生成
   - `sandbox-exec` 命令执行

2. **Landlock 实现**: `codex-rs/core/src/landlock.rs`
   - Linux Landlock 规则设置
   - 文件系统访问控制

3. **沙箱策略**: `codex-rs/protocol/src/protocol.rs`
   - `SandboxPolicy` 枚举定义
   - 策略序列化和反序列化

4. **进程启动**: `codex-rs/core/src/spawn.rs`
   - 根据策略选择沙箱实现
   - 处理 `StdioPolicy`

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `codex_core::seatbelt` | `codex-rs/core/src/seatbelt.rs` | macOS 沙箱 |
| `codex_core::landlock` | `codex-rs/core/src/landlock.rs` | Linux 沙箱 |
| `codex_protocol::protocol::SandboxPolicy` | `codex-rs/protocol/src/protocol.rs` | 策略定义 |
| `skip_if_sandbox!` | `core_test_support` | 沙箱环境跳过宏 |

### 平台特定代码

| 测试 | macOS | Linux | 说明 |
|------|-------|-------|------|
| `python_multiprocessing_lock_works_under_sandbox` | ✓ | ✓ | Linux 需要 `/dev/shm` |
| `python_getpwuid_works_under_sandbox` | ✓ | ✓ | 读取用户数据库 |
| `sandbox_distinguishes_command_and_policy_cwds` | ✓ | ✓ | CWD 区分 |
| `allow_unix_socketpair_recvfrom` | ✓ | ✓ | Unix socket |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `libc` | Unix socket 系统调用 |
| `tokio::process` | 异步进程管理 |
| `tempfile` | 临时目录 |

### 系统调用

**Unix Socket**:
```rust
unsafe {
    libc::socketpair(libc::AF_UNIX, libc::SOCK_DGRAM, 0, fds.as_mut_ptr())
    libc::write(fds[0], msg.as_ptr() as *const libc::c_void, msg.len())
    libc::recvfrom(fds[1], buf.as_mut_ptr() as *mut libc::c_void, ...)
}
```

### 环境变量

| 变量 | 用途 |
|------|------|
| `IN_SANDBOX` | 标记当前是否在沙箱子进程中 |
| `CODEX_SANDBOX` | 沙箱类型标识（seatbelt/landlock） |

### 平台限制

```rust
#![cfg(unix)]
```

仅 Unix 平台运行，Windows 不支持。

## 风险、边界与改进建议

### 当前风险

1. **自执行依赖**: Linux 测试依赖 `codex-exec` 二进制作为沙箱启动器
2. **能力探测**: 可能误判某些容器的 Landlock 支持
3. **时序敏感**: 沙箱启动和进程执行有竞态条件可能

### 边界情况

1. **嵌套沙箱**: 沙箱内再启动沙箱的行为未定义
2. **信号处理**: 沙箱进程的信号处理未充分测试
3. **资源限制**: 未测试沙箱内的资源限制（CPU、内存）
4. **网络隔离**: 仅测试文件系统隔离，网络隔离测试不足

### 改进建议

1. **增加安全边界测试**:
   ```rust
   #[tokio::test]
   async fn sandbox_blocks_unauthorized_write() { ... }
   
   #[tokio::test]
   async fn sandbox_blocks_unauthorized_read() { ... }
   ```

2. **网络隔离测试**:
   ```rust
   #[tokio::test]
   async fn sandbox_blocks_network_when_disabled() { ... }
   ```

3. **资源限制测试**: 测试沙箱内的资源限制生效

4. **模糊测试**: 对沙箱规则进行模糊测试

5. **性能基准**: 沙箱启动和执行的 overhead 测试

### 相关文件

- `codex-rs/core/src/seatbelt.rs` - macOS Seatbelt 实现
- `codex-rs/core/src/landlock.rs` - Linux Landlock 实现
- `codex-rs/core/src/spawn.rs` - 进程启动逻辑
- `codex-rs/protocol/src/protocol.rs` - 沙箱策略定义

### 安全架构

```
┌─────────────────────────────────────┐
│           codex-exec                │
│  (主进程，无沙箱或受限沙箱)          │
└─────────────┬───────────────────────┘
              │ spawn_command_under_sandbox
              ▼
┌─────────────────────────────────────┐
│  ┌─────────────────────────────┐    │
│  │   Seatbelt / Landlock       │    │
│  │   (沙箱规则)                 │    │
│  └─────────────────────────────┘    │
│           │                         │
│           ▼                         │
│  ┌─────────────────────────────┐    │
│  │   子进程 (沙箱内)            │    │
│  │   - 受限文件系统访问         │    │
│  │   - 受限网络访问             │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```
