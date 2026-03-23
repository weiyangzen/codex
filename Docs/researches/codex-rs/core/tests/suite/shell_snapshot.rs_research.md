# shell_snapshot.rs 研究文档

## 场景与职责

`shell_snapshot.rs` 是 Codex Core 的集成测试套件，专注于验证 **Shell 快照（Shell Snapshot）** 功能。Shell 快照是 Codex 用于捕获和复用用户 shell 环境状态（如别名、函数、环境变量等）的机制，确保在沙箱环境中执行的命令能够继承用户的 shell 配置。

核心测试场景包括：
1. **Shell 快照生成** - 验证快照文件是否正确生成
2. **快照环境继承** - 验证执行命令时是否正确加载快照
3. **跨平台行为** - 验证 Linux 和 macOS 上的不同 shell 行为
4. **环境策略集成** - 验证 shell_environment_policy 与快照的交互
5. **生命周期管理** - 验证快照文件的创建和清理

## 功能点目的

### 1. ShellSnapshot 结构

测试验证 `ShellSnapshot` 结构的核心功能：

```rust
#[derive(Debug)]
struct SnapshotRun {
    begin: ExecCommandBeginEvent,    // 命令开始事件
    end: ExecCommandEndEvent,        // 命令结束事件
    snapshot_path: PathBuf,          // 快照文件路径
    snapshot_content: String,        // 快照内容
    codex_home: PathBuf,             // Codex 主目录
}
```

### 2. 平台特定行为

不同平台的 shell 调用方式不同：

**Linux:**
```
<shell> -lc <command>
```

**macOS:**
```
<shell> -c '. "$0" && exec "$@"' <shell> -c <command>
```

**Windows (PowerShell):**
```
powershell -NoProfile -Command "param($snapshot) . $snapshot; & @args" <snapshot> <command>
```

### 3. 快照内容结构

快照文件包含以下部分：
- `# Snapshot file` - 文件标记
- `# aliases` - 别名定义
- `# exports` - 环境变量导出
- `# setopts` - Shell 选项设置
- `# Functions` - 函数定义

## 具体技术实现

### 关键测试流程

#### 1. wait_for_snapshot 辅助函数

异步等待快照文件生成：

```rust
async fn wait_for_snapshot(codex_home: &Path) -> Result<PathBuf> {
    let snapshot_dir = codex_home.join("shell_snapshots");
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Ok(mut entries) = fs::read_dir(&snapshot_dir).await {
            while let Some(entry) = entries.next_entry().await? {
                let path = entry.path();
                if let Some(extension) = path.extension().and_then(|ext| ext.to_str()) {
                    if extension == "sh" || extension == "ps1" {
                        return Ok(path);
                    }
                }
            }
        }
        if Instant::now() >= deadline {
            anyhow::bail!("timed out waiting for shell snapshot");
        }
        sleep(Duration::from_millis(25)).await;
    }
}
```

#### 2. run_snapshot_command 辅助函数

执行带快照的统一执行命令测试：

```rust
async fn run_snapshot_command(command: &str) -> Result<SnapshotRun> {
    let builder = test_codex().with_config(move |config| {
        config.use_experimental_unified_exec_tool = true;
        config.features.enable(Feature::UnifiedExec).expect(...);
        config.features.enable(Feature::ShellSnapshot).expect(...);
    });
    let harness = TestCodexHarness::with_builder(builder).await?;
    
    // 构造 exec_command 参数
    let args = json!({
        "cmd": command,
        "yield_time_ms": 1000,
    });
    
    // 挂载 SSE 响应并执行
    // ...
    
    // 等待 ExecCommandBegin 和 ExecCommandEnd 事件
    let begin = wait_for_event_match(&codex, |ev| match ev {
        EventMsg::ExecCommandBegin(ev) if ev.call_id == call_id => Some(ev.clone()),
        _ => None,
    }).await;
    
    let snapshot_path = wait_for_snapshot(&codex_home).await?;
    let snapshot_content = fs::read_to_string(&snapshot_path).await?;
    
    // ...
}
```

#### 3. 快照内容验证

```rust
fn assert_posix_snapshot_sections(snapshot: &str) {
    assert!(snapshot.contains("# Snapshot file"));
    assert!(snapshot.contains("aliases "));
    assert!(snapshot.contains("exports "));
    assert!(snapshot.contains("setopts "));
    assert!(snapshot.contains("PATH"), "snapshot should include PATH exports");
}
```

### 关键数据结构

#### ExecCommandBeginEvent

```rust
pub struct ExecCommandBeginEvent {
    pub call_id: String,
    pub command: Vec<String>,  // 实际执行的命令数组
    pub cwd: PathBuf,
}
```

#### ExecCommandEndEvent

```rust
pub struct ExecCommandEndEvent {
    pub call_id: String,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}
```

### 环境策略测试

测试验证 `shell_environment_policy` 与快照的交互：

```rust
fn policy_set_path_for_test() -> HashMap<String, String> {
    HashMap::from([("PATH".to_string(), POLICY_PATH_FOR_TEST.to_string())])
}

fn snapshot_override_content_for_policy_test() -> String {
    format!(
        "# Snapshot file\nexport PATH='{SNAPSHOT_PATH_FOR_TEST}'\nexport {SNAPSHOT_MARKER_VAR}='{SNAPSHOT_MARKER_VALUE}'\n"
    )
}
```

测试流程：
1. 首次执行生成快照
2. 手动覆盖快照内容（模拟用户环境）
3. 再次执行验证策略是否正确应用

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/shell_snapshot.rs` - 本测试文件
- `codex-rs/core/tests/common/test_codex.rs` - 测试基础设施
- `codex-rs/core/tests/common/zsh_fork.rs` - zsh fork 测试辅助函数

### 被测试的源代码
- `codex-rs/core/src/shell_snapshot.rs` - Shell 快照核心实现
- `codex-rs/core/src/shell.rs` - Shell 抽象和检测
- `codex-rs/core/src/tools/handlers/unified_exec.rs` - 统一执行工具
- `codex-rs/core/src/tools/runtimes/shell/zsh_fork_backend.rs` - Zsh fork 后端

### 核心测试用例

| 测试用例 | 平台 | 描述 |
|---------|------|------|
| `linux_unified_exec_uses_shell_snapshot` | Linux | 验证统一执行使用 shell 快照 |
| `linux_shell_command_uses_shell_snapshot` | Linux | 验证 shell_command 使用快照 |
| `shell_command_snapshot_preserves_shell_environment_policy_set` | Unix | 验证环境策略在快照后生效 |
| `linux_unified_exec_snapshot_preserves_shell_environment_policy_set` | Linux | 验证统一执行的环境策略继承 |
| `shell_command_snapshot_still_intercepts_apply_patch` | Unix | 验证快照不干扰 apply_patch 拦截 |
| `shell_snapshot_deleted_after_shutdown_with_skills` | Unix | 验证关闭后快照清理 |
| `macos_unified_exec_uses_shell_snapshot` | macOS | 验证 macOS 上的快照行为 |
| `windows_unified_exec_uses_shell_snapshot` | Windows | 验证 Windows 上的快照行为（当前忽略） |

### 快照脚本生成

在 `shell_snapshot.rs` 中，针对不同 shell 生成不同的快照脚本：

**Zsh:**
```bash
# 加载 .zshrc
# 输出别名、函数、选项、环境变量
```

**Bash:**
```bash
# 加载 .bashrc
# 输出别名、函数、选项、环境变量
```

**PowerShell:**
```powershell
# 输出函数、别名、环境变量
```

## 依赖与外部交互

### 测试依赖

1. **core_test_support**
   - `TestCodexHarness` - 测试工具封装
   - `wait_for_event_match` - 异步事件等待
   - `responses::mount_sse_sequence` - SSE 响应模拟

2. **tokio** - 异步运行时
   - `tokio::fs` - 异步文件操作
   - `tokio::time::sleep` - 异步延迟

3. **tempfile** - 临时目录管理

### 外部命令依赖

测试执行以下外部命令：
- `echo` - 简单输出测试
- `printf` - 格式化输出测试
- `sleep` - 延迟测试
- `touch` - 文件操作测试

### 特性标志

测试涉及的特性：
- `Feature::UnifiedExec` - 统一执行工具
- `Feature::ShellSnapshot` - Shell 快照功能

### 协议事件

测试监听的事件：
- `EventMsg::ExecCommandBegin` - 命令开始
- `EventMsg::ExecCommandEnd` - 命令结束
- `EventMsg::TurnComplete` - 回合完成
- `EventMsg::ShutdownComplete` - 关闭完成

## 风险、边界与改进建议

### 当前风险

1. **Windows 测试忽略** - `windows_unified_exec_uses_shell_snapshot` 测试被标记为 `#[ignore]`，Windows 平台覆盖不足
2. **macOS 网络限制** - macOS 测试需要无限制网络访问，CI 环境可能受限
3. **时序敏感** - 快照生成和清理依赖时序，可能存在竞态条件
4. **平台差异** - Linux 和 macOS 的 shell 调用方式差异大，维护成本高

### 边界情况

1. **快照超时** - `wait_for_snapshot` 使用 5 秒超时，慢系统可能失败
2. **并发快照** - 未测试多线程并发生成快照的场景
3. **大环境变量** - 未测试环境变量过大时的快照行为
4. **特殊字符** - 别名/函数中包含特殊字符时的转义处理

### 改进建议

1. **增加并发测试** - 验证多线程环境下的快照正确性
2. **增加压力测试** - 测试大量环境变量、大函数定义的场景
3. **增加恢复测试** - 验证快照损坏时的降级行为
4. **增加安全测试** - 验证快照内容不会泄露敏感信息
5. **统一平台行为** - 减少 Linux/macOS/Windows 的平台差异

### 相关配置项

```rust
config.use_experimental_unified_exec_tool = true;
config.features.enable(Feature::UnifiedExec)?;
config.features.enable(Feature::ShellSnapshot)?;
config.permissions.shell_environment_policy.r#set = ...;
```

### 监控指标

快照功能在代码中记录了以下遥测指标：
- `codex.shell_snapshot` - 快照生成计数
- `codex.shell_snapshot.duration_ms` - 快照生成耗时
- `codex.shell_snapshot.success` - 成功/失败标签

这些指标可用于生产环境监控快照功能的健康状况。
