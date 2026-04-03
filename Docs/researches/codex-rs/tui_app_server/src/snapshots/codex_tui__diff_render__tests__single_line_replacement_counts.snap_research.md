# Research: Single Line Replacement Counts Test

## Snapshot File
`codex_tui__diff_render__tests__single_line_replacement_counts.snap`

## 场景与职责

### 测试目标
该测试验证 diff 渲染器对**单行替换变更**的正确渲染，特别是行号计数和差异标记的显示。这是最基本的 diff 场景之一：一行内容被完全替换为另一行。

### 实际应用场景
- **简单文本编辑**：修改配置文件中的单个值
- **变量重命名**：代码中单个标识符的替换
- **版本号更新**：如 `version = "1.0.0"` → `version = "1.0.1"`
- **文档修正**：修正单个错别字或链接

### 测试数据构造
测试使用了一个简单的 Markdown 文件标题变更：
- **文件**：`README.md`
- **原始内容**：`# Codex CLI (Rust Implementation)`
- **修改后内容**：`# Codex CLI (Rust Implementation) banana`
- **变更类型**：单行替换（1 行删除，1 行添加）

## 功能点目的

### 核心功能验证
1. **行号显示**：验证删除行和添加行都显示行号 1
2. **差异标记**：正确显示 `-`（删除）和 `+`（添加）
3. **行号对齐**：两行行号列对齐
4. **计数准确性**：验证统计为 `(+1 -1)`

### 渲染输出分析
```
• Proposed Change README.md (+1 -1)                                             
    1     -# Codex CLI (Rust Implementation)                                    
    1     +# Codex CLI (Rust Implementation) banana                             
```

### 关键观察点
1. **行号重复**：删除行和添加行都显示行号 `1`，表示这是同一逻辑行的替换
2. **符号对齐**：`-` 和 `+` 符号在行号后对齐
3. **内容对比**：两行内容并排展示，便于比较差异
4. **统计准确**：头部正确显示 `(+1 -1)`

## 具体技术实现

### 测试构造
```rust
// 推测的测试代码（基于 snapshot 和源码分析）
#[test]
fn ui_snapshot_single_line_replacement_counts() {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    
    let original = "# Codex CLI (Rust Implementation)\n";
    let modified = "# Codex CLI (Rust Implementation) banana\n";
    let patch = diffy::create_patch(original, modified).to_string();
    
    changes.insert(
        PathBuf::from("README.md"),
        FileChange::Update {
            unified_diff: patch,
            move_path: None,
        },
    );
    
    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("single_line_replacement_counts", lines, 80, 10);
}
```

### Patch 格式解析
生成的统一 diff patch 格式：
```diff
--- original
+++ modified
@@ -1 +1 @@
-# Codex CLI (Rust Implementation)
+# Codex CLI (Rust Implementation) banana
```

解析结果：
- `@@ -1 +1 @@`：旧文件从第1行开始，1行；新文件从第1行开始，1行
- `-` 开头：删除行
- `+` 开头：添加行

### 行号计算逻辑
```rust
// render_change 函数中处理 Update
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        for h in patch.hunks() {
            let mut old_ln = h.old_range().start();  // = 1
            let mut new_ln = h.new_range().start();  // = 1
            
            for l in h.lines() {
                match l {
                    diffy::Line::Insert(_) => {
                        max_line_number = max_line_number.max(new_ln);
                        // 渲染 new_ln
                        new_ln += 1;
                    }
                    diffy::Line::Delete(_) => {
                        max_line_number = max_line_number.max(old_ln);
                        // 渲染 old_ln
                        old_ln += 1;
                    }
                    diffy::Line::Context(_) => {
                        max_line_number = max_line_number.max(new_ln);
                        old_ln += 1;
                        new_ln += 1;
                    }
                }
            }
        }
    }
}
```

### 行号宽度计算
```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()  // 1.to_string().len() = 1
    }
}
```

对于单行变更，行号宽度为 1。

### 渲染核心函数
```rust
fn push_wrapped_diff_line_inner_with_theme_and_color_level(
    line_number: usize,  // 1
    kind: DiffLineType,  // Delete 或 Insert
    text: &str,
    width: usize,
    line_number_width: usize,  // 1
    syntax_spans: Option<&[RtSpan<'static>]>,
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Vec<RtLine<'static>> {
    let ln_str = line_number.to_string();  // "1"
    let gutter_width = line_number_width.max(1);  // 1
    let prefix_cols = gutter_width + 1;  // 2 (行号 + 空格)
    
    let (sign_char, sign_style, content_style) = match kind {
        DiffLineType::Insert => ('+', style_sign_add(...), style_add(...)),
        DiffLineType::Delete => ('-', style_sign_del(...), style_del(...)),
        DiffLineType::Context => (' ', style_context(), style_context()),
    };
    
    // 格式化："1 "（行号右对齐，宽度1 + 空格）
    let gutter = format!("{ln_str:>gutter_width$} ");
    let sign = format!("{sign_char}");
    
    // 渲染...
}
```

## 关键代码路径与文件引用

### 核心代码路径
```
测试函数
    → diff_summary_for_tests(&changes)
        → create_diff_summary(changes, cwd, 80)
            → collect_rows(changes)
                → calculate_add_remove_from_diff(unified_diff)
            → render_changes_block(rows, 80, cwd)
                → render_change(change, lines, 76, lang)
                    → diffy::Patch::from_str(unified_diff)
                    → 遍历 hunks
                        → 处理 Delete 行（old_ln = 1）
                        → 处理 Insert 行（new_ln = 1）
```

### 行统计计算
```rust
pub(crate) fn calculate_add_remove_from_diff(diff: &str) -> (usize, usize) {
    if let Ok(patch) = diffy::Patch::from_str(diff) {
        patch
            .hunks()
            .iter()
            .flat_map(Hunk::lines)
            .fold((0, 0), |(a, d), l| match l {
                diffy::Line::Insert(_) => (a + 1, d),
                diffy::Line::Delete(_) => (a, d + 1),
                diffy::Line::Context(_) => (a, d),
            })
    } else {
        (0, 0)
    }
}
```

对于单行替换：
- 输入：1 个 Delete 行，1 个 Insert 行
- 输出：`(1, 1)` → `(+1 -1)`

### 关键类型和常量
```rust
// 行类型（第105-110行）
pub(crate) enum DiffLineType {
    Insert,   // '+'
    Delete,   // '-'
    Context,  // ' '
}

// 统计渲染（第392-400行）
fn render_line_count_summary(added: usize, removed: usize) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push("(".into());
    spans.push(format!("+{added}").green());
    spans.push(" ".into());
    spans.push(format!("-{removed}").red());
    spans.push(")".into());
    spans
}
```

## 依赖与外部交互

### diffy crate 集成
```rust
use diffy::Hunk;

// 创建 patch
let patch = diffy::create_patch(original, modified);

// 解析 patch
let patch = diffy::Patch::from_str(unified_diff)?;
for hunk in patch.hunks() {
    let old_start = hunk.old_range().start();
    let new_start = hunk.new_range().start();
    for line in hunk.lines() {
        match line {
            diffy::Line::Insert(text) => { }
            diffy::Line::Delete(text) => { }
            diffy::Line::Context(text) => { }
        }
    }
}
```

### 样式系统
```rust
use ratatui::style::Style;
use ratatui::style::Color;
use ratatui::style::Stylize;

// 删除行样式（红色）
fn style_del(theme: DiffTheme, color_level: DiffColorLevel, backgrounds: ResolvedDiffBackgrounds) -> Style {
    // 返回红色前景或红色背景样式
}

// 添加行样式（绿色）
fn style_add(theme: DiffTheme, color_level: DiffColorLevel, backgrounds: ResolvedDiffBackgrounds) -> Style {
    // 返回绿色前景或绿色背景样式
}
```

### 测试框架
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

## 风险、边界与改进建议

### 已知风险

#### 1. 行号对齐问题
当文件行数从 9 行变为 10 行时，行号宽度从 1 变为 2，可能导致对齐变化：
```
    9 -old line     // 删除行，宽度1
   10 +new line    // 添加行，宽度2（不对齐！）
```

**当前处理**：使用固定的 `line_number_width` 基于最大行号计算
```rust
let line_number_width = line_number_width(max_line_number);
// 所有行使用相同的行号列宽度
```

#### 2. 单行过长
如果单行内容超过终端宽度，会被硬换行：
```
    1 -# Very long line that exceeds the terminal width and needs to be wrapped
    1 +# Very long line that exceeds the terminal width and needs to be wrapped with changes
```

换行后：
```
    1 -# Very long line that exceeds the terminal 
       width and needs to be wrapped
    1 +# Very long line that exceeds the terminal 
       width and needs to be wrapped with changes
```

### 边界条件

| 边界条件 | 行为 | 建议 |
|---------|------|------|
| 空文件 → 单行 | `(+1 -0)` | ✅ 正确 |
| 单行 → 空文件 | `(+0 -1)` | ✅ 正确 |
| 单行 → 单行 | `(+1 -1)` | ✅ 本测试验证 |
| 单行 → 多行 | `(+n -1)` | ✅ 支持 |
| 多行 → 单行 | `(+1 -n)` | ✅ 支持 |

### 改进建议

#### 1. 行内差异高亮
```rust
// 当前：整行显示
    1 -# Codex CLI (Rust Implementation)
    1 +# Codex CLI (Rust Implementation) banana

// 建议：行内差异高亮
    1 -# Codex CLI (Rust Implementation)
    1 +# Codex CLI (Rust Implementation) [banana]
    // 或
    1 -# Codex CLI (Rust Implementation)
    1 +# Codex CLI (Rust Implementation) banana
                                    ^^^^^^^ (绿色高亮)
```

实现思路：
```rust
fn highlight_inline_diff(old: &str, new: &str) -> Vec<DiffSegment> {
    // 使用相似度算法（如 Myers diff）找出共同部分
    // 标记新增/删除的片段
}
```

#### 2. 字符级差异
```rust
// 使用 similar crate 进行字符级 diff
use similar::{ChangeTag, TextDiff};

fn render_char_diff(old: &str, new: &str) -> Vec<Span> {
    let diff = TextDiff::from_chars(old, new);
    for change in diff.iter_all_changes() {
        match change.tag() {
            ChangeTag::Delete => /* 红色 */,
            ChangeTag::Insert => /* 绿色 */,
            ChangeTag::Equal => /* 默认 */,
        }
    }
}
```

#### 3. 统计验证测试
```rust
#[test]
fn verify_line_count_accuracy() {
    let test_cases = vec![
        ("a\n", "b\n", (1, 1)),           // 单行替换
        ("a\n", "a\nb\n", (1, 0)),        // 添加一行
        ("a\nb\n", "a\n", (0, 1)),        // 删除一行
        ("", "a\n", (1, 0)),              // 空到单行
        ("a\n", "", (0, 1)),              // 单行到空
    ];
    
    for (original, modified, expected) in test_cases {
        let patch = diffy::create_patch(original, modified).to_string();
        let actual = calculate_add_remove_from_diff(&patch);
        assert_eq!(actual, expected, "Failed for: {:?} → {:?}", original, modified);
    }
}
```

#### 4. 边界行号测试
```rust
#[test]
fn line_number_alignment_at_boundary() {
    // 测试 9→10, 99→100, 999→1000 等边界
    for max_lines in [9, 10, 99, 100, 999, 1000] {
        let width = line_number_width(max_lines);
        let expected_width = max_lines.to_string().len();
        assert_eq!(width, expected_width);
    }
}
```

### 相关测试建议

#### 1. 多行替换测试
```rust
#[test]
fn ui_snapshot_multi_line_replacement() {
    let original = "line1\nline2\nline3\n";
    let modified = "line1\nmodified2\nmodified3\nline4\n";
    // 验证 (+2 -1) 统计和多行显示
}
```

#### 2. 混合变更测试
```rust
#[test]
fn ui_snapshot_mixed_changes() {
    // 同时包含添加、删除、修改的复杂场景
}
```

#### 3. 大数字行号测试
```rust
#[test]
fn ui_snapshot_large_line_numbers() {
    // 验证 10000+ 行文件的行号显示
}
```

### 调试建议
当遇到行号或计数问题时：
1. 检查 `calculate_add_remove_from_diff` 的返回值
2. 验证 `diffy::Patch::from_str` 是否正确解析
3. 使用 `snapshot_lines_text` 查看纯文本输出
4. 检查 `line_number_width` 的计算
5. 确认 `old_ln` 和 `new_ln` 的递增逻辑
