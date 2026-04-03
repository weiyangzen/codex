# Status Hidden When Height Too Small Height 1 Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the bottom pane rendering when terminal height is extremely limited (height=1), validating graceful degradation of the UI.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Graceful degradation at minimal terminal heights
- Composer remains accessible even with extreme constraints
- Status indicator is hidden when space is insufficient
- Core functionality (input) is preserved

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that the bottom pane renders sensibly when given only 1 row of height, prioritizing the composer input.

### 验证要点
1. Composer input prompt ("›") is visible
2. Placeholder text is partially shown
3. No status indicator visible (insufficient space)
4. No crashes or errors at minimal height
5. UI remains functional for basic input

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    composer: ChatComposer,
    status: Option<StatusIndicatorWidget>,
    // ... other fields
}

impl Renderable for BottomPane {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.as_renderable().render(area, buf);
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        self.as_renderable().desired_height(width)
    }
}
```

### 渲染逻辑
- `as_renderable()` builds a `FlexRenderable` with all components
- Components are rendered in order within the allocated area
- When area is smaller than desired height, lower-priority components are truncated
- Composer typically has flex weight and renders last, but at height=1 only minimal content fits
- Status widget, spacers, and other elements are simply not rendered

### 关键算法
1. **Height Distribution**: Fixed-height elements get space first, then flex items
2. **Truncation**: Elements that don't fit are skipped
3. **Priority**: Composer input is highest priority for minimal height

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `render()` | Renders with constrained area |
| `desired_height()` | Reports minimum required height |
| `as_renderable()` | Builds renderable structure |
| `FlexRenderable::render()` | Distributes limited space to children |

### 测试代码位置
- Test file snapshot shows minimal rendering at height=1
- Source test likely validates graceful handling of extreme constraints
- Shows "› Ask Codex to do a" (truncated placeholder)

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |

### 内部模块依赖
- `FlexRenderable` - Flexible layout with space distribution
- `ChatComposer` - Input composer (highest priority)
- `Renderable` trait - Common rendering interface

### 协议依赖
- None directly

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Critical information loss**: Status may be hidden when user needs it
2. **User confusion**: Users may not understand why UI changed
3. **Input issues**: Very narrow width may break input handling

### 边界情况
- Height of 0 (should not crash)
- Width of 1 (minimal horizontal space)
- Both height and width extremely small
- Rapid resize between small and large

### 改进建议
1. **Minimum size warning**: Show warning when terminal is too small
2. **Alternative layouts**: Special compact layout for extreme constraints
3. **Priority configuration**: Allow users to prioritize which elements hide first
4. **Status persistence**: Show critical status even at small sizes
5. **Resize hints**: Suggest minimum terminal size on startup

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
