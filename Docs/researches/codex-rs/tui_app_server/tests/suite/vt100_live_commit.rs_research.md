# vt100_live_commit.rs 研究文档

## 场景与职责

该文件包含针对 `live_wrap` 模块的 VT100 终端模拟测试，验证实时输出流的行提交逻辑。这是 TUI 中处理流式输出（如命令执行输出）的核心功能测试。

### 业务背景

- TUI 需要实时显示命令执行输出（如 shell 命令、工具调用结果）
- `RowBuilder` 用于增量构建输出行，支持动态宽度调整
- **关键概念 - Commit**: 当缓冲区超过限制时，旧的行需要被"提交"到历史记录
- **Live Ring**: 保持最近 N 行在内存中供实时显示，旧行提交到永久历史
- **测试方法**: 使用 `VT100Backend` 模拟终端，验证提交的行正确显示

## 功能点目的

### 核心测试: `live_001_commit_on_overflow`

验证以下场景：

1. 构建 5 行文本（每行宽度 20）
2. 设置 live ring 最大保持 3 行
3. 调用 `drain_commit_ready(3)` 提交超出的行
4. **断言**: 
   - 最旧的 2 行（"one", "two"）被提交到历史记录
   - 最近的 3 行保留在 live ring 中

### 测试覆盖点

- `RowBuilder` 的增量文本构建
- `drain_commit_ready` 的溢出检测和行提取
- 提交的行通过 `insert_history_lines` 正确显示
- VT100 屏幕内容验证

## 具体技术实现

### 测试代码详解

```rust
#[test]
fn live_001_commit_on_overflow() {
    // 1. 创建 VT100 后端和终端
    let backend = VT100Backend::new(20, 6);
    let mut term = match codex_tui_app_server::custom_terminal::Terminal::with_options(backend) {
        Ok(t) => t,
        Err(e) => panic!("failed to construct terminal: {e}"),
    };
    
    // 2. 设置视口区域（底部 1 行）
    let area = Rect::new(0, 5, 20, 1);
    term.set_viewport_area(area);

    // 3. 使用 RowBuilder 构建 5 行文本
    let mut rb = codex_tui_app_server::live_wrap::RowBuilder::new(20);
    rb.push_fragment("one\n");
    rb.push_fragment("two\n");
    rb.push_fragment("three\n");
    rb.push_fragment("four\n");
    rb.push_fragment("five\n");

    // 4. 保留最近 3 行，提交超出的行
    let commit_rows = rb.drain_commit_ready(3);
    let lines: Vec<Line<'static>> = commit_rows.into_iter().map(|r| r.text.into()).collect();

    // 5. 将提交的行插入历史记录
    codex_tui_app_server::insert_history::insert_history_lines(&mut term, lines)
        .expect("Failed to insert history lines in test");

    // 6. 验证屏幕内容
    let screen = term.backend().vt100().screen();
    let joined = screen.contents();
    assert!(
        joined.contains("one"),
        "expected committed 'one' to be visible\n{joined}"
    );
    assert!(
        joined.contains("two"),
        "expected committed 'two' to be visible\n{joined}"
    );
    // "three", "four", "five" 保留在 live ring，不在历史记录中
}
```

### 关键数据结构

#### `RowBuilder`

```rust
pub struct RowBuilder {
    target_width: usize,
    current_line: String,  // 当前逻辑行的缓冲区
    rows: Vec<Row>,        // 已完成的行
}

pub struct Row {
    pub text: String,
    pub explicit_break: bool,  // 是否以显式换行符结束
}
```

#### `drain_commit_ready` 算法

```rust
pub fn drain_commit_ready(&mut self, max_keep: usize) -> Vec<Row> {
    let display_count = self.rows.len() + if self.current_line.is_empty() { 0 } else { 1 };
    if display_count <= max_keep {
        return Vec::new();  // 未超过限制，无需提交
    }
    let to_commit = display_count - max_keep;  // 需要提交的行数
    let commit_count = to_commit.min(self.rows.len());  // 不超过已完成的行数
    let mut drained = Vec::with_capacity(commit_count);
    for _ in 0..commit_count {
        drained.push(self.rows.remove(0));  // 从最旧的行开始移除
    }
    drained
}
```

### 执行流程

```
RowBuilder::new(20)
├── push_fragment("one\n")
│   └── 创建 Row { text: "one", explicit_break: true }
├── push_fragment("two\n")
│   └── 创建 Row { text: "two", explicit_break: true }
├── push_fragment("three\n")
│   └── 创建 Row { text: "three", explicit_break: true }
├── push_fragment("four\n")
│   └── 创建 Row { text: "four", explicit_break: true }
├── push_fragment("five\n")
│   └── 创建 Row { text: "five", explicit_break: true }
│
drain_commit_ready(3)
├── display_count = 5 (rows) + 0 (current_line 为空)
├── to_commit = 5 - 3 = 2
├── commit_count = 2.min(5) = 2
└── 移除并返回 rows[0..2] ("one", "two")
│
insert_history_lines(term, ["one", "two"])
└── 将行插入终端历史记录
```

## 关键代码路径与文件引用

### 测试文件

| 文件 | 作用 |
|------|------|
| `tests/suite/vt100_live_commit.rs` | 本测试文件 |
| `tests/test_backend.rs` | `VT100Backend` 定义 |
| `tests/all.rs` | 测试套件入口 |

### 被测代码

| 文件 | 相关功能 |
|------|----------|
| `src/live_wrap.rs` | `RowBuilder` 和实时换行实现 |
| `src/insert_history.rs` | 历史记录插入 |
| `src/custom_terminal.rs` | 自定义终端 |

### 依赖 Crate

| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟 |
| `ratatui` | TUI 框架 |
| `unicode_width` | Unicode 字符宽度计算 |

## 依赖与外部交互

### 特性门控

```rust
#![cfg(feature = "vt100-tests")]
```

与 `vt100_history.rs` 一样，测试仅在启用 `vt100-tests` 特性时编译。

### 模块依赖

```rust
use crate::test_backend::VT100Backend;
use ratatui::layout::Rect;
use ratatui::text::Line;
```

### `live_wrap` 模块导出

在 `src/lib.rs` 中：

```rust
pub mod live_wrap;
```

`live_wrap` 模块被标记为 `pub`，以便测试可以访问 `RowBuilder`。

### `RowBuilder` API

```rust
impl RowBuilder {
    pub fn new(target_width: usize) -> Self;
    pub fn push_fragment(&mut self, fragment: &str);
    pub fn drain_commit_ready(&mut self, max_keep: usize) -> Vec<Row>;
    pub fn display_rows(&self) -> Vec<Row>;
    // ... 其他方法
}
```

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖单一**: 当前只有一个测试用例，覆盖场景有限：
   - 未测试宽度变化后的重新换行
   - 未测试无显式换行符的长行
   - 未测试空输入
   - 未测试 Unicode 宽字符

2. **硬编码值**: 测试使用固定值（宽度 20，5 行，保留 3 行），缺乏边界测试

3. **部分验证**: 仅验证提交的行可见，未验证：
   - 保留在 live ring 中的行确实未被提交
   - 行顺序是否正确
   - `explicit_break` 标志是否正确设置

### 边界情况

1. **精确边界**: `max_keep` 等于总行数时，不应提交任何行
2. **零保留**: `max_keep = 0` 应该提交所有行
3. **空 builder**: 空 `RowBuilder` 应该返回空 Vec
4. **未完成的行**: `current_line` 非空时的处理
5. **宽度变化**: `set_width` 后的重新换行

### 改进建议

1. **增加边界测试**:
   ```rust
   #[test]
   fn drain_commit_ready_exact_boundary() {
       let mut rb = RowBuilder::new(20);
       rb.push_fragment("one\n");
       rb.push_fragment("two\n");
       let committed = rb.drain_commit_ready(2);  // 等于总行数
       assert!(committed.is_empty());  // 不应提交任何行
   }

   #[test]
   fn drain_commit_ready_zero_keep() {
       let mut rb = RowBuilder::new(20);
       rb.push_fragment("one\n");
       rb.push_fragment("two\n");
       let committed = rb.drain_commit_ready(0);  // 保留 0 行
       assert_eq!(committed.len(), 2);  // 提交所有行
   }

   #[test]
   fn drain_commit_ready_with_partial_line() {
       let mut rb = RowBuilder::new(20);
       rb.push_fragment("one\n");
       rb.push_fragment("two");  // 无换行符，在 current_line 中
       let committed = rb.drain_commit_ready(1);
       // 验证 behavior：current_line 是否计入 display_count？
   }
   ```

2. **测试 `display_rows` 与 `drain_commit_ready` 的交互**:
   ```rust
   #[test]
   fn display_rows_after_drain() {
       let mut rb = RowBuilder::new(20);
       rb.push_fragment("one\n");
       rb.push_fragment("two\n");
       rb.push_fragment("three\n");
       
       let committed = rb.drain_commit_ready(1);
       assert_eq!(committed.len(), 2);
       
       let remaining = rb.display_rows();
       assert_eq!(remaining.len(), 1);
       assert_eq!(remaining[0].text, "three");
   }
   ```

3. **测试宽度变化**:
   ```rust
   #[test]
   fn rewrap_on_width_change() {
       let mut rb = RowBuilder::new(10);
       rb.push_fragment("hello world test");
       rb.set_width(5);
       
       let rows = rb.display_rows();
       for row in &rows {
           assert!(row.width() <= 5);
       }
   }
   ```

4. **Unicode 测试**:
   ```rust
   #[test]
   fn commit_with_wide_characters() {
       let mut rb = RowBuilder::new(10);
       rb.push_fragment("你好\n");  // 每个 CJK 字符宽度为 2
       rb.push_fragment("世界\n");
       // ...
   }
   ```

5. **验证行顺序**:
   ```rust
   #[test]
   fn commit_preserves_order() {
       let mut rb = RowBuilder::new(20);
       for i in 0..5 {
           rb.push_fragment(&format!("line{}\n", i));
       }
       let committed = rb.drain_commit_ready(2);
       assert_eq!(committed[0].text, "line0");
       assert_eq!(committed[1].text, "line1");
   }
   ```

6. **集成到 `live_wrap.rs`**: 将这些测试移到 `live_wrap.rs` 的 `#[cfg(test)]` 模块中，与实现代码更接近

7. **文档增强**: 为 `drain_commit_ready` 添加更详细的文档注释，说明其语义和边界行为

8. **性能测试**: 测试大量行的处理性能
   ```rust
   #[test]
   fn large_commit_performance() {
       let mut rb = RowBuilder::new(80);
       for i in 0..10000 {
           rb.push_fragment(&format!("Line {}\n", i));
       }
       let start = Instant::now();
       let committed = rb.drain_commit_ready(100);
       assert!(start.elapsed() < Duration::from_millis(10));
   }
   ```
