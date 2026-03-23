# renderable.rs 研究文档

## 场景与职责

`renderable.rs` 是 Codex TUI 渲染系统的核心抽象层，提供：

1. **Renderable Trait**：统一的渲染接口，抽象各种可渲染对象
2. **布局容器**：列布局（`ColumnRenderable`）、行布局（`RowRenderable`）、弹性布局（`FlexRenderable`）、内边距容器（`InsetRenderable`）
3. **类型适配**：为标准类型（`&str`、`String`、`Line`、`Paragraph` 等）实现 `Renderable`
4. **RenderableItem**：统一拥有和借用渲染对象的枚举包装器

该模块实现了类似 Flutter/React 的声明式布局系统，使 UI 组件可以组合和嵌套。

## 功能点目的

### 1. Renderable Trait - 统一渲染接口

```rust
pub trait Renderable {
    fn render(&self, area: Rect, buf: &mut Buffer);
    fn desired_height(&self, width: u16) -> u16;
    fn cursor_pos(&self, _area: Rect) -> Option<(u16, u16)> {
        None
    }
}
```

- `render`：在给定区域内渲染到缓冲区
- `desired_height`：计算给定宽度下的理想高度（用于布局）
- `cursor_pos`：返回光标位置（用于可交互组件）

### 2. 布局容器

| 容器 | 布局方向 | 特点 |
|------|----------|------|
| `ColumnRenderable` | 垂直 | 顺序堆叠子元素，总高度为子元素高度之和 |
| `RowRenderable` | 水平 | 固定宽度子元素横向排列 |
| `FlexRenderable` | 垂直 | 支持 flex 因子分配剩余空间（类似 Flutter） |
| `InsetRenderable` | 包装 | 为子元素添加内边距 |

### 3. 类型适配

为以下类型实现 `Renderable`：
- `()`（空渲染）
- `&str`、`String`（单行文本）
- `Span<'_>`（带样式文本片段）
- `Line<'_>`（单行带样式文本）
- `Paragraph<'_>`（多行文本，自动换行）
- `Option<R>`（可选渲染）
- `Arc<R>`（共享所有权渲染）

## 具体技术实现

### RenderableItem - 统一包装器

```rust
pub enum RenderableItem<'a> {
    Owned(Box<dyn Renderable + 'a>),
    Borrowed(&'a dyn Renderable),
}

impl<'a> Renderable for RenderableItem<'a> {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        match self {
            RenderableItem::Owned(child) => child.render(area, buf),
            RenderableItem::Borrowed(child) => child.render(area, buf),
        }
    }
    // ...
}
```

**设计目的**：允许容器同时存储拥有和借用的渲染对象，避免不必要的克隆。

### ColumnRenderable - 垂直布局

```rustnpub struct ColumnRenderable<'a> {
    children: Vec<RenderableItem<'a>>,
}

impl Renderable for ColumnRenderable<'_> {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let mut y = area.y;
        for child in &self.children {
            let child_area = Rect::new(area.x, y, area.width, child.desired_height(area.width))
                .intersection(area);
            if !child_area.is_empty() {
                child.render(child_area, buf);
            }
            y += child_area.height;
        }
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.children.iter().map(|child| child.desired_height(width)).sum()
    }
}
```

**关键逻辑**：
- 使用 `intersection(area)` 确保子区域不超出父区域
- 累积 `y` 坐标实现垂直堆叠
- 高度为所有子元素高度之和

### FlexRenderable - 弹性布局

```rust
pub struct FlexChild<'a> {
    flex: i32,
    child: RenderableItem<'a>,
}

pub struct FlexRenderable<'a> {
    children: Vec<FlexChild<'a>>,
}
```

**布局算法**（参考 Flutter）：

```rust
fn allocate(&self, area: Rect) -> Vec<Rect> {
    // 1. 为非 flex 子元素分配空间
    for child in &self.children {
        if child.flex == 0 {
            child_sizes[i] = child.desired_height(area.width);
            allocated_size += child_sizes[i];
        }
    }
    
    // 2. 计算剩余空间
    let free_space = max_size.saturating_sub(allocated_size);
    
    // 3. 按 flex 因子分配剩余空间
    let space_per_flex = free_space / total_flex as u16;
    for child in flex_children {
        let max_child_extent = if is_last_flex_child {
            free_space - allocated_flex_space  // 最后一个获得全部剩余
        } else {
            space_per_flex * flex
        };
        child_sizes[i] = child.desired_height(area.width).min(max_child_extent);
    }
}
```

**特殊处理**：最后一个 flex 子元素获得所有剩余空间，避免舍入误差。

### RowRenderable - 水平布局

```rust
pub struct RowRenderable<'a> {
    children: Vec<(u16, RenderableItem<'a>)>,  // (width, child)
}
```

- 每个子元素有固定宽度
- 横向顺序排列
- 高度为子元素最大高度

### InsetRenderable - 内边距容器

```rust
pub struct InsetRenderable<'a> {
    child: RenderableItem<'a>,
    insets: Insets,
}

impl Renderable for InsetRenderable<'_> {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.child.render(area.inset(self.insets), buf);
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        self.child.desired_height(width - self.insets.left - self.insets.right)
            + self.insets.top
            + self.insets.bottom
    }
}
```

### RenderableExt - 扩展方法

```rust
pub trait RenderableExt<'a> {
    fn inset(self, insets: Insets) -> RenderableItem<'a>;
}

impl<'a, R> RenderableExt<'a> for R where R: Renderable + 'a {
    fn inset(self, insets: Insets) -> RenderableItem<'a> {
        let child = RenderableItem::Owned(Box::new(self) as Box<dyn Renderable + 'a>);
        RenderableItem::Owned(Box::new(InsetRenderable { child, insets }))
    }
}
```

**使用方式**：
```rust
some_widget.inset(Insets::vh(1, 2))  // 添加上下1、左右2的内边距
```

## 关键代码路径与文件引用

### 调用方分析

| 文件 | 使用内容 | 用途 |
|------|----------|------|
| `app.rs` | `Renderable` | 应用主循环渲染 |
| `pager_overlay.rs` | `InsetRenderable`, `Renderable` | 分页覆盖层 |
| `cwd_prompt.rs` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 当前目录提示 |
| `model_migration.rs` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 模型迁移对话框 |
| `onboarding/trust_directory.rs` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 信任目录向导 |
| `diff_render.rs` | `ColumnRenderable`, `InsetRenderable`, `Renderable` | Diff 渲染布局 |
| `history_cell.rs` | `Renderable` | 历史单元格 |
| `chatwidget.rs` | `ColumnRenderable`, `FlexRenderable`, `Renderable`, `RenderableExt`, `RenderableItem` | 聊天组件主布局 |
| `update_prompt.rs` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 更新提示 |
| `theme_picker.rs` | `Renderable` | 主题选择器 |
| `selection_list.rs` | `Renderable`, `RowRenderable` | 选择列表 |
| `bottom_pane/mod.rs` | `FlexRenderable`, `Renderable`, `RenderableItem` | 底部面板布局 |
| `bottom_pane/chat_composer.rs` | `Renderable` | 聊天输入框 |
| `bottom_pane/approval_overlay.rs` | `ColumnRenderable`, `Renderable` | 审批覆盖层 |
| `bottom_pane/app_link_view.rs` | `Renderable` (impl for AppLinkView) | 应用链接视图 |

### 依赖关系

```
renderable.rs
├── ratatui::buffer::Buffer
├── ratatui::layout::Rect
├── ratatui::text::Line
├── ratatui::text::Span
├── ratatui::widgets::Paragraph
├── ratatui::widgets::WidgetRef
├── std::sync::Arc
└── render/mod.rs (Insets, RectExt)
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | 提供 `Buffer`, `Rect`, `Line`, `Span`, `Paragraph`, `WidgetRef` |

### 内部依赖

- `render/mod.rs`：导入 `Insets` 和 `RectExt`

## 风险、边界与改进建议

### 已知风险

1. **递归深度**
   - 布局容器可以无限嵌套
   - 极端嵌套可能导致栈溢出
   - 当前无深度限制

2. **性能考虑**
   - `desired_height` 可能被多次调用（布局计算）
   - 复杂计算（如 `Paragraph::line_count`）可能重复执行
   - 无缓存机制

3. **Flex 布局限制**
   - 仅支持垂直方向 flex
   - 不支持水平 flex
   - 不支持 flex 子元素的最小/最大尺寸约束

### 边界情况

1. **空容器**
   - `ColumnRenderable` 空 children：高度为 0，不渲染任何内容
   - `FlexRenderable` 空 children：同上
   - `RowRenderable` 空 children：高度为 0

2. **溢出处理**
   - 所有容器使用 `intersection(area)` 裁剪子区域
   - 子元素超出父区域的部分被静默裁剪

3. **零宽度/高度**
   - `desired_height(0)` 应返回合理值（通常为 0 或最小高度）
   - 实际渲染时零区域会被跳过

4. **光标位置**
   - `cursor_pos` 默认返回 `None`
   - 容器实现返回第一个有光标的子元素位置
   - 假设最多一个子元素有光标

### 改进建议

1. **功能扩展**
   - 添加 `HorizontalFlexRenderable` 支持水平 flex
   - 添加 `StackRenderable` 支持重叠布局（z-index）
   - 支持子元素可见性控制（`visible: bool`）

2. **性能优化**
   - 添加 `CachedRenderable` 包装器缓存 `desired_height` 结果
   - 使用 `RefCell` 或类似机制避免重复计算

3. **调试支持**
   - 添加 `DebugRenderable` 包装器显示布局边界
   - 支持渲染区域可视化（调试用边框）

4. **API 改进**
   - `ColumnRenderable::push_ref` 当前标记为 `#[allow(dead_code)]`，可考虑移除或启用
   - 添加 `ColumnRenderable::extend` 批量添加子元素
   - 支持从迭代器构造（`FromIterator`）

5. **类型安全**
   - 考虑使用 `NonZeroU16` 表示宽度/高度
   - 添加编译时断言确保尺寸合理

6. **测试覆盖**
   - 当前无内联测试，建议添加：
     - 各容器的布局计算测试
     - 边界情况测试（空容器、溢出、零尺寸）
     - 光标位置传播测试

### 代码风格

该模块遵循项目风格：
- 使用 `pub struct` 公开容器类型
- 使用 `pub trait` 定义扩展接口
- 泛型约束清晰（`R: Renderable + 'a`）
- 生命周期标注完整
