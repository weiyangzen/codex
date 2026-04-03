# 研究文档：ps_output_multiline_snapshot

## 场景与职责

该快照测试验证 `/ps` 命令输出中多行命令的处理逻辑。当后台终端进程的命令包含换行符时（例如复杂的 shell 脚本），需要正确处理多行显示，同时展示命令的最新输出片段。

**核心职责**：
- 处理包含换行符的命令显示
- 显示命令的最新输出片段（recent chunks）
- 使用合适的缩进和视觉层次区分命令和输出

## 功能点目的

**从快照内容分析**：
```
/ps

Background terminals

  • echo hello [...]
    ↳ hello
      done
  • rg "foo" src
    ↳ src/main.rs:12:foo
```

**功能特性**：
1. 多行命令只显示第一行，并添加 `[...]` 后缀表示有更多内容
2. 每个进程的最新输出片段以 `↳` 符号前缀显示
3. 多个输出片段使用不同的缩进级别（第一行 `↳`，后续行空格）
4. 多个进程之间保持清晰的视觉分隔

## 具体技术实现

### 多行命令处理逻辑

**代码位置**：`codex-rs/tui/src/history_cell.rs` 第 689-707 行

```rust
let (snippet, snippet_truncated) = {
    // 1. 分割第一行和剩余部分
    let (first_line, has_more_lines) = match command.split_once('\n') {
        Some((first, _)) => (first, true),
        None => (command.as_str(), false),
    };
    
    // 2. 限制 grapheme 数量
    let max_graphemes = 80;
    let mut graphemes = first_line.grapheme_indices(true);
    if let Some((byte_index, _)) = graphemes.nth(max_graphemes) {
        (first_line[..byte_index].to_string(), true)
    } else {
        (first_line.to_string(), has_more_lines)
    }
};
```

### 输出片段渲染

**代码位置**：第 724-754 行

```rust
let chunk_prefix_first = "    ↳ ";
let chunk_prefix_next = "      ";

for (idx, chunk) in process.recent_chunks.iter().enumerate() {
    let chunk_prefix = if idx == 0 {
        chunk_prefix_first
    } else {
        chunk_prefix_next
    };
    // 宽度检查和截断逻辑...
    out.push(vec![chunk_prefix.dim(), truncated.dim()].into());
}
```

### 关键参数

| 参数 | 值 | 说明 |
|-----|---|------|
| `chunk_prefix_first` | `"    ↳ "` | 第一个输出片段的前缀（6 字符） |
| `chunk_prefix_next` | `"      "` | 后续输出片段的前缀（6 字符） |
| `max_graphemes` | 80 | 命令显示的最大 grapheme 数 |
| `truncation_suffix` | `" [...]"` | 截断提示后缀 |

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `UnifiedExecProcessesCell` 实现 |

### 测试代码

**位置**：第 2805-2819 行

```rust
#[test]
fn ps_output_multiline_snapshot() {
    let cell = new_unified_exec_processes_output(vec![
        UnifiedExecProcessDetails {
            command_display: "echo hello\nand then some extra text".to_string(),
            recent_chunks: vec!["hello".to_string(), "done".to_string()],
        },
        UnifiedExecProcessDetails {
            command_display: "rg \"foo\" src".to_string(),
            recent_chunks: vec!["src/main.rs:12:foo".to_string()],
        },
    ]);
    let rendered = render_lines(&cell.display_lines(40)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 核心渲染函数

```rust
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 宽度检查
        if width == 0 {
            return Vec::new();
        }

        let wrap_width = width as usize;
        let mut out: Vec<Line<'static>> = Vec::new();
        
        // 2. 添加标题
        out.push(vec!["Background terminals".bold()].into());
        out.push("".into());

        // 3. 遍历进程
        for process in &self.processes {
            // 3.1 处理命令显示（截断第一行）
            let command = &process.command_display;
            let (first_line, has_more_lines) = match command.split_once('\n') {
                Some((first, _)) => (first, true),
                None => (command.as_str(), false),
            };
            // ... 截断和渲染逻辑 ...

            // 3.2 处理输出片段
            for (idx, chunk) in process.recent_chunks.iter().enumerate() {
                let chunk_prefix = if idx == 0 { "    ↳ " } else { "      " };
                // ... 渲染逻辑 ...
            }
        }

        out
    }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `unicode_segmentation::UnicodeSegmentation` | Grapheme 级别的文本处理 |
| `unicode_width::UnicodeWidthStr` | 计算字符串显示宽度 |
| `ratatui::prelude::*` | 终端 UI 渲染 |

### 内部依赖

- `crate::live_wrap::take_prefix_by_width`：宽度敏感的文本截断

### 数据结构关系

```
CompositeHistoryCell
├── PlainHistoryCell("/ps")
└── UnifiedExecProcessesCell
    └── Vec<UnifiedExecProcessDetails>
        ├── command_display: String
        └── recent_chunks: Vec<String>
```

## 风险、边界与改进建议

### 潜在风险

1. **换行符处理不一致**：
   - 使用 `\n` 作为换行符，但在 Windows 上可能是 `\r\n`
   - `split_once('\n')` 会保留 `\r`，可能导致显示问题

2. **输出片段数量无限制**：
   - `recent_chunks` 向量没有长度限制
   - 如果 chunks 过多，可能占用大量屏幕空间

3. **缩进硬编码**：
   - 前缀长度硬编码为 6 字符
   - 如果修改前缀，需要同步修改宽度计算

### 边界情况

| 场景 | 行为 | 评估 |
|-----|------|------|
| 命令只有换行符 | 第一行为空，显示 `[...]` | ⚠️ 可能显示异常 |
| 输出片段为空 | 不显示任何输出 | ✅ 合理 |
| 输出片段包含换行 | 只显示第一行 | ⚠️ 信息丢失 |
| 多个输出片段 | 使用不同前缀区分 | ✅ 清晰 |

### 改进建议

1. **统一换行符处理**：
   ```rust
   let command = command_display.replace("\r\n", "\n").replace('\r', '\n');
   ```

2. **限制输出片段数量**：
   ```rust
   let max_chunks = 3;
   for (idx, chunk) in process.recent_chunks.iter().take(max_chunks).enumerate() {
       // ...
   }
   if process.recent_chunks.len() > max_chunks {
       out.push("      ...".dim().into());
   }
   ```

3. **显示多行输出**：
   ```rust
   // 支持输出片段中的换行
   for line in chunk.lines() {
       out.push(vec![chunk_prefix.dim(), line.dim()].into());
   }
   ```

4. **配置化前缀**：
   ```rust
   struct DisplayConfig {
       chunk_prefix_first: &'static str,
       chunk_prefix_next: &'static str,
       chunk_prefix_width: usize,  // 自动计算
   }
   ```

5. **添加悬停提示**：
   - 当命令被截断时，添加悬停提示显示完整命令
   - 对于多行命令，提供展开/折叠功能

6. **改进视觉层次**：
   ```rust
   // 使用不同颜色区分命令和输出
   out.push(vec![prefix.dim(), truncated.cyan()].into());  // 命令用青色
   out.push(vec![chunk_prefix.dim(), truncated.white()].into());  // 输出用白色
   ```
