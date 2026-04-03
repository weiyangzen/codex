# Research: Diff Gallery 120x40 Terminal Rendering Test

## Snapshot File
`codex_tui__diff_render__tests__diff_gallery_120x40.snap`

## 场景与职责

### 测试目标
该测试验证 diff 渲染器在**大尺寸终端（120列 x 40行）**下的综合渲染能力，展示多文件、多类型变更的完整渲染效果。这是 diff gallery 测试系列中终端尺寸最大的测试用例。

### 实际应用场景
- **大屏终端展示**：在大型显示器或全屏终端中查看代码变更
- **复杂变更概览**：同时展示多个文件的变更，提供项目级别的变更视图
- **国际化内容支持**：验证 emoji 和 CJK（中日韩）字符的正确渲染

### 测试数据构造（diff_gallery_changes 函数）
测试构造了6个文件的复杂变更场景：

| 文件路径 | 变更类型 | 内容特点 |
|---------|---------|---------|
| `src/lib.rs` | Update | Rust 代码，包含 emoji 和 CJK 字符 |
| `scripts/calc.txt → scripts/calc.py` | Update + Rename | Python 代码，文件重命名 |
| `assets/banner.txt` | Add | 包含 tab 分隔符、emoji、CJK |
| `examples/new_sample.rs` | Add | Rust 代码 |
| `tmp/obsolete.log` | Delete | 普通文本删除 |
| `legacy/old_script.py` | Delete | Python 代码删除 |

## 功能点目的

### 核心功能验证
1. **多文件汇总渲染**：验证 `create_diff_summary` 函数正确处理多个文件
2. **文件重命名显示**：验证 `move_path` 字段的箭头（→）显示
3. **语法高亮**：验证 Rust、Python 文件的语法高亮
4. **宽字符处理**：验证 emoji（🚀✨）和 CJK（東京、你好世界）的宽度计算
5. **行号对齐**：在 120 列宽度下验证行号列的对齐

### 渲染输出结构分析
```
• Edited 6 files (+9 -9)                                                                                                
  └ assets/banner.txt (+3 -0)                                                                                           
    1 +HEADER	VALUE                                                                                                     
    2 +rocket	🚀                                                                                                        [多宽度符号隐藏: (15, " ")]
    3 +city	東京                                                                                                        [多宽度符号隐藏: (13, " "), (15, " ")]
```

### 关键观察点
1. **汇总行**：显示总文件数、总添加/删除行数
2. **文件头**：每个文件显示相对路径和变更统计
3. **重命名指示**：`scripts/calc.txt → scripts/calc.py`
4. **隐藏标记**：`Hidden by multi-width symbols` 指示宽字符占用的额外列

## 具体技术实现

### 测试函数实现
```rust
fn snapshot_diff_gallery(name: &str, width: u16, height: u16) {
    let lines = create_diff_summary(
        &diff_gallery_changes(),
        &PathBuf::from("/"),
        usize::from(width),
    );
    snapshot_lines(name, lines, width, height);
}

#[test]
fn ui_snapshot_diff_gallery_120x40() {
    snapshot_diff_gallery("diff_gallery_120x40", 120, 40);
}
```

### 多文件渲染核心逻辑

#### 1. 文件变更收集与排序
```rust
fn collect_rows(changes: &HashMap<PathBuf, FileChange>) -> Vec<Row> {
    let mut rows: Vec<Row> = Vec::new();
    for (path, change) in changes.iter() {
        let (added, removed) = match change {
            FileChange::Add { content } => (content.lines().count(), 0),
            FileChange::Delete { content } => (0, content.lines().count()),
            FileChange::Update { unified_diff, .. } => 
                calculate_add_remove_from_diff(unified_diff),
        };
        let move_path = match change {
            FileChange::Update { move_path: Some(new), .. } => Some(new.clone()),
            _ => None,
        };
        rows.push(Row { path: path.clone(), move_path, added, removed, change: change.clone() });
    }
    rows.sort_by_key(|r| r.path.clone());  // 按路径排序确保确定性输出
    rows
}
```

#### 2. 汇总渲染
```rust
fn render_changes_block(rows: Vec<Row>, wrap_cols: usize, cwd: &Path) -> Vec<RtLine<'static>> {
    // 计算总计
    let total_added: usize = rows.iter().map(|r| r.added).sum();
    let total_removed: usize = rows.iter().map(|r| r.removed).sum();
    let file_count = rows.len();
    let noun = if file_count == 1 { "file" } else { "files" };
    
    // 单文件 vs 多文件头部显示
    let mut header_spans: Vec<RtSpan<'static>> = vec!["• ".dim()];
    if let [row] = &rows[..] {
        // 单文件：显示 "Added"/"Deleted"/"Edited" + 路径
        let verb = match &row.change {
            FileChange::Add { .. } => "Added",
            FileChange::Delete { .. } => "Deleted",
            _ => "Edited",
        };
        header_spans.push(verb.bold());
        header_spans.push(" ".into());
        header_spans.extend(render_path(row));
    } else {
        // 多文件：显示 "Edited N files"
        header_spans.push("Edited".bold());
        header_spans.push(format!(" {file_count} {noun} ").into());
    }
    header_spans.extend(render_line_count_summary(total_added, total_removed));
    out.push(RtLine::from(header_spans));
    // ...
}
```

#### 3. 行数统计渲染
```rust
fn render_line_count_summary(added: usize, removed: usize) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push("(".into());
    spans.push(format!("+{added}").green());  // 绿色显示添加
    spans.push(" ".into());
    spans.push(format!("-{removed}").red());   // 红色显示删除
    spans.push(")".into());
    spans
}
```

### 宽字符处理机制

#### Unicode 宽度计算
```rust
use unicode_width::UnicodeWidthChar;

fn display_width(text: &str) -> usize {
    text.chars()
        .map(|ch| ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 }))
        .sum()
}
```

#### 宽字符隐藏标记
测试输出中的 `Hidden by multi-width symbols` 是测试框架（insta）的特性，用于标记宽字符（如 emoji 占2列、CJK 占2列）在终端网格中占用的额外空间。

```
"    2 +rocket	🚀                                                                                                        " Hidden by multi-width symbols: [(15, " ")]
```
这表示 emoji 🚀 占用了2列，导致位置15的空格被"隐藏"。

### 语法高亮集成

#### 语言检测
```rust
fn detect_lang_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    Some(ext.to_string())  // 返回扩展名供后续处理
}
```

#### 重命名文件的高亮处理
```rust
// 对于重命名文件，使用目标路径的扩展名进行高亮
let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
let lang = detect_lang_for_path(lang_path);
```

## 关键代码路径与文件引用

### 核心渲染流程
```
diff_gallery_changes() 
    → create_diff_summary()
        → collect_rows()           // 收集并排序文件
        → render_changes_block()   // 渲染汇总块
            → render_path()        // 渲染文件路径
            → render_line_count_summary()  // 渲染 (+n -m)
            → render_change()      // 渲染单个文件变更
                → FileChange::Add/Delete/Update 处理
```

### 关键函数位置
| 函数 | 行号 | 职责 |
|-----|------|------|
| `diff_gallery_changes` | 1404-1458 | 测试数据构造 |
| `snapshot_diff_gallery` | 1460-1467 | 测试辅助函数 |
| `create_diff_summary` | 345-352 | 创建 diff 汇总 |
| `collect_rows` | 365-390 | 收集文件变更行 |
| `render_changes_block` | 402-464 | 渲染变更块 |
| `render_change` | 474-736 | 渲染单个变更 |
| `display_path_for` | 741-762 | 路径显示格式化 |

### 类型定义
```rust
// Row 结构（第355-363行）
struct Row {
    path: PathBuf,
    move_path: Option<PathBuf>,  // 重命名目标路径
    added: usize,
    removed: usize,
    change: FileChange,
}

// DiffSummary 结构（第295-304行）
pub struct DiffSummary {
    changes: HashMap<PathBuf, FileChange>,
    cwd: PathBuf,
}
```

## 依赖与外部交互

### 核心依赖
| 依赖 | 用途 |
|-----|------|
| `diffy` | 创建和解析 diff patch |
| `ratatui` | 终端 UI 渲染 |
| `unicode_width` | Unicode 字符宽度计算 |
| `insta` | 快照测试框架 |

### 测试框架集成
```rust
use insta::assert_snapshot;
use ratatui::Terminal;
use ratatui::backend::TestBackend;

fn snapshot_lines(name: &str, lines: Vec<RtLine<'static>>, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|f| {
            Paragraph::new(Text::from(lines))
                .wrap(Wrap { trim: false })
                .render_ref(f.area(), f.buffer_mut())
        })
        .expect("draw");
    assert_snapshot!(name, terminal.backend());
}
```

### 颜色系统
```rust
// 样式应用示例
"• ".dim()           // 暗淡的 bullet
"Edited".bold()      // 粗体标题
format!("+{added}").green()   // 绿色添加计数
format!("-{removed}").red()   // 红色删除计数
```

## 风险、边界与改进建议

### 已知风险

#### 1. 宽字符对齐问题
```rust
// 当前：依赖 unicode_width crate
let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
```
- **风险**：某些终端对特定 emoji 的宽度处理不一致
- **案例**：🚀 在某些终端占1列，某些占2列
- **缓解**：测试输出中的 `Hidden by multi-width symbols` 标记帮助识别问题

#### 2. 大文件性能
- **风险**：当变更文件过多时，渲染可能变慢
- **当前保护**：`exceeds_highlight_limits` 检查跳过超大文件的语法高亮

### 边界条件

| 边界条件 | 行为 | 建议 |
|---------|------|------|
| 120列宽 | 充分利用空间，较少换行 | ✅ 理想场景 |
| 超长行（>120列） | 硬换行 | ✅ 已处理 |
| 大量文件（>100） | 线性增长，无分页 | ⚠️ 考虑分页 |
| 混合编码文件 | 依赖 Rust 字符串处理 | ✅ UTF-8 支持 |

### 改进建议

#### 1. 响应式布局
```rust
// 建议：根据终端宽度动态调整缩进
fn get_indent_for_width(width: usize) -> &'static str {
    match width {
        0..=80 => "  ",
        81..=120 => "    ",
        _ => "      ",
    }
}
```

#### 2. 文件分组
```rust
// 建议：按目录分组显示
struct FileGroup {
    directory: PathBuf,
    files: Vec<Row>,
}
```

#### 3. 性能优化
```rust
// 当前：同步渲染所有文件
// 建议：大变更集使用并行渲染
use rayon::prelude::*;

let rendered: Vec<_> = rows.par_iter()
    .map(|row| render_row(row))
    .collect();
```

#### 4. 可访问性
- 添加 `--no-color` 选项支持
- 提供纯文本模式（无 Unicode 边框）
- 支持屏幕阅读器的结构化输出

### 相关测试矩阵

| 测试名称 | 终端尺寸 | 测试重点 |
|---------|---------|---------|
| `diff_gallery_80x24` | 80x24 | 标准终端 |
| `diff_gallery_94x35` | 94x35 | 中等终端 |
| `diff_gallery_120x40` | 120x40 | 大屏终端 |

### 调试建议
当遇到渲染问题时：
1. 检查 `display_width` 计算是否正确
2. 验证 `wrap_styled_spans` 的换行逻辑
3. 使用 `snapshot_lines_text` 查看纯文本输出
4. 对比不同终端尺寸的输出差异
