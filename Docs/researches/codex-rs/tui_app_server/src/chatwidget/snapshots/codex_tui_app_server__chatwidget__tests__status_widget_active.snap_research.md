# 研究文档：Status Widget Active 快照测试

## 场景与职责

此快照文件验证当 Agent 任务处于活动状态（"Analyzing"）时，TUI 底部状态栏（Status Widget）的渲染输出。测试确保状态指示器在任务进行中正确显示活动状态、持续时间、打断提示以及上下文使用率信息。

## 功能点目的

1. **活动状态可视化**：清晰显示 Agent 正在处理任务（"Analyzing"）
2. **持续时间显示**：显示任务已运行时间（0s）
3. **打断提示**：提供打断任务的快捷键提示（esc to interrupt）
4. **上下文监控**：显示剩余上下文窗口百分比（100% context left）
5. **布局稳定性**：确保状态栏在不同终端尺寸下渲染一致

## 具体技术实现

### 关键流程

测试函数 `status_widget_active_snapshot`（行 10312）：

```rust
#[tokio::test]
async fn status_widget_active_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 1. 激活状态指示器 - 模拟任务开始
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });
    
    // 2. 通过粗体推理块提供确定性的标题
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "**Analyzing**".into(),
        }),
    });
    
    // 3. 渲染并捕获快照
    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw status widget");
    assert_snapshot!("status_widget_active", terminal.backend());
}
```

### 事件流分析

1. **TurnStarted 事件**：
   - 标记新一轮 Agent 回合开始
   - 激活底部状态栏的任务运行指示器
   - `collaboration_mode_kind: ModeKind::Default` 表示默认协作模式

2. **AgentReasoningDelta 事件**：
   - 提供推理内容的增量更新
   - `**Analyzing**` 使用 Markdown 粗体语法
   - 状态栏提取粗体文本作为状态标题

### 渲染输出格式

快照显示 80x6 字符的终端输出：
```
"                                                                                "
"• Analyzing (0s • esc to interrupt)                                             "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

格式解析：
- 第 1 行：空行（间距）
- 第 2 行：`• Analyzing (0s • esc to interrupt)` - 状态指示器
  - `•` - 活动指示器（可能带有旋转动画）
  - `Analyzing` - 从推理内容提取的状态文本
  - `(0s` - 已运行时间
  - `• esc to interrupt)` - 打断提示
- 第 3-4 行：空行（间距）
- 第 5 行：`› Ask Codex to do anything` - 输入提示
- 第 6 行：空行（间距）
- 第 7 行：`? for shortcuts` + `100% context left` - 帮助提示和上下文使用率

### 数据结构

**TurnStartedEvent**（`codex-rs/protocol/src/protocol.rs`）：
```rust
pub struct TurnStartedEvent {
    pub turn_id: String,
    pub model_context_window: Option<usize>,  // 模型上下文窗口大小
    pub collaboration_mode_kind: ModeKind,    // 协作模式
}
```

**AgentReasoningDeltaEvent**：
```rust
pub struct AgentReasoningDeltaEvent {
    pub delta: String,  // 推理内容的增量文本
}
```

**ModeKind** 枚举：
```rust
pub enum ModeKind {
    Default,
    // ... 其他协作模式
}
```

## 关键代码路径与文件引用

### 测试代码
- **文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
- **测试函数**：`status_widget_active_snapshot`（行 10312）
- **测试注解**：`Snapshot test: status widget active (StatusIndicatorView)`

### 状态栏组件
- **文件**：`codex-rs/tui_app_server/src/bottom_pane/` 目录
  - `status_widget.rs` 或相关模块
  - 处理状态指示器的渲染逻辑

### ChatWidget 事件处理
- **文件**：`codex-rs/tui_app_server/src/chatwidget.rs`
  - `handle_codex_event` 方法处理 `TurnStarted` 和 `AgentReasoningDelta`
  - `update_task_running_state` 同步任务运行状态

### 协议定义
- **文件**：`codex-rs/protocol/src/protocol.rs`
  - `TurnStartedEvent`
  - `AgentReasoningDeltaEvent`
  - `ModeKind`

## 依赖与外部交互

### 上游依赖
1. **codex-protocol**：定义 TurnStarted 和 AgentReasoning 事件
2. **ratatui**：
   - `TestBackend` 用于测试渲染
   - `Terminal` 用于管理渲染状态
3. **insta**：快照测试框架

### 下游消费
1. **底部面板（Bottom Pane）**：状态栏是底部面板的一部分
2. **用户界面**：实时显示当前 Agent 状态
3. **输入提示**：与输入框（Composer）协同显示

### 相关组件
- `StatusLineItem`：状态栏项目定义
- `StatusLinePreviewData`：预览数据
- `StatusLineSetupView`：设置视图

## 风险、边界与改进建议

### 当前风险

1. **时间敏感性**：`0s` 是测试开始时的快照，实际运行中时间会持续更新
2. **动画依赖**：`•` 指示器可能有旋转动画，快照捕获特定帧
3. **宽度硬编码**：测试使用 80 字符宽度，可能不覆盖窄屏设备

### 边界情况

1. **超长状态文本**：
   - `"Analyzing very complex codebase with multiple modules..."`
   - 可能溢出或被截断

2. **特殊字符**：
   - 状态文本包含 Unicode 或 Emoji
   - 宽度计算可能不准确

3. **上下文使用率变化**：
   - 本测试显示 `100% context left`
   - 未测试低上下文场景（如 `10% context left`）

4. **不同协作模式**：
   - 测试使用 `ModeKind::Default`
   - 其他模式（如实时协作）可能有不同显示

### 改进建议

1. **增加变体测试**：
   ```rust
   // 测试不同终端宽度
   for width in [40, 80, 120, 160] {
       // 测试状态栏渲染
   }
   ```

2. **测试上下文警告**：
   ```rust
   // 模拟低上下文场景
   assert_snapshot!("status_widget_low_context", ...);
   // 预期显示警告颜色或图标
   ```

3. **测试不同状态**：
   - `Coding` - 编写代码
   - `Searching` - 搜索文件
   - `Testing` - 运行测试
   - `Planning` - 规划任务

4. **国际化支持**：
   - 状态文本需要本地化
   - 时间格式（`0s` vs `0秒`）

5. **可访问性改进**：
   - 除颜色外增加图标表示状态
   - 支持屏幕阅读器

6. **动画测试**：
   - 如果 `•` 有旋转动画，测试多帧捕获
   - 或使用确定性种子

7. **打断提示变体**：
   - 测试不同打断快捷键（如 Ctrl+C）
   - 测试打断不可用时的显示
