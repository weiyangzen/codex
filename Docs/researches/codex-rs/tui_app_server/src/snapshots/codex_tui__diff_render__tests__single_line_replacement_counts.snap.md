# Single Line Replacement Counts 快照研究文档

## 场景与职责

此快照测试展示了**单行替换变更**的渲染效果，即一个文件中的一行被修改（一行删除 + 一行插入）。这是代码审查中最常见的变更类型之一。

### 测试场景
- **文件**: `README.md`
- **变更类型**: 单行替换（`+# Codex CLI (Rust Implementation) banana` 替换 `-# Codex CLI (Rust Implementation)`）
- **统计**: `(+1 -1)` - 一行添加，一行删除

该测试验证 diff 渲染器正确处理最简单的 Update 场景：单行修改的准确计数和展示。

## 功能点目的

### 1. 单行变更统计准确性
- 验证 `calculate_add_remove_from_diff` 函数正确计算增删行数
- 确保 `(+1 -1)` 统计在文件头正确显示

### 2. 单行差异渲染
- 展示删除行（带 `-` 号）和插入行（带 `+` 号）的对比
- 行号对齐：两行都显示行号 `1`，表示同一位置的变更

### 3. "Proposed Change" 标题模式
- 单文件变更时使用 `"Proposed Change {filename}"` 格式
- 与多文件变更的 `"Edited N files"` 格式区分

## 具体技术实现

### 差异解析流程

```rust
// calculate_add_remove_from_diff 函数实现
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

### 单文件头部渲染逻辑

```rust
// render_changes_block 中的单文件处理
if let [row] = &rows[..] {
    let verb = match &row.change {
        FileChange::Add { .. } => "Added",
        FileChange::Delete { .. } => "Deleted",
        _ => "Edited",  // Update 类型使用 "Edited"
    };
    header_spans.push(verb.bold());
    header_spans.push(" ".into());
    header_spans.extend(render_path(row));
    header_spans.push(" ".into());
    header_spans.extend(render_line_count_summary(row.added, row.removed));
}
```

### 行号宽度计算

```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}
```

在本例中，最大行号为 1，因此行号宽度为 1，gutter 格式为 `"{ln_str:>1$} "`。

## 关键代码路径与文件引用

### 核心函数

| 函数名 | 文件 | 职责 |
|--------|------|------|
| `calculate_add_remove_from_diff` | diff_render.rs:764 | 从统一差异计算增删行数 |
| `render_line_count_summary` | diff_render.rs:392 | 渲染 `(+n -m)` 统计 |
| `render_changes_block` | diff_render.rs:402 | 主渲染逻辑，区分单/多文件 |
| `render_change` | diff_render.rs:474 | 根据变更类型渲染差异内容 |

### 依赖的 diffy 类型

```rust
use diffy::Hunk;
use diffy::Patch;
use diffy::Line;  // Insert / Delete / Context
```

### 测试相关

虽然此快照存在于 `tui_app_server/src/snapshots/`，但 `source` 字段指向 `tui/src/diff_render.rs`，表明：
- 原始测试在 `tui` crate 中
- `tui_app_server` 是并行实现，共享相同的快照预期
- 符合 AGENTS.md 中 "TUI code conventions" 的约定

## 依赖与外部交互

### diffy crate 集成

```rust
// Patch 解析
if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
    for h in patch.hunks() {
        let mut old_ln = h.old_range().start();  // 旧文件起始行号
        let mut new_ln = h.new_range().start();  // 新文件起始行号
        for l in h.lines() {
            match l {
                diffy::Line::Insert(_) => { /* 渲染插入行 */ new_ln += 1; }
                diffy::Line::Delete(_) => { /* 渲染删除行 */ old_ln += 1; }
                diffy::Line::Context(_) => { /* 渲染上下文 */ old_ln += 1; new_ln += 1; }
            }
        }
    }
}
```

### 行号追踪机制

对于单行替换 diff：
```diff
--- a/README.md
+++ b/README.md
@@ -1 +1 @@
-# Codex CLI (Rust Implementation)
+# Codex CLI (Rust Implementation) banana
```

- 旧文件行号从 1 开始，删除后递增到 2
- 新文件行号从 1 开始，插入后递增到 2
- 两行都显示为 `1`，表示同一逻辑位置

## 风险、边界与改进建议

### 边界情况

1. **空 diff 处理**
   - 如果 `Patch::from_str` 失败，返回 `(0, 0)` 计数
   - 可能导致统计与实际变更不符

2. **行号宽度变化**
   - 当变更涉及行号位数变化（如从 9 行到 10 行）
   - 当前实现使用统一的最大宽度，确保对齐

3. **纯添加/删除 vs 替换**
   - 纯添加：只显示 `+` 行，统计 `(+n -0)`
   - 纯删除：只显示 `-` 行，统计 `(+0 -n)`
   - 替换：同时显示 `-` 和 `+` 行，统计 `(+n -n)`

### 潜在风险

1. **diff 解析失败**
   - 如果 `diffy` 无法解析统一差异格式，整个变更块将不显示
   - 建议添加降级处理，至少显示原始内容

2. **统计与内容不一致**
   - 如果 `calculate_add_remove_from_diff` 和实际渲染逻辑不一致
   - 可能导致头部统计与内容行数不匹配

### 改进建议

1. **行内差异高亮**
   - 当前仅展示整行差异
   - 可考虑使用类似 `diff-highlight` 的方式展示行内变更

2. **统计验证**
   - 在 debug 模式下验证统计与实际渲染行数的一致性
   - 添加断言确保 `(+n -m)` 准确

3. **空上下文优化**
   - 当前快照显示大量空行（`" "`）
   - 可考虑动态调整终端高度，避免不必要的空白

4. **测试覆盖**
   - 添加边界测试：最大行号为 0、1、9、10、99、100 等情况
   - 测试 diff 解析失败时的降级行为
