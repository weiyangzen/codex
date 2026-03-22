# scrollable_diff.rs 研究文档

## 场景与职责

`scrollable_diff.rs` 实现了 Codex Cloud Tasks TUI 中的**可滚动差异查看器**。它是一个轻量级的本地滚动视图组件，用于：

- 显示代码 diff（统一差异格式）
- 显示对话/消息文本
- 支持自动换行和滚动导航
- 提供百分比滚动位置指示

该组件是 `DiffOverlay` 的核心依赖，在任务详情弹窗中展示 diff 内容或对话记录。

## 功能点目的

### 1. ScrollViewState - 滚动状态管理

```rust
#[derive(Clone, Copy, Debug, Default)]
pub struct ScrollViewState {
    pub scroll: u16,        // 当前滚动行偏移
    pub viewport_h: u16,    // 视口高度
    pub content_h: u16,     // 内容总高度（换行后）
}
```

**核心功能**：
- `clamp()`: 自动限制滚动范围，防止越界
- 当视口缩小或内容变化时自动调整 `scroll`

### 2. ScrollableDiff - 可滚动内容视图

```rust
#[derive(Clone, Debug, Default)]
pub struct ScrollableDiff {
    raw: Vec<String>,           // 原始行（未换行）
    wrapped: Vec<String>,       // 换行后的显示行
    wrapped_src_idx: Vec<usize>, // 每行对应的原始行索引
    wrap_cols: Option<u16>,     // 当前换行宽度
    pub state: ScrollViewState, // 滚动状态
}
```

**设计特点**：
- **延迟换行**: `set_content()` 不立即换行，等待 `set_width()` 时统一处理
- **缓存机制**: 宽度不变时复用已换行内容
- **原始行映射**: 维护 `wrapped_src_idx` 用于样式渲染时查找原始行信息

### 3. 智能换行算法

**文件**: `scrollable_diff.rs:114-175`

实现特点：
- **Tab 处理**: 将 `\t` 替换为 4 个空格
- **软换行点**: 在空格、标点符号处优先断行
  - 支持: `, ; . : ) ] } | / ? ! - _`
- **字符宽度**: 使用 `unicode_width` 正确处理宽字符（如 CJK）
- **回退策略**: 宽度为 0 时不换行，直接复制原始内容

## 具体技术实现

### 关键流程

#### 初始化与内容设置
```rust
let mut sd = ScrollableDiff::new();
sd.set_content(diff_lines);  // 仅存储原始行，标记需要换行
sd.set_width(80);            // 触发换行计算
sd.set_viewport(24);         // 设置视口高度，触发 clamp
```

#### 渲染循环
```rust
// 获取当前可见区域的换行后内容
let visible: Vec<Line> = sd.wrapped_lines()
    .iter()
    .skip(sd.state.scroll as usize)
    .take(sd.state.viewport_h as usize)
    .map(|l| style_diff_line(l))  // 应用 diff 样式
    .collect();
```

#### 用户滚动操作
```rust
sd.scroll_by(1);     // 按行滚动
sd.page_by(10);      // 按页滚动（通常 viewport_h - 1）
sd.to_top();         // 跳到顶部
sd.to_bottom();      // 跳到底部
```

### 数据结构关系

```
DiffOverlay (app.rs)
└── sd: ScrollableDiff
    ├── raw: Vec<String>              // 原始 diff 行
    ├── wrapped: Vec<String>          // 换行后行
    ├── wrapped_src_idx: Vec<usize>   // 映射: wrapped[i] -> raw[idx]
    ├── wrap_cols: Option<u16>        // 当前宽度缓存
    └── state: ScrollViewState
        ├── scroll: u16
        ├── viewport_h: u16
        └── content_h: u16 (wrapped.len())
```

### 换行算法详解

```rust
fn rewrap(&mut self, width: u16) {
    for (raw_idx, raw) in self.raw.iter().enumerate() {
        let raw = raw.replace('\t', "    ");  // 1. Tab 转空格
        
        // 逐字符处理
        for ch in raw.char_indices() {
            // 2. 检查是否需要换行
            if line_cols + char_width > max_cols {
                // 3. 优先在软换行点分割
                if let Some(split) = last_soft_idx {
                    // 在标点/空格处分割
                } else {
                    // 强制硬分割
                }
            }
            
            // 4. 更新软换行点
            if ch.is_whitespace() || is_punctuation(ch) {
                last_soft_idx = Some(line.len());
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 创建与初始化

**文件**: `app.rs:174-192`
```rust
impl DiffOverlay {
    pub fn new(task_id: TaskId, title: String, attempt_total_hint: Option<usize>) -> Self {
        let mut sd = ScrollableDiff::new();
        sd.set_content(Vec::new());  // 初始为空
        // ...
    }
}
```

### 设置内容

**文件**: `app.rs:253-288`
```rust
pub fn apply_selection_to_fields(&mut self) {
    match self.current_view {
        DetailView::Diff => {
            self.sd.set_content(diff_lines);
        }
        DetailView::Prompt => {
            self.sd.set_content(text_lines);
        }
    }
}
```

### 渲染时更新尺寸

**文件**: `ui.rs:417-424`
```rust
// 在 draw_diff_overlay 中
ov.sd.set_width(rows[1].width);
ov.sd.set_viewport(rows[1].height);
```

### 样式渲染

**文件**: `ui.rs:434-445`
```rust
let styled_lines: Vec<Line<'static>> = if is_diff_view {
    raw.unwrap_or(&[])
        .iter()
        .map(|l| style_diff_line(l))
        .collect()
} else {
    style_conversation_lines(&o.sd, o.current_attempt())
};
```

### 滚动事件处理

**文件**: `lib.rs:1686-1708`
```rust
KeyCode::Down | KeyCode::Char('j') => {
    if let Some(ov) = &mut app.diff_overlay { 
        ov.sd.scroll_by(1); 
    }
    needs_redraw = true;
}
KeyCode::PageDown | KeyCode::Char(' ') => {
    if let Some(ov) = &mut app.diff_overlay { 
        let step = ov.sd.state.viewport_h.saturating_sub(1) as i16; 
        ov.sd.page_by(step); 
    }
    needs_redraw = true;
}
```

## 依赖与外部交互

### 上游依赖（被调用）

1. **unicode_width crate**
   - `UnicodeWidthChar::width()`: 计算字符显示宽度
   - `UnicodeWidthStr::width()`: 计算字符串显示宽度

2. **ratatui crate**（通过 ui.rs 间接使用）
   - 渲染 `Line` 和 `Text` 组件
   - 处理终端尺寸变化

### 下游调用（调用方）

| 调用方 | 用途 |
|--------|------|
| `app.rs::DiffOverlay` | 存储和管理 diff/对话内容 |
| `ui.rs::draw_diff_overlay` | 渲染 diff 弹窗内容 |
| `ui.rs::style_conversation_lines` | 基于原始行索引应用对话样式 |
| `lib.rs` 事件处理 | 响应键盘滚动操作 |

## 风险、边界与改进建议

### 当前风险

1. **内存占用**
   - 同时存储 `raw` 和 `wrapped` 两份数据
   - 大 diff（如数千行）可能占用较多内存
   - **缓解**: 当前使用场景是单文件 diff，通常不会太大

2. **换行性能**
   - 每次宽度变化都重新计算所有行的换行
   - O(n*m) 复杂度，n=行数, m=平均行长
   - **缓解**: 宽度变化不频繁，且 diff 通常不会极大

3. **Tab 宽度硬编码**
   ```rust
   let raw = raw.replace('\t', "    ");  // 固定4空格
   ```
   - 不支持配置 Tab 宽度

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 宽度为 0 | 直接复制原始行，不换行 |
| 空内容 | `wrapped` 为空，显示占位符 `<no diff available>` |
| 超长无空格行 | 在字符边界强制分割 |
| 快速连续滚动 | 通过 `clamp()` 防止越界，安全 |
| 终端快速resize | 可能短暂显示错位，下一帧修正 |

### 改进建议

1. **虚拟滚动优化**
   ```rust
   // 当前: 存储所有换行后内容
   // 优化: 只计算可见区域的换行
   pub fn visible_lines(&self, offset: u16, count: u16) -> &[String] {
       // 按需计算，减少内存和计算
   }
   ```

2. **配置 Tab 宽度**
   ```rust
   pub struct ScrollableDiff {
       tab_width: usize,  // 可配置，默认4
   }
   ```

3. **增量换行缓存**
   - 缓存每行在特定宽度下的换行结果
   - 宽度变化时复用未受影响的行

4. **搜索/高亮支持**
   ```rust
   pub fn set_search_pattern(&mut self, pattern: &str) -> Vec<usize> {
       // 返回匹配的行索引，支持在原始行和换行后行中搜索
   }
   ```

5. **平滑滚动**
   - 当前按行滚动，可考虑支持平滑滚动动画
   - 使用 `scroll` 浮点值插值

6. **行号显示**
   - 在 diff 视图中显示原始行号
   - 需要维护 `wrapped_src_idx` 到原始行号的映射
