# vt100_live_commit.rs 研究文档

## 场景与职责

`codex-rs/tui/tests/suite/vt100_live_commit.rs` 验证实时流式输出时的行提交机制。测试 `live_wrap::RowBuilder` 的 `drain_commit_ready` 功能，确保当环形缓冲区溢出时，旧的行被正确提交到历史记录。

**核心场景**: 在 AI 响应流式输出时，TUI 使用环形缓冲区显示"实时"内容。当缓冲区达到容量上限时，最旧的行应该被"提交"（移动到历史记录），而不是被丢弃。

## 功能点目的

1. **环形缓冲区管理**: 验证 `RowBuilder` 的容量限制和溢出处理
2. **行提交机制**: 确保旧行在溢出时正确提交到历史
3. **数据完整性**: 验证提交的行内容完整无损
4. **实时流模拟**: 测试流式输出场景下的数据流

## 具体技术实现

### 测试架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Test: live_001_commit_on_overflow                              │
├─────────────────────────────────────────────────────────────────┤
│  1. 创建 20x6 的 VT100 终端                                      │
│  2. 设置视口在最后一行（y=5）                                     │
│  3. 使用 RowBuilder 构建 5 行文本（每行 20 字符）                 │
│  4. 调用 drain_commit_ready(3) 保留最后 3 行                     │
│  5. 将提交的 2 行插入历史记录                                     │
│  6. 验证 "one" 和 "two" 出现在屏幕上                              │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码解析

#### 测试用例
```rust
#[test]
fn live_001_commit_on_overflow() {
    // 创建 20x6 的 VT100 后端
    let backend = VT100Backend::new(20, 6);
    let mut term = match codex_tui::custom_terminal::Terminal::with_options(backend) {
        Ok(t) => t,
        Err(e) => panic!("failed to construct terminal: {e}"),
    };
    
    // 设置视口在最后一行（高度 1，位于 y=5）
    let area = Rect::new(0, 5, 20, 1);
    term.set_viewport_area(area);

    // 构建 5 行显式文本，每行宽度 20
    let mut rb = codex_tui::live_wrap::RowBuilder::new(20);
    rb.push_fragment("one\n");
    rb.push_fragment("two\n");
    rb.push_fragment("three\n");
    rb.push_fragment("four\n");
    rb.push_fragment("five\n");

    // 保留最后 3 行在环形缓冲区，提交前 2 行
    let commit_rows = rb.drain_commit_ready(3);
    let lines: Vec<Line<'static>> = commit_rows.into_iter()
        .map(|r| r.text.into())
        .collect();

    // 将提交的行插入历史记录
    codex_tui::insert_history::insert_history_lines(&mut term, lines)
        .expect("Failed to insert history lines in test");

    // 验证提交的行出现在屏幕上
    let screen = term.backend().vt100().screen();
    let joined = screen.contents();
    assert!(joined.contains("one"), "expected committed 'one' to be visible");
    assert!(joined.contains("two"), "expected committed 'two' to be visible");
    // "three", "four", "five" 仍保留在 live ring 中，此处未验证
}
```

### RowBuilder 状态转换

```
初始状态:
┌─────────────────────────────────────┐
│ RowBuilder {                        │
│   target_width: 20,                 │
│   current_line: "",                 │
│   rows: []                          │
│ }                                   │
└─────────────────────────────────────┘

push_fragment("one\n") 后:
┌─────────────────────────────────────┐
│ rows: [Row { text: "one", explicit_break: true }] │
└─────────────────────────────────────┘

... 推送全部 5 行后:
┌─────────────────────────────────────┐
│ rows: [                             │
│   Row { text: "one", explicit_break: true },
│   Row { text: "two", explicit_break: true },
│   Row { text: "three", explicit_break: true },
│   Row { text: "four", explicit_break: true },
│   Row { text: "five", explicit_break: true },
│ ]                                   │
└─────────────────────────────────────┘

drain_commit_ready(3) 后:
┌─────────────────────────────────────┐
│ 返回: [                             │
│   Row { text: "one", ... },         │
│   Row { text: "two", ... },         │
│ ]                                   │
│                                     │
│ rows 剩余: [                        │
│   Row { text: "three", ... },       │
│   Row { text: "four", ... },        │
│   Row { text: "five", ... },        │
│ ]                                   │
└─────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 核心被测代码
| 文件 | 结构/函数 | 功能 |
|------|-----------|------|
| `codex-rs/tui/src/live_wrap.rs` | `RowBuilder` | 实时行构建和换行 |
| `codex-rs/tui/src/live_wrap.rs` | `RowBuilder::drain_commit_ready()` | 溢出行提取 |
| `codex-rs/tui/src/insert_history.rs` | `insert_history_lines()` | 历史记录插入 |

### RowBuilder 关键实现
```rust
pub struct RowBuilder {
    target_width: usize,
    current_line: String,
    rows: Vec<Row>,
}

impl RowBuilder {
    /// Drain the oldest rows that exceed `max_keep` display rows
    pub fn drain_commit_ready(&mut self, max_keep: usize) -> Vec<Row> {
        let display_count = self.rows.len() + 
            if self.current_line.is_empty() { 0 } else { 1 };
        
        if display_count <= max_keep {
            return Vec::new();  // 未溢出，无需提交
        }
        
        let to_commit = display_count - max_keep;
        let commit_count = to_commit.min(self.rows.len());
        
        let mut drained = Vec::with_capacity(commit_count);
        for _ in 0..commit_count {
            drained.push(self.rows.remove(0));  // 从头部移除最旧的行
        }
        drained
    }
}
```

### Row 结构
```rust
pub struct Row {
    pub text: String,
    /// True if this row ends with an explicit line break
    pub explicit_break: bool,
}
```

## 依赖与外部交互

### Feature 标志
```rust
#![cfg(feature = "vt100-tests")]
```

### 依赖模块
| 模块 | 路径 | 用途 |
|------|------|------|
| VT100Backend | `codex-rs/tui/src/test_backend.rs` | 测试终端后端 |
| custom_terminal | `codex-rs/tui/src/custom_terminal.rs` | 自定义终端 |
| insert_history | `codex-rs/tui/src/insert_history.rs` | 历史插入 |
| live_wrap | `codex-rs/tui/src/live_wrap.rs` | 实时换行 |

### 测试执行
```bash
cargo test -p codex-tui --features vt100-tests live_001_commit_on_overflow
```

## 风险、边界与改进建议

### 风险
1. **单一测试**: 仅有一个基础测试用例，覆盖有限
2. **硬编码尺寸**: 使用固定 20x6 屏幕和 20 字符宽度
3. **无溢出验证**: 未测试 `max_keep` 大于实际行数的情况

### 边界条件
- 测试假设所有行都有 `explicit_break = true`（显式换行）
- 不测试部分行（`current_line` 非空）的场景
- 不测试 `set_width` 动态调整宽度后的行为

### 改进建议
1. **扩展测试覆盖**:
   - 添加 `max_keep` 大于行数的测试（应返回空）
   - 测试 `max_keep = 0`（提交所有行）
   - 测试包含 `current_line` 的部分行场景
   - 测试动态宽度调整后的 `drain_commit_ready`

2. **集成测试增强**:
   - 测试与真实流式输出管道的集成
   - 验证高频率提交的性能
   - 测试并发场景下的线程安全

3. **文档改进**:
   - 在 `live_wrap.rs` 中添加更多使用示例
   - 明确 `drain_commit_ready` 的契约和边界条件

4. **代码重构建议**:
   - 考虑使用 `VecDeque` 替代 `Vec` 优化头部移除性能
   - 添加 `drain_commit_ready` 的单元测试到 `live_wrap.rs`
