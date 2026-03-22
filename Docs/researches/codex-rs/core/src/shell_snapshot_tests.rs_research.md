# shell_snapshot_tests.rs 深度研究文档

## 场景与职责

`shell_snapshot_tests.rs` 是 Codex 核心模块中 `shell_snapshot.rs` 的配套测试文件，位于 `codex-rs/core/src/` 目录下。其主要职责是全面验证 Shell 快照功能的正确性、可靠性和安全性。

该测试文件覆盖以下关键方面：
1. **快照内容正确性** - 验证捕获的函数、别名、环境变量和选项
2. **文件生命周期管理** - 验证快照文件的创建、重命名和删除
3. **进程隔离** - 确保快照进程不继承标准输入
4. **超时处理** - 验证超时后进程正确终止
5. **并发安全** - 验证多代快照的正确管理
6. **过期清理** - 验证基于 rollout 文件的清理逻辑

## 功能点目的

### 1. 内容验证测试
确保快照脚本正确捕获和输出 Shell 环境状态：
- 验证 `# Snapshot file` 标记存在
- 验证函数、别名、环境变量、选项都被捕获
- 验证无效变量名被过滤

### 2. 文件操作测试
验证快照文件的原子性操作：
- 创建后立即存在
- Drop 时自动删除
- 多代快照使用不同路径

### 3. 进程隔离测试
确保快照执行环境的独立性：
- 标准输入被正确重定向为 null
- 超时后进程被强制终止

### 4. 清理逻辑测试
验证过期快照的自动清理：
- 孤儿快照（无对应 rollout）被删除
- 过期 rollout 对应的快照被删除
- 活跃会话的快照被保留

## 具体技术实现

### 测试辅助结构

#### `BlockingStdinPipe` (Unix)
```rust
#[cfg(unix)]
struct BlockingStdinPipe {
    original: i32,      // 原始 stdin 文件描述符
    write_end: i32,     // 管道的写端
}
```

用于测试标准输入隔离：
1. 创建管道
2. 保存原始 stdin
3. 将管道读端替换为 stdin
4. Drop 时恢复原始 stdin

```rust
impl BlockingStdinPipe {
    fn install() -> Result<Self> {
        let mut fds = [0i32; 2];
        unsafe { libc::pipe(fds.as_mut_ptr()) };
        
        let original = unsafe { libc::dup(libc::STDIN_FILENO) };
        unsafe { libc::dup2(fds[0], libc::STDIN_FILENO) };
        unsafe { libc::close(fds[0]) };
        
        Ok(Self { original, write_end: fds[1] })
    }
}

impl Drop for BlockingStdinPipe {
    fn drop(&mut self) {
        unsafe {
            libc::dup2(self.original, libc::STDIN_FILENO);
            libc::close(self.original);
            libc::close(self.write_end);
        }
    }
}
```

### 关键测试用例

#### 1. 内容剥离测试
```rust
#[test]
fn strip_snapshot_preamble_removes_leading_output() {
    let snapshot = "noise\n# Snapshot file\nexport PATH=/bin\n";
    let cleaned = strip_snapshot_preamble(snapshot).expect("snapshot marker exists");
    assert_eq!(cleaned, "# Snapshot file\nexport PATH=/bin\n");
}

#[test]
fn strip_snapshot_preamble_requires_marker() {
    let result = strip_snapshot_preamble("missing header");
    assert!(result.is_err());
}
```

验证 `strip_snapshot_preamble` 函数：
- 正确移除标记前的内容
- 无标记时返回错误

#### 2. 文件名解析测试
```rust
#[test]
fn snapshot_file_name_parser_supports_legacy_and_suffixed_names() {
    let session_id = "019cf82b-6a62-7700-bbbd-46909794ef89";
    
    assert_eq!(
        snapshot_session_id_from_file_name(&format!("{session_id}.sh")),
        Some(session_id)
    );
    assert_eq!(
        snapshot_session_id_from_file_name(&format!("{session_id}.123.sh")),
        Some(session_id)
    );
    assert_eq!(
        snapshot_session_id_from_file_name(&format!("{session_id}.tmp-123")),
        Some(session_id)
    );
    assert_eq!(
        snapshot_session_id_from_file_name("not-a-snapshot.txt"),
        None
    );
}
```

验证文件名解析支持：
- 旧格式：`{session_id}.sh`
- 新格式：`{session_id}.{nonce}.sh`
- 临时文件：`{session_id}.tmp-{nonce}`
- 无效文件返回 `None`

#### 3. Bash 快照过滤测试
```rust
#[cfg(unix)]
#[test]
fn bash_snapshot_filters_invalid_exports() -> Result<()> {
    let output = Command::new("/bin/bash")
        .arg("-c")
        .arg(bash_snapshot_script())
        .env("BASH_ENV", "/dev/null")
        .env("VALID_NAME", "ok")
        .env("PWD", "/tmp/stale")
        .env("NEXTEST_BIN_EXE_codex-write-config-schema", "/path/to/bin")
        .env("BAD-NAME", "broken")
        .output()?;
    
    assert!(output.status.success());
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("VALID_NAME"));
    assert!(!stdout.contains("PWD=/tmp/stale"));  // 排除 PWD
    assert!(!stdout.contains("NEXTEST_BIN_EXE_codex-write-config-schema"));  // 排除无效名称
    assert!(!stdout.contains("BAD-NAME"));  // 排除带连字符的名称
    
    Ok(())
}
```

验证环境变量过滤：
- 保留有效变量名（`VALID_NAME`）
- 排除 `PWD` 和 `OLDPWD`
- 排除非标识符名称（带连字符、特殊字符）

#### 4. 多行变量测试
```rust
#[cfg(unix)]
#[test]
fn bash_snapshot_preserves_multiline_exports() -> Result<()> {
    let multiline_cert = "-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----";
    let output = Command::new("/bin/bash")
        .arg("-c")
        .arg(bash_snapshot_script())
        .env("BASH_ENV", "/dev/null")
        .env("MULTILINE_CERT", multiline_cert)
        .output()?;
    
    // 验证快照可以被正确 source
    let validate = Command::new("/bin/bash")
        .arg("-c")
        .arg("set -e; . \"$1\"")
        .arg("bash")
        .arg(&snapshot_path)
        .env("BASH_ENV", "/dev/null")
        .output()?;
    
    assert!(validate.status.success());
    Ok(())
}
```

验证多行环境变量的正确处理：
- 多行值被正确捕获
- 生成的快照可以被 Bash 正确 source

#### 5. 文件生命周期测试
```rust
#[cfg(unix)]
#[tokio::test]
async fn try_new_creates_and_deletes_snapshot_file() -> Result<()> {
    let dir = tempdir()?;
    let shell = Shell { ... };
    
    let snapshot = ShellSnapshot::try_new(dir.path(), ThreadId::new(), dir.path(), &shell)
        .await
        .expect("snapshot should be created");
    let path = snapshot.path.clone();
    assert!(path.exists());
    
    drop(snapshot);
    assert!(!path.exists());  // Drop 后文件被删除
    
    Ok(())
}
```

验证 `ShellSnapshot` 的 RAII 语义：
- 创建后文件存在
- Drop 后文件被删除

#### 6. 多代快照测试
```rust
#[cfg(unix)]
#[tokio::test]
async fn try_new_uses_distinct_generation_paths() -> Result<()> {
    let dir = tempdir()?;
    let session_id = ThreadId::new();
    
    let initial_snapshot = ShellSnapshot::try_new(dir.path(), session_id, dir.path(), &shell)
        .await?;
    let refreshed_snapshot = ShellSnapshot::try_new(dir.path(), session_id, dir.path(), &shell)
        .await?;
    
    assert_ne!(initial_path, refreshed_path);  // 不同路径
    
    drop(initial_snapshot);
    assert!(!initial_path.exists());  // 旧快照删除
    assert!(refreshed_path.exists());  // 新快照保留
    
    Ok(())
}
```

验证同一会话的多代快照：
- 使用不同文件名（基于时间戳 nonce）
- 旧快照删除不影响新快照

#### 7. 标准输入隔离测试
```rust
#[cfg(unix)]
#[tokio::test]
async fn snapshot_shell_does_not_inherit_stdin() -> Result<()> {
    let _stdin_guard = BlockingStdinPipe::install()?;
    
    // 创建特殊的 .bashrc，尝试读取 stdin
    let bashrc = format!("read -t 1 -r ignored\nprintf '%s' \"$?\" > \"{read_status_display}\"\n");
    fs::write(home.join(".bashrc"), bashrc).await?;
    
    // 执行快照
    let output = run_script_with_timeout(&shell, &script, Duration::from_secs(2), true, home)
        .await?;
    
    let read_status = fs::read_to_string(&read_status_path).await?;
    assert_eq!(read_status, "1");  // read 命令看到 EOF，返回 1
    
    Ok(())
}
```

验证快照进程的标准输入隔离：
- 使用 `BlockingStdinPipe` 替换 stdin 为管道
- Shell 启动脚本中的 `read` 命令应该立即看到 EOF
- `read` 退出码为 1 表示超时/EOF，而非阻塞等待

#### 8. 超时终止测试
```rust
#[cfg(target_os = "linux")]
#[tokio::test]
async fn timed_out_snapshot_shell_is_terminated() -> Result<()> {
    let dir = tempdir()?;
    let script = format!("echo $$ > \"{}\"; sleep 30", pid_path.display());
    
    let err = run_script_with_timeout(&shell, &script, Duration::from_secs(1), true, dir.path())
        .await
        .expect_err("snapshot shell should time out");
    
    // 验证进程已终止
    let pid = fs::read_to_string(&pid_path).await?.trim().parse::<i32>()?;
    loop {
        let kill_status = StdCommand::new("kill")
            .arg("-0")
            .arg(pid.to_string())
            .status()?;
        if !kill_status.success() {
            break;  // 进程不存在
        }
        sleep(TokioDuration::from_millis(50)).await;
    }
    
    Ok(())
}
```

验证超时后进程终止：
- 脚本写入 PID 后睡眠 30 秒
- 1 秒超时后应该返回错误
- 使用 `kill -0` 验证进程已不存在

#### 9. 清理逻辑测试
```rust
#[tokio::test]
async fn cleanup_stale_snapshots_removes_orphans_and_keeps_live() -> Result<()> {
    let dir = tempdir()?;
    let codex_home = dir.path();
    
    // 创建测试数据
    let live_session = ThreadId::new();
    let orphan_session = ThreadId::new();
    let live_snapshot = snapshot_dir.join(format!("{live_session}.123.sh"));
    let orphan_snapshot = snapshot_dir.join(format!("{orphan_session}.456.sh"));
    
    write_rollout_stub(codex_home, live_session).await?;  // 为活跃会话创建 rollout
    fs::write(&live_snapshot, "live").await?;
    fs::write(&orphan_snapshot, "orphan").await?;  // 孤儿快照，无 rollout
    
    cleanup_stale_snapshots(codex_home, ThreadId::new()).await?;
    
    assert!(live_snapshot.exists());      // 保留
    assert!(!orphan_snapshot.exists());   // 删除
    
    Ok(())
}
```

验证清理逻辑：
- 有对应 rollout 的快照保留
- 无对应 rollout 的孤儿快照删除

#### 10. 过期 rollout 测试
```rust
#[cfg(unix)]
#[tokio::test]
async fn cleanup_stale_snapshots_removes_stale_rollouts() -> Result<()> {
    let dir = tempdir()?;
    let stale_session = ThreadId::new();
    let stale_snapshot = snapshot_dir.join(format!("{stale_session}.123.sh"));
    
    let rollout_path = write_rollout_stub(codex_home, stale_session).await?;
    fs::write(&stale_snapshot, "stale").await?;
    
    // 设置 rollout 文件修改时间为 3 天前
    set_file_mtime(&rollout_path, SNAPSHOT_RETENTION + Duration::from_secs(60))?;
    
    cleanup_stale_snapshots(codex_home, ThreadId::new()).await?;
    
    assert!(!stale_snapshot.exists());  // 过期，删除
    Ok(())
}
```

验证基于 rollout 修改时间的清理：
- 使用 `set_file_mtime` 将文件时间设为 3 天前
- 超过 `SNAPSHOT_RETENTION`（3 天）的快照被删除

### 平台特定测试

| 测试 | 平台 | 说明 |
|------|------|------|
| `macos_zsh_snapshot_includes_sections` | macOS | Zsh 快照内容验证 |
| `linux_bash_snapshot_includes_sections` | Linux | Bash 快照内容验证 |
| `linux_sh_snapshot_includes_sections` | Linux | Sh 快照内容验证 |
| `windows_powershell_snapshot_includes_sections` | Windows | PowerShell 快照（被忽略） |

## 关键代码路径与文件引用

### 测试依赖图

```
shell_snapshot_tests.rs
├── shell_snapshot.rs (被测试模块)
│   ├── ShellSnapshot
│   ├── write_shell_snapshot()
│   ├── bash_snapshot_script()
│   ├── zsh_snapshot_script()
│   └── cleanup_stale_snapshots()
├── shell.rs
│   ├── Shell
│   └── ShellType
├── tempfile (测试工具)
│   └── tempdir()
├── pretty_assertions
│   └── assert_eq!
└── libc (Unix 测试)
    ├── pipe()
    ├── dup()
    └── dup2()
```

### 测试组织结构

```
#[cfg(test)]
#[path = "shell_snapshot_tests.rs"]
mod tests;
```

测试作为 `shell_snapshot.rs` 的子模块，通过 `#[path]` 属性指定文件路径。

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tempfile` | 创建临时测试目录 |
| `pretty_assertions` | 美观的断言输出 |
| `tokio` | 异步测试运行时 |
| `libc` | Unix 系统调用（管道、dup） |

### 系统依赖

| 组件 | 用途 |
|------|------|
| `/bin/bash` | Bash 快照测试 |
| `/bin/zsh` | Zsh 快照测试（macOS） |
| `/bin/sh` | Sh 快照测试 |
| `kill` | 验证进程终止 |

## 风险、边界与改进建议

### 已知风险

1. **平台条件编译**
   - 大量测试使用 `#[cfg(unix)]` 或 `#[cfg(target_os = "linux")]`
   - Windows 平台测试覆盖不足

2. **外部 Shell 依赖**
   - 测试依赖系统安装的 Bash/Zsh
   - 不同版本的行为可能略有差异

3. **时序敏感测试**
   - 超时测试依赖系统调度
   - 在慢速系统上可能不稳定

### 边界情况

1. **临时文件清理**
   ```rust
   let dir = tempdir()?;
   ```
   使用 `tempfile` 的 RAII 语义确保测试后清理。

2. **并发执行**
   - 测试使用唯一的 `ThreadId`，避免并发冲突
   - 但 `BlockingStdinPipe` 修改全局 stdin，需要串行执行

3. **时间操作精度**
   ```rust
   fn set_file_mtime(path: &Path, age: Duration) -> Result<()> {
       let now = SystemTime::now()
           .duration_since(SystemTime::UNIX_EPOCH)?
           .as_secs()
           .saturating_sub(age.as_secs());
       // ...
   }
   ```
   使用 `saturating_sub` 避免时间计算溢出。

### 改进建议

1. **测试稳定性**
   - 为超时测试添加重试机制
   - 使用模拟 Shell 替代真实系统 Shell

2. **覆盖率提升**
   - 添加 Zsh 特定功能测试（如 zsh 模块）
   - 添加更多错误路径测试

3. **Windows 支持**
   - 实现并启用 PowerShell 测试
   - 添加 Cmd 支持测试

4. **性能优化**
   - 并行执行独立的测试用例
   - 使用共享的临时目录减少 IO

5. **诊断增强**
   - 失败时输出更多调试信息
   - 添加快照内容对比工具

### 测试最佳实践

1. **使用 `pretty_assertions`**
   ```rust
   use pretty_assertions::assert_eq;
   ```
   提供清晰的差异输出。

2. **平台条件编译**
   ```rust
   #[cfg(unix)]
   #[tokio::test]
   async fn unix_specific_test() { ... }
   ```
   确保测试只在支持的平台运行。

3. **资源清理**
   ```rust
   impl Drop for BlockingStdinPipe {
       fn drop(&mut self) {
           // 恢复原始 stdin
       }
   }
   ```
   使用 RAII 模式确保测试资源清理。
