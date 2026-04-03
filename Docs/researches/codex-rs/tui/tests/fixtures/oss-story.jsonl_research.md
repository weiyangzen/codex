# oss-story.jsonl 研究文档

## 文件概述

**文件路径**: `codex-rs/tui/tests/fixtures/oss-story.jsonl`

**文件类型**: JSON Lines (JSONL) 格式的会话日志文件

**文件用途**: 该文件是 Codex TUI (Terminal User Interface) 的测试固件(fixture)，用于记录和回放真实的用户会话交互过程。它捕获了与 gpt-oss:20b 模型的完整对话会话，包括用户输入、AI 响应、键盘事件和内部应用事件。

---

## 场景与职责

### 1. 核心场景

该文件记录了一个真实的 Codex CLI 使用场景：

- **会话初始化**: 用户启动 Codex CLI，使用 `gpt-oss:20b` 模型
- **首次交互**: 用户输入 "hello"，AI 响应问候
- **二次交互**: 用户输入 "hello again"，AI 再次响应
- **长文本生成**: 用户请求 "write me a all long story"（用户输入时有拼写修正），AI 生成了一篇名为 "The Last Ember of Evernight" 的故事

### 2. 文件职责

| 职责 | 说明 |
|------|------|
| **测试固件** | 为 TUI 组件提供真实的数据输入，用于回归测试和快照测试 |
| **事件回放** | 支持将会话事件按时间顺序回放，验证 TUI 状态机正确性 |
| **性能基准** | 包含大量 `RequestRedraw`/`Redraw` 事件，可用于渲染性能分析 |
| **VT100 测试** | 配合 `vt100_history.rs` 和 `vt100_live_commit.rs` 测试终端渲染 |

---

## 功能点目的

### 1. 会话日志格式 (Session Log Format)

该文件实现了 `session_log.rs` 中定义的日志格式，每条记录包含：

```json
{
  "ts": "2025-08-10T03:12:26.500Z",  // ISO 8601 时间戳
  "dir": "to_tui",                    // 事件方向: to_tui/from_tui/meta
  "kind": "session_start",            // 事件类型
  "payload": {...}                    // 事件负载（可选）
}
```

### 2. 事件类型覆盖

文件包含以下事件类型（按出现频率排序）：

| 事件类型 | 数量 | 说明 |
|----------|------|------|
| `app_event` | ~1200+ | 应用内部事件，主要为 `RequestRedraw` 和 `Redraw` |
| `codex_event` | ~200+ | 来自 Codex 核心的事件，如 `agent_message_delta` |
| `key_event` | ~100+ | 用户键盘输入事件 |
| `insert_history` | ~10 | 历史记录插入事件 |
| `log_line` | ~1 | 日志输出行 |
| `session_start` | 1 | 会话开始标记 |

### 3. 关键功能验证点

#### 3.1 流式响应处理
```jsonl
{"ts":"...","dir":"to_tui","kind":"codex_event","payload":{"id":"5","msg":{"type":"agent_message_delta","delta":"**"}}}
{"ts":"...","dir":"to_tui","kind":"codex_event","payload":{"id":"5","msg":{"type":"agent_message_delta","delta":"The"}}}
...
```

验证 `streaming/controller.rs` 中的 `StreamController` 正确处理分块消息。

#### 3.2 Commit 动画机制
```jsonl
{"ts":"2025-08-10T03:23:24.680Z","dir":"to_tui","kind":"app_event","variant":"StartCommitAnimation"}
{"ts":"2025-08-10T03:23:24.735Z","dir":"to_tui","kind":"app_event","variant":"CommitTick"}
{"ts":"2025-08-10T03:23:24.735Z","dir":"to_tui","kind":"app_event","variant":"StopCommitAnimation"}
```

验证 `commit_tick.rs` 中的提交动画状态机。

#### 3.3 历史记录插入
```jsonl
{"ts":"2025-08-10T03:23:24.735Z","dir":"to_tui","kind":"insert_history","lines":2}
```

验证 `insert_history.rs` 中的 `insert_history_lines` 函数正确处理行插入。

---

## 具体技术实现

### 1. 关键流程

#### 1.1 事件记录流程 (`session_log.rs`)

```rust
// 会话日志初始化
pub(crate) fn maybe_init(config: &Config) {
    let enabled = std::env::var("CODEX_TUI_RECORD_SESSION")
        .map(|v| matches!(v.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false);
    // ... 初始化 LOGGER
}

// 记录入站应用事件
pub(crate) fn log_inbound_app_event(event: &AppEvent) {
    match event {
        AppEvent::CodexEvent(ev) => write_record("to_tui", "codex_event", ev),
        // ... 其他事件类型
    }
}
```

#### 1.2 流式消息处理流程 (`streaming/controller.rs`)

```rust
impl StreamController {
    pub(crate) fn push(&mut self, delta: &str) -> bool {
        state.collector.push_delta(delta);
        if delta.contains('\n') {
            let newly_completed = state.collector.commit_complete_lines();
            if !newly_completed.is_empty() {
                state.enqueue(newly_completed);
                return true; // 触发重绘
            }
        }
        false
    }
    
    pub(crate) fn on_commit_tick(&mut self) -> (Option<Box<dyn HistoryCell>>, bool) {
        let step = self.state.step();
        (self.emit(step), self.state.is_idle())
    }
}
```

#### 1.3 历史记录插入流程 (`insert_history.rs`)

```rust
pub fn insert_history_lines<B>(
    terminal: &mut crate::custom_terminal::Terminal<B>,
    lines: Vec<Line>,
) -> io::Result<()>
where
    B: Backend + Write,
{
    // 1. 计算包装宽度
    let wrap_width = area.width.max(1) as usize;
    
    // 2. 自适应包装处理
    let line_wrapped = if line_contains_url_like(line) {
        vec![line.clone()] // URL 行保持完整
    } else {
        adaptive_wrap_line(line, RtOptions::new(wrap_width))
    };
    
    // 3. 设置滚动区域并插入行
    queue!(writer, SetScrollRegion(1..area.top()))?;
    // ... 写入行内容
    queue!(writer, ResetScrollRegion)?;
    
    Ok(())
}
```

### 2. 数据结构

#### 2.1 核心数据结构关系

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   SessionLog    │────▶│   JSONL File     │────▶│  Test Fixture   │
│  (session_log)  │     │ (oss-story.jsonl)│     │  (VT100Backend) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                               │
         ▼                                               ▼
┌─────────────────┐                           ┌─────────────────┐
│   AppEvent      │                           │  TestScenario   │
│   Enum          │                           │  (vt100_history)│
└─────────────────┘                           └─────────────────┘
         │                                               │
         ▼                                               ▼
┌─────────────────┐                           ┌─────────────────┐
│  StreamState    │                           │  insert_history │
│ (streaming/mod) │                           │    validation   │
└─────────────────┘                           └─────────────────┘
```

#### 2.2 事件数据结构

```rust
// AppEvent 枚举 (app_event.rs)
pub(crate) enum AppEvent {
    CodexEvent(Event),
    InsertHistoryCell(Box<dyn HistoryCell>),
    StartCommitAnimation,
    StopCommitAnimation,
    CommitTick,
    // ... 其他变体
}

// Codex Event (来自 codex_protocol)
pub struct Event {
    pub id: String,
    pub msg: EventMsg,
}

pub enum EventMsg {
    AgentMessageDelta(AgentMessageDeltaEvent),
    AgentReasoningRawContentDelta(AgentReasoningDeltaEvent),
    TaskStarted,
    TaskComplete,
    // ... 其他变体
}
```

### 3. 协议与命令

#### 3.1 环境变量控制

| 环境变量 | 用途 |
|----------|------|
| `CODEX_TUI_RECORD_SESSION` | 启用会话记录 (1/true/yes) |
| `CODEX_TUI_SESSION_LOG_PATH` | 自定义日志文件路径 |

#### 3.2 测试特性标志

```rust
// tests/all.rs
#[cfg(feature = "vt100-tests")]
mod test_backend;

// tests/suite/vt100_history.rs
#![cfg(feature = "vt100-tests")]
```

---

## 关键代码路径与文件引用

### 1. 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/tui/src/session_log.rs` | 会话日志记录器实现 |
| `codex-rs/tui/src/streaming/controller.rs` | 流式消息控制器 |
| `codex-rs/tui/src/streaming/mod.rs` | 流状态管理 |
| `codex-rs/tui/src/insert_history.rs` | 历史记录插入实现 |
| `codex-rs/tui/src/history_cell.rs` | 历史单元格定义 |
| `codex-rs/tui/src/app_event.rs` | 应用事件定义 |

### 2. 测试相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/tui/tests/fixtures/oss-story.jsonl` | **本研究文档目标文件** |
| `codex-rs/tui/tests/test_backend.rs` | VT100 测试后端导出 |
| `codex-rs/tui/src/test_backend.rs` | VT100 测试后端实现 |
| `codex-rs/tui/tests/suite/vt100_history.rs` | 历史记录 VT100 测试 |
| `codex-rs/tui/tests/suite/vt100_live_commit.rs` | 实时提交 VT100 测试 |
| `codex-rs/tui/tests/suite/mod.rs` | 测试套件聚合 |
| `codex-rs/tui/tests/all.rs` | 集成测试入口 |

### 3. 调用链分析

```
用户输入 → ChatWidget::handle_codex_event
              │
              ▼
    AppEvent::CodexEvent → session_log::log_inbound_app_event
              │
              ▼
    StreamController::push → 写入 oss-story.jsonl
              │
              ▼
    CommitTick → insert_history_lines → VT100Backend
```

---

## 依赖与外部交互

### 1. 内部依赖

```
codex-rs/tui/tests/fixtures/oss-story.jsonl
    │
    ├── 由 session_log.rs 生成
    │       └── 依赖: codex_core::config::Config
    │       └── 依赖: codex_protocol::protocol::Event
    │
    ├── 由 vt100_history.rs 消费
    │       └── 依赖: VT100Backend (test_backend.rs)
    │       └── 依赖: insert_history.rs
    │
    └── 由 vt100_live_commit.rs 消费
            └── 依赖: StreamController (streaming/controller.rs)
```

### 2. 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟，用于测试后端 |
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制 |
| `serde_json` | JSON 序列化/反序列化 |
| `chrono` | 时间戳处理 |

### 3. 协议依赖

- `codex_protocol::protocol::Event` - 核心事件协议
- `codex_protocol::protocol::EventMsg` - 事件消息变体
- `codex_app_server_protocol` - 应用服务器协议

---

## 风险、边界与改进建议

### 1. 已知风险

#### 1.1 文件大小风险
- **现状**: 该文件包含 ~2000 行 JSON 记录，大小约 200KB
- **风险**: 长期会话日志可能产生非常大的文件
- **缓解**: `session_log.rs` 使用 `truncate(true)` 打开文件，每次会话覆盖旧日志

#### 1.2 敏感信息泄露
- **风险**: 日志可能包含用户输入的敏感信息（代码、密钥等）
- **现状**: 文件权限设置为 `0o600` (Unix) 限制访问
- **建议**: 考虑增加敏感信息检测和脱敏机制

#### 1.3 性能影响
- **风险**: 高频事件（如 `RequestRedraw`）的日志写入可能影响性能
- **现状**: 使用 `Mutex<File>` 和同步写入
- **建议**: 考虑批量写入或异步日志通道

### 2. 边界情况

#### 2.1 事件顺序边界
```jsonl
// 文件中观察到的模式：多个 RequestRedraw 连续出现
{"ts":"...","dir":"to_tui","kind":"app_event","variant":"RequestRedraw"}
{"ts":"...","dir":"to_tui","kind":"app_event","variant":"RequestRedraw"}
{"ts":"...","dir":"to_tui","kind":"app_event","variant":"Redraw"}
```
- 说明 TUI 实现了请求-确认机制防止过度重绘

#### 2.2 字符编码边界
- 文件包含 Unicode 字符（如故事中的引号、特殊符号）
- VT100 测试验证 CJK 和 Emoji 渲染：`"😀😀😀😀😀 你好世界"`

#### 2.3 长文本处理边界
- 故事生成触发 `StartCommitAnimation` → `CommitTick` → `StopCommitAnimation` 序列
- 验证大文本块的流式处理和动画机制

### 3. 改进建议

#### 3.1 日志轮转
```rust
// 建议实现
pub(crate) fn maybe_init_with_rotation(config: &Config, max_size: usize) {
    // 当文件超过阈值时自动轮转
}
```

#### 3.2 选择性记录
```rust
// 建议：允许配置记录的事件类型
pub struct LogFilter {
    include_redraw: bool,  // 默认 false，减少噪音
    include_codex_events: bool,
    // ...
}
```

#### 3.3 压缩存储
- 对历史固件文件使用 gzip 压缩
- 测试时动态解压，减少仓库体积

#### 3.4 结构化查询
- 考虑使用 SQLite 或类似结构存储，支持按时间/类型查询
- 当前 JSONL 格式适合流式处理但难以随机访问

#### 3.5 测试覆盖率扩展
```rust
// 建议增加测试用例
#[test]
fn oss_story_replay_produces_expected_frames() {
    // 回放 oss-story.jsonl 并验证关键帧
}

#[test]
fn oss_story_long_story_commit_animation() {
    // 验证长故事生成的 commit 动画序列
}
```

### 4. 相关配置

| 配置项 | 当前值 | 建议 |
|--------|--------|------|
| `CODEX_TUI_RECORD_SESSION` | 默认关闭 | 增加 `auto` 模式（仅测试环境启用） |
| 日志文件权限 | `0o600` | 保持当前设置 |
| 日志格式 | JSON Lines | 考虑增加二进制格式选项以提升性能 |

---

## 总结

`oss-story.jsonl` 是 Codex TUI 测试基础设施的关键组成部分，它：

1. **记录真实交互**: 捕获用户与 gpt-oss:20b 模型的完整会话
2. **支持回归测试**: 为 VT100 渲染、流式处理、历史插入提供测试数据
3. **验证架构设计**: 体现了 `session_log.rs` → `streaming/` → `insert_history.rs` 的完整数据流
4. **暴露边界情况**: 包含长文本、流式 delta、commit 动画等复杂场景

该文件与 `VT100Backend` 测试框架结合，构成了 Codex CLI 终端渲染层的核心测试基础设施。
