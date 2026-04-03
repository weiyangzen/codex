# PS 输出块前导空白测试快照研究文档

## 场景与职责

本快照测试验证 **UnifiedExecProcessesCell** 对后台进程输出（`/ps` 命令）的渲染，特别是当进程输出块包含**前导空白字符**（缩进）时的正确处理。这是后台终端管理功能的一部分，确保进程输出的原始格式（包括缩进）被正确保留和展示。

测试场景：
- 执行 `/ps` 命令查看后台终端
- 进程 `just fix` 有输出块
- 输出块包含前导空格（`  indented first` 和 `    more indented`）
- 验证前导空白被正确保留和展示

## 功能点目的

### 核心功能
1. **后台进程展示**：展示当前运行的后台终端进程列表
2. **输出块保留**：保留进程输出的原始格式，包括缩进
3. **前导空白处理**：正确处理输出中的前导空格和制表符

### 展示目标
- 命令行显示 `/ps`
- 标题显示 "Background terminals"
- 每个进程显示命令和最近的输出块
- 输出块保留原始缩进

## 具体技术实现

### 数据结构

```rust
// UnifiedExecProcessDetails（history_cell.rs:657）
#[derive(Debug, Clone)]
pub(crate) struct UnifiedExecProcessDetails {
    pub(crate) command_display: String,
    pub(crate) recent_chunks: Vec<String>,  // 可能包含前导空白的输出块
}

// UnifiedExecProcessesCell（history_cell.rs:646）
#[derive(Debug)]
struct UnifiedExecProcessesCell {
    processes: Vec<UnifiedExecProcessDetails>,
}
```

### 关键渲染逻辑

位于 `history_cell.rs` 的 `UnifiedExecProcessesCell::display_lines` 方法（行 662-770）：

```rust
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        let chunk_prefix_first = "    ↳ ";
        let chunk_prefix_next = "      ";
        for (idx, chunk) in process.recent_chunks.iter().enumerate() {
            let chunk_prefix = if idx == 0 {
                chunk_prefix_first
            } else {
                chunk_prefix_next
            };
            let chunk_prefix_width = UnicodeWidthStr::width(chunk_prefix);
            if wrap_width <= chunk_prefix_width {
                out.push(Line::from(chunk_prefix.dim()));
                continue;
            }
            let budget = wrap_width.saturating_sub(chunk_prefix_width);
            let (truncated, remainder, _) = take_prefix_by_width(chunk, budget);
            if !remainder.is_empty() && budget > truncation_suffix_width {
                let available = budget.saturating_sub(truncation_suffix_width);
                let (shorter, _, _) = take_prefix_by_width(chunk, available);
                out.push(
                    vec![chunk_prefix.dim(), shorter.dim(), truncation_suffix.dim()].into(),
                );
            } else {
                out.push(vec![chunk_prefix.dim(), truncated.dim()].into());
            }
        }
        // ...
    }
}
```

### 输出块前缀

```rust
const CHUNK_PREFIX_FIRST: &str = "    ↳ ";  // 6字符：4空格 + ↳ + 1空格
const CHUNK_PREFIX_NEXT: &str = "      ";   // 6空格
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 2848-2858）：

```rust
#[test]
fn ps_output_chunk_leading_whitespace_snapshot() {
    let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
        command_display: "just fix".to_string(),
        recent_chunks: vec![
            "  indented first".to_string(),    // 2空格前导
            "    more indented".to_string(),   // 4空格前导
        ],
    }]);
    let rendered = render_lines(&cell.display_lines(60)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
/ps

Background terminals

  • just fix
    ↳   indented first
          more indented
```

输出结构解析：
1. `/ps` - 命令行（品红色）

2. `Background terminals` - 标题（粗体）

3. `  • just fix` - 进程命令
   - `  • ` - 项目符号前缀（2空格 + 点 + 1空格）
   - `just fix` - 命令显示（青色）

4. `    ↳   indented first` - 第一个输出块
   - `    ↳ ` - 输出块前缀（4空格 + ↳ + 1空格）
   - `  indented first` - 原始内容（2空格前导 + 文本）
   - **注意**：合并后显示为 6空格 + 文本

5. `          more indented` - 第二个输出块
   - `      ` - 续行前缀（6空格）
   - `    more indented` - 原始内容（4空格前导 + 文本）
   - **注意**：合并后显示为 10空格 + 文本

**前导空白保留验证**：
- 原始：`"  indented first"`（2空格）
- 展示：`"    ↳   indented first"`（4空格前缀 + 2空格内容 = 6空格）
- 原始：`"    more indented"`（4空格）
- 展示：`"          more indented"`（6空格前缀 + 4空格内容 = 10空格）

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，行 646-770 |
| `codex-rs/tui/src/live_wrap.rs` | `take_prefix_by_width` 工具函数 |

### 关键函数
| 函数 | 位置 | 职责 |
|-----|------|------|
| `new_unified_exec_processes_output` | `history_cell.rs:772` | 构造函数 |
| `display_lines` | `history_cell.rs:663` | 渲染方法 |
| `take_prefix_by_width` | `live_wrap.rs` | 按宽度截取字符串 |

### 构造函数

```rust
pub(crate) fn new_unified_exec_processes_output(
    processes: Vec<UnifiedExecProcessDetails>,
) -> CompositeHistoryCell {
    let command = PlainHistoryCell::new(vec!["/ps".magenta().into()]);
    let summary = UnifiedExecProcessesCell::new(processes);
    CompositeHistoryCell::new(vec![Box::new(command), Box::new(summary)])
}
```

## 依赖与外部交互

### 内部依赖
- `unicode_width::UnicodeWidthStr` - Unicode 宽度计算
- `crate::live_wrap::take_prefix_by_width` - 字符串截取

### 字符宽度处理
```rust
let chunk_prefix_width = UnicodeWidthStr::width(chunk_prefix);
let budget = wrap_width.saturating_sub(chunk_prefix_width);
let (truncated, remainder, _) = take_prefix_by_width(chunk, budget);
```

### 缩进计算
| 层级 | 前缀 | 内容前导 | 总前导 |
|-----|------|---------|--------|
| 命令 | `  • ` | - | 2空格 |
| 输出首行 | `    ↳ ` | 2空格 | 6空格 |
| 输出续行 | `      ` | 4空格 | 10空格 |

## 风险、边界与改进建议

### 潜在风险
1. **缩进累积**：多层前缀 + 内容缩进可能导致过度缩进
2. **宽度计算错误**：前导空白宽度计算错误导致截断
3. **制表符处理**：制表符宽度计算可能不一致

### 边界情况
1. **全空白输出**：输出块仅包含空白字符
2. **超长缩进**：内容本身有 20+ 空格缩进
3. **混合缩进**：空格和制表符混合
4. **RTL 文本**：从右到左文本与缩进的交互

### 改进建议

#### 高优先级
1. **制表符标准化**：将制表符转换为固定宽度空格
   ```rust
   fn normalize_indent(text: &str, tab_width: usize) -> String {
       text.replace('\t', &" ".repeat(tab_width))
   }
   ```

2. **缩进限制**：防止过度缩进导致内容不可见
   ```rust
   const MAX_INDENT: usize = 20;
   ```

#### 中优先级
3. **相对缩进**：显示相对于第一行的缩进差异
   ```
   just fix
     ↳ indented first
       +2 more indented  ← 显示相对缩进
   ```

4. **空白可视化**：可选显示空白字符（如 IDE）
   ```
   just fix
     ↳ ··indented first  ← · 表示空格
   ```

#### 低优先级
5. **智能折叠**：折叠深层缩进的内容
6. **代码块检测**：检测输出是否为代码块并应用语法高亮

### 测试建议
1. 增加制表符缩进测试
2. 增加极端缩进测试（100+ 空格）
3. 增加混合空白字符测试
4. 增加 Unicode 空白字符测试（全角空格、不间断空格等）
