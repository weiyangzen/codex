# Research: Diff Gallery 94x35 Terminal Rendering Test

## Snapshot File
`codex_tui__diff_render__tests__diff_gallery_94x35.snap`

## 场景与职责

### 测试目标
该测试验证 diff 渲染器在**中等终端尺寸（94列 x 35行）**下的渲染能力。这个尺寸介于标准终端（80x24）和大屏终端（120x40）之间，代表了许多现代终端模拟器的实际使用尺寸。

### 实际应用场景
- **现代终端默认尺寸**：许多终端模拟器（如 Windows Terminal、iTerm2、Alacritty）的默认尺寸大于 80x24
- **笔记本屏幕**：13-14 寸笔记本全屏终端的常见尺寸
- **分屏工作流**：在编辑器旁边打开终端时的典型尺寸
- **渐进增强验证**：验证渲染在"标准"和"大屏"之间的过渡行为

### 尺寸选择意义
- **94列**：比 80 列多 14 列，可以显示更多内容而减少换行
- **35行**：比 24 行多 11 行，可以显示更多文件而不滚动
- 这个尺寸足够展示所有 6 个测试文件的完整内容（对比 80x24 可能截断）

## 功能点目的

### 核心功能验证
1. **中等尺寸适配**：验证在 94 列宽度下的布局优化
2. **减少换行**：相比 80 列，更多内容可以在一行内显示
3. **完整内容展示**：35 行高度足够显示所有测试文件
4. **渐进式布局**：验证从 80 到 120 列的平滑过渡

### 三尺寸测试对比分析

| 特性 | 80x24 | 94x35 | 120x40 |
|-----|-------|-------|--------|
| 内容宽度 | ~70列 | ~84列 | ~110列 |
| 显示文件数 | 部分 | 全部 | 全部 |
| 换行频率 | 高 | 中 | 低 |
| 使用场景 | 保守兼容 | 现代终端 | 大屏展示 |

### 渲染输出特点
```
• Edited 6 files (+9 -9)                                                                      
  └ assets/banner.txt (+3 -0)                                                                 
    1 +HEADER	VALUE                                                                           
    2 +rocket	🚀                                                                              [Hidden: (15, " ")]
    3 +city	東京                                                                              [Hidden: (13, " "), (15, " ")]
```

在 94 列下：
- 相比 80 列，每行多 14 列可用空间
- `src/lib.rs` 中的 CJK 内容可以完整显示在一行
- 所有 6 个文件都能在 35 行内完整展示

## 具体技术实现

### 测试函数
```rust
#[test]
fn ui_snapshot_diff_gallery_94x35() {
    snapshot_diff_gallery("diff_gallery_94x35", 94, 35);
}
```

### 宽度分配计算

当 `width = 94` 时：

```rust
// create_diff_summary 调用
let lines = create_diff_summary(
    &diff_gallery_changes(),
    &PathBuf::from("/"),
    94,  // wrap_cols
);

// render_changes_block 内部
render_change(&r.change, &mut lines, wrap_cols - 4, lang.as_deref());
// 实际内容宽度 = 94 - 4 (缩进) = 90 列

// push_wrapped_diff_line_inner_with_theme_and_color_level 内部
let prefix_cols = gutter_width + 1;  // 行号宽度 + 符号列
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
// 可用文本区域 ≈ 90 - 4-6 = 84-86 列
```

### 高度优势

35 行高度允许显示：
- 1 行汇总头部
- 6 个文件，每个约 4-6 行
- 文件间空行
- 总计约 30-35 行

相比 24 行高度，94x35 可以完整显示所有内容而不截断。

### 内容对比示例

**80x24 下的 `src/lib.rs` 显示（可能截断）：**
```
  └ src/lib.rs (+2 -2)                                                          
    1  fn greet(name: &str) {                                                   
    2 -    println!("hello");                                                   
    3 -    println!("bye");                                                     
    2 +    println!("hello {name}");                                            
    3 +    println!("emoji: 🚀✨ and CJK: 你好世界");                           
    4  }                                                                        
```

**94x35 下的完整显示：**
```
  └ src/lib.rs (+2 -2)                                                                        
    1  fn greet(name: &str) {                                                                 
    2 -    println!("hello");                                                                 
    3 -    println!("bye");                                                                   
    2 +    println!("hello {name}");                                                          
    3 +    println!("emoji: 🚀✨ and CJK: 你好世界");                                         
    4  }                                                                                      
```

注意 CJK 行在 94 列下有更多空间，显示更完整。

## 关键代码路径与文件引用

### 尺寸相关代码路径
```
snapshot_diff_gallery("diff_gallery_94x35", 94, 35)
    → create_diff_summary(changes, cwd, 94)
        → render_changes_block(rows, 94, cwd)
            → render_change(change, lines, 90, lang)  // 94 - 4 = 90
                → push_wrapped_diff_line_inner_with_theme_and_color_level(..., 90, ...)
```

### 关键参数传递
| 阶段 | 宽度值 | 说明 |
|-----|-------|------|
| 测试函数 | 94 | 终端总宽度 |
| create_diff_summary | 94 | wrap_cols |
| render_change | 90 | wrap_cols - 4 (缩进) |
| wrap_styled_spans | ~84 | 扣除行号和符号列 |

### 与尺寸无关的通用代码
```rust
// 样式定义（所有尺寸共用）
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);

// 行号计算（所有尺寸共用）
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 { 1 } else { max_line_number.to_string().len() }
}

// 换行逻辑（所有尺寸共用）
fn wrap_styled_spans(spans: &[RtSpan<'static>], max_cols: usize) -> Vec<Vec<RtSpan<'static>>> {
    // ...
}
```

## 依赖与外部交互

### 测试基础设施
```rust
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use insta::assert_snapshot;
```

### 尺寸检测（生产环境）
```rust
// 生产代码中检测实际终端尺寸
use crossterm::terminal::size;

fn get_terminal_size() -> (u16, u16) {
    size().unwrap_or((80, 24))  // 默认回退到 80x24
}
```

### 响应式渲染
```rust
impl Renderable for DiffSummary {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let width = area.width as usize;
        let lines = create_diff_summary(&self.changes, &self.cwd, width);
        // ...
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        let lines = create_diff_summary(&self.changes, &self.cwd, width as usize);
        lines.len() as u16
    }
}
```

## 风险、边界与改进建议

### 当前测试覆盖分析

#### 已覆盖尺寸
- ✅ 80x24：标准终端，保守兼容
- ✅ 94x35：现代终端，平衡尺寸
- ✅ 120x40：大屏终端，最大展示

#### 未覆盖的边界
- ❌ < 60 列：超窄终端（手机竖屏）
- ❌ > 200 列：超宽终端（4K 显示器）
- ❌ < 10 行：矮窗口（分屏底部）

### 风险分析

#### 1. 尺寸间隙
80x24 和 94x35 之间（如 85x30）的行为未明确测试
```rust
// 建议：添加参数化测试
#[test_case(80, 24)]
#[test_case(85, 30)]
#[test_case(94, 35)]
#[test_case(120, 40)]
fn ui_snapshot_diff_gallery_parametric(width: u16, height: u16) {
    snapshot_diff_gallery(&format!("gallery_{}x{}", width, height), width, height);
}
```

#### 2. 高度敏感性
当前测试主要关注宽度，高度只是截断阈值
```rust
// 建议：添加高度敏感测试
#[test]
fn ui_snapshot_diff_gallery_94x10() {
    // 验证截断行为和滚动指示器
    snapshot_diff_gallery("diff_gallery_94x10", 94, 10);
}
```

### 改进建议

#### 1. 智能尺寸选择
```rust
enum TerminalSizeClass {
    Narrow,      // < 60 cols
    Standard,    // 60-90 cols
    Wide,        // 90-150 cols
    UltraWide,   // > 150 cols
}

impl TerminalSizeClass {
    fn from_width(width: u16) -> Self {
        match width {
            0..=60 => Self::Narrow,
            61..=90 => Self::Standard,
            91..=150 => Self::Wide,
            _ => Self::UltraWide,
        }
    }
    
    fn indent(&self) -> &'static str {
        match self {
            Self::Narrow => "  ",
            Self::Standard | Self::Wide | Self::UltraWide => "    ",
        }
    }
}
```

#### 2. 内容优先级（窄终端）
```rust
fn render_with_priority(rows: Vec<Row>, width: usize, height: usize) -> Vec<RtLine> {
    if width < 60 {
        // 窄终端：简化显示
        render_compact(rows, width, height)
    } else {
        // 正常显示
        render_full(rows, width, height)
    }
}
```

#### 3. 动态换行策略
```rust
fn should_wrap_line(line: &str, width: usize, size_class: TerminalSizeClass) -> bool {
    let display_width = calculate_display_width(line);
    match size_class {
        TerminalSizeClass::Narrow => display_width > width * 2, // 允许超长行
        _ => display_width > width,  // 正常换行
    }
}
```

### 测试改进建议

#### 1. 添加边界尺寸测试
```rust
#[test]
fn ui_snapshot_diff_gallery_60x20() {
    snapshot_diff_gallery("diff_gallery_60x20", 60, 20);
}

#[test]
fn ui_snapshot_diff_gallery_150x50() {
    snapshot_diff_gallery("diff_gallery_150x50", 150, 50);
}
```

#### 2. 添加尺寸变化测试
```rust
#[test]
fn test_responsive_layout() {
    let changes = diff_gallery_changes();
    
    // 验证不同尺寸下的行数变化
    let lines_80 = create_diff_summary(&changes, &PathBuf::from("/"), 80);
    let lines_94 = create_diff_summary(&changes, &PathBuf::from("/"), 94);
    let lines_120 = create_diff_summary(&changes, &PathBuf::from("/"), 120);
    
    // 更宽的终端应该产生更少或相等的行数（因为更少换行）
    assert!(lines_94.len() <= lines_80.len());
    assert!(lines_120.len() <= lines_94.len());
}
```

#### 3. 性能基准
```rust
#[bench]
fn bench_diff_gallery_94x35(b: &mut Bencher) {
    let changes = diff_gallery_changes();
    b.iter(|| {
        create_diff_summary(&changes, &PathBuf::from("/"), 94)
    });
}
```

### 监控与遥测建议
在生产环境中收集终端尺寸分布：
```rust
// 匿名遥测
fn report_terminal_size(width: u16, height: u16) {
    let size_class = TerminalSizeClass::from_width(width);
    telemetry::track("terminal.size", json!({
        "class": format!("{:?}", size_class),
        "width": width,
        "height": height,
    }));
}
```
