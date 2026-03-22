# shell_snapshot.rs 深度研究文档

## 场景与职责

`shell_snapshot.rs` 是 Codex 核心模块中负责 Shell 环境状态捕获和持久化的组件，位于 `codex-rs/core/src/` 目录下。其主要职责是：

1. **捕获 Shell 环境状态** - 获取当前 Shell 的函数、别名、环境变量和选项设置
2. **持久化快照** - 将捕获的状态保存到文件系统，供后续恢复使用
3. **支持多 Shell 类型** - 适配 Zsh、Bash、Sh 和 PowerShell 的不同特性
4. **异步管理** - 使用异步任务执行快照操作，避免阻塞主流程
5. **生命周期管理** - 自动清理过期快照，防止磁盘空间泄漏

该模块解决的核心问题是：在 Codex 执行命令时，需要确保命令在正确的 Shell 环境中运行，包括用户的自定义函数、别名和环境变量。通过快照机制，可以在新的 Shell 进程中恢复这些环境状态。

## 功能点目的

### 1. Shell 状态捕获
捕获以下 Shell 状态：
- **函数定义** - Shell 函数（`functions`/`declare -f`）
- **Shell 选项** - `setopt`（Zsh）或 `set -o`（Bash/Sh）
- **别名** - 命令别名（`alias`）
- **环境变量** - 导出的变量（`export`）

### 2. 快照文件管理
- 生成唯一的快照文件名（基于时间戳）
- 原子性写入（先写临时文件，再重命名）
- 自动清理（Drop 时删除文件）

### 3. 异步快照任务
- 在后台执行快照捕获
- 支持超时控制（10 秒）
- 遥测数据收集

### 4. 过期快照清理
- 基于会话 rollout 文件的存在性判断
- 3 天保留期（`SNAPSHOT_RETENTION`）
- 活跃会话保护

## 具体技术实现

### 核心数据结构

#### `ShellSnapshot`
```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShellSnapshot {
    pub path: PathBuf,    // 快照文件路径
    pub cwd: PathBuf,     // 捕获时的工作目录
}
```

#### 常量定义
```rust
const SNAPSHOT_TIMEOUT: Duration = Duration::from_secs(10);           // 快照超时
const SNAPSHOT_RETENTION: Duration = Duration::from_secs(60*60*24*3); // 3天保留期
const SNAPSHOT_DIR: &str = "shell_snapshots";                         // 快照目录名
const EXCLUDED_EXPORT_VARS: &[&str] = &["PWD", "OLDPWD"];             // 排除的变量
```

### 关键流程

#### 1. 启动快照任务 (`start_snapshotting`)
```rust
pub fn start_snapshotting(
    codex_home: PathBuf,
    session_id: ThreadId,
    session_cwd: PathBuf,
    shell: &mut Shell,
    session_telemetry: SessionTelemetry,
) -> watch::Sender<Option<Arc<ShellSnapshot>>> {
    let (shell_snapshot_tx, shell_snapshot_rx) = watch::channel(None);
    shell.shell_snapshot = shell_snapshot_rx;
    
    Self::spawn_snapshot_task(
        codex_home,
        session_id,
        session_cwd,
        shell.clone(),
        shell_snapshot_tx.clone(),
        session_telemetry,
    );
    
    shell_snapshot_tx
}
```

#### 2. 异步任务执行 (`spawn_snapshot_task`)
```rust
fn spawn_snapshot_task(...) {
    let snapshot_span = info_span!("shell_snapshot", thread_id = %session_id);
    tokio::spawn(
        async move {
            let timer = session_telemetry.start_timer("codex.shell_snapshot.duration_ms", &[]);
            let snapshot = ShellSnapshot::try_new(...).await.map(Arc::new);
            
            // 记录遥测
            let success = snapshot.is_ok();
            let success_tag = if success { "true" } else { "false" };
            let _ = timer.map(|timer| timer.record(&[("success", success_tag)]));
            
            // 发送结果
            let _ = shell_snapshot_tx.send(snapshot.ok());
        }
        .instrument(snapshot_span),
    );
}
```

#### 3. 快照创建 (`try_new`)
```rust
async fn try_new(
    codex_home: &Path,
    session_id: ThreadId,
    session_cwd: &Path,
    shell: &Shell,
) -> std::result::Result<Self, &'static str> {
    // 1. 生成唯一路径
    let extension = match shell.shell_type {
        ShellType::PowerShell => "ps1",
        _ => "sh",
    };
    let nonce = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let path = codex_home
        .join(SNAPSHOT_DIR)
        .join(format!("{session_id}.{nonce}.{extension}"));
    let temp_path = codex_home
        .join(SNAPSHOT_DIR)
        .join(format!("{session_id}.tmp-{nonce}"));
    
    // 2. 清理旧快照（后台任务）
    tokio::spawn(async move {
        if let Err(err) = cleanup_stale_snapshots(&codex_home, cleanup_session_id).await {
            tracing::warn!("Failed to clean up shell snapshots: {err:?}");
        }
    });
    
    // 3. 写入快照
    let temp_path = match write_shell_snapshot(shell.shell_type.clone(), &temp_path, session_cwd).await {
        Ok(path) => path,
        Err(err) => return Err("write_failed"),
    };
    
    // 4. 验证快照
    if let Err(err) = validate_snapshot(shell, &temp_path.path, session_cwd).await {
        remove_snapshot_file(&temp_path.path).await;
        return Err("validation_failed");
    }
    
    // 5. 原子性重命名
    if let Err(err) = fs::rename(&temp_path.path, &path).await {
        remove_snapshot_file(&temp_path.path).await;
        return Err("write_failed");
    }
    
    Ok(Self { path, cwd: session_cwd.to_path_buf() })
}
```

### Shell 特定脚本生成

#### Zsh 快照脚本 (`zsh_snapshot_script`)
```rust
fn zsh_snapshot_script() -> String {
    r##"if [[ -n "$ZDOTDIR" ]]; then
  rc="$ZDOTDIR/.zshrc"
else
  rc="$HOME/.zshrc"
fi
[[ -r "$rc" ]] && . "$rc"
print '# Snapshot file'
print '# Unset all aliases to avoid conflicts with functions'
print 'unalias -a 2>/dev/null || true'
print '# Functions'
functions
print ''
setopt_count=$(setopt | wc -l | tr -d ' ')
print "# setopts $setopt_count"
setopt | sed 's/^/setopt /'
print ''
alias_count=$(alias -L | wc -l | tr -d ' ')
print "# aliases $alias_count"
alias -L
print ''
export_lines=$(export -p | awk '...')
export_count=$(printf '%s\n' "$export_lines" | sed '/^$/d' | wc -l | tr -d ' ')
print "# exports $export_count"
if [[ -n "$export_lines" ]]; then
  print -r -- "$export_lines"
fi
"##
}
```

**关键步骤：**
1. 加载 `.zshrc`（考虑 `ZDOTDIR`）
2. 输出标记行 `# Snapshot file`
3. 取消所有别名（避免与函数冲突）
4. 输出函数定义
5. 输出 `setopt` 设置
6. 输出别名定义
7. 输出环境变量（过滤 `PWD`、`OLDPWD` 和无效名称）

#### Bash 快照脚本 (`bash_snapshot_script`)
类似 Zsh，但使用 Bash 语法：
- 加载 `.bashrc`（考虑 `BASH_ENV`）
- 使用 `declare -f` 输出函数
- 使用 `set -o` 输出选项
- 使用 `alias -p` 输出别名
- 使用 `compgen -e` 枚举环境变量

#### Sh 快照脚本 (`sh_snapshot_script`)
更通用的 POSIX 兼容脚本：
- 加载 `$ENV` 文件
- 兼容 `typeset -f` 和 `declare -f`
- 处理 `set -o` 可能失败的情况
- 处理 `alias` 可能失败的情况
- 使用 `env` 作为 `export -p` 的备选

#### PowerShell 快照脚本 (`powershell_snapshot_script`)
```powershell
$ErrorActionPreference = 'Stop'
Write-Output '# Snapshot file'
Write-Output '# Unset all aliases to avoid conflicts with functions'
Write-Output 'Remove-Item Alias:* -ErrorAction SilentlyContinue'
Write-Output '# Functions'
Get-ChildItem Function: | ForEach-Object {
    "function {0} {{`n{1}`n}}" -f $_.Name, $_.Definition
}
Write-Output ''
$aliases = Get-Alias
Write-Output ("# aliases " + $aliases.Count)
$aliases | ForEach-Object {
    "Set-Alias -Name {0} -Value {1}" -f $_.Name, $_.Definition
}
Write-Output ''
$envVars = Get-ChildItem Env:
Write-Output ("# exports " + $envVars.Count)
$envVars | ForEach-Object {
    $escaped = $_.Value -replace "'", "''"
    "`$env:{0}='{1}'" -f $_.Name, $_.Escaped
}
```

**注意：** PowerShell 和 Cmd 快照当前返回错误（`bail!`），表示尚未完全支持。

### 快照验证
```rust
async fn validate_snapshot(shell: &Shell, snapshot_path: &Path, cwd: &Path) -> Result<()> {
    let snapshot_path_display = snapshot_path.display();
    let script = format!("set -e; . \"{snapshot_path_display}\"");
    run_script_with_timeout(
        shell,
        &script,
        SNAPSHOT_TIMEOUT,
        /*use_login_shell*/ false,
        cwd,
    )
    .await
    .map(|_| ())
}
```

通过尝试 source 快照文件来验证其语法正确性。

### 过期快照清理
```rust
pub async fn cleanup_stale_snapshots(codex_home: &Path, active_session_id: ThreadId) -> Result<()> {
    let snapshot_dir = codex_home.join(SNAPSHOT_DIR);
    let mut entries = fs::read_dir(&snapshot_dir).await?;
    let now = SystemTime::now();
    
    while let Some(entry) = entries.next_entry().await? {
        // 1. 解析文件名获取 session_id
        let Some(session_id) = snapshot_session_id_from_file_name(&file_name) else {
            remove_snapshot_file(&path).await;
            continue;
        };
        
        // 2. 跳过活跃会话
        if session_id == active_session_id {
            continue;
        }
        
        // 3. 检查对应的 rollout 文件
        let rollout_path = find_thread_path_by_id_str(codex_home, session_id).await?;
        let Some(rollout_path) = rollout_path else {
            remove_snapshot_file(&path).await;  // 无 rollout，删除
            continue;
        };
        
        // 4. 检查 rollout 修改时间
        let modified = fs::metadata(&rollout_path).await?.modified()?;
        if now.duration_since(modified)?.as_secs() >= SNAPSHOT_RETENTION.as_secs() {
            remove_snapshot_file(&path).await;
        }
    }
    
    Ok(())
}
```

## 关键代码路径与文件引用

### 模块依赖图

```
shell_snapshot.rs
├── shell.rs
│   ├── Shell
│   └── ShellType
├── rollout::list
│   └── find_thread_path_by_id_str()
├── codex_otel::SessionTelemetry
├── shell_snapshot_tests.rs (测试模块)
└── tokio
    ├── fs
    ├── process::Command
    ├── sync::watch
    └── time::timeout
```

### 调用关系

**快照创建流程：**
```
ShellSnapshot::start_snapshotting()
└── spawn_snapshot_task()
    └── ShellSnapshot::try_new()
        ├── write_shell_snapshot()
        │   ├── capture_snapshot()
        │   │   └── run_shell_script()
        │   └── strip_snapshot_preamble()
        ├── validate_snapshot()
        └── fs::rename() (原子性)
```

**清理流程：**
```
cleanup_stale_snapshots()
├── fs::read_dir()
├── snapshot_session_id_from_file_name()
├── find_thread_path_by_id_str()
└── remove_snapshot_file()
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步文件操作、进程执行、超时控制 |
| `tracing` | 日志和 span 跟踪 |
| `anyhow` | 错误处理 |
| `codex_protocol` | `ThreadId` 类型 |
| `codex_otel` | 遥测数据收集 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `shell.rs` | `Shell` 和 `ShellType` 定义 |
| `rollout::list` | 查找会话 rollout 文件 |

### 系统交互

- 文件系统：读写 `$CODEX_HOME/shell_snapshots/`
- 进程执行：启动 Shell 子进程执行快照脚本
- 信号处理：使用 `codex_utils_pty::process_group::detach_from_tty()` 分离 TTY

## 风险、边界与改进建议

### 已知风险

1. **PowerShell/Cmd 支持不完整**
   ```rust
   if shell_type == ShellType::PowerShell || shell_type == ShellType::Cmd {
       bail!("Shell snapshot not supported yet for {shell_type:?}");
   }
   ```
   Windows 平台的快照功能尚未实现。

2. **Shell 注入风险**
   快照脚本通过字符串拼接生成，如果环境变量值包含恶意代码，可能导致注入。当前通过过滤变量名（仅允许有效标识符）缓解。

3. **大文件处理**
   如果用户有大量函数或环境变量，快照文件可能很大。当前无大小限制。

### 边界情况

1. **超时处理**
   ```rust
   let output = timeout(snapshot_timeout, handler.output()).await
       .map_err(|_| anyhow!("Snapshot command timed out for {shell_name}"))?
   ```
   超时后使用 `kill_on_drop(true)` 确保进程终止。

2. **前置内容剥离**
   ```rust
   fn strip_snapshot_preamble(snapshot: &str) -> Result<String> {
       let marker = "# Snapshot file";
       let Some(start) = snapshot.find(marker) else {
           bail!("Snapshot output missing marker {marker}");
       };
       Ok(snapshot[start..].to_string())
   }
   ```
   Shell 启动时可能输出欢迎消息或 MOTD，通过查找标记行定位实际内容。

3. **文件名解析**
   ```rust
   fn snapshot_session_id_from_file_name(file_name: &str) -> Option<&str> {
       let (stem, extension) = file_name.rsplit_once('.')?;
       match extension {
           "sh" | "ps1" => Some(stem.split_once('.').map_or(stem, |(session_id, _)| session_id)),
           _ if extension.starts_with("tmp-") => Some(stem),
           _ => None,
       }
   }
   ```
   支持多种文件名格式：
   - `{session_id}.sh`（旧格式）
   - `{session_id}.{nonce}.sh`（新格式）
   - `{session_id}.tmp-{nonce}`（临时文件）

### 改进建议

1. **Windows 支持**
   - 完成 PowerShell 快照实现
   - 添加 Cmd 支持
   - 处理 Windows 路径差异

2. **安全性增强**
   - 对导出的变量值进行转义验证
   - 添加快照文件签名验证
   - 限制快照文件大小

3. **性能优化**
   - 增量快照（仅捕获变化）
   - 压缩快照内容
   - 并行执行多个 Shell 的快照

4. **可靠性改进**
   - 快照失败时自动重试
   - 更详细的错误分类
   - 快照恢复时的冲突处理

5. **遥测增强**
   - 记录快照大小分布
   - 跟踪快照使用频率
   - 分析快照内容类型

6. **配置选项**
   - 允许用户排除特定变量
   - 自定义快照保留期
   - 选择是否包含特定 Shell 特性

### 测试覆盖

测试位于 `shell_snapshot_tests.rs`，包括：
- 快照文件创建和删除
- 多代快照路径区分
- 标准输入隔离验证
- 超时终止验证
- 快照内容结构验证
- 过期快照清理逻辑
