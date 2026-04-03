# render_pending_steers_above_queued_messages Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件同时处理 **Pending Steers** 和 **Queued Messages** 两种消息类型时的渲染行为。验证当两种消息同时存在时，Pending Steers 显示在上方，Queued Messages 显示在下方，中间有空行分隔。

**典型使用场景**：
- 用户在后台任务执行期间发送了 steer 指令，同时又排队了后续问题
- 复杂的对话流程中需要区分不同类型的待处理消息
- 需要清晰展示消息的处理优先级和顺序

## 功能点目的

该测试验证以下核心功能：

1. **分层显示**：Pending Steers 始终显示在 Queued Messages 上方
2. **空行分隔**：两个部分之间有空行提高可读性
3. **独立标题**：每个部分有自己的标题和样式
4. **编辑提示位置**：`"⌥ + ↑ edit"` 提示只在 Queued Messages 部分底部显示

**渲染输出特征**：
```
• Messages to be submitted after next tool call     <- Pending Steers 标题
  (press esc to interrupt and send immediately)     <- 中断提示
  ↳ Please continue.                                <- Steer 消息 1
  ↳ Check the last command output.                  <- Steer 消息 2
                                                    <- 空行分隔
• Queued follow-up messages                         <- Queued Messages 标题
  ↳ Queued follow-up question                       <- 排队消息
    ⌥ + ↑ edit last queued message                  <- 编辑提示
```

## 具体技术实现

### 分层渲染逻辑
```rust
// 1. 先渲染 Pending Steers
if !self.pending_steers.is_empty() {
    Self::push_section_header(&mut lines, width, /* ... */);
    for steer in &self.pending_steers {
        // 渲染每个 steer...
    }
}

// 2. 渲染 Queued Messages（如果有 pending_steers，先加空行）
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));  // 空行分隔
    }
    Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());
    for message in &self.queued_messages {
        // 渲染每个消息...
    }
}

// 3. 编辑提示（仅当有 queued_messages）
if !self.queued_messages.is_empty() {
    lines.push(Line::from(vec![
        "    ".into(),
        self.edit_binding.into(),
        " edit last queued message".into(),
    ]).dim());
}
```

### 样式对比
| 元素 | Pending Steers | Queued Messages |
|------|----------------|-----------------|
| 标题 | `"Messages to be submitted after next tool call"` | `"Queued follow-up messages"` |
| 附加文本 | `"(press Esc to interrupt...)"` | 无 |
| 消息样式 | `dim()` | `dim().italic()` |
| 编辑提示 | 无 | 有 |

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_pending_steers_above_queued_messages` (test) | 286-303 | 本测试用例 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |

### 测试数据
```rust
// Pending Steers
queue.pending_steers.push("Please continue.".to_string());
queue.pending_steers.push("Check the last command output.".to_string());

// Queued Messages
queue.queued_messages.push("Queued follow-up question".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::key_hint` - 键盘快捷键提示

### 渲染顺序
1. Pending Steers 标题 + 说明
2. Pending Steers 列表
3. 空行分隔
4. Queued Messages 标题
5. Queued Messages 列表
6. 编辑提示（仅 Queued Messages）

## 风险、边界与改进建议

### 当前边界情况
1. **空行分隔**：仅当两个部分都存在时才添加空行
2. **高度计算**：总高度 = Steers 高度 + 1（空行）+ Messages 高度
3. **宽度一致**：两个部分使用相同的宽度设置

### 潜在风险
1. **高度膨胀**：同时存在多种消息时，面板高度可能过高
2. **视觉拥挤**：如果消息数量多，空行分隔可能不够明显
3. **优先级误解**：用户可能误解显示顺序与处理顺序的关系

### 改进建议
1. **可折叠区域**：允许用户折叠/展开某个部分
2. **计数显示**：在标题后显示消息数量，如 `"Queued follow-up messages (1)"`
3. **优先级指示**：添加视觉元素表明 Pending Steers 会先被处理
4. **批量操作**：支持一次性清空或提交某类消息
5. **动画过渡**：添加展开/收起的动画效果提升用户体验
