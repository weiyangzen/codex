# vt100_history.rs 研究文档

## 场景与职责

该文件包含针对 `insert_history` 模块的 VT100 终端模拟测试。这些测试验证历史记录插入功能在各种复杂场景下的正确性，包括文本换行、Unicode 字符处理、ANSI 样式保留等。

### 业务背景

- TUI 使用内联模式（inline mode）时，需要在视口（viewport）上方插入历史记录
- `insert_history_lines` 函数负责将文本行插入到终端滚动缓冲区
- 这些行可能包含：
  - 长文本需要自动换行
  - Emoji 和 CJK 等宽字符
  - ANSI 颜色样式
  - URL 需要特殊处理以保持可点击性
- **测试方法**: 使用 `VT100Backend` 模拟 VT100 终端，验证输出符合预期

## 功能点目的

### 测试用例概览

| 测试函数 | 目的 |
|----------|------|
| `basic_insertion_no_wrap` | 验证基本插入功能，无换行场景 |
| `long_token_wraps` | 验证超长 token 的正确换行 |
| `emoji_and_cjk` | 验证 Emoji 和 CJK 字符（宽字符）处理 |
| `mixed_ansi_spans` | 验证混合 ANSI 样式的文本处理 |
| `cursor_restoration` | 验证光标位置在插入后正确恢复 |
| `word_wrap_no_mid_word_split` | 验证单词换行不会截断单词 |
| `em_dash_and_space_word_wrap` | 验证特殊标点（em-dash）附近的换行行为 |

## 具体技术实现

### 测试基础设施

```rust
struct TestScenario {
    term: codex_tui_app_server::custom_terminal::Terminal<VT100Backend>,
}

impl TestScenario {
    fn new(width: u16, height: u16, viewport: Rect) -> Self {
        let backend = VT100Backend::new(width, height);
        let mut term = codex_tui_app_server::custom_terminal::Terminal::with_options(backend)
            .expect("failed to construct terminal");
        term.set_viewport_area(viewport);
        Self { term }
    }

    fn run_insert(&mut self, lines: Vec<Line<'static>>) {
        codex_tui_app_server::insert_history::insert_history_lines(&mut self.term, lines)
            .expect("Failed to insert history lines in test");
    }
}
```

### 核心测试模式

1. **创建测试场景**:
   ```rust
   let area = Rect::new(0, 5, 20, 1);  // x=0, y=5, width=20, height=1
   let mut scenario = TestScenario::new(20, 6, area);
   ```

2. **准备输入行**:
   ```rust
   let lines = vec!["first".into(), "second".into()];
   ```

3. **执行插入**:
   ```rust
   scenario.run_insert(lines);
   ```

4. **验证屏幕内容**:
   ```rust
   let rows = scenario.term.backend().vt100().screen().contents();
   assert_contains!(rows, String::from("first"));
   ```

### 具体测试用例分析

#### 1. `long_token_wraps`

验证超长 token 的换行不会丢失字符：

```rust
let long = "A".repeat(45); // > 2 lines at width 20
let lines = vec![long.clone().into()];
scenario.run_insert(lines);

// 统计屏幕上 'A' 的数量
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
assert_eq!(count_a, long.len(), "wrapped content did not preserve all characters");
```

#### 2. `emoji_and_cjk`

验证宽字符（Emoji 宽度为 2，CJK 字符宽度为 2）正确处理：

```rust
let text = String::from("😀😀😀😀😀 你好世界");
let lines = vec![text.clone().into()];
scenario.run_insert(lines);

let rows = scenario.term.backend().vt100().screen().contents();
for ch in text.chars().filter(|c| !c.is_whitespace()) {
    assert!(rows.contains(ch), "missing character {ch:?} in reconstructed screen");
}
```

#### 3. `word_wrap_no_mid_word_split`

验证单词换行不会截断单词（使用 `textwrap` 库）：

```rust
let sample = "Years passed, and Willowmere thrived...";
scenario.run_insert(vec![sample.into()]);
let joined = scenario.term.backend().vt100().screen().contents();
assert!(
    !joined.contains("bo\nth"),  // "both" 不应该被分割为 "bo" + "th"
    "word 'both' should not be split across lines:\n{joined}"
);
```

#### 4. `cursor_restoration`

验证光标位置在插入后恢复：

```rust
let lines = vec!["x".into()];
scenario.run_insert(lines);
assert_eq!(scenario.term.last_known_cursor_pos, (0, 0).into());
```

### 辅助宏

```rust
macro_rules! assert_contains {
    ($collection:expr, $item:expr $(,)?) => {
        assert!(
            $collection.contains(&$item),
            "Expected {:?} to contain {:?}",
            $collection,
            $item
        );
    };
    // ... 重载版本
}
```

## 关键代码路径与文件引用

### 测试文件

| 文件 | 作用 |
|------|------|
| `tests/suite/vt100_history.rs` | 本测试文件 |
| `tests/test_backend.rs` | `VT100Backend` 定义 |
| `tests/all.rs` | 测试套件入口 |

### 被测代码

| 文件 | 相关功能 |
|------|----------|
| `src/insert_history.rs` | 历史记录插入核心实现 |
| `src/wrapping.rs` | 文本换行逻辑（URL 感知） |
| `src/custom_terminal.rs` | 自定义终端实现 |

### 依赖 Crate

| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟 |
| `ratatui` | TUI 框架 |
| `textwrap` | 文本换行算法 |

## 依赖与外部交互

### 特性门控

```rust
#![cfg(feature = "vt100-tests")]
```

测试仅在启用 `vt100-tests` 特性时编译和运行。

### VT100Backend

```rust
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}
```

`VT100Backend` 包装了 `vt100::Parser`，可以：
- 接收 ANSI 转义序列
- 模拟 VT100 终端状态
- 查询屏幕内容、光标位置等

### insert_history_lines 调用链

```
insert_history_lines(terminal, lines)
├── 计算换行宽度
├── 判断 URL 类型（是否仅包含 URL、混合内容等）
├── 调用 adaptive_wrap_line 进行智能换行
├── 设置滚动区域（DECSTBM）
├── 输出 Reverse Index（ESC M）滚动视口
├── 逐行输出内容
│   ├── 处理多行 URL 的清屏
│   ├── 设置颜色样式
│   └── 输出文本 span
├── 恢复滚动区域
└── 恢复光标位置
```

## 风险、边界与改进建议

### 当前风险

1. **特性门控依赖**: 测试需要显式启用 `vt100-tests` 特性，CI 配置需要确保覆盖

2. **测试覆盖有限**: 未覆盖以下场景：
   - 终端 resize 后的历史记录插入
   - 极端长行（超过屏幕缓冲区）
   - 复杂的嵌套 ANSI 序列
   - RTL（从右到左）文本
   - 组合字符（如带变音符号的字符）

3. **硬编码尺寸**: 测试使用固定的终端尺寸（20x6, 40x10 等），可能无法发现尺寸相关的问题

4. **VT100 模拟限制**: `vt100` crate 可能无法完全模拟所有真实终端行为

### 边界情况

1. **视口位置**: 测试将视口设置在屏幕底部（y=5 或 y=9），验证向上插入逻辑
2. **空输入**: 未测试空行列表的插入
3. **零宽度字符**: 未测试零宽度连接符等 Unicode 特性
4. **颜色继承**: `mixed_ansi_spans` 测试简单颜色，未测试复杂样式继承

### 改进建议

1. **增加边界测试**:
   ```rust
   #[test]
   fn empty_lines_insertion() {
       let area = Rect::new(0, 5, 20, 1);
       let mut scenario = TestScenario::new(20, 6, area);
       scenario.run_insert(vec![]);
       // 验证无变化或正确处理
   }

   #[test]
   fn zero_width_joiner() {
       // 测试 emoji 组合序列
       let text = "👨‍👩‍👧‍👦";  // 家庭 emoji，由多个 emoji 组合
       // ...
   }
   ```

2. **参数化测试**: 使用不同终端尺寸运行相同测试
   ```rust
   fn run_word_wrap_test(width: u16, height: u16) {
       // 提取通用测试逻辑
   }
   ```

3. **快照测试**: 对于复杂的渲染输出，考虑使用 `insta` 进行快照测试
   ```rust
   insta::assert_snapshot!(scenario.term.backend().vt100().screen().contents());
   ```

4. **性能测试**: 测试大量历史记录插入的性能
   ```rust
   #[test]
   fn large_history_insertion_performance() {
       let lines: Vec<_> = (0..1000).map(|i| format!("Line {}", i).into()).collect();
       // 测量插入时间
   }
   ```

5. **错误处理测试**: 测试 `insert_history_lines` 返回错误的情况
   ```rust
   // 模拟后端写入失败
   ```

6. **文档增强**: 为每个测试添加更详细的注释，说明测试的具体场景和预期行为

7. **与产品代码合并**: 考虑将这些测试移到 `insert_history.rs` 的 `#[cfg(test)]` 模块中，与实现更接近
