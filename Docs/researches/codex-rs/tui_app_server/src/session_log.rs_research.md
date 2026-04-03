# session_log.rs 研究文档

## 场景与职责

`session_log.rs` 是 Codex TUI 应用服务器中的**会话日志记录模块**，负责在启用时记录 TUI 会话中的关键事件到 JSON Lines 格式的日志文件。这是一个诊断和调试工具，用于：

1. **会话审计** - 记录用户与会话的完整交互历史
2. **问题诊断** - 通过日志分析用户遇到的问题
3. **行为分析** - 了解用户如何使用 TUI 功能
4. **调试支持** - 开发过程中追踪事件流

该模块采用**惰性初始化**模式，仅在环境变量启用时才激活日志记录功能。

## 功能点目的

### 1. 会话生命周期记录
- 会话开始（`session_start`）- 包含 CWD、模型、提供商等上下文
- 会话结束（`session_end`）- 标记会话终止

### 2. 入站事件记录
记录从 AppServer 发送到 TUI 的事件：
- `new_session` - 新会话事件
- `clear_ui` - 清空 UI 事件
- `insert_history_cell` - 插入历史单元格（记录行数）
- `file_search_start` - 文件搜索开始
- `file_search_result` - 文件搜索结果（记录匹配数）
- 其他事件 - 记录变体名称

### 3. 出站操作记录
记录从 TUI 发送到 AppServer 的操作（`AppCommand`），以序列化 JSON 形式记录完整操作内容。

### 4. 安全日志管理
- 文件权限控制（Unix 系统设置 `0o600`）
- 原子性写入（使用 Mutex）
- 错误优雅降级（写入失败不中断应用）

## 具体技术实现

### 核心数据结构

```rust
// 全局日志实例（惰性初始化）
static LOGGER: LazyLock<SessionLogger> = LazyLock::new(SessionLogger::new);

// 日志记录器
struct SessionLogger {
    file: OnceLock<Mutex<File>>,
}

// 日志条目结构（JSON 格式）
{
    "ts": "2024-01-01T00:00:00.000Z",  // RFC3339 时间戳
    "dir": "to_tui|from_tui|meta",      // 方向
    "kind": "event_type",               // 事件类型
    // ... 额外字段
}
```

### 初始化流程

```rust
pub(crate) fn maybe_init(config: &Config) {
    // 1. 检查环境变量 CODEX_TUI_RECORD_SESSION
    let enabled = std::env::var("CODEX_TUI_RECORD_SESSION")
        .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false);
    
    if !enabled { return; }
    
    // 2. 确定日志路径
    let path = if let Ok(path) = std::env::var("CODEX_TUI_SESSION_LOG_PATH") {
        PathBuf::from(path)
    } else {
        // 默认: {log_dir}/session-{timestamp}.jsonl
    };
    
    // 3. 打开文件并写入会话头
    LOGGER.open(path)?;
    LOGGER.write_json_line(header);
}
```

### 文件打开逻辑

```rust
fn open(&self, path: PathBuf) -> std::io::Result<()> {
    let mut opts = OpenOptions::new();
    opts.create(true).truncate(true).write(true);
    
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);  // 仅所有者可读写
    }
    
    let file = opts.open(path)?;
    self.file.get_or_init(|| Mutex::new(file));
    Ok(())
}
```

### 写入逻辑

```rust
fn write_json_line(&self, value: serde_json::Value) {
    // 1. 检查是否已启用
    let Some(mutex) = self.file.get() else { return; };
    
    // 2. 获取锁（处理 poison）
    let mut guard = match mutex.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    
    // 3. 序列化并写入
    match serde_json::to_string(&value) {
        Ok(serialized) => {
            guard.write_all(serialized.as_bytes())?;
            guard.write_all(b"\n")?;
            guard.flush()?;
        }
        Err(e) => tracing::warn!("session log serialize error: {}", e),
    }
}
```

### 事件记录函数

```rust
// 入站事件记录
pub(crate) fn log_inbound_app_event(event: &AppEvent)

// 出站操作记录
pub(crate) fn log_outbound_op(op: &AppCommand)

// 会话结束记录
pub(crate) fn log_session_end()
```

## 关键代码路径与文件引用

### 初始化
- `maybe_init()` - 第 80-119 行
- 调用位置：`lib.rs` 第 958 行 `session_log::maybe_init(&initial_config);`

### 事件记录
- `log_inbound_app_event()` - 第 121-183 行
- `log_outbound_op()` - 第 185-190 行
- `log_session_end()` - 第 192-202 行

### 核心实现
- `SessionLogger::open()` - 第 29-42 行
- `SessionLogger::write_json_line()` - 第 44-68 行
- `SessionLogger::is_enabled()` - 第 70-72 行
- `now_ts()` - 第 75-78 行
- `write_record()` - 第 204-215 行

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::app_command::AppCommand` | 出站操作类型 |
| `crate::app_event::AppEvent` | 入站事件类型 |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `serde` | JSON 序列化 |
| `serde_json` | JSON 处理 |
| `chrono` | 时间戳生成 |
| `tracing` | 错误日志记录 |
| `std::sync::LazyLock` | 全局实例惰性初始化 |
| `std::sync::OnceLock` | 文件句柄一次性初始化 |

### Core 依赖
| 模块 | 用途 |
|------|------|
| `codex_core::config::Config` | 配置访问 |
| `codex_core::config::log_dir` | 日志目录获取 |

### 调用方
通过 Grep 搜索发现以下位置调用了日志功能：
- `lib.rs` - `session_log::maybe_init(&initial_config);`
- `app_event_sender.rs` - `session_log::log_inbound_app_event(event);`
- `app.rs` - 出站操作记录

## 风险、边界与改进建议

### 安全风险

1. **敏感信息泄露**
   - 当前实现记录完整的 `AppCommand` 和 `AppEvent`
   - 可能包含用户输入的敏感信息（API 密钥、密码等）
   - **建议**: 添加敏感字段过滤机制

2. **文件权限**
   - Unix 系统已设置 `0o600` 权限
   - Windows 系统未设置等效权限（注释中提到实现复杂）

3. **日志文件累积**
   - 每次会话创建新日志文件
   - 无自动清理机制

### 性能风险

1. **同步写入**
   - 每次写入都执行 `flush()`
   - 高频事件可能影响性能
   - **建议**: 考虑批量写入或异步通道

2. **锁竞争**
   - 使用 `Mutex` 保护文件句柄
   - 高频并发写入可能产生竞争

### 边界情况

1. **磁盘满**
   - 写入失败仅记录警告日志
   - 不影响主应用流程

2. ** Poisoned Mutex**
   - 正确处理 poison 情况：`poisoned.into_inner()`
   - 确保即使发生 panic 也能继续写入

3. **环境变量变化**
   - 仅在初始化时检查环境变量
   - 运行时无法动态启用/禁用

### 改进建议

1. **敏感信息过滤**
   ```rust
   fn sanitize_value(value: &mut serde_json::Value) {
       // 递归遍历，替换敏感字段
       // 如: api_key, password, token 等
   }
   ```

2. **日志轮转**
   - 添加文件大小限制
   - 自动创建新文件或截断旧文件

3. **配置化**
   - 从 `config.toml` 读取日志配置
   - 支持配置日志级别、过滤规则等

4. **异步写入**
   ```rust
   // 使用 channel 解耦写入
   let (tx, rx) = mpsc::channel();
   // 后台任务批量写入
   ```

5. **结构化日志增强**
   ```rust
   // 当前
   "kind": "insert_history_cell",
   "lines": 5
   
   // 建议添加
   "thread_id": "...",
   "turn_id": "...",
   "duration_ms": 100
   ```

6. **日志分析工具**
   - 提供 CLI 工具解析和分析日志
   - 生成会话报告、统计信息等

### 代码质量

该模块代码质量良好：
- 使用 `LazyLock` 和 `OnceLock` 实现线程安全的惰性初始化
- 错误处理优雅，不影响主流程
- Unix 权限控制到位

建议改进：
- 添加更多文档注释说明日志格式
- 考虑添加版本字段以便未来格式变更
