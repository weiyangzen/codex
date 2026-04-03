# 研究文档：ps_output_long_command_snapshot

## 场景与职责

该快照测试验证 `/ps` 命令输出中长命令的截断和显示逻辑。场景是当用户在 Codex TUI 中执行 `/ps` 命令查看后台终端进程列表时，如果某个命令非常长（如复杂的 ripgrep 搜索命令），需要合理地截断显示以保证 UI 的整洁性。

具体职责包括：
- 处理超长命令的显示，避免占用过多屏幕空间
- 提供视觉提示（`[...]`）表明命令已被截断
- 显示命令的最新输出片段（recent chunks）

## 功能点目的

**核心功能**：`UnifiedExecProcessesCell` 负责渲染后台终端进程列表，当命令长度超过限制时需要智能截断。

**从快照内容分析**：
```
/ps

Background terminals

  • rg "foo" src --glob '**/*. [...]
    ↳ searching...
```

可以看到：
1. `/ps` 命令本身以洋红色显示
2. 标题 "Background terminals" 使用粗体
3. 长命令被截断为 `rg "foo" src --glob '**/*. [...]`，使用了 `[...]` 后缀
4. 最新输出片段 `searching...` 以 `↳` 符号前缀显示

## 具体技术实现

### 关键数据结构和算法

**1. UnifiedExecProcessDetails 结构体**（位于 `codex-rs/tui/src/history_cell.rs` 第 657-666 行）：
```rust
#[derive(Debug, Clone)]
pub(crate) struct UnifiedExecProcessDetails {
    pub(crate) command_display: String,
    pub(crate) recent_chunks: Vec<String>,
}
```

**2. 命令截断逻辑**（第 689-707 行）：
- 首先检查命令是否包含换行符，如果有则只取第一行
- 使用 `grapheme_indices` 限制最大显示 80 个 graphemes
- 根据可用宽度计算是否需要添加 `[...]` 后缀
- 使用 `take_prefix_by_width` 函数精确控制显示宽度

**3. 关键参数**：
```rust
let max_graphemes = 80;
let truncation_suffix = " [...]";
let max_processes = 16usize;  // 最多显示 16 个进程
```

**4. 渲染流程**：
1. 检查 `width == 0`，避免除以零错误
2. 添加标题 "Background terminals"
3. 遍历进程列表，对每个进程：
   - 截断命令显示（带 `[...]` 后缀）
   - 渲染最新输出片段（带 `↳` 前缀）
4. 如果进程超过 16 个，显示 "... and N more running"

### 宽度计算

```rust
let prefix = "  • ";
let prefix_width = UnicodeWidthStr::width(prefix);
let budget = wrap_width.saturating_sub(prefix_width);
```

可用宽度 = 总宽度 - 前缀宽度（4 个字符）

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 包含 `UnifiedExecProcessesCell` 和 `UnifiedExecProcessDetails` 的实现 |
| `codex-rs/tui/src/live_wrap.rs` | 包含 `take_prefix_by_width` 函数用于宽度敏感的文本截断 |

### 关键函数

1. **`new_unified_exec_processes_output`**（第 772-778 行）：
   ```rust
   pub(crate) fn new_unified_exec_processes_output(
       processes: Vec<UnifiedExecProcessDetails>,
   ) -> CompositeHistoryCell {
       let command = PlainHistoryCell::new(vec!["/ps".magenta().into()]);
       let summary = UnifiedExecProcessesCell::new(processes);
       CompositeHistoryCell::new(vec![Box::new(command), Box::new(summary)])
   }
   ```

2. **`UnifiedExecProcessesCell::display_lines`**（第 662-770 行）：核心渲染逻辑

3. **`take_prefix_by_width`**（位于 `live_wrap.rs`）：用于精确控制文本显示宽度

### 测试代码位置

测试位于 `codex-rs/tui/src/history_cell.rs` 第 2821-2831 行：
```rust
#[test]
fn ps_output_long_command_snapshot() {
    let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
        command_display: String::from(
            "rg \"foo\" src --glob '**/*.rs' --max-count 1000 --no-ignore --hidden --follow --glob '!target/**'",
        ),
        recent_chunks: vec!["searching...".to_string()],
    }]);
    let rendered = render_lines(&cell.display_lines(36)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `unicode_width` | 计算字符串的显示宽度（处理 Unicode） |
| `unicode_segmentation` | Grapheme 级别的文本处理 |
| `ratatui` | 终端 UI 渲染框架 |

### 内部模块依赖

- `crate::live_wrap::take_prefix_by_width`：宽度敏感的文本截断
- `crate::render::line_utils`：行处理工具

### 协议/接口

- 输入：`Vec<UnifiedExecProcessDetails>` 包含命令显示文本和最近输出块
- 输出：`Vec<Line<'static>>` 用于 ratatui 渲染

## 风险、边界与改进建议

### 潜在风险

1. **Unicode 处理风险**：
   - 使用 grapheme 计数而非字节计数，但在截断时可能切断组合字符
   - 某些终端对 emoji 或宽字符的宽度计算可能与 `unicode_width` 不一致

2. **宽度计算边界**：
   - 当 `width <= prefix_width` 时，只显示前缀，可能导致信息完全丢失
   - 极端窄宽度下的用户体验不佳

3. **截断逻辑问题**：
   - 当前固定 80 graphemes 的限制可能不适合所有屏幕尺寸
   - 没有考虑 CJK 字符的宽度差异

### 边界情况

1. **空进程列表**：由 `ps_output_empty_snapshot` 测试覆盖
2. **多行命令**：只显示第一行，添加截断标记
3. **超多进程**：超过 16 个时显示 "... and N more running"
4. **零宽度终端**：提前返回空向量

### 改进建议

1. **动态截断限制**：
   ```rust
   // 建议根据终端宽度动态调整
   let max_graphemes = (wrap_width as f32 * 0.8) as usize;
   ```

2. **更好的 Unicode 支持**：
   - 使用 `unicode_segmentation` 的 `GraphemeCursor` 避免切断组合字符
   - 考虑使用 `wcwidth` 替代 `unicode_width` 以获得更准确的终端宽度

3. **可配置性**：
   - 将 `max_processes` 和 `max_graphemes` 作为配置参数
   - 允许用户自定义截断后缀

4. **性能优化**：
   - 对大量进程（>100）使用虚拟列表，避免一次性渲染所有行
   - 缓存截断结果，避免重复计算

5. **可访问性**：
   - 添加键盘快捷键查看完整命令（如按 Enter 展开）
   - 在截断处添加悬停提示显示完整命令
