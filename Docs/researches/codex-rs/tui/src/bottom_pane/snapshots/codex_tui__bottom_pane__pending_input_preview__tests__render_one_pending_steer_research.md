# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_one_pending_steer.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_one_pending_steer`

---

## 1. 场景与职责

### 测试场景
本测试验证 `PendingInputPreview` 组件在只有一条 pending steer 时的渲染行为。Pending steer 是用户输入的指令，将在下一个工具调用边界后提交。

### 业务场景
用户在系统执行工具调用时输入了后续指令（如 "Please continue."），这些指令被存储为 `pending_steers`，将在当前操作完成后自动发送。

### 组件职责
- 显示待提交的 steer 消息
- 说明 steer 的提交时机（下一个工具调用后）
- 提供中断并立即发送的选项（Esc 键）
- 使用与 queued messages 不同的视觉样式

---

## 2. 功能点目的

### 核心功能验证
1. **Steer 区域渲染**: 验证 "Messages to be submitted after next tool call" 标题
2. **中断提示**: 验证显示 "(press esc to interrupt and send immediately)" 提示
3. **Steer 内容**: 验证 steer 消息正确显示
4. **无编辑提示**: 验证 steer 区域不显示 "⌥ + ↑ edit" 提示

### 用户体验目标
- 让用户了解 steer 的自动提交机制
- 提供明确的快捷键（Esc）用于紧急发送
- 区分 steer 和 queued message 的视觉样式

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.pending_steers.push("Please continue.".to_string());
let width = 48;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 48, height: 3 },
    content: [
        "• Messages to be submitted after next tool call ",  // 第0行：标题
        "  (press esc to interrupt and send immediately) ",  // 第1行：中断提示
        "  ↳ Please continue.                            ",  // 第2行：steer内容
    ],
    ...
}
```

### 与 Queued Messages 的关键区别
| 特性 | Pending Steers | Queued Messages |
|---|---|---|
| 标题 | "Messages to be submitted after next tool call" | "Queued follow-up messages" |
| 中断提示 | 有 (press esc...) | 无 |
| 编辑提示 | 无 | 有 (⌥ + ↑ ...) |
| 内容样式 | dim() | dim().italic() |
| 省略号样式 | dim() | dim().italic() |

### 样式映射
| 行 | 列范围 | 样式 |
|---|---|---|
| 0 | 0-1 | DIM ("• ") |
| 0 | 2-46 | NONE (标题) |
| 1 | 0-47 | DIM (中断提示) |
| 2 | 0-3 | DIM ("  ↳ ") |
| 2 | 4-19 | NONE (steer内容) |

---

## 4. 关键代码路径与文件引用

### Steer 渲染逻辑 (lines 76-97)
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
            steer.lines().map(|line| Line::from(line.dim())),
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
```

### 关键差异点
1. **内容样式**: steer 使用 `line.dim()`，而 queued message 使用 `line.dim().italic()`
2. **省略号样式**: steer 使用 `"    …".dim()`，而 queued message 使用 `"    …".dim().italic()`
3. **无编辑提示**: steer 区域不添加 `edit_binding` 提示

---

## 5. 依赖与外部交互

### key_hint 集成
```rust
key_hint::plain(KeyCode::Esc).into()
```
- 将 `KeyCode::Esc` 转换为可显示的 Span
- 使用 `plain` 函数创建无修饰键的绑定
- 显示为 "esc"

### 样式对比
```rust
// Pending steer - 仅暗淡
steer.lines().map(|line| Line::from(line.dim()))

// Queued message - 暗淡+斜体  
message.lines().map(|line| Line::from(line.dim().italic()))
```

---

## 6. 风险边界与改进建议

### 当前限制
1. **样式差异细微**: dim() 和 dim().italic() 的差异在某些终端可能不明显
2. **无 steer 编辑**: 用户无法编辑 pending steer，只能中断后重新输入
3. **steer 和 message 顺序**: steer 总是显示在 message 上方，用户无法调整

### 改进建议
1. **增强视觉区分**
   - 使用不同的前缀符号（如 "→" 用于 steer，"↳" 用于 message）
   - 或添加颜色区分

2. **Steer 编辑功能**
   - 添加编辑 pending steer 的能力
   - 类似 queued message 的 ⌥ + ↑ 快捷键

3. **优先级提示**
   - 当有 steer 和 message 同时存在时，说明处理顺序
   - steer 先提交，然后是 message

4. **批量中断**
   - 提供中断所有 steer 的选项
   - 或选择性中断特定 steer

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 48, height: 3 },
    content: [
        "• Messages to be submitted after next tool call ",
        "  (press esc to interrupt and send immediately) ",
        "  ↳ Please continue.                            ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 47, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 20, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
