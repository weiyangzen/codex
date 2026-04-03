# Snapshot Research: hook_events_render_snapshot

## 场景与职责

此快照测试验证 SessionStart Hook 事件的渲染效果。Hook 系统是 Codex 的扩展机制，允许在特定生命周期事件（如会话开始）时执行自定义脚本或命令。此测试确保 Hook 执行状态和输出能够正确显示在历史记录中。

测试场景：
- 会话开始时触发 SessionStart Hook
- Hook 开始执行，显示运行状态
- Hook 执行完成，显示输出结果（包括警告和上下文信息）
- 历史记录中保留 Hook 执行的完整记录

## 功能点目的

1. **Hook 执行可视化**：显示 Hook 正在运行的状态
2. **执行结果展示**：显示 Hook 完成后的输出内容
3. **输出分类显示**：区分不同类型的输出（警告、上下文信息等）
4. **执行时间记录**：显示 Hook 执行耗时

## 具体技术实现

### 关键流程

```
HookStartedEvent → 显示运行中状态 → HookCompletedEvent → 显示完成状态和输出
```

### Hook 事件数据结构

```rust
// Hook 开始事件
HookStartedEvent {
    turn_id: Option<String>,
    run: HookRunSummary,
}

// Hook 完成事件
HookCompletedEvent {
    turn_id: Option<String>,
    run: HookRunSummary,
}

// Hook 运行摘要
struct HookRunSummary {
    id: String,                    // Hook ID
    event_name: HookEventName,     // 事件名称（如 SessionStart）
    handler_type: HookHandlerType, // 处理器类型（Command/Script等）
    execution_mode: HookExecutionMode, // 执行模式（Sync/Async）
    scope: HookScope,              // 作用域（Thread/Global）
    source_path: PathBuf,          // Hook 源文件路径
    display_order: u32,            // 显示顺序
    status: HookRunStatus,         // 运行状态
    status_message: Option<String>, // 状态消息
    started_at: u64,               // 开始时间戳
    completed_at: Option<u64>,     // 完成时间戳
    duration_ms: Option<u64>,      // 执行耗时
    entries: Vec<HookOutputEntry>, // 输出条目
}
```

### Hook 输出条目

```rust
struct HookOutputEntry {
    kind: HookOutputEntryKind, // 输出类型
    text: String,              // 输出内容
}

enum HookOutputEntryKind {
    Info,    // 普通信息
    Warning, // 警告
    Error,   // 错误
    Context, // 上下文信息
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理 Hook 事件 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格定义和渲染 |
| `codex-protocol/src/protocol.rs` | Hook 相关协议事件定义 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 HookStartedEvent 和 HookCompletedEvent
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn hook_events_render_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 模拟 Hook 开始
    chat.handle_codex_event(Event {
        msg: EventMsg::HookStarted(HookStartedEvent {
            run: HookRunSummary {
                id: "session-start:0:/tmp/hooks.json".to_string(),
                event_name: HookEventName::SessionStart,
                handler_type: HookHandlerType::Command,
                execution_mode: HookExecutionMode::Sync,
                scope: HookScope::Thread,
                source_path: PathBuf::from("/tmp/hooks.json"),
                display_order: 0,
                status: HookRunStatus::Running,
                status_message: Some("warming the shell".to_string()),
                started_at: 1,
                completed_at: None,
                duration_ms: None,
                entries: vec![],
            },
        }),
    });

    // 模拟 Hook 完成
    chat.handle_codex_event(Event {
        msg: EventMsg::HookCompleted(HookCompletedEvent {
            run: HookRunSummary {
                status: HookRunStatus::Completed,
                completed_at: Some(11),
                duration_ms: Some(10),
                entries: vec![
                    HookOutputEntry {
                        kind: HookOutputEntryKind::Warning,
                        text: "Heads up from the hook".to_string(),
                    },
                    HookOutputEntry {
                        kind: HookOutputEntryKind::Context,
                        text: "Remember the startup checklist.".to_string(),
                    },
                ],
                // ...
            },
        }),
    });
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::HookStartedEvent` - Hook 开始事件
- `codex_protocol::protocol::HookCompletedEvent` - Hook 完成事件
- `codex_protocol::protocol::HookRunSummary` - Hook 运行摘要
- `codex_protocol::protocol::HookOutputEntry` - Hook 输出条目

### 外部交互

- **Hook 系统**：执行配置文件中定义的 Hook 脚本
- **文件系统**：读取 Hook 配置文件（如 hooks.json）

## 风险、边界与改进建议

### 潜在风险

1. **Hook 执行超时**：长时间运行的 Hook 可能导致 UI 卡顿
2. **输出过多**：大量 Hook 输出可能淹没历史记录
3. **错误处理**：Hook 执行失败的错误信息可能不够清晰

### 边界情况

- Hook 执行失败（非零退出码）
- Hook 输出包含特殊字符或 ANSI 转义序列
- 多个 Hook 同时执行的场景
- Hook 执行过程中会话被中断

### 改进建议

1. **显示优化**：
   - 添加 Hook 执行进度条
   - 支持折叠/展开 Hook 输出
   - 为不同类型的输出使用不同颜色

2. **交互改进**：
   - 允许用户手动重新运行 Hook
   - 提供 Hook 配置编辑快捷方式
   - 添加 Hook 执行历史查看

3. **性能优化**：
   - 对大量 Hook 输出进行分页
   - 异步处理 Hook 输出更新
   - 添加 Hook 执行超时保护

4. **可观测性**：
   - 记录 Hook 执行日志
   - 提供 Hook 性能分析
   - 添加 Hook 执行统计

---

**快照内容**：
```
• Running SessionStart hook: warming the shell

SessionStart hook (completed)
  warning: Heads up from the hook
  hook context: Remember the startup checklist.
```

**说明**：
- 第一行显示 Hook 正在运行，包含状态消息 "warming the shell"
- 空行分隔运行状态和完成状态
- "SessionStart hook (completed)" 表示 Hook 已完成
- 缩进显示 Hook 输出条目：
  - `warning:` 前缀表示警告类型的输出
  - `hook context:` 前缀表示上下文信息
- 此格式让用户清楚了解 Hook 的执行过程和输出内容
