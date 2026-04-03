# ChatWidget 增量消息后相同最终消息渲染测试

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 正确处理流式增量消息（deltas）后接相同内容最终消息的场景。这测试了去重逻辑，确保内容不会重复渲染。

### 测试目的
- 验证流式增量与最终消息的去重逻辑
- 确保相同内容不会重复显示
- 测试推理内容和回答内容的正确处理

### 业务场景
- Codex 流式返回推理过程（"I will first analyze..."）
- 随后发送最终消息包含相同内容
- 用户应只看到一次内容，而非重复

## 功能点目的

### 1. 流式内容去重
当以下序列发生时：
1. `AgentReasoningDelta` × N - 流式推理增量
2. `AgentReasoning` - 最终推理消息（可能与增量累积相同）
3. `AgentMessageDelta` × N - 流式回答增量
4. `AgentMessage` - 最终消息（可能与增量累积相同）

系统应：
- 正确累积增量内容
- 识别并去重最终消息
- 保持渲染的连贯性

### 2. 推理与回答分离
- 推理内容（reasoning）和回答内容（message）应分开处理
- 推理通常不显示给用户，或显示为折叠状态
- 回答内容是用户可见的最终输出

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn deltas_then_same_final_message_are_rendered_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 1. 流式推理增量
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "I will ".into(),
        }),
    });
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "first analyze the ".into(),
        }),
    });
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "request.".into(),
        }),
    });
    
    // 2. 最终推理消息（与累积内容相同）
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentReasoning(AgentReasoningEvent {
            text: "request.".into(), // 注意：这里可能是部分匹配
        }),
    });

    // 3. 流式回答增量
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent {
            chunk: "Here is ".into(),
        }),
    });
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent {
            chunk: "the answer.".into(),
        }),
    });
    
    // 4. 最终回答消息（与累积内容相同）
    chat.handle_codex_event(Event {
        id: "s1".into(),
        msg: EventMsg::AgentMessage(AgentMessageEvent {
            message: "Here is the answer.".into(),
            phase: None,
            memory_citation: None,
        }),
    });

    // 5. 提交并捕获
    chat.on_commit_tick();
    let cells = drain_insert_history(&mut rx);
    let combined: String = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect();
    
    assert_snapshot!(combined);
}
```

### Snapshot 内容
```
（空字符串）
```

**分析**：
- Snapshot 显示为空，表明：
  1. 所有内容被正确去重，没有重复渲染
  2. 或者内容被识别为与缓冲区相同而被跳过
  3. 可能推理内容默认不显示在历史中

### 去重逻辑
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

impl ChatWidget {
    fn handle_agent_message(&mut self, event: AgentMessageEvent) {
        let buffered = self.message_buffer.clone();
        
        // 检查最终消息是否与缓冲区内容相同
        if event.message.trim() == buffered.trim() {
            // 内容相同，跳过最终消息（已显示）
            return;
        }
        
        // 内容不同，追加差异部分或替换
        self.message_buffer = event.message;
        self.active_cell_revision += 1;
    }
    
    fn handle_agent_message_delta(&mut self, delta: AgentMessageDeltaEvent) {
        // 累积增量
        self.message_buffer.push_str(&delta.chunk);
        self.active_cell_revision += 1;
    }
}
```

## 关键代码路径与文件引用

### 流式控制器
```rust
// codex-rs/tui_app_server/src/streaming/controller.rs

pub struct StreamController {
    buffer: String,
    last_commit: String,
    commit_interval: Duration,
}

impl StreamController {
    /// 处理增量内容
    pub fn push_delta(&mut self, delta: &str) {
        self.buffer.push_str(delta);
    }
    
    /// 尝试提交（基于时间或大小）
    pub fn try_commit(&mut self) -> Option<String> {
        if self.should_commit() {
            let content = self.buffer.clone();
            self.last_commit = content.clone();
            self.buffer.clear();
            Some(content)
        } else {
            None
        }
    }
    
    /// 检查最终消息是否重复
    pub fn is_duplicate(&self, final_message: &str) -> bool {
        final_message.trim() == self.last_commit.trim()
    }
}
```

### 活跃单元格管理
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

pub(crate) struct ActiveCellTranscriptKey {
    /// 缓存失效版本号
    pub(crate) revision: u64,
    /// 是否流式延续
    pub(crate) is_stream_continuation: bool,
    /// 动画刻度（用于时间相关输出）
    pub(crate) animation_tick: Option<u64>,
}

impl ChatWidget {
    /// 获取活跃单元格的转录缓存键
    pub(crate) fn active_cell_transcript_key(&self) -> ActiveCellTranscriptKey {
        ActiveCellTranscriptKey {
            revision: self.active_cell_revision,
            is_stream_continuation: self.active_cell.as_ref()
                .map(|c| c.is_stream_continuation())
                .unwrap_or(false),
            animation_tick: self.get_animation_tick(),
        }
    }
}
```

### 消息阶段处理
```rust
// codex-protocol 中的消息阶段
pub enum MessagePhase {
    Commentary,  // 评论/推理阶段
    Answer,      // 回答阶段
}

pub struct AgentMessageEvent {
    pub message: String,
    pub phase: Option<MessagePhase>,
    pub memory_citation: Option<MemoryCitation>,
}
```

## 依赖与外部交互

### 协议事件类型
| 事件 | 描述 |
|------|------|
| `AgentReasoningDeltaEvent` | 流式推理增量 |
| `AgentReasoningEvent` | 最终推理消息 |
| `AgentMessageDeltaEvent` | 流式回答增量 |
| `AgentMessageEvent` | 最终回答消息 |

### 内部状态
```rust
struct ChatWidget {
    message_buffer: String,           // 消息累积缓冲区
    reasoning_buffer: String,         // 推理累积缓冲区
    active_cell_revision: u64,        // 活跃单元格版本
    active_cell: Option<Box<dyn HistoryCell>>, // 当前活跃单元格
}
```

### 提交机制
```
增量事件 → 累积到 buffer
              ↓
    on_commit_tick() / 自动提交
              ↓
    创建/更新 AgentMessageCell
              ↓
    插入到历史记录
              ↓
    触发 UI 更新
```

## 风险、边界与改进建议

### 当前限制

1. **空 Snapshot**
   - 无法验证去重逻辑的实际效果
   - 难以区分"正确去重"和"渲染失败"

2. **部分匹配问题**
   - 测试中的 `AgentReasoningEvent` 只包含 "request."
   - 而累积内容是 "I will first analyze the request."
   - 可能不是真正的去重测试

3. **时序依赖**
   - `on_commit_tick()` 的调用时机影响结果
   - 不同提交策略可能导致不同行为

### 改进建议

1. **增强测试验证**
   ```rust
   #[tokio::test]
   async fn deltas_then_same_final_message_are_rendered_snapshot() {
       // ... 现有代码 ...
       
       // 添加中间状态断言
       assert_eq!(chat.message_buffer, "Here is the answer.");
       assert_eq!(chat.reasoning_buffer, "I will first analyze the request.");
       
       // 提交前验证
       chat.on_commit_tick();
       
       // 验证历史单元格数量
       let cells = drain_insert_history(&mut rx);
       assert_eq!(cells.len(), 1, "应只有一个历史单元格（去重后）");
       
       let combined = cells.iter()
           .map(|lines| lines_to_single_string(lines))
           .collect::<String>();
       
       // 验证内容正确性
       assert!(combined.contains("Here is the answer."));
       assert!(!combined.contains("Here is the answer.Here is the answer."));
       
       assert_snapshot!(combined);
   }
   ```

2. **测试不同去重场景**
   ```rust
   #[tokio::test]
   async fn partial_duplicate_handling() {
       // 测试部分重复的情况
       // 增量："Hello " → "world"
       // 最终："Hello world!"（带额外标点）
   }
   
   #[tokio::test]
   async fn whitespace_difference_handling() {
       // 测试空白字符差异
       // 缓冲区："Hello world"
       // 最终："Hello world "（尾部空格）
   }
   ```

3. **推理内容可见性测试**
   ```rust
   #[tokio::test]
   async fn reasoning_content_visibility() {
       // 测试推理内容是否按配置显示/隐藏
   }
   ```

4. **性能测试**
   ```rust
   #[tokio::test]
   async fn large_delta_stream_performance() {
       // 测试大量增量消息的处理性能
       for i in 0..10_000 {
           chat.handle_codex_event(/* 小增量 */);
       }
   }
   ```

### 相关测试
- `final_reasoning_then_message_without_deltas_are_rendered` - 无增量的推理+消息
- `thread_snapshot_replay_does_not_duplicate_agent_message_history` - 回放去重
- `preamble_keeps_working_status_snapshot` - 前言内容处理

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__deltas_then_same_final_message_are_rendered_snapshot.snap*
