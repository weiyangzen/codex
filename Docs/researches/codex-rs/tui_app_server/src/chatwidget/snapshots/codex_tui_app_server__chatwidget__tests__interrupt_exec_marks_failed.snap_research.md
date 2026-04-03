# 中断执行标记失败测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中用户中断执行命令时的 UI 行为。当用户按下 ESC 键中断正在执行的命令时，系统会将该命令标记为失败，并将执行单元格从活动状态转为历史记录。测试确保中断后的执行单元格正确显示失败标记（红色 ✗）和命令信息。

## 功能点目的

1. **中断反馈**: 向用户明确反馈命令已被中断
2. **状态转换**: 将活动执行单元格正确转换为历史记录
3. **失败标记**: 使用红色 ✗ 标记中断的命令
4. **历史保留**: 保留中断命令的信息供用户查看

## 具体技术实现

### 测试流程

```rust
async fn interrupt_exec_marks_failed_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 2. 开始一个长时间运行的命令（创建活动执行单元格）
    begin_exec(&mut chat, "call-int", "sleep 1");

    // 3. 模拟任务被中断（如同按下 ESC 键）
    chat.handle_codex_event(Event {
        id: "call-int".into(),
        msg: EventMsg::TurnAborted(TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    // 4. 捕获并验证历史单元格
    let cells = drain_insert_history(&mut rx);
    assert!(!cells.is_empty(), "expected finalized exec cell to be inserted into history");
    
    // 5. 验证第一个单元格是最终化的执行单元格
    let exec_blob = lines_to_single_string(&cells[0]);
    assert_snapshot!("interrupt_exec_marks_failed", exec_blob);
}
```

### 关键数据结构

- **`TurnAbortedEvent`**: 回合中止事件
  - `turn_id`: 被中止的回合 ID
  - `reason`: 中止原因（`Interrupted`, `Error`, `Timeout` 等）

- **`TurnAbortReason`**: 中止原因枚举
  - `Interrupted`: 用户中断
  - `Error`: 错误导致
  - `Timeout`: 超时

### 渲染输出格式

```
• Ran sleep 1
  └ (no output)
```

（注：实际渲染中，命令前会显示红色 ✗ 标记表示失败）

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 7110-7138)
  - 测试函数 `interrupt_exec_marks_failed_snapshot`
  - 使用 `begin_exec` 辅助函数创建执行命令
  - 验证中断后执行单元格被正确标记为失败

### 辅助函数
- **`begin_exec`** (行 3618-3620): 开始一个代理执行命令
- **`begin_exec_with_source`** (行 3494-3522): 带指定来源的执行命令开始

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `handle_codex_event` 方法处理 `TurnAborted` 事件
  - 执行单元格状态转换逻辑
  - 失败标记渲染

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `TurnAbortedEvent` 结构定义
  - `TurnAbortReason` 枚举定义

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__interrupt_exec_marks_failed.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理中断事件 |
| `ExecCell` | 执行单元格管理 |
| `HistoryCell` | 历史单元格渲染 |
| `InterruptManager` | 中断管理器 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `TurnAborted` | Core → TUI | 回合被中止 |
| `ExecCommandBegin` | Core → TUI | 执行命令开始 |
| `ExecCommandEnd` | Core → TUI | 执行命令结束 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `begin_exec`: 开始执行命令
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**: 命令完成和中断事件同时到达时的处理
2. **UI 闪烁**: 中断时 UI 可能出现的闪烁问题
3. **历史顺序**: 中断命令在历史记录中的位置可能不符合用户预期

### 边界情况
1. **空命令**: 命令信息为空时的处理
2. **多命令中断**: 多个命令同时执行时中断其中一个
3. **中断后恢复**: 中断后用户继续操作的场景
4. **网络延迟**: 中断信号延迟到达的情况

### 改进建议
1. **添加中断动画**: 中断时添加视觉反馈动画
2. **中断原因展示**: 更详细地展示中断原因
3. **重试机制**: 提供中断命令的重试选项
4. **批量中断**: 支持同时中断多个执行中的命令
5. **中断确认**: 对于长时间运行的命令，添加中断确认对话框
