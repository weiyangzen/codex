# Syntax Highlighted Insert Wraps - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__syntax_highlighted_insert_wraps.snap`

## Snapshot Content
```
"1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin          "
"   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o          "
"   ne) }                                                                                  "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **带语法高亮的插入行长行换行渲染效果**。当新增代码行包含语法高亮且超出终端宽度时，系统需要正确换行并保持语法高亮样式。

### 1.2 业务职责
- **语法高亮保持**: 换行后保持语法高亮样式
- **样式分割**: 在样式 span 边界处分割，避免样式断裂
- **视觉对齐**: 换行后的内容正确缩进对齐

### 1.3 与纯文本换行的区别
| 场景 | 处理方式 |
|------|---------|
| 纯文本 | 按字符截断 |
| 语法高亮 | 在样式 span 边界处分割，保持样式连续性 |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
测试 Rust 代码的语法高亮换行：
- 函数定义（`fn` 关键字）
- 参数列表（类型标注）
- 返回类型（`Result<...>`）
- 函数体（`{ Ok(arg_one) }`）

### 2.2 语法高亮保持
```rust
fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }
```

换行后：
- `fn` 关键字保持高亮
- 类型名称保持高亮
- 字符串保持高亮

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 语法高亮换行
```rust
// diff_render.rs:951-1020
fn wrap_styled_spans(
    spans: &[RtSpan<'static>],
    max_cols: usize,
) -> Vec<Vec<RtSpan<'static>>> {
    // 在 span 边界处分割，保持样式
    // ...
}
```

### 3.2 测试实现
```rust
// diff_render.rs:1729-1763
#[test]
fn ui_snapshot_syntax_highlighted_insert_wraps() {
    let long_rust = "fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }";
    
    let syntax_spans =
        highlight_code_to_styled_spans(long_rust, "rust").expect("rust highlighting");
    let spans = &syntax_spans[0];
    
    let lines = push_wrapped_diff_line_with_syntax_and_style_context(
        1,
        DiffLineType::Insert,
        long_rust,
        80,
        line_number_width(1),
        spans,
        current_diff_render_style_context(),
    );
    
    snapshot_lines("syntax_highlighted_insert_wraps", lines, 80, 10);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染和换行 |
| `tui_app_server/src/render/highlight.rs` | 语法高亮 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `syntect` | 语法高亮引擎 |
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 样式断裂 | 在 span 中间分割可能导致样式断裂 | 在 span 边界处分割 |
| 性能 | 大量样式 span 可能影响性能 | 限制高亮范围 |

### 6.2 改进建议
1. **语义换行**: 在语义边界（如逗号后）换行
2. **样式合并**: 合并相邻的相同样式 span

---

## 7. 相关文档链接

- [Syntax Highlighted Insert Wraps Text](../codex_tui_app_server__diff_render__tests__syntax_highlighted_insert_wraps_text.snap_research.md)
