# render_multiline_pending_steer_uses_single_prefix_and_truncates Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**多行 Pending Steer** 时的渲染行为。Pending Steer 是将在下一个工具调用后自动提交的消息，与 Queued Messages 不同，它们有独立的标题和说明文字。

**典型使用场景**：
- 用户在工具执行期间发送的引导性指令（如 "Please continue"）
- 需要延迟到特定时机（工具调用边界）才发送的消息
- 用户希望在后台任务继续时预设的后续指令

## 功能点目的

该测试验证以下核心功能：

1. **独立标题**：Pending Steers 使用 `"Messages to be submitted after next tool call"` 标题
2. **中断提示**：显示 `"(press Esc to interrupt and send immediately)"` 说明
3. **单前缀多行**：多行内容只使用一个 `"  ↳ "` 前缀，续行缩进对齐
4. **行数限制**：超过 3 行时显示省略号

**渲染输出特征**：
```
• Messages to be submitted after next tool call <- 标题（dim 样式）
  (press esc to interrupt and send immediately) <- 中断提示（dim 样式）
  ↳ First line                                  <- 第一行（dim）
    Second line                                 <- 续行（dim）
    Third line                                  <- 续行（dim）
    …                                           <- 截断提示（dim）
```

## 具体技术实现

### Pending Steer 渲染逻辑
```rust
if !self.pending_steers.is_empty() {
    Self::push_section_header(
        &mut lines,
        width,
        Line::from(vec![
            "Messages to be submitted after next tool call".into(),
            " (press ".dim(),
            key_hint::plain(KeyCode::Esc).into(),
            " to interrupt and send immediately)".dim(),
        ]),
    );

    for steer in &self.pending_steers {
        let wrapped = adaptive_wrap_lines(
            steer.lines().map(|line| Line::from(line.dim())),  // 注意：无 italic
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
```

### 样式差异（vs Queued Messages）
| 元素 | Pending Steers | Queued Messages |
|------|----------------|-----------------|
| 标题 | `"Messages to be submitted after next tool call"` | `"Queued follow-up messages"` |
| 附加说明 | `"(press Esc to interrupt...)"` | 无 |
| 消息样式 | `dim()` | `dim().italic()` |
| 省略号样式 | `"    …".dim()` | `"    …".dim().italic()` |
| 编辑提示 | 无 | `"⌥ + ↑ edit last queued message"` |

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_multiline_pending_steer_uses_single_prefix_and_truncates` (test) | 306-319 | 本测试用例 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |
| `push_section_header()` | 60-67 | 节标题渲染 |

### 测试数据
```rust
queue.pending_steers.push("First line\nSecond line\nThird line\nFourth line".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::wrapping::RtOptions` - 换行选项配置
- `crate::key_hint` - 键盘快捷键提示
- `crossterm::event::KeyCode` - 按键定义

### Pending Steer 生命周期
1. 用户在工具执行期间输入消息
2. 消息被添加到 `pending_steers` 队列
3. 在下一个工具/结果边界自动提交
4. 用户可按 Esc 中断并立即发送

## 风险、边界与改进建议

### 当前边界情况
1. **样式区分**：Pending Steers 使用 `dim()`，Queued Messages 使用 `dim().italic()`，区分度有限
2. **无编辑功能**：Pending Steers 不支持 `"⌥ + ↑ edit"` 功能
3. **自动提交时机**：依赖工具调用边界，用户可能不清楚何时会提交

### 潜在风险
1. **用户混淆**：Pending Steers 和 Queued Messages 的区别可能不够明显
2. **意外提交**：用户可能忘记有待处理的 steer 而在不期望的时机被提交
3. **中断行为**：Esc 中断行为可能与用户的直觉不符（是中断任务还是发送消息）

### 改进建议
1. **视觉强化**：为 Pending Steers 添加独特的颜色或图标区分
2. **计数显示**：在标题后显示待处理 steer 数量
3. **时间提示**：显示 steer 已等待多长时间
4. **编辑支持**：为 Pending Steers 也添加编辑功能
5. **确认提示**：在自动提交前提供视觉反馈
6. **文档提示**：在首次使用时显示 Pending Steer 的功能说明
