# renderable.rs 研究文档

## 场景与职责

`renderable.rs` 是 TUI 应用服务器的可渲染组件系统，提供：

1. **Renderable trait** - 统一的可渲染对象接口，抽象各种 UI 组件的渲染能力
2. **布局容器** - 实现 Flex、Column、Row、Inset 等布局模式
3. **类型适配** - 为 `&str`、`String`、`Line`、`Paragraph`、`Option`、`Arc` 等标准类型实现 Renderable

该模块是 TUI 组件系统的核心，所有 UI 元素都通过 `Renderable` trait 进行统一渲染，支持灵活的布局组合。

## 功能点目的

### 1. Renderable trait - 统一渲染接口
```rust
pub trait Renderable {
    fn render(&self, area: Rect, buf: &mut Buffer);
    fn desired_height(&self, width: u16) -> u16;
    fn cursor_pos(&self, _area: Rect) -> Option<(u16, u16)> { None }
}
```

核心方法：
- `render`: 在给定区域内渲染到缓冲区
- `desired_height`: 计算给定宽度下的期望高度（用于布局）
- `cursor_pos`: 返回光标位置（用于交互组件）

### 2. RenderableItem - 类型擦除包装器
```rust
pub enum RenderableItem<'a> {
    Owned(Box<dyn Renderable + 'a>),
    Borrowed(&'a dyn Renderable),
}
```

用途：
- 允许在集合中混合存储拥有和借用的渲染对象
- 实现类型擦除，支持异构集合
- 用于 `ColumnRenderable`、`FlexRenderable` 等容器的子元素存储

### 3. 布局容器

#### ColumnRenderable - 垂直堆叠布局
- 按顺序垂直堆叠子元素
- 每个子元素获得完整宽度
- 高度为所有子元素高度之和
- 支持光标位置传递

#### FlexRenderable - 弹性布局
- 类似 Flutter 的 Flex 布局
- 支持 flex 因子分配剩余空间
- 非 flex 子元素获得其自然高度
- 最后一个 flex 子元素获得所有剩余空间（避免舍入误差）

#### RowRenderable - 水平行布局
- 按顺序水平排列子元素
- 每个子元素有固定宽度
- 高度为所有子元素中的最大高度
- 支持光标位置传递

#### InsetRenderable - 内边距包装器
- 为子元素添加内边距
- 使用 `Insets` 和 `RectExt::inset` 计算实际渲染区域
- 调整期望高度以包含边距

### 4. 标准类型实现
为以下类型实现 Renderable：
- `()`: 空渲染，高度为 0
- `&str` / `String`: 单行文本，高度为 1
- `Span`: 单行样式文本，高度为 1
- `Line`: 单行文本，高度为 1
- `Paragraph`: 多行文本，高度为行数
- `Option<R>`: 有值时渲染，无值时空渲染
- `Arc<R>`: 通过引用渲染

## 具体技术实现

### 关键数据结构

```rust
// 可渲染 trait
pub trait Renderable {
    fn render(&self, area: Rect, buf: &mut Buffer);
    fn desired_height(&self, width: u16) -> u16;
    fn cursor_pos(&self, _area: Rect) -> Option<(u16, u16)> { None }
}

// 类型擦除包装器
pub enum RenderableItem<'a> {
    Owned(Box<dyn Renderable + 'a>),
    Borrowed(&'a dyn Renderable),
}

// 垂直堆叠容器
pub struct ColumnRenderable<'a> {
    children: Vec<RenderableItem<'a>>,
}

// 弹性布局容器
pub struct FlexChild<'a> {
    flex: i32,
    child: RenderableItem<'a>,
}
pub struct FlexRenderable<'a> {
    children: Vec<FlexChild<'a>>,
}

// 水平行容器
pub struct RowRenderable<'a> {
    children: Vec<(u16, RenderableItem<'a>)>,  // (width, child)
}

// 内边距包装器
pub struct InsetRenderable<'a> {
    child: RenderableItem<'a>,
    insets: Insets,
}
```

### 核心算法

#### Flex 布局分配算法
```rust
fn allocate(&self, area: Rect) -> Vec<Rect> {
    // 1. 为非 flex 子元素分配空间
    for child in &self.children {
        if child.flex > 0 {
            total_flex += flex;
        } else {
            child_sizes[i] = child.desired_height(area.width)
                .min(max_size - allocated_size);
            allocated_size += child_sizes[i];
        }
    }
    
    // 2. 为 flex 子元素按比例分配剩余空间
    let free_space = max_size - allocated_size;
    for child in &self.children {
        if child.flex > 0 {
            // 最后一个 flex 子元素获得所有剩余空间
            let max_child_extent = if i == last_flex_child_idx {
                free_space - allocated_flex_space
            } else {
                space_per_flex * flex
            };
            child_sizes[i] = child.desired_height(area.width).min(max_child_extent);
        }
    }
    
    // 3. 构建矩形区域
    // ...
}
```

**算法特点**：
- 参考 Flutter 的 Flex 渲染实现
- 两轮分配：先非 flex，后 flex
- 特殊处理最后一个 flex 子元素以避免舍入误差

#### Column 光标位置计算
```rust
fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> {
    let mut y = area.y;
    for child in &self.children {
        let child_area = Rect::new(area.x, y, area.width, child.desired_height(area.width));
        if let Some((px, py)) = child.cursor_pos(child_area) {
            return Some((px, py));  // 返回第一个有光标的子元素位置
        }
        y += child_area.height;
    }
    None
}
```

### 类型转换实现

```rust
// 从具体类型到 Box<dyn Renderable>
impl<'a, R> From<R> for Box<dyn Renderable + 'a>
where
    R: Renderable + 'a,
{
    fn from(value: R) -> Self {
        Box::new(value)
    }
}

// RenderableExt 提供便捷的 inset 方法
pub trait RenderableExt<'a> {
    fn inset(self, insets: Insets) -> RenderableItem<'a>;
}

impl<'a, R> RenderableExt<'a> for R
where
    R: Renderable + 'a,
{
    fn inset(self, insets: Insets) -> RenderableItem<'a> {
        let child = RenderableItem::Owned(Box::new(self));
        RenderableItem::Owned(Box::new(InsetRenderable { child, insets }))
    }
}
```

## 关键代码路径与文件引用

### 内部依赖
| 文件 | 依赖内容 | 说明 |
|------|---------|------|
| `render/mod.rs` | `Insets`, `RectExt` | 内边距类型和矩形扩展 |

### 外部调用方（广泛分布）

| 文件 | 使用类型 | 用途 |
|------|---------|------|
| `app.rs:43` | `Renderable` | 应用主逻辑 |
| `chatwidget.rs:311-315` | `ColumnRenderable`, `FlexRenderable`, `Renderable`, `RenderableExt`, `RenderableItem` | 聊天组件布局 |
| `pager_overlay.rs:27-28` | `InsetRenderable`, `Renderable` | 分页覆盖层 |
| `cwd_prompt.rs:5-7` | `ColumnRenderable`, `Renderable`, `RenderableExt` | CWD 提示 |
| `model_migration.rs:4-6` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 模型迁移提示 |
| `onboarding/trust_directory.rs:21-23` | `ColumnRenderable`, `Renderable`, `RenderableExt` | 信任目录引导 |
| `theme_picker.rs:37` | `Renderable` | 主题选择器 |
| `selection_list.rs:1-2` | `Renderable`, `RowRenderable` | 选择列表 |
| `status_indicator_widget.rs:25` | `Renderable` | 状态指示器 |
| `diff_render.rs:86-88` | `ColumnRenderable`, `InsetRenderable`, `Renderable` | Diff 渲染 |
| `history_cell.rs:27` | `Renderable` | 历史消息单元格 |
| `bottom_pane/mod.rs:25-27` | `FlexRenderable`, `Renderable`, `RenderableItem` | 底部面板主布局 |
| `bottom_pane/skills_toggle_view.rs:20-21` | `ColumnRenderable`, `Renderable` | 技能切换视图 |
| `bottom_pane/feedback_view.rs:23` | `Renderable` | 反馈视图 |
| `bottom_pane/approval_overlay.rs:17-18` | `ColumnRenderable`, `Renderable` | 审批覆盖层 |
| `bottom_pane/multi_select_picker.rs:53-54` | `ColumnRenderable`, `Renderable` | 多选选择器 |
| `bottom_pane/chat_composer.rs:193` | `Renderable` | 聊天输入框 |
| `bottom_pane/experimental_features_view.rs:18-19` | `ColumnRenderable`, `Renderable` | 实验性功能视图 |
| `bottom_pane/app_link_view.rs:479` | `Renderable` (impl) | 应用链接视图实现 |
| `public_widgets/composer_input.rs:16` | `Renderable` | 组合输入框 |

## 依赖与外部交互

### 外部 crate 依赖
```rust
use ratatui::buffer::Buffer;           // 终端缓冲区
use ratatui::layout::Rect;             // 矩形区域
use ratatui::text::{Line, Span};       // 文本类型
use ratatui::widgets::{Paragraph, WidgetRef};  // 组件 trait
use std::sync::Arc;                    // 原子引用计数
```

### 架构关系
```
Renderable (trait)
    ├── 基础类型实现: (), &str, String, Span, Line, Paragraph
    ├── 包装类型实现: Option<R>, Arc<R>
    ├── RenderableItem (类型擦除枚举)
    │       ├── Owned (Box<dyn Renderable>)
    │       └── Borrowed (&dyn Renderable)
    ├── ColumnRenderable (垂直堆叠)
    ├── FlexRenderable (弹性布局)
    ├── RowRenderable (水平行)
    └── InsetRenderable (内边距)
            └── 使用 Insets + RectExt::inset
```

## 风险、边界与改进建议

### 已知风险

1. **Flex 布局舍入误差**
   - 当前算法通过将剩余空间全部分配给最后一个 flex 子元素来避免舍入误差
   - 极端情况下（大量 flex 子元素、小空间）可能导致分布不均

2. **RowRenderable 截断**
   - 如果子元素宽度总和超过可用宽度，后续子元素会被截断（`break`）
   - 没有滚动或换行机制

3. **递归渲染深度**
   - 嵌套的容器（Column 包含 Flex 包含 Inset...）可能导致深层递归
   - 当前无最大深度限制

4. **光标位置假设**
   - `cursor_pos` 假设最多一个子元素有光标
   - 多个子元素有光标时，只返回第一个

### 边界条件

1. **空容器**
   ```rust
   let col = ColumnRenderable::new();
   assert_eq!(col.desired_height(80), 0);  // 空容器高度为 0
   ```

2. **零宽度区域**
   ```rust
   // 所有容器在 area.is_empty() 时都应安全处理
   // 实际渲染前通常有检查: if !child_area.is_empty() { render(...) }
   ```

3. **Flex 零因子**
   ```rust
   // flex = 0 的子元素被视为非 flex，获得自然高度
   // flex < 0 的行为未定义（当前代码未处理）
   ```

4. **Row 宽度不足**
   ```rust
   // 当剩余宽度为 0 时，后续子元素不会被渲染
   // 不会 panic，但内容被截断
   ```

### 改进建议

1. **Flex 布局增强**
   ```rust
   // 支持 flex 方向（目前只有 Column）
   pub enum FlexDirection { Row, Column }
   
   // 支持主轴和交叉轴对齐
   pub enum MainAxisAlignment { Start, End, Center, SpaceBetween, SpaceAround }
   pub enum CrossAxisAlignment { Start, End, Center, Stretch }
   ```

2. **Row 布局增强**
   ```rust
   // 支持溢出处理策略
   pub enum Overflow { Clip, Scroll, Wrap }
   
   // 支持可变宽度子元素
   pub enum RowChildWidth { Fixed(u16), Flex(i32), Auto }
   ```

3. **性能优化**
   ```rust
   // 缓存 desired_height 结果
   pub struct ColumnRenderable<'a> {
       children: Vec<RenderableItem<'a>>,
       cached_heights: RefCell<Option<Vec<u16>>>,  // 宽度 -> 高度缓存
   }
   ```

4. **调试支持**
   ```rust
   // 添加调试边框渲染
   pub struct DebugRenderable<'a> {
       child: RenderableItem<'a>,
       label: String,
   }
   impl Renderable for DebugRenderable<'_> {
       fn render(&self, area: Rect, buf: &mut Buffer) {
           // 绘制边框和标签
           self.child.render(area.inset(Insets::ONE), buf);
       }
   }
   ```

5. **动画支持**
   ```rust
   // 支持过渡动画
   pub trait AnimatedRenderable: Renderable {
       fn animate(&mut self, delta: Duration);
       fn is_animating(&self) -> bool;
   }
   ```

### 测试建议

当前模块缺少单元测试，建议添加：
- 各容器的空子元素测试
- Flex 布局的舍入误差测试
- 嵌套容器的深度测试
- 光标位置传递测试
- 边界条件测试（零宽度、零高度、超大 Insets）
