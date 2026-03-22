# spawn.rs 深度研究文档

## 场景与职责

`spawn.rs` 是 Codex 核心模块中负责子进程创建和管理的组件，位于 `codex-rs/core/src/` 目录下。其主要职责是：

1. **统一子进程创建** - 封装异步子进程创建逻辑，确保一致的行为
2. **环境变量管理** - 正确设置和清理环境变量
3. **沙箱集成** - 根据网络沙箱策略设置相应的环境标记
4. **代理配置应用** - 将网络代理配置应用到子进程环境
5. **进程生命周期管理** - 确保父进程终止时子进程也被清理
6. **标准 IO 控制** - 管理子进程的标准输入、输出、错误流

该模块是 Codex 执行外部命令（如 Shell 工具调用）的基础，确保在各种沙箱和代理配置下都能正确、安全地创建子进程。

## 功能点目的

### 1. 子进程创建封装
提供统一的 `spawn_child_async` 函数，处理所有子进程创建的复杂性。

### 2. 沙箱环境标记
根据 `NetworkSandboxPolicy` 设置 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量，通知子进程网络访问状态。

### 3. 代理配置传递
将网络代理配置（HTTP、SOCKS 等）通过环境变量传递给子进程。

### 4. 进程组管理
- Unix：分离 TTY，设置父进程死亡信号（Linux）
- Windows：继承或重定向标准 IO

### 5. 资源清理
使用 `kill_on_drop` 确保子进程在父进程终止时被清理。

## 具体技术实现

### 核心数据结构

#### `StdioPolicy` 枚举
```rust
#[derive(Debug, Clone, Copy)]
pub enum StdioPolicy {
    RedirectForShellTool,  // 重定向 stdin 为 null，stdout/stderr 为管道
    Inherit,               // 继承父进程的 stdio
}
```

控制子进程标准 IO 的行为：
- `RedirectForShellTool`：用于 Shell 工具调用，防止命令挂起等待输入
- `Inherit`：用于需要用户交互的场景

#### `SpawnChildRequest` 结构体
```rust
pub(crate) struct SpawnChildRequest<'a> {
    pub program: PathBuf,                           // 可执行文件路径
    pub args: Vec<String>,                          // 命令行参数
    pub arg0: Option<&'a str>,                      // 可选的 argv[0] 覆盖
    pub cwd: PathBuf,                               // 工作目录
    pub network_sandbox_policy: NetworkSandboxPolicy, // 网络沙箱策略
    pub network: Option<&'a NetworkProxy>,          // 网络代理配置
    pub stdio_policy: StdioPolicy,                  // 标准 IO 策略
    pub env: HashMap<String, String>,               // 环境变量
}
```

封装创建子进程所需的所有参数。

### 环境变量常量

```rust
/// 当进程由 Codex 作为 Shell 工具调用的一部分生成且 NetworkSandboxPolicy 为受限时设置
pub const CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR: &str = "CODEX_SANDBOX_NETWORK_DISABLED";

/// 当进程在沙箱下生成时设置，值为 "seatbelt"（macOS）
pub const CODEX_SANDBOX_ENV_VAR: &str = "CODEX_SANDBOX";
```

### 核心函数实现

#### `spawn_child_async`
```rust
pub(crate) async fn spawn_child_async(request: SpawnChildRequest<'_>) -> std::io::Result<Child> {
    let SpawnChildRequest {
        program,
        args,
        arg0,
        cwd,
        network_sandbox_policy,
        network,
        stdio_policy,
        mut env,
    } = request;
    
    // 1. 记录调试日志
    trace!("spawn_child_async: {program:?} {args:?} ...");
    
    // 2. 创建命令
    let mut cmd = Command::new(&program);
    
    // 3. 设置 argv[0]（Unix）
    #[cfg(unix)]
    cmd.arg0(arg0.map_or_else(|| program.to_string_lossy().to_string(), String::from));
    
    // 4. 设置参数和工作目录
    cmd.args(args);
    cmd.current_dir(cwd);
    
    // 5. 应用代理配置到环境变量
    if let Some(network) = network {
        network.apply_to_env(&mut env);
    }
    
    // 6. 清理并设置环境变量
    cmd.env_clear();
    cmd.envs(env);
    
    // 7. 设置网络沙箱标记
    if !network_sandbox_policy.is_enabled() {
        cmd.env(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR, "1");
    }
    
    // 8. Unix 特定的进程组设置
    #[cfg(unix)]
    unsafe {
        let detach_from_tty = matches!(stdio_policy, StdioPolicy::RedirectForShellTool);
        #[cfg(target_os = "linux")]
        let parent_pid = libc::getpid();
        
        cmd.pre_exec(move || {
            if detach_from_tty {
                codex_utils_pty::process_group::detach_from_tty()?;
            }
            
            // Linux：设置父进程死亡信号
            #[cfg(target_os = "linux")]
            {
                codex_utils_pty::process_group::set_parent_death_signal(parent_pid)?;
            }
            Ok(())
        });
    }
    
    // 9. 设置标准 IO
    match stdio_policy {
        StdioPolicy::RedirectForShellTool => {
            cmd.stdin(Stdio::null());  // 防止命令等待输入
            cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
        }
        StdioPolicy::Inherit => {
            cmd.stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
        }
    }
    
    // 10. 启动进程
    cmd.kill_on_drop(true).spawn()
}
```

### 关键技术点

#### 1. 标准输入重定向
```rust
StdioPolicy::RedirectForShellTool => {
    // 不为 stdin 创建文件描述符，防止命令永远等待输入
    // 例如：ripgrep 有启发式逻辑可能尝试从 stdin 读取
    // https://github.com/BurntSushi/ripgrep/...
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
}
```

某些命令（如 ripgrep）会检测 stdin 是否为 TTY，如果不是则尝试从 stdin 读取。将 stdin 重定向为 `null` 可以防止这种挂起行为。

#### 2. Linux 父进程死亡信号
```rust
#[cfg(target_os = "linux")]
{
    // 请求在父进程死亡时接收 SIGTERM
    codex_utils_pty::process_group::set_parent_death_signal(parent_pid)?;
}
```

使用 `prctl(PR_SET_PDEATHSIG, SIGTERM)` 确保如果 Codex 进程被杀死（包括 SIGKILL），子进程也会收到 SIGTERM 并终止。

**注意：** 这仅在 Linux 上有效，因为依赖于 `prctl(2)` 系统调用。

#### 3. TTY 分离
```rust
if detach_from_tty {
    codex_utils_pty::process_group::detach_from_tty()?;
}
```

对于 Shell 工具调用，将子进程从控制 TTY 分离，防止：
- 信号（如 Ctrl+C）同时传递给父进程和子进程
- 子进程持有 TTY 导致父进程无法读取输入

#### 4. 环境变量清理
```rust
cmd.env_clear();
cmd.envs(env);
```

显式清理环境变量，然后只设置指定的变量。这：
- 防止敏感环境变量泄漏到子进程
- 确保沙箱策略的确定性
- 避免不受信任的环境变量影响命令行为

#### 5. 网络沙箱标记
```rust
if !network_sandbox_policy.is_enabled() {
    cmd.env(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR, "1");
}
```

当网络被禁用时，设置环境变量通知子进程。这允许：
- 子进程可以检测网络状态并相应调整行为
- 测试可以验证沙箱是否正确应用

## 关键代码路径与文件引用

### 模块依赖图

```
spawn.rs
├── codex_network_proxy::NetworkProxy
│   └── apply_to_env()
├── codex_protocol::permissions::NetworkSandboxPolicy
│   └── is_enabled()
├── codex_utils_pty::process_group (Unix)
│   ├── detach_from_tty()
│   └── set_parent_death_signal()
├── tokio::process
│   ├── Command
│   └── Child
└── libc (Linux)
    └── getpid()
```

### 调用关系

**调用方：**
- `exec.rs` - 执行外部命令
- `seatbelt.rs` - macOS 沙箱下执行命令
- `sandboxing/mod.rs` - 沙箱转换后的命令执行
- `shell_snapshot.rs` - 执行 Shell 快照脚本

**调用图：**
```
调用方
└── spawn_child_async(SpawnChildRequest { ... })
    ├── Command::new()
    ├── network.apply_to_env()
    ├── cmd.env_clear()
    ├── cmd.envs()
    ├── cmd.pre_exec() [Unix]
    │   ├── detach_from_tty()
    │   └── set_parent_death_signal() [Linux]
    └── cmd.spawn()
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步进程管理 (`Command`, `Child`, `Stdio`) |
| `tracing` | 调试日志 (`trace!`) |
| `codex_network_proxy` | 网络代理配置 (`NetworkProxy`) |
| `codex_protocol` | 权限类型 (`NetworkSandboxPolicy`) |
| `codex_utils_pty` | Unix 进程组管理 |
| `libc` | Unix 系统调用 (`getpid`) |

### 系统交互

**Unix/Linux：**
- 进程创建 (`fork`/`exec`)
- TTY 分离 (`setsid`, `setpgid`)
- 父进程死亡信号 (`prctl(PR_SET_PDEATHSIG)`)

**Windows：**
- 进程创建 (`CreateProcess`)
- 标准 IO 重定向

## 风险、边界与改进建议

### 已知风险

1. **平台差异**
   - `set_parent_death_signal` 仅在 Linux 有效
   - macOS 和其他 Unix 系统没有等效机制
   - Windows 使用完全不同的进程管理模型

2. **竞争条件**
   ```rust
   #[cfg(target_os = "linux")]
   let parent_pid = libc::getpid();
   ```
   `pre_exec` 闭包捕获 `parent_pid`，但如果父进程在 `pre_exec` 执行前退出，信号可能不会被正确设置。

3. **环境变量大小限制**
   某些系统对环境变量总大小有限制，大量代理配置可能超出限制。

### 边界情况

1. **空参数处理**
   ```rust
   cmd.arg0(arg0.map_or_else(|| program.to_string_lossy().to_string(), String::from));
   ```
   如果没有提供 `arg0`，使用程序路径作为默认值。

2. **网络代理可选**
   ```rust
   if let Some(network) = network {
       network.apply_to_env(&mut env);
   }
   ```
   代理配置是可选的，没有时代理相关环境变量不会被设置。

3. **沙箱策略转换**
   ```rust
   if !network_sandbox_policy.is_enabled() {
       cmd.env(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR, "1");
   }
   ```
   注意逻辑：`is_enabled()` 返回 `false` 时设置禁用标记（双重否定）。

### 改进建议

1. **跨平台父进程死亡处理**
   - macOS：考虑使用 `kqueue` 监控父进程
   - Windows：使用作业对象（Job Objects）

2. **环境变量验证**
   - 在设置前验证环境变量大小
   - 提供清晰的错误消息当超出限制

3. **资源限制**
   - 添加内存限制（`setrlimit`）
   - 添加 CPU 时间限制
   - 添加文件描述符限制

4. **安全增强**
   - 验证可执行文件路径（防止 PATH 注入）
   - 考虑使用命名空间隔离（Linux）
   - 添加 seccomp 过滤器（Linux）

5. **可观测性**
   - 添加更多 span 标签用于追踪
   - 记录子进程启动时间和资源使用
   - 提供子进程生命周期事件

6. **错误处理**
   - 区分可恢复和不可恢复错误
   - 提供重试机制
   - 更好的错误上下文

### 代码质量

- **简洁性**：函数逻辑清晰，步骤明确
- **平台抽象**：使用条件编译处理平台差异
- **安全性**：`unsafe` 块最小化，注释清晰
- **文档**：常量有详细的文档注释

### 测试建议

当前文件无内联测试，建议添加：
1. 模拟 `NetworkProxy` 测试环境变量设置
2. 测试 `StdioPolicy` 的不同行为
3. 测试进程终止时子进程是否被清理
4. 测试环境变量清理是否正确
5. 测试大参数和环境变量的处理
