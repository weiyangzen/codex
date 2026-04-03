# Bottom Pane Status and Queued Messages Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `mod.rs` 模块的测试快照，用于验证**底部面板状态栏和排队消息的组合渲染**。当系统正在处理任务且有排队消息时，显示此界面。

### 业务场景
- 用户发送了多条消息，系统正在处理第一条
- 用户想要查看当前任务状态和排队消息
- 需要同时显示状态指示和排队消息预览

### 底部面板组合特性
- 显示当前任务状态（运行时间、中断提示）
- 显示排队消息预览
- 显示输入框
- 显示底部栏

## 功能点目的

### 核心功能
1. **状态指示**：显示当前任务状态和运行时间
2. **排队消息**：显示等待处理的消息预览
3. **输入就绪**：保持输入框可用，允许继续输入
4. **中断提示**：提示用户可以按 Esc 中断当前任务

### 用户体验目标
- **状态可见**：用户清楚知道系统正在做什么
- **队列可见**：用户知道有多少消息在等待
- **持续输入**：即使任务运行中，用户也可以继续输入

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct BottomPane {
    status_view: Option<StatusView>,
    message_queue_view: Option<MessageQueueView>,
    chat_composer: ChatComposer,
    // ...
}

pub(crate) struct StatusView {
    pub status: String,
    pub duration: Duration,
    pub show_interrupt_hint: bool,
}
```

### 渲染逻辑
```rust
impl Renderable for BottomPane {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 垂直布局：状态栏、排队消息、输入框、底部栏
        let [status_area, queue_area, composer_area, footer_area] =
            Layout::vertical([
                Constraint::Length(status_height),
                Constraint::Length(queue_height),
                Constraint::Min(3),
                Constraint::Length(footer_height),
            ])
            .areas(area);
        
        // 渲染状态栏
        if let Some(status) = &self.status_view {
            status.render(status_area, buf);
        }
        
        // 渲染排队消息
        if let Some(queue) = &self.message_queue_view {
            queue.render(queue_area, buf);
        }
        
        // 渲染输入框
        self.chat_composer.render(composer_area, buf);
        
        // 渲染底部栏
        self.render_footer(footer_area, buf);
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
- **测试函数**: `status_and_queued_messages_snapshot` (在 tests 模块中)

### 渲染输出分析
```
• Working (0s • esc to interrupt)               
                                                
• Queued follow-up messages                     
  ↳ Queued follow-up question                   
    ⌥ + ↑ edit last queued message              
                                                
› Ask Codex to do anything                      
                                                
  ? for shortcuts            100% context left
```

- 第 1 行：状态栏（运行中，0秒，可中断）
- 第 3-5 行：排队消息区域
- 第 7 行：输入框
- 第 9 行：底部栏

## 依赖与外部交互

### 内部依赖
- `BottomPane` - 底部面板
- `StatusView` - 状态视图
- `MessageQueueView` - 消息队列视图
- `ChatComposer` - 聊天输入框

### 外部交互
- **任务管理器**：获取任务状态和运行时间
- **消息队列**：获取排队消息
- **输入系统**：处理用户输入

## 风险、边界与改进建议

### 潜在风险
1. **空间竞争**：状态栏和排队消息可能占用过多空间
2. **信息过载**：过多信息可能让用户感到压力
3. **响应延迟**：任务状态更新可能不及时

### 边界情况
1. **无排队消息**：仅显示状态栏
2. **无运行任务**：仅显示排队消息
3. **终端高度不足**：高度不够时的截断策略

### 改进建议
1. **可折叠区域**：允许用户折叠状态栏或排队消息
2. **进度指示**：显示任务完成进度百分比
3. **预计时间**：显示预计剩余时间
4. **队列管理**：提供清除或重新排序排队消息的选项
5. **优先级标记**：允许标记紧急消息优先处理

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
