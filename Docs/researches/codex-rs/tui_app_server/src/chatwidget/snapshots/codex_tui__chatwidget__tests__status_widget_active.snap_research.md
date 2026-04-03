# 研究文档：status_widget_active

## 场景与职责

此 snapshot 测试验证状态小部件（Status Widget）在活动状态下的渲染效果。测试场景模拟了：
- 一个正在运行的任务（TurnStarted 事件）
- 代理正在分析中（"Analyzing" 状态头）
- 显示已运行时间（0s）
- 提供中断提示（esc to interrupt）
- 底部显示上下文剩余百分比（100% context left）

该测试确保在 AI 处理用户请求时，用户能够清晰地看到系统状态并了解如何中断操作。

## 功能点目的

状态小部件是 TUI 中反馈 AI 活动状态的核心组件：
1. **活动指示**：通过动画点（•）和状态文本告知用户系统正在工作
2. **进度感知**：显示已运行时间，帮助用户判断处理时长
3. **中断能力**：明确提示用户可按 ESC 键中断当前操作
4. **上下文监控**：持续显示上下文窗口使用情况
5. **状态细化**：通过推理增量（reasoning delta）更新具体状态描述

这些功能共同提供了对 AI 工作状态的完整可见性。

## 具体技术实现

### 测试设置
```rust
let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
// 激活状态指示器 - 模拟任务开始
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: "turn-1".to_string(),
        model_context_window: None,
        collaboration_mode_kind: ModeKind::Default,
    }),
});
// 通过 reasoning delta 设置确定性状态头
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
        delta: "**Analyzing**".into(),
    }),
});
```

### 渲染输出格式
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
- 第1行：空行（顶部边距）
- 第2行：状态指示器行
  - `•`：活动指示器（动画点）
  - `Analyzing`：状态头（从 reasoning delta 解析）
  - `(0s • esc to interrupt)`：时间计数和中断提示
- 第3-4行：空行（间距）
- 第5行：输入提示符（`›`）和占位文本
- 第6行：空行
- 第7行：页脚（快捷键提示 + 上下文剩余百分比）

### 状态指示器结构
状态指示器由以下部分组成：
1. **动画点**：`•` 表示活动状态
2. **状态头**：从 `AgentReasoningDelta` 中的粗体文本提取
3. **计时器**：显示任务已运行时间
4. **中断提示**：`esc to interrupt` 提示用户可中断

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/bottom_pane/mod.rs`**
   - 定义 `BottomPane` 结构体
   - 管理状态指示器的显示/隐藏
   - `status_indicator_visible()` 方法检查状态指示器是否可见

2. **`codex-rs/tui/src/status/`**（状态指示器子模块）
   - 实现状态动画和计时逻辑
   - 处理状态文本的更新和渲染

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 9603-9629）
   - 测试函数 `status_widget_active_snapshot`
   - 验证状态小部件的渲染输出

### 相关数据结构
```rust
// AgentReasoningDeltaEvent - 用于更新状态头
pub struct AgentReasoningDeltaEvent {
    pub delta: String,  // 支持 Markdown 格式，如 "**Analyzing**"
}

// TurnStartedEvent - 触发任务开始
pub struct TurnStartedEvent {
    pub turn_id: String,
    pub model_context_window: Option<i64>,
    pub collaboration_mode_kind: ModeKind,
}
```

### 状态更新流程
1. `TurnStarted` 事件 → 激活状态指示器，开始计时
2. `AgentReasoningDelta` 事件 → 解析粗体文本更新状态头
3. 计时器更新 → 每秒刷新运行时间显示
4. `TurnComplete` 事件 → 隐藏状态指示器

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::BottomPane` | 状态指示器容器和显示控制 |
| `status` 子模块 | 状态动画和计时实现 |
| `chatwidget::ChatWidget` | 事件处理和状态管理 |

### 事件依赖
- `TurnStartedEvent`：触发状态指示器显示
- `AgentReasoningDeltaEvent`：提供状态头更新
- `AgentMessageDeltaEvent`：流式消息更新
- `TurnCompleteEvent`：触发状态指示器隐藏

### 渲染依赖
- `ratatui::Terminal`：终端渲染
- `TestBackend`：测试后端捕获输出

## 风险、边界与改进建议

### 潜在风险
1. **状态头解析失败**：如果 reasoning delta 不包含粗体文本，状态头可能显示默认值
2. **计时器漂移**：长时间运行的任务可能出现计时器不准确
3. **中断延迟**：ESC 键中断可能存在延迟，用户可能多次按键

### 边界情况
1. **快速状态切换**：连续多个 reasoning delta 可能导致状态头闪烁
2. **空状态头**：当 reasoning delta 为空或无效时，应显示默认状态（如 "Working"）
3. **终端宽度不足**：窄终端中状态文本可能被截断，中断提示可能不可见

### 改进建议
1. **状态历史**：显示最近几个状态头的历史，帮助用户了解处理流程
2. **进度估计**：基于历史数据提供预计完成时间
3. **中断确认**：对于长时间运行的任务，中断前要求确认
4. **状态动画**：为活动指示器添加更多动画选项（如旋转条）
5. **声音提示**：任务完成或中断时提供可选的声音反馈

### 相关测试
- `status_widget_active_snapshot`：本测试文件
- `status_widget_and_approval_modal_snapshot`：状态与模态框组合测试
- `unified_exec_begin_restores_working_status_snapshot`：执行状态恢复测试
