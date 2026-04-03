# 中断回合错误消息测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中用户中断回合后的错误消息展示。当用户按下 ESC 键中断正在进行的 AI 回合时，系统会向用户显示一条友好的错误消息，提示用户告知模型需要做出的改变，并提供反馈渠道。

## 功能点目的

1. **用户引导**: 向用户解释中断后的下一步操作
2. **反馈入口**: 提供 `/feedback` 命令入口供用户报告问题
3. **状态恢复**: 帮助用户理解当前会话状态
4. **体验优化**: 使用友好的语言减少用户中断后的困惑

## 具体技术实现

### 测试流程

```rust
async fn interrupted_turn_error_message_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 2. 模拟进行中的任务（使组件进入运行状态）
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 3. 中止回合（如同按下 Esc 键）
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnAborted(TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    // 4. 捕获并验证历史单元格
    let cells = drain_insert_history(&mut rx);
    assert!(!cells.is_empty(), "expected error message to be inserted after interruption");
    let last = lines_to_single_string(cells.last().unwrap());
    assert_snapshot!("interrupted_turn_error_message", last);
}
```

### 关键数据结构

- **`TurnAbortedEvent`**: 回合中止事件
  - `turn_id`: 被中止的回合 ID
  - `reason`: 中止原因（`Interrupted`, `Error`, `Timeout`）

- **`TurnAbortReason::Interrupted`**: 用户中断原因
  - 表示用户主动中断回合（通常通过 ESC 键）

### 渲染输出格式

```
■ Conversation interrupted - tell the model what to do differently. Something went wrong? Hit `/feedback` to report the issue.
```

### 消息内容解析

- **■**: 红色方块图标，表示错误或中断状态
- **Conversation interrupted**: 明确告知用户会话已被中断
- **tell the model what to do differently**: 引导用户修改指令
- **Something went wrong?**: 询问是否遇到问题
- **Hit `/feedback` to report the issue**: 提供反馈命令入口

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 7140-7172)
  - 测试函数 `interrupted_turn_error_message_snapshot`
  - 验证中断后错误消息被正确插入历史记录

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `handle_codex_event` 方法处理 `TurnAborted` 事件
  - 中断后错误消息生成逻辑
  - `submit_pending_steers_after_interrupt` 标志检查

### 相关测试
- **`interrupted_turn_pending_steers_message_snapshot`** (行 7174-7208)
  - 测试有待处理 steer 时的中断消息（不同消息内容）

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `TurnAbortedEvent` 结构定义
  - `TurnAbortReason` 枚举定义

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__interrupted_turn_error_message.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理中断事件 |
| `BottomPane` | 底部面板，显示状态信息 |
| `HistoryCell` | 历史单元格渲染 |
| `pending_steers` | 待处理 steer 队列 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `TurnStarted` | Core → TUI | 回合开始 |
| `TurnAborted` | Core → TUI | 回合中止 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **消息重复**: 多次中断可能导致多条错误消息
2. **消息覆盖**: 待处理 steer 场景下的消息覆盖问题
3. **国际化**: 错误消息未国际化，仅支持英文

### 边界情况
1. **无运行回合**: 没有运行中的回合时收到中断事件
2. **快速中断**: 回合开始后立即中断
3. **网络中断**: 网络问题导致的中断与手动中断的区分
4. **多回合中断**: 多个回合同时运行时的中断处理

### 改进建议
1. **国际化支持**: 将错误消息添加到国际化资源文件
2. **消息分类**: 根据中断原因显示不同的消息
3. **快捷操作**: 在错误消息中添加快捷操作按钮
4. **历史折叠**: 支持折叠/展开中断错误消息
5. **统计收集**: 收集中断频率数据用于产品优化
