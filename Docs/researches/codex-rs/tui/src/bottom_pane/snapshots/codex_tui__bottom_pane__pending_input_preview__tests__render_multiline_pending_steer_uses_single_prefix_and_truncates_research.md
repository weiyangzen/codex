# PendingInputPreview 测试快照研究文档

## 文件信息
- **快照文件**: `codex_tui__bottom_pane__pending_input_preview__tests__render_multiline_pending_steer_uses_single_prefix_and_truncates.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- **测试函数**: `render_multiline_pending_steer_uses_single_prefix_and_truncates`

---

## 1. 场景与职责

### 测试场景
本测试验证多行 pending steer 的渲染行为，特别是：
1. 只有第一行有 "↳" 前缀，后续行使用普通缩进
2. 超过 `PREVIEW_LINE_LIMIT`（3行）时的截断行为

### 业务场景
用户输入了一段多行 steer 指令（如包含多个指令或说明），组件需要正确渲染并限制显示行数。

### 组件职责
- 为多行 steer 的第一行添加 "↳" 前缀
- 为后续行使用统一的缩进（无箭头）
- 截断超过3行的内容并显示省略号
- 保持 steer 的 dim() 样式（无 italic）

---

## 2. 功能点目的

### 核心功能验证
1. **单行前缀**: 验证只有第一行有 "↳" 前缀
2. **统一缩进**: 验证后续行使用 "    " 缩进
3. **行数截断**: 验证超过3行时显示省略号
4. **样式保持**: 验证所有行保持 dim() 样式

### 用户体验目标
- 通过箭头符号标识 steer 的开始
- 通过统一缩进展示内容的延续性
- 限制长 steer 的显示行数，保持界面紧凑

---

## 3. 具体技术实现

### 测试数据
```rust
let mut queue = PendingInputPreview::new();
queue.pending_steers.push("First line\nSecond line\nThird line\nFourth line".to_string());
let width = 48;
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 48, height: 6 },
    content: [
        "• Messages to be submitted after next tool call ",  // 第0行：标题
        "  (press esc to interrupt and send immediately) ",  // 第1行：中断提示
        "  ↳ First line                                  ",  // 第2行：第1行（有箭头）
        "    Second line                                 ",  // 第3行：第2行（无箭头）
        "    Third line                                  ",  // 第4行：第3行（无箭头）
        "    …                                           ",  // 第5行：省略号
    ],
    ...
}
```

### 前缀逻辑分析
| 行 | 前缀 | 说明 |
|---|---|---|
| 第1行 | "  ↳ " | initial_indent，带箭头 |
| 第2行+ | "    " | subsequent_indent，纯缩进 |

### 截断行为
- 原始内容：4行（"First", "Second", "Third", "Fourth"）
- 显示限制：3行
- 第4行替换为 "    …"

---

## 4. 关键代码路径与文件引用

### 缩进配置
```rust
let wrapped = adaptive_wrap_lines(
    steer.lines().map(|line| Line::from(line.dim())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))    // 第一行前缀
        .subsequent_indent(Line::from("    ")),       // 后续行缩进
);
```

### wrapping.rs 中的处理逻辑
```rust
pub(crate) fn adaptive_wrap_lines<'a, I, L>(...)
where
    I: IntoIterator<Item = L>,
    L: IntoLineInput<'a>,
{
    for (idx, line) in lines.into_iter().enumerate() {
        let opts = if idx == 0 {
            base_opts.clone()  // 使用 initial_indent
        } else {
            base_opts
                .clone()
                .initial_indent(base_opts.subsequent_indent.clone())  // 使用 subsequent_indent
        };
        // ...
    }
}
```

### 关键观察
- `adaptive_wrap_lines` 将 `subsequent_indent` 作为非第一行的 `initial_indent`
- 这确保了换行后的新行也有正确的缩进

---

## 5. 依赖与外部交互

### RtOptions 配置
```rust
RtOptions::new(width as usize)
    .initial_indent(Line::from("  ↳ ".dim()))     // 4字符，带箭头，暗淡
    .subsequent_indent(Line::from("    "))         // 4空格，无样式
```

### 样式应用顺序
1. 文本内容：`line.dim()`（暗淡）
2. 第一行前缀：`"  ↳ ".dim()`（暗淡）
3. 后续行前缀：`"    "`（无样式）

### 与 Queued Message 的对比
```rust
// Pending steer - 无斜体
steer.lines().map(|line| Line::from(line.dim()))

// Queued message - 有斜体
message.lines().map(|line| Line::from(line.dim().italic()))
```

---

## 6. 风险边界与改进建议

### 当前限制
1. **缩进硬编码**: 4字符缩进在极窄宽度下可能不合适
2. **前缀符号固定**: 无法自定义或使用不同符号
3. **截断无提示**: 不显示被截断的行数

### 改进建议
1. **动态缩进**
   ```rust
   fn calculate_indent(width: u16) -> &'static str {
       match width {
           0..=20 => " ",    // 极窄：1空格
           21..=40 => "  ",  // 窄：2空格
           _ => "    ",      // 正常：4空格
       }
   }
   ```

2. **可配置前缀**
   - 允许通过配置更改箭头符号
   - 支持不同主题使用不同符号

3. **截断提示增强**
   - 显示 "… (+1 more line)" 提示被截断的行数
   - 帮助用户了解内容完整性

4. **展开功能**
   - 添加快捷键展开显示完整 steer
   - 或提供悬停提示显示完整内容

---

## 附录：完整快照内容

```
---
source: tui/src/bottom_pane/pending_input_preview.rs
expression: "format!(\"{buf:?}\")"
---
Buffer {
    area: Rect { x: 0, y: 0, width: 48, height: 6 },
    content: [
        "• Messages to be submitted after next tool call ",
        "  (press esc to interrupt and send immediately) ",
        "  ↳ First line                                  ",
        "    Second line                                 ",
        "    Third line                                  ",
        "    …                                           ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 2, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 47, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 14, y: 2, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 4, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 15, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 4, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 14, y: 4, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 5, y: 5, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
    ]
}
```
