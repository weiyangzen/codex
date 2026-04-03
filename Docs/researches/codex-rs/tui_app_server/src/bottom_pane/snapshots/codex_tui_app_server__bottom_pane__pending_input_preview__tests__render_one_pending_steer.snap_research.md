# render_one_pending_steer Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**单条 Pending Steer** 时的渲染行为。Pending Steer 是一种特殊的消息类型，它会在下一个工具调用边界自动提交，而不是立即发送。

**典型使用场景**：
- 用户在后台命令执行期间发送 "Please continue." 等引导指令
- 希望在当前工具完成后自动继续对话
- 预设的后续操作指令

## 功能点目的

该测试验证以下核心功能：

1. **独立标题**：Pending Steers 使用专门的标题 `"Messages to be submitted after next tool call"`
2. **中断说明**：显示 `"(press esc to interrupt and send immediately)"` 提示用户可立即发送
3. **简洁渲染**：单条 steer 时只显示标题、说明和消息内容
4. **无编辑提示**：Pending Steers 不显示 `"⌥ + ↑ edit"` 提示

**渲染输出特征**：
```
• Messages to be submitted after next tool call <- 标题（dim 样式）
  (press esc to interrupt and send immediately) <- 中断提示（dim 样式）
  ↳ Please continue.                            <- 消息内容（dim 样式）
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
            steer.lines().map(|line| Line::from(line.dim())),  // 仅 dim，无 italic
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
// 注意：没有 queued_messages 的编辑提示逻辑
```

### 与 Queued Messages 的关键区别
| 特性 | Pending Steers | Queued Messages |
|------|----------------|-----------------|
| 标题 | `"Messages to be submitted after next tool call"` | `"Queued follow-up messages"` |
| 附加说明 | `"(press Esc to interrupt...)"` | 无 |
| 消息样式 | `dim()` | `dim().italic()` |
| 编辑提示 | 无 | 有 `"⌥ + ↑ edit..."` |
| 提交时机 | 工具调用边界 | 当前任务完成 |

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_one_pending_steer` (test) | 275-283 | 本测试用例 |
| `as_renderable()` | 69-132 | 主渲染逻辑（76-97 行处理 pending_steers） |

### 测试数据
```rust
queue.pending_steers.push("Please continue.".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::key_hint` - 键盘快捷键提示
- `crossterm::event::KeyCode` - Esc 键定义
- `crate::wrapping::adaptive_wrap_lines` - 文本换行

### 中断行为
用户可以通过以下方式中断 Pending Steer 的自动提交：
1. 按 Esc 键
2. 触发 `key_hint::plain(KeyCode::Esc)` 对应的事件
3. 消息立即发送，不再等待工具调用边界

## 风险、边界与改进建议

### 当前边界情况
1. **单条 steer**：测试仅验证单条 steer，未验证多条
2. **短消息**：`"Please continue."` 较短，未触发换行
3. **宽度充足**：48 字符宽度足够显示完整内容

### 潜在风险
1. **用户认知**：新用户可能不理解 Pending Steer 和 Queued Message 的区别
2. **中断歧义**：Esc 键可能与其他功能（如关闭弹窗）冲突
3. **自动提交时机**：用户可能不清楚"下一个工具调用边界"具体指什么

### 改进建议
1. **首次使用提示**：首次出现 Pending Steer 时显示功能说明
2. **视觉区分**：使用不同颜色或图标强化与 Queued Messages 的区别
3. **悬停提示**：鼠标悬停时显示详细说明（如果支持鼠标）
4. **时间戳**：显示 steer 已等待的时间
5. **批量管理**：支持查看和管理所有待处理的 steers
