# seatbelt.rs 研究文档

## 场景与职责

`seatbelt.rs` 是 Codex CLI 的 macOS 专用模块，位于 `codex-rs/cli/src/debug_sandbox/` 目录下。其核心职责是**捕获和记录 macOS Seatbelt 沙箱的权限拒绝（denial）事件**，帮助开发者调试沙箱策略配置。

### 使用场景

1. **沙箱策略调试**：当命令在 Seatbelt 沙箱中运行失败时，需要了解具体被拒绝的权限
2. **策略优化**：通过分析拒绝日志，识别需要放宽的沙箱策略
3. **安全审计**：追踪沙箱化进程尝试访问的受限资源

### 架构位置

```
cli/src/debug_sandbox/
├── mod.rs           # 主模块，协调 Seatbelt/Landlock/Windows 沙箱
├── pid_tracker.rs   # 进程树追踪（被本模块使用）
└── seatbelt.rs      # 本文件：拒绝日志捕获与解析
```

### CLI 入口

```bash
# 启用拒绝日志记录
codex sandbox macos --log-denials <command>
```

---

## 功能点目的

### 1. 拒绝日志捕获（DenialLogger）

- **目的**：实时捕获 macOS 系统的沙箱拒绝日志
- **机制**：使用 `log stream` 命令订阅系统日志
- **过滤**：通过谓词（predicate）只捕获与沙箱相关的日志

### 2. 进程归因

- **目的**：将拒绝事件归因到被监控的进程树
- **机制**：结合 `PidTracker` 追踪所有后代进程
- **输出**：提取进程名称和被拒绝的能力（capability）

### 3. 日志解析与去重

- **目的**：从原始日志中提取结构化信息
- **机制**：使用正则表达式解析 `Sandbox:` 格式的日志行
- **去重**：使用 HashSet 避免重复报告相同的拒绝

---

## 具体技术实现

### 核心数据结构

```rust
/// 单个沙箱拒绝事件
pub struct SandboxDenial {
    pub name: String,        // 进程名称
    pub capability: String,  // 被拒绝的能力/权限
}

/// 拒绝日志记录器
pub struct DenialLogger {
    log_stream: Child,                    // log stream 子进程
    pid_tracker: Option<PidTracker>,      // 进程树追踪器
    log_reader: Option<JoinHandle<Vec<u8>>>, // 异步日志读取任务
}
```

### 日志流启动

```rust
fn start_log_stream() -> Option<Child> {
    const PREDICATE: &str = r#"(((processID == 0) AND (senderImagePath CONTAINS "/Sandbox")) OR (subsystem == "com.apple.sandbox.reporting"))"#;
    
    tokio::process::Command::new("log")
        .args(["stream", "--style", "ndjson", "--predicate", PREDICATE])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .ok()
}
```

**谓词说明**：
- `processID == 0 AND senderImagePath CONTAINS "/Sandbox"`：捕获内核沙箱消息
- `subsystem == "com.apple.sandbox.reporting"`：捕获沙箱子系统报告

### 日志解析

```rust
fn parse_message(msg: &str) -> Option<(i32, String, String)> {
    // 示例消息：
    // Sandbox: processname(1234) deny(1) capability-name args...
    static RE: std::sync::OnceLock<regex_lite::Regex> = std::sync::OnceLock::new();
    let re = RE.get_or_init(|| {
        regex_lite::Regex::new(
            r"^Sandbox:\s*(.+?)\((\d+)\)\s+deny\(.*?\)\s*(.+)$"
        ).unwrap()
    });
    
    let (_, [name, pid_str, capability]) = re.captures(msg)?.extract();
    let pid = pid_str.trim().parse::<i32>().ok()?;
    Some((pid, name.to_string(), capability.to_string()))
}
```

### 拒绝收集流程

```rust
pub(crate) async fn finish(mut self) -> Vec<SandboxDenial> {
    // 1. 停止 PID 追踪，获取所有监控的进程 ID
    let pid_set = match self.pid_tracker {
        Some(tracker) => tracker.stop().await,
        None => Default::default(),
    };
    
    if pid_set.is_empty() {
        return Vec::new();
    }
    
    // 2. 终止 log stream 进程
    let _ = self.log_stream.kill().await;
    let _ = self.log_stream.wait().await;
    
    // 3. 获取日志内容
    let logs_bytes = match self.log_reader.take() {
        Some(handle) => handle.await.unwrap_or_default(),
        None => Vec::new(),
    };
    let logs = String::from_utf8_lossy(&logs_bytes);
    
    // 4. 解析并过滤日志
    let mut seen: HashSet<(String, String)> = HashSet::new();
    let mut denials: Vec<SandboxDenial> = Vec::new();
    
    for line in logs.lines() {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(line)
            && let Some(msg) = json.get("eventMessage").and_then(|v| v.as_str())
            && let Some((pid, name, capability)) = parse_message(msg)
            && pid_set.contains(&pid)        // 只保留监控的进程
            && seen.insert((name.clone(), capability.clone()))  // 去重
        {
            denials.push(SandboxDenial { name, capability });
        }
    }
    denials
}
```

### 异步日志读取

```rust
pub(crate) fn new() -> Option<Self> {
    let mut log_stream = start_log_stream()?;
    let stdout = log_stream.stdout.take()?;
    
    // 在独立任务中读取日志
    let log_reader = tokio::spawn(async move {
        let mut reader = tokio::io::BufReader::new(stdout);
        let mut logs = Vec::new();
        let mut chunk = Vec::new();
        loop {
            match reader.read_until(b'\n', &mut chunk).await {
                Ok(0) | Err(_) => break,      // EOF 或错误
                Ok(_) => {
                    logs.extend_from_slice(&chunk);
                    chunk.clear();
                }
            }
        }
        logs
    });
    
    Some(Self {
        log_stream,
        pid_tracker: None,
        log_reader: Some(log_reader),
    })
}
```

---

## 关键代码路径与文件引用

### 本文件关键函数

| 函数/方法 | 行号 | 职责 |
|-----------|------|------|
| `DenialLogger::new` | 20-44 | 启动 log stream，创建异步读取任务 |
| `DenialLogger::on_child_spawn` | 46-50 | 在子进程启动时开始 PID 追踪 |
| `DenialLogger::finish` | 52-84 | 停止追踪，收集并解析拒绝日志 |
| `start_log_stream` | 87-100 | 启动 macOS log stream 命令 |
| `parse_message` | 102-114 | 解析 Sandbox 格式的日志消息 |

### 调用方

**debug_sandbox.rs**（父模块）
```rust
// 创建 DenialLogger（仅在 --log-denials 标志时）
#[cfg(target_os = "macos")]
let mut denial_logger = log_denials.then(DenialLogger::new).flatten();

// 子进程启动后通知 DenialLogger
#[cfg(target_os = "macos")]
if let Some(denial_logger) = &mut denial_logger {
    denial_logger.on_child_spawn(&child);
}

// 子进程结束后收集并打印拒绝信息
#[cfg(target_os = "macos")]
if let Some(denial_logger) = denial_logger {
    let denials = denial_logger.finish().await;
    eprintln!("\n=== Sandbox denials ===");
    if denials.is_empty() {
        eprintln!("None found.");
    } else {
        for seatbelt::SandboxDenial { name, capability } in denials {
            eprintln!("({name}) {capability}");
        }
    }
}
```

### 依赖模块

**pid_tracker.rs**（同目录）
```rust
use super::pid_tracker::PidTracker;

pub(crate) fn on_child_spawn(&mut self, child: &Child) {
    if let Some(root_pid) = child.id() {
        self.pid_tracker = PidTracker::new(root_pid as i32);
    }
}
```

### CLI 参数定义

**lib.rs**（cli crate）
```rust
#[derive(Debug, Parser)]
pub struct SeatbeltCommand {
    /// While the command runs, capture macOS sandbox denials via `log stream` and print them after exit
    #[arg(long = "log-denials", default_value_t = false)]
    pub log_denials: bool,
    // ...
}
```

**main.rs**（cli 入口）
```rust
Some(Subcommand::Sandbox(sandbox_args)) => match sandbox_args.cmd {
    SandboxCommand::Macos(mut seatbelt_cli) => {
        codex_cli::debug_sandbox::run_command_under_seatbelt(
            seatbelt_cli,
            arg0_paths.codex_linux_sandbox_exe.clone(),
        ).await?;
    }
    // ...
}
```

---

## 依赖与外部交互

### 外部依赖

```toml
# Cargo.toml (codex-cli)
[dependencies]
tokio = { workspace = true, features = ["process", "io-util"] }
serde_json = { workspace = true }
regex-lite = { workspace = true }
```

### 模块依赖图

```
seatbelt.rs
    ├── pid_tracker.rs (PidTracker)
    ├── tokio::process (Child, Command)
    ├── tokio::io (AsyncBufReadExt, BufReader)
    ├── serde_json (日志解析)
    └── regex-lite (消息解析)
    
被 debug_sandbox.rs 使用
    └── run_command_under_seatbelt
    
依赖 macOS 系统命令
    └── /usr/bin/log stream
```

### 外部系统交互

| 组件 | 交互方式 | 用途 |
|------|----------|------|
| `log` 命令 | 子进程 | 订阅系统日志流 |
| `kqueue` | 系统调用（通过 pid_tracker） | 监控进程事件 |
| `proc_listchildpids` | 系统调用（通过 pid_tracker） | 获取子进程列表 |

### 平台限制

- **仅 macOS**：依赖 macOS 的 `log` 命令和 Seatbelt 沙箱日志格式
- 编译条件：`#[cfg(target_os = "macos")]`

---

## 风险、边界与改进建议

### 已知风险

1. **日志丢失风险**
   - 问题：`log stream` 启动和 PID 追踪开始之间存在时间窗口，可能丢失早期拒绝事件
   - 缓解：先启动 log stream，再 spawn 被监控进程

2. **权限要求**
   - 问题：读取某些系统日志可能需要特殊权限
   - 现状：当前实现使用 `.ok()` 忽略错误，可能静默失败

3. **正则表达式脆弱性**
   - 问题：日志格式可能随 macOS 版本变化
   - 现状：使用 `regex-lite`，但不支持复杂回退逻辑

4. **内存使用**
   - 问题：长时间运行的进程可能产生大量日志
   - 现状：所有日志存储在内存中，可能导致 OOM

5. **进程 ID 复用**
   - 问题：PID 可能在收集期间被复用
   - 缓解：PidTracker 使用 `seen` 集合，但时间窗口仍存在

### 边界条件

| 场景 | 处理 |
|------|------|
| log stream 启动失败 | 返回 None，静默禁用 |
| 无法获取 stdout | 返回 None，静默禁用 |
| PID 追踪失败 | 返回空集合，不报告拒绝 |
| 日志解析失败 | 跳过该行，继续处理 |
| 正则不匹配 | 返回 None，跳过 |
| 子进程快速退出 | 可能错过拒绝事件 |

### 改进建议

1. **增强错误报告**
   - 添加 `--verbose` 模式显示内部错误
   - 区分"无拒绝"和"无法收集日志"

2. **日志轮转支持**
   - 考虑使用临时文件存储日志，避免内存压力
   - 或实现日志大小限制和截断

3. **格式兼容性**
   - 添加对旧版 macOS 日志格式的支持
   - 或明确记录支持的 macOS 版本范围

4. **性能优化**
   - 考虑使用 `log show` 的 `--last` 选项而非实时流
   - 或使用 `OSLog` 框架的私有 API（如果可行）

5. **功能增强**
   - 添加时间戳信息
   - 记录拒绝次数统计
   - 支持导出为结构化格式（JSON）

6. **测试覆盖**
   - 当前无单元测试
   - 建议添加模拟日志解析测试
   - 集成测试需要真实沙箱拒绝场景

### 相关代码

**Seatbelt 策略文件**（core crate）：
- `codex-rs/core/src/seatbelt_base_policy.sbpl` - 基础策略
- `codex-rs/core/src/seatbelt_network_policy.sbpl` - 网络策略
- `codex-rs/core/src/seatbelt_permissions.rs` - 权限扩展

**相关测试**：
- `codex-rs/core/tests/suite/seatbelt.rs` - Seatbelt 集成测试
- `codex-rs/core/src/seatbelt_tests.rs` - Seatbelt 单元测试
