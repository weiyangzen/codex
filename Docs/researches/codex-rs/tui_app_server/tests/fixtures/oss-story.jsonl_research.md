# oss-story.jsonl 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl`
- **文件格式**: JSON Lines (JSONL)
- **文件用途**: TUI App Server 的测试固件（test fixture）
- **记录类型**: 会话日志/事件追踪记录

---

## 1. 场景与职责

### 1.1 核心场景

`oss-story.jsonl` 是一个**真实会话记录文件**，捕获了用户与 Codex TUI 应用服务器之间的完整交互过程。该文件记录了从会话开始到结束的完整时间线，包括：

1. **会话初始化** - 模型配置、工作目录设置
2. **用户输入** - 键盘事件（输入 "hello"、"hello again"、"write me a long story" 等）
3. **AI 推理过程** - 原始推理内容的流式增量更新
4. **AI 响应** - 代理消息的流式增量更新
5. **UI 渲染事件** - 重绘请求和实际重绘操作

### 1.2 文件职责

| 职责 | 说明 |
|------|------|
| **测试固件** | 为 VT100 终端模拟测试提供真实数据输入 |
| **回归测试** | 验证 TUI 渲染引擎对真实会话的处理能力 |
| **性能基准** | 提供流式渲染的性能测试数据 |
| **调试参考** | 为开发者提供完整的事件序列参考 |

### 1.3 使用场景

该文件主要用于以下测试场景：
- **VT100 历史记录测试** (`vt100_history.rs`) - 验证终端历史插入逻辑
- **VT100 实时提交测试** (`vt100_live_commit.rs`) - 验证流式内容提交
- **Markdown 流式渲染测试** - 验证长文本（故事）的流式渲染

---

## 2. 功能点目的

### 2.1 事件追踪与记录

文件中的每一行都是一个独立的事件记录，用于追踪 TUI 应用服务器内部状态变化：

```json
{"ts":"2025-08-10T03:12:26.500Z","dir":"meta","kind":"session_start",...}
```

**关键字段说明**:
- `ts`: ISO 8601 时间戳（毫秒精度）
- `dir`: 事件方向 (`to_tui` = 发往 TUI, `from_tui` = 来自 TUI, `meta` = 元数据)
- `kind`: 事件类型
- `variant`/`payload`: 事件具体内容

### 2.2 支持的功能验证

#### 2.2.1 键盘输入追踪
```json
{"ts":"...","dir":"to_tui","kind":"key_event","event":"KeyEvent { code: Char('h'), ... }"}
```
- 记录用户每次按键（Press/Release）
- 支持特殊键（Enter, Backspace, Space）
- 用于测试输入处理和自动完成

#### 2.2.2 流式 AI 响应渲染
```json
{"ts":"...","dir":"to_tui","kind":"codex_event","payload":{"id":"1","msg":{"type":"agent_reasoning_raw_content_delta","delta":"The"}}}
```
- `agent_reasoning_raw_content_delta`: AI 推理内容的增量更新
- `agent_message_delta`: AI 最终响应的增量更新
- 用于测试流式 Markdown 渲染

#### 2.2.3 UI 重绘协调
```json
{"ts":"...","dir":"to_tui","kind":"app_event","variant":"RequestRedraw"}
{"ts":"...","dir":"to_tui","kind":"app_event","variant":"Redraw"}
```
- `RequestRedraw`: 请求重绘（可能批量）
- `Redraw`: 实际执行重绘
- 用于测试渲染性能优化

#### 2.2.4 历史记录插入
```json
{"ts":"...","dir":"to_tui","kind":"insert_history","lines":9}
```
- 记录历史记录行的插入
- 用于测试 VT100 终端的历史滚动行为

---

## 3. 具体技术实现

### 3.1 数据结构定义

#### 3.1.1 事件记录结构（Rust 伪代码）

```rust
// 对应 session_log.rs 中的记录格式
struct SessionLogEntry {
    ts: String,           // RFC3339 格式时间戳
    dir: Direction,       // "to_tui" | "from_tui" | "meta"
    kind: String,         // 事件类型
    // 可选字段:
    variant: Option<String>,
    payload: Option<serde_json::Value>,
    lines: Option<usize>,
    event: Option<String>,
}

enum Direction {
    ToTui,      // 发往 TUI 的事件
    FromTui,    // 来自 TUI 的操作
    Meta,       // 元数据（会话开始/结束）
}
```

#### 3.1.2 事件类型枚举

| kind | 说明 | 来源代码 |
|------|------|----------|
| `session_start` | 会话开始元数据 | `session_log.rs:109-118` |
| `session_end` | 会话结束 | `session_log.rs:192-202` |
| `key_event` | 键盘事件 | `app.rs` (通过 `log_inbound_app_event`) |
| `app_event` | 应用事件（重绘等） | `session_log.rs:173-181` |
| `codex_event` | Codex 协议事件 | `chatwidget.rs` |
| `insert_history` | 历史记录插入 | `session_log.rs:144-151` |
| `log_line` | 日志行输出 | `session_log.rs` |

### 3.2 关键流程

#### 3.2.1 会话记录生成流程

```
用户交互 → AppEvent → session_log::log_inbound_app_event() → JSONL 文件
                ↓
         条件：CODEX_TUI_RECORD_SESSION=1
```

**代码路径**: `codex-rs/tui_app_server/src/session_log.rs`

```rust
pub(crate) fn log_inbound_app_event(event: &AppEvent) {
    if !LOGGER.is_enabled() { return; }
    
    match event {
        AppEvent::NewSession => { /* 记录 */ }
        AppEvent::InsertHistoryCell(cell) => { /* 记录行数 */ }
        other => { /* 记录变体名称 */ }
    }
}
```

#### 3.2.2 会话记录回放流程（测试中使用）

```
JSONL 文件 → 测试代码解析 → VT100Backend → Terminal → 断言验证
```

**相关测试文件**:
- `tests/suite/vt100_history.rs`: 历史插入测试
- `tests/suite/vt100_live_commit.rs`: 实时提交测试

### 3.3 协议与序列化

#### 3.3.1 JSONL 格式规范

- **编码**: UTF-8
- **分隔符**: 每行一个 JSON 对象，使用 `\n` 分隔
- **时间戳**: RFC3339 格式，毫秒精度 (`2025-08-10T03:12:26.500Z`)
- **方向标记**:
  - `dir: "to_tui"` - 发往 TUI 的事件（AppEvent, CodexEvent）
  - `dir: "from_tui"` - 来自 TUI 的操作（AppCommand/Op）
  - `dir: "meta"` - 会话元数据

#### 3.3.2 关键事件负载示例

**会话配置**:
```json
{
  "ts": "2025-08-10T03:12:26.519Z",
  "dir": "to_tui",
  "kind": "codex_event",
  "payload": {
    "id": "0",
    "msg": {
      "type": "session_configured",
      "session_id": "8f7c4ac2-6141-42da-b4d5-7032a8e8df3b",
      "model": "gpt-oss:20b",
      "history_log_id": 2532619,
      "history_entry_count": 355
    }
  }
}
```

**任务完成**:
```json
{
  "ts": "...",
  "dir": "to_tui",
  "kind": "codex_event",
  "payload": {
    "id": "1",
    "msg": {
      "type": "task_complete",
      "last_agent_message": "Hello! How can I help you today?"
    }
  }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|---------------|
| `src/session_log.rs` | 会话日志记录 | `SessionLogger`, `log_inbound_app_event()` |
| `src/app.rs` | 应用主逻辑，事件分发 | `App::run()`, 事件处理循环 |
| `src/chatwidget.rs` | 聊天组件，Codex 事件处理 | `handle_codex_event()` |
| `src/test_backend.rs` | VT100 测试后端 | `VT100Backend` |
| `src/insert_history.rs` | 历史记录插入 | `insert_history_lines()` |

### 4.2 测试相关文件

| 文件 | 测试类型 | 说明 |
|------|----------|------|
| `tests/suite/vt100_history.rs` | 单元测试 | VT100 历史插入行为测试 |
| `tests/suite/vt100_live_commit.rs` | 单元测试 | 实时内容提交测试 |
| `tests/test_backend.rs` | 测试基础设施 | VT100Backend 导出 |
| `src/markdown_stream.rs` | 单元测试 | Markdown 流式渲染测试 |
| `src/insert_history.rs` (tests) | 单元测试 | 历史插入的 VT100 验证 |

### 4.3 依赖关系图

```
oss-story.jsonl (fixture)
    │
    ▼
session_log.rs ───────┐
    │                  │
    ▼                  ▼
AppEvent ───────► VT100Backend (test)
    │                  │
    ▼                  ▼
chatwidget.rs ◄─── vt100_history.rs (test)
    │
    ▼
MarkdownStreamCollector
    │
    ▼
insert_history.rs
```

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 用途 | 版本/特性 |
|------|------|-----------|
| `chrono` | 时间戳生成 | workspace |
| `serde_json` | JSON 序列化 | workspace |
| `vt100` | VT100 终端模拟 | workspace (dev) |
| `ratatui` | TUI 渲染 | workspace + scrolling-regions |

### 5.2 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CODEX_TUI_RECORD_SESSION` | 启用会话记录 | `false` |
| `CODEX_TUI_SESSION_LOG_PATH` | 自定义日志路径 | `<log_dir>/session-<timestamp>.jsonl` |

### 5.3 与其他组件的交互

#### 5.3.1 与 codex-core 的交互
- 使用 `codex_core::config::log_dir()` 获取默认日志目录
- 依赖 `Config` 结构获取会话配置

#### 5.3.2 与 codex-protocol 的交互
- 处理 `codex_protocol::protocol::Event` 事件
- 序列化 `EventMsg` 变体到 JSON

#### 5.3.3 与 codex-app-server-protocol 的交互
- 处理 `ServerNotification` 类型事件
- 记录线程状态变化

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 隐私风险
- **风险**: 会话日志可能包含敏感信息（用户输入、AI 响应、文件路径）
- **缓解**: 
  - 文件权限设置为 `0o600`（Unix）
  - 需要显式启用 `CODEX_TUI_RECORD_SESSION=1`
  - 建议用户定期清理日志文件

#### 6.1.2 性能风险
- **风险**: 高频事件（如 `RequestRedraw`）可能导致 I/O 瓶颈
- **当前状态**: 文件显示大量重复的重绘请求（约 100ms 间隔）
- **缓解**: 当前实现已过滤部分高频事件，仅记录变体名称

#### 6.1.3 存储风险
- **风险**: 长会话可能产生大文件（当前文件约 2000 行）
- **建议**: 实现日志轮转或大小限制

### 6.2 边界情况

#### 6.2.1 时间戳精度
- 使用毫秒级 RFC3339 时间戳
- 在极高频事件场景下可能出现相同时间戳

#### 6.2.2 JSON 序列化边界
- 使用 `serde_json::to_string()` 进行序列化
- 极端大的 payload 可能导致内存问题

#### 6.2.3 文件系统边界
- 依赖临时目录或配置目录的可写性
- 磁盘满时静默失败（仅记录警告日志）

### 6.3 改进建议

#### 6.3.1 短期改进

1. **压缩存储**
   ```rust
   // 建议: 使用 gzip 压缩旧日志
   session-20250810T031226.jsonl.gz
   ```

2. **事件采样**
   ```rust
   // 建议: 对高频事件进行采样记录
   if event_count % SAMPLE_RATE == 0 { log(); }
   ```

3. **敏感信息过滤**
   ```rust
   // 建议: 添加敏感信息检测和脱敏
   fn sanitize_payload(payload: &mut Value) { ... }
   ```

#### 6.3.2 中期改进

1. **结构化查询**
   - 将日志导入 SQLite 或专用日志数据库
   - 支持按时间范围、事件类型查询

2. **可视化工具**
   - 开发日志查看器，支持时间线可视化
   - 与 TUI 集成，支持会话回放

3. **测试自动化**
   ```rust
   // 建议: 从 JSONL 自动生成测试用例
   #[test]
   fn replay_session_from_fixture() {
       let events = load_fixture("oss-story.jsonl");
       for event in events { replay(event); }
   }
   ```

#### 6.3.3 长期改进

1. **分布式追踪**
   - 集成 OpenTelemetry
   - 支持跨会话关联

2. **智能分析**
   - 自动检测异常模式
   - 性能热点分析

3. **隐私增强**
   - 端到端加密存储
   - 自动过期策略

### 6.4 测试建议

当前 `oss-story.jsonl` 未被直接引用在自动化测试中，建议：

1. **添加 fixture 测试**
   ```rust
   // tests/suite/session_replay.rs
   #[test]
   fn test_oss_story_fixture() {
       let fixture = include_str!("../fixtures/oss-story.jsonl");
       // 验证解析、回放、渲染
   }
   ```

2. **性能回归测试**
   - 使用 fixture 测量渲染延迟
   - 监控 `RequestRedraw` 到 `Redraw` 的时间差

3. **模糊测试**
   - 基于真实事件生成变异测试用例
   - 验证错误处理边界

---

## 附录：事件类型统计（基于 oss-story.jsonl）

| 事件类型 | 出现次数 | 占比 |
|----------|----------|------|
| `app_event` (RequestRedraw) | ~800 | ~40% |
| `app_event` (Redraw) | ~800 | ~40% |
| `codex_event` (agent_reasoning_raw_content_delta) | ~200 | ~10% |
| `codex_event` (agent_message_delta) | ~100 | ~5% |
| `key_event` | ~60 | ~3% |
| `insert_history` | ~10 | <1% |
| 其他 | ~30 | ~1% |

---

## 参考文档

- [AGENTS.md](../../../../../../AGENTS.md) - 项目级开发规范
- [session_log.rs](../../../../../../codex-rs/tui_app_server/src/session_log.rs) - 会话日志实现
- [test_backend.rs](../../../../../../codex-rs/tui_app_server/src/test_backend.rs) - VT100 测试后端
- [vt100_history.rs](../../../../../../codex-rs/tui_app_server/tests/suite/vt100_history.rs) - 历史测试
