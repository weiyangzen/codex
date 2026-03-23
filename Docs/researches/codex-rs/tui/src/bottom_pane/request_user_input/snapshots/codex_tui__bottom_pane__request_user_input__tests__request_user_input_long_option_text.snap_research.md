# 研究文档: request_user_input_long_option_text.snap

## 场景与职责

本快照文件测试 **超长选项文本的自动换行** 渲染。当选项的标签（label）或描述（description）过长时，系统需要智能地进行文本换行，确保内容可读且布局美观。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2636-2653 行。

## 功能点目的

### 核心功能
1. **标签换行**: 选项标签过长时在适当位置换行
2. **描述对齐**: 描述文本与标签的第二行及以后对齐
3. **缩进保持**: 换行后的文本保持适当的缩进，维持视觉层次

### 测试场景设计

测试数据包含两个极端选项：
1. **超长标签**: 
   ```
   "Job: running/completed/failed/expired; Run/Experiment: succeeded/failed/unknown (Recommended when triaging long-running background work and status transitions)"
   ```
2. **长描述**: 
   ```
   "Keep async job statuses for progress tracking and include enough context for debugging retries, stale workers, and unexpected expiration paths."
   ```

## 具体技术实现

### 数据结构

```rust
// 选项行数据结构 (GenericDisplayRow)
pub struct GenericDisplayRow {
    pub name: String,           // 显示名称（带前缀如 "› 1. "）
    pub description: Option<String>,
    pub wrap_indent: Option<usize>,  // 换行后的缩进量
    // ...
}
```

### 关键流程

1. **选项行生成** (`option_rows`, mod.rs 第 268-312 行):
   ```rust
   pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
       // ...
       let prefix_label = format!("{prefix} {number}. ");
       let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
       GenericDisplayRow {
           name: format!("{prefix_label}{label}"),
           description: Some(opt.description.clone()),
           wrap_indent: Some(wrap_indent),  // 关键：计算缩进宽度
           ..Default::default()
       }
   }
   ```

2. **渲染换行** (`render_rows`, selection_popup_common.rs):
   ```rust
   // 使用 wrap_styled_line 进行智能换行
   // 考虑 wrap_indent 保持对齐
   ```

3. **高度计算** (`options_required_height`, mod.rs 第 314-333 行):
   ```rust
   pub(super) fn options_required_height(&self, width: u16) -> u16 {
       let rows = self.option_rows();
       measure_rows_height(&rows, &state, rows.len(), width.max(1))
   }
   ```

### 渲染输出分析

```
  Question 1/1 (1 unanswered)
  Choose one option.

  › 1. Job: running/completed/failed/expired; Run/Experiment: succeeded/failed/    Keep async job statuses for
       unknown (Recommended when triaging long-running background work and status  progress tracking and include
       transitions)                                                                enough context for debugging
                                                                                   retries, stale workers, and
                                                                                   unexpected expiration paths.

    2. Add a short status model                                                    Simpler labels with less detail for
                                                                                   quick rollouts.
```

关键观察：
- 选项1的标签在第1行后换行，保持与 "› 1. " 后的对齐
- 描述文本与标签的第二行对齐
- 选项2的描述也正确换行

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 选项行生成、缩进计算 |
| `selection_popup_common.rs` | 通用行渲染、换行处理 |
| `render.rs` | 整体渲染协调 |

### 关键代码位置

1. **选项行生成**: `mod.rs:268-312`
2. **缩进计算**: `mod.rs:284` (`UnicodeWidthStr::width`)
3. **测试数据**: `mod.rs:1391-1409` (`question_with_very_long_option_text`)
4. **测试用例**: `mod.rs:2636-2653`

### 辅助函数

```rust
// selection_popup_common.rs
pub fn measure_rows_height(
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    width: u16,
) -> u16 {
    // 计算考虑换行后的总高度
}
```

## 依赖与外部交互

### Unicode 宽度计算

```rust
use unicode_width::UnicodeWidthStr;

// 计算字符串的显示宽度（考虑宽字符）
let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
```

### 文本换行库

```rust
// 使用 textwrap 进行文本换行
use textwrap::wrap;

// 在 wrapped_question_lines 中使用
pub(super) fn wrapped_question_lines(&self, width: u16) -> Vec<String> {
    textwrap::wrap(&q.question, width.max(1) as usize)
        .into_iter()
        .map(|line| line.to_string())
        .collect()
}
```

## 风险、边界与改进建议

### 潜在风险

1. **缩进计算错误**: 如果前缀包含宽字符（如中文），`UnicodeWidthStr::width` 计算可能不准确
2. **极端长文本**: 单行文本超过宽度限制多次时，高度计算可能不准确
3. **描述与标签错位**: 当标签换行次数与描述不一致时，视觉对齐可能出现问题

### 边界情况

| 场景 | 当前处理 |
|------|---------|
| 标签为空 | 显示空行 |
| 描述为空 | 只显示标签 |
| 宽度为 0 | 返回最小高度 1 |
| 包含换行符 | 由 textwrap 处理 |

### 改进建议

1. **最大高度限制**: 为单个选项设置最大高度，防止极端长文本占用过多空间
2. **截断指示**: 当内容被截断时显示 "..." 或展开按钮
3. **响应式缩进**: 根据内容动态调整缩进，而不是固定基于前缀
4. **性能优化**: 缓存换行结果，避免重复计算

### 测试覆盖

当前测试验证：
- ✅ 超长标签换行
- ✅ 长描述换行
- ✅ 缩进对齐

建议添加：
- 包含宽字符（中文、日文）的选项
- 包含制表符或特殊空白字符的选项
- 极端窄宽度下的渲染

### 代码优化建议

```rust
// 当前：每次渲染都重新计算行
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    // 每次都重新生成
}

// 建议：添加缓存机制
pub(super) fn option_rows(&mut self) -> &[GenericDisplayRow] {
    // 如果问题未改变，返回缓存结果
}
```
