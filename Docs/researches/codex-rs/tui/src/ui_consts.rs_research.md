# ui_consts.rs 研究文档

## 场景与职责

`ui_consts.rs` 是 Codex TUI 的共享 UI 常量定义模块，集中管理布局和对齐相关的常量，确保整个 TUI 中视觉元素的一致性。

主要使用场景：
- 定义活细胞（live cells）和状态指示器的左槽宽度
- 统一聊天编辑器（chat composer）的边框和内边距
- 用户历史行的文本换行对齐

## 功能点目的

### 1. 左槽宽度常量

**常量定义**：
```rust
pub(crate) const LIVE_PREFIX_COLS: u16 = 2;
pub(crate) const FOOTER_INDENT_COLS: usize = LIVE_PREFIX_COLS as usize;
```

**语义说明**：
- `LIVE_PREFIX_COLS`：为活细胞和状态指示器预留的左槽宽度（2 列）
- `FOOTER_INDENT_COLS`：页脚缩进列数，与左槽宽度一致

**使用场景**：
1. **聊天编辑器**：预留 2 列用于左边框和内边距
2. **状态指示器行**：以 2 个空格开头，保持与活细胞对齐
3. **用户历史行**：换行时考虑 2 列前缀（如 "▌ "）

## 具体技术实现

### 常量设计原理

选择 2 列作为标准宽度，平衡了以下需求：
- **足够显示前缀符号**：如 "▌ "（1 列符号 + 1 列空格）
- **不占用过多水平空间**：保持主要内容区域宽敞
- **视觉一致性**：所有左侧装饰元素对齐

### 使用示例

**聊天编辑器**（`bottom_pane/chat_composer.rs`）：
```rust
// 可用宽度 = 总宽度 - 左槽宽度
let available_width = area.width.saturating_sub(LIVE_PREFIX_COLS);
```

**用户历史行**（`history_cell.rs`）：
```rust
// 换行宽度 = 总宽度 - 左槽宽度 - 右边距
let wrap_width = width
    .saturating_sub(LIVE_PREFIX_COLS + 1)
    .max(1);
```

**状态指示器**（`status_indicator_widget.rs`）：
```rust
// 以空格开头对齐
let prefix = "  "; // 2 个空格
```

## 关键代码路径与文件引用

### 引用文件

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `bottom_pane/chat_composer.rs` | `crate::ui_consts::LIVE_PREFIX_COLS` | 编辑器宽度计算 |
| `history_cell.rs` | `crate::ui_consts::LIVE_PREFIX_COLS` | 用户消息换行 |
| `status_indicator_widget.rs` | `crate::ui_consts::FOOTER_INDENT_COLS` | 状态行缩进 |

### 依赖关系

```
ui_consts.rs
├── bottom_pane/chat_composer.rs  (使用 LIVE_PREFIX_COLS)
├── history_cell.rs               (使用 LIVE_PREFIX_COLS)
└── status_indicator_widget.rs    (使用 FOOTER_INDENT_COLS)
```

## 依赖与外部交互

### 无外部依赖

`ui_consts.rs` 是纯常量定义模块，不依赖任何外部 crate 或内部模块。

### 被依赖关系

被以下模块直接引用：
- `crate::bottom_pane`
- `crate::history_cell`
- `crate::status_indicator_widget`

## 风险、边界与改进建议

### 已知风险

1. **硬编码常量**
   - 2 列宽度是经验值，可能不适合所有终端尺寸或用户偏好
   - 缓解：当前设计简单，修改影响范围可控

2. **类型不一致**
   - `LIVE_PREFIX_COLS` 是 `u16`，`FOOTER_INDENT_COLS` 是 `usize`
   - 需要频繁类型转换，可能引入错误

### 边界条件

1. **极小终端宽度**
   - 当终端宽度小于 2 列时，使用这些常量的代码需要处理溢出
   - 缓解：调用方通常使用 `saturating_sub` 避免溢出

### 改进建议

1. **配置化宽度**
   - 考虑从配置文件读取左槽宽度，适应不同用户偏好

2. **统一类型**
   - 考虑统一使用 `u16` 或 `usize`，减少类型转换

3. **文档化使用模式**
   - 添加更多使用示例，帮助新开发者理解常量的预期用法

4. **扩展常量集**
   - 如果未来需要更多布局常量（如右槽宽度、垂直间距），可在此模块集中定义
