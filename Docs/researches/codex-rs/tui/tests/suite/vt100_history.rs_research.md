# vt100_history.rs 研究文档

## 场景与职责

`codex-rs/tui/tests/suite/vt100_history.rs` 是一组 VT100 模拟测试，验证 `insert_history_lines` 函数的历史记录插入和文本换行功能。

这些测试使用 `VT100Backend` 模拟真实终端行为，确保 TUI 在滚动历史记录时的渲染正确性，包括：
- 基本文本插入
- 长文本自动换行
- Unicode 字符（Emoji、CJK）处理
- ANSI 样式保留
- 光标位置恢复
- 智能单词换行（避免单词中间断开）

## 功能点目的

1. **历史记录渲染验证**: 确保聊天历史正确插入到视口上方
2. **文本换行正确性**: 验证不同宽度文本的换行行为
3. **Unicode 支持**: 确保宽字符（Emoji、中文）正确显示
4. **样式保留**: 验证 ANSI 颜色/样式在换行后保留
5. **光标恢复**: 确保操作后光标位置正确

## 具体技术实现

### 测试架构

```
┌─────────────────────────────────────────────────────────────────┐
│  VT100 Test Scenario                                            │
├─────────────────────────────────────────────────────────────────┤
│  VT100Backend (模拟终端)                                         │
│  ├── CrosstermBackend (渲染后端)                                │
│  └── vt100::Parser (屏幕状态解析)                                │
│         └── 提供 screen().contents() 验证渲染结果                │
└─────────────────────────────────────────────────────────────────┘
```

### 测试场景结构
```rust
struct TestScenario {
    term: codex_tui::custom_terminal::Terminal<VT100Backend>,
}

impl TestScenario {
    fn new(width: u16, height: u16, viewport: Rect) -> Self {
        let backend = VT100Backend::new(width, height);
        let mut term = codex_tui::custom_terminal::Terminal::with_options(backend)
            .expect("failed to construct terminal");
        term.set_viewport_area(viewport);  // 设置视口区域
        Self { term }
    }

    fn run_insert(&mut self, lines: Vec<Line<'static>>) {
        codex_tui::insert_history::insert_history_lines(&mut self.term, lines)
            .expect("Failed to insert history lines in test");
    }
}
```

### 关键测试用例

#### 1. 基本插入（无换行）
```rust
#[test]
fn basic_insertion_no_wrap() {
    let area = Rect::new(0, 5, 20, 1);  // 视口在最后一行
    let mut scenario = TestScenario::new(20, 6, area);

    let lines = vec!["first".into(), "second".into()];
    scenario.run_insert(lines);
    
    let rows = scenario.term.backend().vt100().screen().contents();
    assert_contains!(rows, String::from("first"));
    assert_contains!(rows, String::from("second"));
}
```

#### 2. 长文本换行
```rust
#[test]
fn long_token_wraps() {
    let long = "A".repeat(45);  // 45 个 A，在 20 列宽度下应换行 3 次
    let lines = vec![long.clone().into()];
    scenario.run_insert(lines);
    
    // 统计屏幕上 A 的数量，验证所有字符都被渲染
    let mut count_a = 0usize;
    for row in 0..6 {
        for col in 0..20 {
            if let Some(cell) = screen.cell(row, col)
                && let Some(ch) = cell.contents().chars().next()
                && ch == 'A'
            {
                count_a += 1;
            }
        }
    }
    assert_eq!(count_a, long.len());
}
```

#### 3. Emoji 和 CJK 字符
```rust
#[test]
fn emoji_and_cjk() {
    let text = String::from("😀😀😀😀😀 你好世界");
    let lines = vec![text.clone().into()];
    scenario.run_insert(lines);
    
    let rows = scenario.term.backend().vt100().screen().contents();
    for ch in text.chars().filter(|c| !c.is_whitespace()) {
        assert!(rows.contains(ch), "missing character {ch:?}");
    }
}
```

#### 4. ANSI 样式混合
```rust
#[test]
fn mixed_ansi_spans() {
    let line = vec!["red".red(), "+plain".into()].into();
    scenario.run_insert(vec![line]);
    
    let rows = scenario.term.backend().vt100().screen().contents();
    assert_contains!(rows, String::from("red+plain"));
}
```

#### 5. 光标恢复
```rust
#[test]
fn cursor_restoration() {
    let lines = vec!["x".into()];
    scenario.run_insert(lines);
    assert_eq!(scenario.term.last_known_cursor_pos, (0, 0).into());
}
```

#### 6. 单词换行（避免单词中间断开）
```rust
#[test]
fn word_wrap_no_mid_word_split() {
    let sample = "Years passed, and Willowmere thrived...";
    scenario.run_insert(vec![sample.into()]);
    
    let joined = scenario.term.backend().vt100().screen().contents();
    assert!(
        !joined.contains("bo\nth"),  // "both" 不应被断开
        "word 'both' should not be split across lines"
    );
}
```

#### 7. 特殊标点处理（em-dash）
```rust
#[test]
fn em_dash_and_space_word_wrap() {
    let sample = "...sand—and inside lay a single...";
    scenario.run_insert(vec![sample.into()]);
    
    let joined = scenario.term.backend().vt100().screen().contents();
    assert!(
        !joined.contains("insi\nde"),  // "inside" 不应被断开
        "word 'inside' should not be split across lines"
    );
}
```

## 关键代码路径与文件引用

### 核心被测代码
| 文件 | 函数/结构 | 功能 |
|------|-----------|------|
| `codex-rs/tui/src/insert_history.rs` | `insert_history_lines()` | 历史记录插入主函数 |
| `codex-rs/tui/src/wrapping.rs` | `adaptive_wrap_line()` | 自适应文本换行 |
| `codex-rs/tui/src/custom_terminal.rs` | `Terminal` | 自定义终端实现 |
| `codex-rs/tui/src/test_backend.rs` | `VT100Backend` | 测试用 VT100 后端 |

### VT100Backend 实现
```rust
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}

impl VT100Backend {
    pub fn new(width: u16, height: u16) -> Self {
        crossterm::style::force_color_output(true);
        Self {
            crossterm_backend: CrosstermBackend::new(
                vt100::Parser::new(height, width, 0)
            ),
        }
    }

    pub fn vt100(&self) -> &vt100::Parser {
        self.crossterm_backend.writer()
    }
}
```

### 依赖库
| 库 | 用途 |
|----|------|
| `vt100` | VT100 终端模拟器，解析 ANSI 序列 |
| `ratatui` | TUI 框架，提供 Backend trait |
| `crossterm` | 跨平台终端控制 |

## 依赖与外部交互

### Feature 标志
```rust
#![cfg(feature = "vt100-tests")]
```

测试仅在启用 `vt100-tests` feature 时编译和运行。

### Cargo.toml 配置
```toml
[features]
vt100-tests = []

[dev-dependencies]
vt100 = { workspace = true }
```

### 测试执行
```bash
# 运行 VT100 测试
cargo test -p codex-tui --features vt100-tests

# 运行特定测试
cargo test -p codex-tui --features vt100-tests word_wrap_no_mid_word_split
```

## 风险、边界与改进建议

### 风险
1. **Feature 依赖**: 测试需要显式启用 `vt100-tests` feature，可能遗漏
2. **屏幕尺寸硬编码**: 测试使用固定 20x6 或 40x10 屏幕尺寸
3. **单断言覆盖**: 部分测试仅验证内容存在性，不验证精确布局

### 边界条件
- 视口始终设置为屏幕底部（`y = height - 1`）
- 不测试复杂滚动区域交互
- 不测试真实终端的差异化行为

### 改进建议
1. **自动化**: 考虑将 `vt100-tests` 加入默认测试套件
2. **参数化**: 使用 `rstest` 或类似工具参数化屏幕尺寸
3. **快照测试**: 引入 `insta` 快照测试验证精确屏幕状态
4. **扩展覆盖**:
   - 多行视口滚动
   - 复杂 ANSI 序列（256色、真彩色）
   - URL 检测和保留（与 `wrapping.rs` 联动）
   - BiDi 文本（阿拉伯语、希伯来语）
5. **性能**: 考虑并行化独立测试场景
