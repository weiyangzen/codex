# Diff Render - 三位数行号对齐渲染测试

## 场景与职责

该快照测试验证 TUI 中**大文件 diff 的行号对齐**渲染效果。当文件行数超过 100 行时，行号从 2 位变为 3 位，需要确保所有行的行号列保持正确对齐，避免视觉上的错位。

这是 diff 渲染中一个重要的排版细节，直接影响用户阅读大文件 diff 的体验。

## 功能点目的

1. **动态行号宽度**：根据最大行号自动计算行号列宽度
2. **右对齐显示**：所有行号右对齐，保持整齐
3. **统一列宽**：整个 diff 块使用统一的行号列宽
4. **边界行号测试**：特别验证 99→100 行号变化时的对齐
5. **上下文保留**：大文件中仍能正确显示变更周围的上下文

## 具体技术实现

### 行号宽度计算

```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}

// 示例：
// max_line_number = 97  → width = 2
// max_line_number = 100 → width = 3
// max_line_number = 999 → width = 3
```

### 行号格式化

```rust
let ln_str = line_number.to_string();
let gutter_width = line_number_width.max(1);
let prefix_cols = gutter_width + 1; // +1 for sign column

// 格式化：右对齐，预留空格
let gutter = format!("{ln_str:>gutter_width$} ");
```

### 预处理扫描确定宽度

```rust
// diff_render.rs:549-579
FileChange::Update { unified_diff, .. } => {
    if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
        let mut max_line_number = 0;
        
        // 第一遍扫描：计算最大行号
        for h in patch.hunks() {
            let mut old_ln = h.old_range().start();
            let mut new_ln = h.new_range().start();
            for l in h.lines() {
                match l {
                    diffy::Line::Insert(_) => {
                        max_line_number = max_line_number.max(new_ln);
                        new_ln += 1;
                    }
                    diffy::Line::Delete(_) => {
                        max_line_number = max_line_number.max(old_ln);
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
        
        // 使用统一的 line_number_width 渲染所有行
        let line_number_width = line_number_width(max_line_number);
        // ...
    }
}
```

### 关键代码路径

```rust
// diff_render.rs:1022-1028
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}

// diff_render.rs:849-854
let ln_str = line_number.to_string();
let gutter_width = line_number_width.max(1);
let prefix_cols = gutter_width + 1;

// 格式化行号
let gutter = format!("{ln_str:>gutter_width$} ");
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 行号宽度计算 | `diff_render.rs:1022-1028` | `line_number_width` 函数 |
| Update 渲染 | `diff_render.rs:547-736` | 包含行号扫描和渲染逻辑 |
| 单行渲染 | `diff_render.rs:837-938` | 行号格式化应用 |
| 测试用例 | `diff_render.rs:1648-1673` | `ui_snapshot_apply_update_block_line_numbers_three_digits_text` |

### 测试数据构造

```rust
#[test]
fn ui_snapshot_apply_update_block_line_numbers_three_digits_text() {
    // 构造 110 行的文件，在第 100 行做修改
    let original = (1..=110).map(|i| format!("line {i}\n")).collect::<String>();
    let modified = (1..=110)
        .map(|i| {
            if i == 100 {
                format!("line {i} changed\n")
            } else {
                format!("line {i}\n")
            }
        })
        .collect::<String>();
    let patch = diffy::create_patch(&original, &modified).to_string();
    // ...
}
```

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式解析和创建
2. **ratatui**：终端 UI 渲染框架

### 内部依赖

- `push_wrapped_diff_line_inner_with_theme_and_color_level()` - 单行渲染函数

### 数据流

```
unified_diff string
    ↓ diffy::Patch::from_str()
Patch { hunks: [...] }
    ↓ 扫描所有 hunks
max_line_number = 103
    ↓ line_number_width()
line_number_width = 3
    ↓ 渲染每一行
" 97", " 98", " 99", "100", "101"... (右对齐，宽度 3)
```

## 风险、边界与改进建议

### 潜在风险

1. **行号溢出**：当行号超过 9999 时，4 位行号可能占用过多空间
2. **性能影响**：大文件需要两次遍历（扫描+渲染）
3. **内存占用**：需要保存整个 patch 结构

### 边界情况

1. **行号 0**：理论上不会出现，但代码做了防护（返回宽度 1）
2. **空文件**：max_line_number = 0，宽度为 1
3. **超大文件**：行号位数变化时的对齐（99→100→999→1000）
4. **多 hunk 文件**：不同 hunk 可能有不同的行号范围

### 测试场景分析

当前测试用例构造了特定场景：
- 文件共 110 行
- 修改发生在第 100 行（从 2 位行号变为 3 位行号的边界）
- 显示上下文：97-103 行

验证点：
- 97, 98, 99 使用 3 位列宽右对齐（前面补空格）
- 100 使用 3 位列宽
- 所有行号左边界对齐

### 改进建议

1. **动态调整**：
   - 考虑是否需要在 hunk 级别动态调整行号宽度
   - 当前实现使用全局最大宽度，可能导致小行号前空白过多

2. **配置选项**：
   - 允许用户设置最大行号列宽
   - 提供紧凑模式（最小化行号列宽）

3. **性能优化**：
   - 流式计算最大行号，避免两次遍历
   - 预估行号宽度，避免完整扫描

4. **可读性增强**：
   - 考虑在行号变化处添加视觉提示
   - 千位分隔符（如 1,000）提升大文件可读性

5. **边界测试补充**：
   - 999→1000 行号变化测试
   - 空文件测试
   - 单行文件测试
   - 多 hunk 不同行号范围测试

### 视觉格式说明

```
// 当前输出格式（统一宽度 3）：
"    97  line 97"     // 前面 4 空格缩进 + 2 空格 + "97"
"    98  line 98"
"    99  line 99"
"   100  line 100"    // 前面 4 空格缩进 + "100"
"   100 -line 100"    // 删除行
"   100 +line 100 changed"  // 新增行
"   101  line 101"
```

注意：输出中的缩进包含：
1. 文件级别的 4 空格缩进（`prefix_lines` 添加）
2. 行号列（动态宽度，右对齐）
3. 标记列（`-`/`+`/` `）
4. 内容
