# session_log.rs 研究文档

## 场景与职责

`session_log.rs` 是 Codex TUI 的会话日志记录模块，负责在启用时记录 TUI 与核心层之间的所有交互事件。该模块主要用于调试和会话回放，提供高保真的操作记录。

该模块是一个可选功能，通过环境变量 `CODEX_TUI_RECORD_SESSION` 控制启用。日志以 JSON Lines (JSONL) 格式写入文件，便于后续分析和处理。

## 功能点目的

### 1. 会话事件记录
- 记录进入 TUI 的 AppEvent（入站事件）
- 记录从 TUI 发出的 Op（出站操作）
- 记录会话生命周期（开始、结束）

### 2. 结构化日志输出
- 使用 JSONL 格式，每行一个 JSON 对象
- 包含时间戳、方向、事件类型和载荷
- 便于程序化解析和分析

### 3. 可选功能控制
- 通过环境变量启用/禁用
- 支持自定义日志路径
- 默认使用日志目录自动生成文件名

## 具体技术实现

### 关键数据结构

```rust
// 全局单例日志记录器
static LOGGER: LazyLock<SessionLogger> = LazyLock::new(SessionLogger::new);

struct SessionLogger {
    file: OnceLock<Mutex<File>>,  // 懒加载的文件句柄
}
```

### 日志记录格式

```json
// 会话开始（元数据）
{
    "ts": "2025-01-01T00:00:00.000Z",
    "dir": "meta",
    "kind": "session_start",
    "cwd": "/path/to/project",
    "model": "gpt-4",
    "model_provider_id": "openai",
    "model_provider_name": "OpenAI"
}

// 入站事件（TUI 接收）
{
    "ts": "2025-01-01T00:00:01.000Z",
    "dir": "to_tui",
    "kind": "codex_event",
    "payload": { ... }
}

// 出站操作（TUI 发送）
{
    "ts": "2025-01-01T00:00:02.000Z",
    "dir": "from_tui",
    "kind": "op",
    "payload": { ... }
}

// 会话结束
{
    "ts": "2025-01-01T00:01:00.000Z",
    "dir": "meta",
    "kind": "session_end"
}
```

### 核心函数实现

#### 初始化 (`maybe_init`)

```rust
pub(crate) fn maybe_init(config: &Config) {
    // 检查环境变量 CODEX_TUI_RECORD_SESSION
    let enabled = std::env::var("CODEX_TUI_RECORD_SESSION")
        .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false);
    if !enabled {
        return;
    }

    // 确定日志路径
    let path = if let Ok(path) = std::env::var("CODEX_TUI_SESSION_LOG_PATH") {
        PathBuf::from(path)
    } else {
        // 默认路径: ~/.codex/logs/session-YYYYMMDDTHHMMSSZ.jsonl
        let mut p = codex_core::config::log_dir(config)?;
        let filename = format!("session-{}.jsonl", chrono::Utc::now().format("%Y%m%dT%H%M%SZ"));
        p.push(filename);
        p
    };

    // 打开文件并写入会话头
    LOGGER.open(path)?;
    LOGGER.write_json_line(header);
}
```

#### 文件打开 (`open`)

```rust
fn open(&self, path: PathBuf) -> std::io::Result<()> {
    let mut opts = OpenOptions::new();
    opts.create(true).truncate(true).write(true);

    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);  // Unix: 仅所有者可读写
    }

    let file = opts.open(path)?;
    self.file.get_or_init(|| Mutex::new(file));
    Ok(())
}
```

#### 入站事件记录 (`log_inbound_app_event`)

```rust
pub(crate) fn log_inbound_app_event(event: &AppEvent) {
    if !LOGGER.is_enabled() { return; }

    match event {
        AppEvent::CodexEvent(ev) => {
            write_record("to_tui", "codex_event", ev);
        }
        AppEvent::NewSession => {
            // 简化的记录（无载荷）
            write_json_line(json!({ "ts": ..., "dir": "to_tui", "kind": "new_session" }));
        }
        // ... 其他事件类型
        other => {
            // 噪声事件仅记录变体名
            write_json_line(json!({
                "ts": ...,
                "dir": "to_tui",
                "kind": "app_event",
                "variant": format!("{other:?}").split('(').next().unwrap()
            }));
        }
    }
}
```

#### 出站操作记录 (`log_outbound_op`)

```rust
pub(crate) fn log_outbound_op(op: &Op) {
    if !LOGGER.is_enabled() { return; }
    write_record("from_tui", "op", op);
}
```

#### 通用写入 (`write_record`)

```rust
fn write_record<T>(dir: &str, kind: &str, obj: &T)
where
    T: Serialize,
{
    let value = json!({
        "ts": now_ts(),      // RFC3339 时间戳
        "dir": dir,          // 方向: "to_tui", "from_tui", "meta"
        "kind": kind,        // 事件类型
        "payload": obj,      // 序列化载荷
    });
    LOGGER.write_json_line(value);
}
```

### 线程安全

```rust
fn write_json_line(&self, value: serde_json::Value) {
    let Some(mutex) = self.file.get() else { return; };
    
    // 处理 poisoned mutex（其他线程 panic 后）
    let mut guard = match mutex.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    
    // 序列化并写入，带错误处理
    match serde_json::to_string(&value) {
        Ok(serialized) => {
            if let Err(e) = guard.write_all(serialized.as_bytes()) {
                tracing::warn!("session log write error: {}", e);
                return;
            }
            if let Err(e) = guard.write_all(b"\n") { ... }
            if let Err(e) = guard.flush() { ... }
        }
        Err(e) => tracing::warn!("session log serialize error: {}", e),
    }
}
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `maybe_init` | 80 | 初始化日志记录器（检查环境变量） |
| `log_inbound_app_event` | 121 | 记录入站 AppEvent |
| `log_outbound_op` | 188 | 记录出站 Op |
| `log_session_end` | 195 | 记录会话结束 |
| `write_record` | 207 | 通用记录写入 |
| `open` | 29 | 打开日志文件 |
| `write_json_line` | 44 | 写入 JSON 行 |

### 依赖模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `Config` | `codex_core::config::Config` | 获取日志目录配置 |
| `Op` | `codex_protocol::protocol::Op` | 出站操作类型 |
| `AppEvent` | `crate::app_event::AppEvent` | 入站事件类型 |
| `serde_json` | 外部 crate | JSON 序列化 |
| `chrono` | 外部 crate | 时间戳生成 |

### 调用方

| 文件 | 函数 | 用途 |
|------|------|------|
| `lib.rs` | `run_app` | 会话开始时初始化日志 |
| `app_event_sender.rs` | `send` | 发送事件前记录入站事件 |
| `app.rs` | 多处 | 记录出站 Op |
| `lib.rs` | 清理代码 | 会话结束时记录 |

## 依赖与外部交互

### 数据流

```
AppEvent / Op
    ↓
session_log::log_*(event/op)
    ↓
SessionLogger (全局单例)
    ↓
Mutex<File>
    ↓
~/.codex/logs/session-*.jsonl
```

### 与 AppEventSender 的集成

```rust
// app_event_sender.rs
pub(crate) fn send(&self, event: AppEvent) {
    // 记录入站事件（排除 CodexOp 避免重复）
    if !matches!(event, AppEvent::CodexOp(_)) {
        session_log::log_inbound_app_event(&event);
    }
    
    // 发送到事件通道
    if let Err(e) = self.app_event_tx.send(event) {
        tracing::error!("failed to send event: {e}");
    }
}
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CODEX_TUI_RECORD_SESSION` | 未设置（禁用） | 启用会话记录（1/true/yes） |
| `CODEX_TUI_SESSION_LOG_PATH` | `~/.codex/logs/session-*.jsonl` | 自定义日志路径 |

## 风险、边界与改进建议

### 风险分析

1. **性能影响**
   - 每次事件都进行 JSON 序列化和文件写入
   - 在高频事件场景下可能影响性能
   - 当前实现是同步写入（带 flush），可能成为瓶颈

2. **磁盘空间**
   - 长时间会话可能产生大量日志
   - 无自动清理机制

3. **敏感信息泄露**
   - 日志可能包含用户输入和模型输出
   - Unix 系统设置了 0o600 权限，但其他平台无此保护

4. **Poisoned Mutex**
   - 处理了 mutex poison 情况，但可能导致部分日志丢失

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 文件打开失败 | 记录 error 日志，静默禁用 |
| 序列化失败 | 记录 warning，跳过该条 |
| 写入失败 | 记录 warning，继续运行 |
| Flush 失败 | 记录 warning，不中断 |
| Mutex poison | 使用 `into_inner()` 恢复 |

### 改进建议

1. **性能优化**
   - 使用缓冲写入和批量 flush
   - 考虑使用异步写入通道
   - 添加采样率控制（如只记录 1% 的事件）

2. **功能增强**
   - 添加日志轮转（按大小或时间）
   - 支持压缩旧日志
   - 添加配置选项控制记录详细程度

3. **安全改进**
   - 添加敏感信息过滤（如 API 密钥）
   - Windows 平台设置文件权限
   - 添加日志加密选项

4. **可观测性**
   - 添加日志统计指标（事件数、字节数）
   - 支持动态启用/禁用（通过命令）

5. **代码改进**
   - 考虑使用专门的日志库（如 `tracing-appender`）
   - 添加单元测试验证序列化格式
   - 考虑使用 `serde_json::to_writer` 直接写入减少内存分配
