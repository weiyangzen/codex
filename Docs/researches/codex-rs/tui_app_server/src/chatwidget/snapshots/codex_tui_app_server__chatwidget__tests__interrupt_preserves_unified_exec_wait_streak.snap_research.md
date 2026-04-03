# 中断保留统一执行等待序列测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中用户中断回合时，统一执行（Unified Exec）等待状态的保留行为。当用户使用统一执行功能启动后台进程，然后中断当前回合时，系统需要正确处理等待序列，确保中断后执行单元格能够正确完成并保留在历史记录中。

## 功能点目的

1. **等待序列保留**: 确保中断不会丢失统一执行的等待状态
2. **状态一致性**: 验证中断后执行单元格的正确完成
3. **历史完整性**: 保证中断后的执行历史完整可用
4. **进程管理**: 正确处理后台进程的生命周期

## 具体技术实现

### 测试流程

```rust
async fn interrupt_preserves_unified_exec_wait_streak_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 2. 开始回合
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 3. 开始统一执行启动（带进程 ID）
    let begin = begin_unified_exec_startup(&mut chat, "call-1", "process-1", "just fix");
    
    // 4. 模拟终端交互
    terminal_interaction(&mut chat, "call-1a", "process-1", "");

    // 5. 中断回合
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnAborted(TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    // 6. 结束执行
    end_exec(&mut chat, begin, "", "", 0);
    
    // 7. 验证历史单元格
    let cells = drain_insert_history(&mut rx);
    let combined = cells.iter().map(...).collect::<Vec<_>>().join("\n");
    let snapshot = format!("cells={}\n{combined}", cells.len());
    assert_snapshot!("interrupt_preserves_unified_exec_wait_streak", snapshot);
}
```

### 关键数据结构

- **`UnifiedExecWaitStreak`**: 统一执行等待序列状态
  - 跟踪多个统一执行进程的状态
  - 管理进程的开始、等待和结束

- **`ExecCommandBeginEvent`**（统一执行模式）:
  - `process_id`: 进程唯一标识（统一执行模式下有值）
  - `source`: 命令来源（`UnifiedExecStartup`）

### 渲染输出格式

```
cells=1
■ Conversation interrupted - tell the model what to do differently. Something went wrong? Hit `/feedback` to report the issue.
```

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 9907-9940)
  - 测试函数 `interrupt_preserves_unified_exec_wait_streak_snapshot`
  - 使用 `begin_unified_exec_startup` 创建统一执行命令
  - 使用 `terminal_interaction` 模拟终端交互
  - 使用 `end_exec` 结束执行命令

### 辅助函数
- **`begin_unified_exec_startup`** (行 3524-3547): 开始统一执行启动命令
  - 设置 `process_id` 和 `source: ExecCommandSource::UnifiedExecStartup`
- **`terminal_interaction`** (行 3549-3563): 模拟终端交互事件
- **`end_exec`** (行 3622-3681): 结束执行命令

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `unified_exec_wait_streak` 字段管理等待序列
  - `handle_codex_event` 处理 `TurnAborted` 和 `ExecCommandEnd` 事件
  - `last_unified_wait` 跟踪最后等待状态

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `TurnAbortedEvent`, `TurnAbortReason` 定义
  - `ExecCommandBeginEvent`, `ExecCommandEndEvent` 定义
  - `TerminalInteractionEvent` 定义
  - `ExecCommandSource` 枚举（`Agent`, `User`, `UnifiedExecStartup`）

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__interrupt_preserves_unified_exec_wait_streak.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理统一执行状态 |
| `InterruptManager` | 中断管理器 |
| `unified_exec_wait_streak` | 等待序列状态跟踪 |
| `unified_exec_processes` | 统一执行进程列表 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `TurnStarted` | Core → TUI | 回合开始 |
| `TurnAborted` | Core → TUI | 回合中止 |
| `ExecCommandBegin` | Core → TUI | 执行命令开始 |
| `ExecCommandEnd` | Core → TUI | 执行命令结束 |
| `TerminalInteraction` | Core → TUI | 终端交互事件 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `begin_unified_exec_startup`: 开始统一执行启动
- `terminal_interaction`: 模拟终端交互
- `end_exec`: 结束执行命令
- `drain_insert_history`: 从事件通道中提取所有历史单元格

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**: 中断事件和执行结束事件的竞争条件
2. **内存泄漏**: 统一执行进程状态未正确清理
3. **历史顺序**: 多个统一执行进程的历史记录顺序问题

### 边界情况
1. **多进程中断**: 多个统一执行进程同时运行时的中断
2. **中断后新回合**: 中断后立即开始新回合的处理
3. **进程崩溃**: 统一执行进程异常退出的处理
4. **长时间等待**: 统一执行进程长时间等待的情况

### 改进建议
1. **增强测试覆盖**: 添加多进程中断的测试场景
2. **状态监控**: 添加统一执行进程状态的实时监控
3. **优雅关闭**: 支持统一执行进程的优雅关闭
4. **超时处理**: 为统一执行进程添加超时机制
5. **资源限制**: 限制同时运行的统一执行进程数量
