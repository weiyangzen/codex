# Hook 事件渲染测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中 Hook 事件的渲染行为。Hook 是 Codex 在特定生命周期点（如会话开始、回合开始等）执行的自定义脚本或命令。测试确保 Hook 的开始、执行状态更新和完成事件能够正确渲染到聊天历史界面中，包括状态消息和输出条目（警告、上下文等）。

## 功能点目的

1. **Hook 生命周期可视化**: 确保用户能够看到 Hook 的执行状态（运行中、已完成）
2. **Hook 输出展示**: 显示 Hook 执行过程中产生的警告、上下文信息等输出条目
3. **历史记录整合**: 将 Hook 事件作为历史单元格插入到聊天记录中
4. **状态一致性**: 验证 Hook 状态变更时 UI 的同步更新

## 具体技术实现

### 测试流程

```rust
async fn hook_events_render_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 2. 发送 HookStarted 事件
    chat.handle_codex_event(Event {
        id: "hook-1".into(),
        msg: EventMsg::HookStarted(HookStartedEvent { ... }),
    });

    // 3. 发送 HookCompleted 事件（包含输出条目）
    chat.handle_codex_event(Event {
        id: "hook-1".into(),
        msg: EventMsg::HookCompleted(HookCompletedEvent {
            run: HookRunSummary {
                status: HookRunStatus::Completed,
                entries: vec![
                    HookOutputEntry { kind: Warning, text: "Heads up from the hook" },
                    HookOutputEntry { kind: Context, text: "Remember the startup checklist." },
                ],
                ...
            },
        }),
    });

    // 4. 捕获并验证渲染的历史单元格
    let cells = drain_insert_history(&mut rx);
    let combined = cells.iter().map(...).collect::<String>();
    assert_snapshot!("hook_events_render_snapshot", combined);
}
```

### 关键数据结构

- **`HookRunSummary`**: 包含 Hook 执行的完整信息
  - `event_name`: Hook 事件名称（如 `SessionStart`）
  - `status`: 执行状态（`Running`, `Completed`, `Failed`）
  - `status_message`: 状态描述（如 "warming the shell"）
  - `entries`: 输出条目列表

- **`HookOutputEntry`**: Hook 输出条目
  - `kind`: 条目类型（`Warning`, `Context`, `Stdout`, `Stderr`）
  - `text`: 条目内容

### 渲染输出格式

```
• Running SessionStart hook: warming the shell

SessionStart hook (completed)
  warning: Heads up from the hook
  hook context: Remember the startup checklist.
```

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 11613-11675)
  - 测试函数 `hook_events_render_snapshot`
  - 使用 `make_chatwidget_manual` 创建测试实例
  - 使用 `drain_insert_history` 捕获历史单元格

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `handle_codex_event` 方法处理 `HookStarted` 和 `HookCompleted` 事件
  - 历史单元格渲染逻辑

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `HookStartedEvent`, `HookCompletedEvent` 结构定义
  - `HookRunSummary`, `HookOutputEntry` 定义
  - `HookEventName`, `HookRunStatus`, `HookOutputEntryKind` 枚举

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__hook_events_render_snapshot.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理 Hook 事件 |
| `BottomPane` | 底部面板，显示状态信息 |
| `HistoryCell` | 历史单元格渲染 |
| `AppEventSender` | 应用事件发送器 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `HookStarted` | Core → TUI | Hook 开始执行 |
| `HookCompleted` | Core → TUI | Hook 执行完成 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **Hook 输出顺序**: 如果多个 Hook 同时执行，输出顺序可能不一致
2. **长文本截断**: Hook 输出条目过长时可能需要截断处理
3. **状态同步延迟**: Hook 状态变更与 UI 更新之间可能存在延迟

### 边界情况
1. **空输出**: Hook 执行成功但没有输出条目
2. **失败状态**: Hook 执行失败时的错误展示
3. **大量条目**: Hook 产生大量输出条目时的性能表现
4. **特殊字符**: Hook 输出中包含特殊字符或控制序列

### 改进建议
1. **添加失败状态测试**: 补充 Hook 失败时的渲染测试
2. **性能测试**: 测试大量 Hook 输出条目时的渲染性能
3. **并发测试**: 测试多个 Hook 同时执行的场景
4. **国际化支持**: 考虑 Hook 输出的多语言展示
5. **时间戳显示**: 考虑在 Hook 输出中显示执行时间戳
