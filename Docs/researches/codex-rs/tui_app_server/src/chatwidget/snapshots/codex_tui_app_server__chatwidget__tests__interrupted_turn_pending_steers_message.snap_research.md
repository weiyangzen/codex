# 中断回合待处理引导消息测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中用户中断回合以提交待处理 steer 指令时的消息展示。当有待处理的 steer（引导指令）在队列中，用户中断当前回合来提交这些 steer 时，系统会显示一条特定的信息性消息，而不是通用的错误提示。

## 功能点目的

1. **Steer 提交反馈**: 告知用户中断是为了提交待处理的 steer 指令
2. **操作意图明确**: 区分普通中断和 steer 提交中断
3. **用户体验优化**: 避免用户困惑，明确中断目的
4. **状态同步**: 确认 steer 提交流程已启动

## 具体技术实现

### 测试流程

```rust
async fn interrupted_turn_pending_steers_message_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());
    
    // 2. 添加待处理的 steer 到队列
    chat.pending_steers.push_back(pending_steer("steer 1"));
    chat.submit_pending_steers_after_interrupt = true;

    // 3. 开始回合
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 4. 中止回合
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnAborted(TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    // 5. 捕获并验证 steer 中断消息
    let cells = drain_insert_history(&mut rx);
    let info = cells
        .iter()
        .map(|cell| lines_to_single_string(cell))
        .find(|line| line.contains("Model interrupted to submit steer instructions."))
        .expect("expected steer interrupt info message to be inserted");
    assert_snapshot!("interrupted_turn_pending_steers_message", info);
}
```

### 关键数据结构

- **`PendingSteer`**: 待处理的 steer 指令
  - `user_message`: 用户消息内容
  - `compare_key`: 用于去重的比较键

- **`PendingSteerCompareKey`**: Steer 比较键
  - `message`: 消息文本
  - `image_count`: 图像数量

- **`submit_pending_steers_after_interrupt`**: 标志位
  - 表示中断后应提交待处理的 steer

### 渲染输出格式

```
• Model interrupted to submit steer instructions.
```

### 与通用中断消息的区别

| 场景 | 消息内容 |
|------|----------|
| 通用中断 | `■ Conversation interrupted - tell the model what to do differently...` |
| Steer 提交中断 | `• Model interrupted to submit steer instructions.` |

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 7174-7208)
  - 测试函数 `interrupted_turn_pending_steers_message_snapshot`
  - 使用 `pending_steer` 辅助函数创建 steer 对象
  - 验证 steer 特定的中断消息被正确插入

### 辅助函数
- **`pending_steer`** (行 3583-3591): 创建待处理 steer 对象
  ```rust
  fn pending_steer(text: &str) -> PendingSteer {
      PendingSteer {
          user_message: UserMessage::from(text),
          compare_key: PendingSteerCompareKey {
              message: text.to_string(),
              image_count: 0,
          },
      }
  }
  ```

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `pending_steers: VecDeque<PendingSteer>` 字段存储待处理 steer
  - `submit_pending_steers_after_interrupt: bool` 标志
  - `handle_codex_event` 方法处理 `TurnAborted` 事件时的消息选择逻辑

### 相关模块
- **`codex-rs/tui_app_server/src/chatwidget/realtime.rs`**
  - `PendingSteer` 结构定义
  - `PendingSteerCompareKey` 用于 steer 去重

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `TurnAbortedEvent`, `TurnAbortReason` 定义

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__interrupted_turn_pending_steers_message.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理 steer 队列 |
| `PendingSteer` | 待处理 steer 数据结构 |
| `pending_steers` | steer 队列（VecDeque） |
| `submit_pending_steers_after_interrupt` | 提交标志 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `TurnStarted` | Core → TUI | 回合开始 |
| `TurnAborted` | Core → TUI | 回合中止 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `pending_steer`: 创建待处理 steer 对象
- `drain_insert_history`: 从事件通道中提取所有历史单元格
- `lines_to_single_string`: 将多行文本合并为单个字符串

## 风险、边界与改进建议

### 潜在风险
1. **标志同步**: `submit_pending_steers_after_interrupt` 标志可能未及时重置
2. **队列竞争**: steer 队列操作可能存在竞争条件
3. **消息丢失**: 多个 steer 同时提交时的消息处理问题

### 边界情况
1. **空队列中断**: steer 队列为空但标志为 true 的情况
2. **大量 steer**: 队列中有大量 steer 时的性能表现
3. **快速中断**: steer 提交后立即再次中断
4. **Steer 重复**: 相同内容的 steer 去重处理

### 改进建议
1. **Steer 计数**: 在消息中显示待提交 steer 的数量
2. **Steer 预览**: 允许用户在中断前预览待提交的 steer
3. **批量提交优化**: 优化大量 steer 的批量提交性能
4. **提交确认**: 添加 steer 提交成功的确认消息
5. **Steer 历史**: 维护 steer 提交历史供用户查看
