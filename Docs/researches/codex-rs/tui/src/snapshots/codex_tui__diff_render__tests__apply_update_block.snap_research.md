# Diff Render - 文件更新块渲染测试

## 场景与职责

该快照测试验证 TUI 中**文件更新操作**的 diff 渲染效果。当 Codex 修改现有文件内容时，需要以统一 diff 格式展示变更，清晰标识删除的行、新增的行和未变更的上下文行，帮助用户精确理解每一处修改。

这是 Codex TUI 最复杂的 diff 渲染场景，涉及统一 diff 解析、语法高亮、行号对齐等多个技术点。

## 功能点目的

1. **统一 Diff 展示**：使用标准统一 diff 格式展示文件变更
2. **三列布局**：
   - 行号列：右对齐显示行号
   - 标记列：`-` 删除、`+` 新增、` ` 上下文
   - 内容列：实际代码内容
3. **语法高亮**：根据文件扩展名对代码进行语法高亮
4. **上下文保留**：显示变更周围的未修改行，提供代码语境
5. **变更统计**：汇总显示新增和删除的行数

## 具体技术实现

### 核心数据结构

```rust
pub enum FileChange {
    Update {
        unified_diff: String,       // 统一 diff 格式字符串
        move_path: Option<PathBuf>, // 可选的重命名目标
    },
    // ... Add, Delete
}

// diffy 库解析后的结构
pub struct Patch<'a> {
    hunks: Vec<Hunk<'a>>,
}

pub struct Hunk<'a> {
    old_range: Range,
    new_range: Range,
    lines: Vec<Line<'a>>,
}

pub enum Line<'a> {
    Insert(&'a str),   // 新增行
    Delete(&'a str),   // 删除行
    Context(&'a str),  // 上下文行
}
```

### 渲染流程

1. **Diff 解析**：
   ```rust
   if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
       // 解析成功，继续渲染
   }
   ```

2. **预处理扫描**：
   - 计算最大行号（确定行号列宽）
   - 统计总字节数和行数（用于决定是否跳过语法高亮）

3. **Hunk 遍历**：
   ```rust
   for h in patch.hunks() {
       // 非首个 hunk 前添加分隔符 "⋮"
       // 对整个 hunk 进行语法高亮（保持解析器状态）
       // 逐行渲染
   }
   ```

4. **单行渲染**（`push_wrapped_diff_line_inner_with_theme_and_color_level`）：
   - 格式化行号（右对齐）
   - 添加标记符（`-`/`+`/` `）
   - 应用语法高亮样式
   - 处理长行自动换行

### 语法高亮策略

```rust
// 对整个 hunk 进行高亮，保持解析器状态
let hunk_text: String = h.lines().iter().map(|line| /* ... */).collect();
let syntax_lines = highlight_code_to_styled_spans(&hunk_text, language)?;

// 逐行应用高亮结果
for (line_idx, l) in h.lines().iter().enumerate() {
    let syntax_spans = syntax_lines.get(line_idx);
    // 渲染...
}
```

### 样式系统

| 行类型 | 深色主题 | 浅色主题 | 标记 |
|--------|----------|----------|------|
| Insert | `#213A2B` 绿背景 | `#dafbe1` 浅绿背景 | `+` |
| Delete | `#4A221D` 红背景 | `#ffebe9` 浅红背景 | `-` |
| Context | 默认背景 | 默认背景 | ` ` |

### 关键代码路径

```rust
// diff_render.rs:547-736
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        // 1. 预处理：计算最大行号、统计大小
        let mut max_line_number = 0;
        let mut total_diff_bytes: usize = 0;
        let mut total_diff_lines: usize = 0;
        
        // 2. 决定是否跳过语法高亮
        let diff_lang = if exceeds_highlight_limits(total_diff_bytes, total_diff_lines) {
            None
        } else {
            lang
        };
        
        // 3. 逐 hunk 渲染
        for h in patch.hunks() {
            // Hunk 间分隔符
            if !is_first_hunk {
                out.push(RtLine::from(vec![spacer_span, "⋮".dim()]));
            }
            
            // 对整个 hunk 语法高亮
            let hunk_syntax_lines = diff_lang.and_then(|language| { /* ... */ });
            
            // 逐行渲染
            for (line_idx, l) in h.lines().iter().enumerate() {
                match l {
                    diffy::Line::Insert(text) => { /* 渲染新增行 */ },
                    diffy::Line::Delete(text) => { /* 渲染删除行 */ },
                    diffy::Line::Context(text) => { /* 渲染上下文行 */ },
                }
            }
        }
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| Diff 渲染主模块 | `codex-rs/tui/src/diff_render.rs` | 完整的 diff 渲染实现 |
| Update 渲染 | `diff_render.rs:547-736` | Update 类型变更渲染逻辑 |
| 单行渲染 | `diff_render.rs:837-938` | `push_wrapped_diff_line_inner_with_theme_and_color_level` |
| 语法高亮 | `codex-rs/tui/src/render/highlight.rs` | 代码语法高亮实现 |
| 高亮限制 | `render/highlight.rs` | `exceeds_highlight_limits` 函数 |
| 测试用例 | `diff_render.rs:1508-1526` | `ui_snapshot_apply_update_block` |

### 相关函数

- `render_change()` - 主渲染入口
- `calculate_add_remove_from_diff()` - 统计计算
- `highlight_code_to_styled_spans()` - 语法高亮
- `exceeds_highlight_limits()` - 高亮限制检查
- `wrap_styled_spans()` - 长行自动换行

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式解析（`Patch::from_str`, `create_patch`）
2. **ratatui**：终端 UI 渲染框架
3. **syntect**：语法高亮引擎（通过 `highlight_code_to_styled_spans`）
4. **unicode-width**：Unicode 字符宽度计算

### 内部依赖

- `crate::render::highlight::*` - 语法高亮模块
- `crate::terminal_palette::*` - 终端调色板

### 性能优化

```rust
// 当 diff 过大时跳过语法高亮，避免性能问题
const MAX_HIGHLIGHT_BYTES: usize = 500_000;
const MAX_HIGHLIGHT_LINES: usize = 10_000;

fn exceeds_highlight_limits(bytes: usize, lines: usize) -> bool {
    bytes > MAX_HIGHLIGHT_BYTES || lines > MAX_HIGHLIGHT_LINES
}
```

## 风险、边界与改进建议

### 潜在风险

1. **大文件 diff 性能**：超大 diff 可能导致渲染卡顿
2. **语法高亮准确性**：跨 hunk 的语法状态丢失可能导致高亮错误
3. **内存占用**：大 diff 的语法高亮结果可能占用大量内存

### 边界情况

1. **空 diff**：无实际变更的 diff 渲染
2. **纯新增/删除 hunk**：无上下文行的 hunk
3. **多 hunk 文件**：hunk 间分隔符的正确显示
4. **行号对齐**：行号位数变化时的对齐（1位→2位→3位）
5. **长行换行**：超长代码行的自动换行处理

### 改进建议

1. **性能优化**：
   - 实现虚拟滚动，只渲染可见行
   - 语法高亮异步化，不阻塞主线程
   - diff 内容流式解析

2. **功能增强**：
   - 字符级 diff：在行内高亮具体变更的字符
   - 忽略空白：支持忽略空白字符的 diff 选项
   - 单词级 diff：更细粒度的变更展示

3. **交互改进**：
   - 支持在 diff 中直接编辑
   - 行级操作：接受/拒绝单行变更
   - 代码折叠：折叠未变更的上下文行

4. **可访问性**：
   - 色盲友好模式：不依赖颜色区分增删
   - 屏幕阅读器支持：提供纯文本 fallback

5. **配置选项**：
   - 自定义上下文行数
   - 语法高亮开关
   - 颜色主题自定义

### 测试覆盖

当前测试用例验证了：
- 基本更新渲染（1行删除 + 1行新增）
- 上下文行保留（3行上下文）
- 行号正确性（1, 2, 2, 3）
- 统计信息准确性（+1 -1）

建议补充：
- 多 hunk 文件测试
- 大文件性能测试
- 语法高亮准确性测试
- 各种编程语言的渲染测试
