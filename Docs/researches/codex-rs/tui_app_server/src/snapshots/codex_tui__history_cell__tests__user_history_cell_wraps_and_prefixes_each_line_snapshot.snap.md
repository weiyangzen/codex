# UserHistoryCell 文本换行与前缀处理测试

## 场景与职责

该快照测试验证 `UserHistoryCell` 在处理长文本消息时的自动换行和前缀一致性。当用户输入的消息长度超过终端宽度时，TUI需要：

1. 正确地将长文本换行到多行
2. 保持首行和续行的前缀一致性
3. 确保视觉层次清晰

这是终端UI中文本布局的基础功能，直接影响用户体验。

## 功能点目的

### 核心功能
- **自动换行**：根据终端宽度自动将长文本分割到多行
- **前缀一致性**：首行使用 `› ` 前缀，续行使用 `  `（两个空格）缩进
- **宽度计算**：考虑前缀宽度，确保实际内容宽度正确

### 测试场景
```rust
let msg = "one two three four five six seven";
let cell = UserHistoryCell {
    message: msg.to_string(),
    text_elements: Vec::new(),
    local_image_paths: Vec::new(),
    remote_image_urls: Vec::new(),
};
let width: u16 = 12; // 强制换行的窄宽度
```

测试故意使用窄宽度（12字符）来强制产生多行输出。

## 具体技术实现

### 换行宽度计算
```rust
let wrap_width = width
    .saturating_sub(LIVE_PREFIX_COLS + 1) // 考虑前缀和右边距
    .max(1);
```

其中 `LIVE_PREFIX_COLS` 是直播中前缀的列数。

### 文本换行流程

1. **消息预处理**（第317行）：
   ```rust
   let message_without_trailing_newlines = self.message.trim_end_matches(['\r', '\n']);
   ```

2. **按行分割并换行**（第318-325行）：
   ```rust
   let wrapped = adaptive_wrap_lines(
       message_without_trailing_newlines
           .split('\n')
           .map(|line| Line::from(line).style(style)),
       RtOptions::new(usize::from(wrap_width))
           .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit),
   );
   ```

3. **去除末尾空行**（第326行）：
   ```rust
   let wrapped = trim_trailing_blank_lines(wrapped);
   ```

4. **添加前缀**（第361-367行）：
   ```rust
   lines.extend(prefix_lines(
       wrapped_message,
       "› ".bold().dim(),  // 首行前缀
       "  ".into(),        // 续行前缀
   ));
   ```

### 快照输出解析
```
› one two
  three
  four five
  six seven
```

- 第1行：`› one two`（`› ` + 内容）
- 第2行：`  three`（两个空格缩进）
- 第3行：`  four five`
- 第4行：`  six seven`

注意：实际换行位置取决于 `textwrap` 的 `FirstFit` 算法。

## 关键代码路径与文件引用

### 核心实现
| 位置 | 描述 |
|-----|------|
| `history_cell.rs:288-372` | `HistoryCell for UserHistoryCell` |
| `history_cell.rs:290-294` | 换行宽度计算 |
| `history_cell.rs:314-342` | 消息文本处理 |
| `history_cell.rs:361-367` | 前缀添加 |

### 辅助函数
| 函数 | 位置 | 用途 |
|-----|------|------|
| `adaptive_wrap_lines` | `wrapping.rs` | 自适应文本换行 |
| `prefix_lines` | `render/line_utils.rs` | 为行添加前缀 |
| `trim_trailing_blank_lines` | `history_cell.rs:278-286` | 去除末尾空行 |

### 测试代码
- 位置：`history_cell.rs:3842-3857`
- 函数：`user_history_cell_wraps_and_prefixes_each_line_snapshot`

## 依赖与外部交互

### textwrap 配置
```rust
RtOptions::new(usize::from(wrap_width))
    .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit)
```

使用 `FirstFit` 算法，优先在第一个合适的位置换行。

### 前缀系统
```rust
pub fn prefix_lines(
    lines: Vec<Line<'static>>,
    first_prefix: impl Into<Line<'static>>,
    rest_prefix: impl Into<Line<'static>>,
) -> Vec<Line<'static>>
```

- `first_prefix`：首行前缀（`› `）
- `rest_prefix`：续行前缀（`  `）

## 风险、边界与改进建议

### 边界情况

| 场景 | 行为 | 风险等级 |
|-----|------|---------|
| 宽度为0 | 返回空Vec | 低（有保护） |
| 单字超长 | 可能溢出 | 中 |
| 包含换行符 | 按原始换行+自动换行 | 低 |
| 全为空格 | 被trim后可能为空 | 低 |

### 潜在问题

1. **CJK字符宽度**
   - 当前使用 `UnicodeWidthStr` 计算宽度
   - 某些终端对CJK字符的宽度处理可能不一致

2. **非常窄的终端**
   - 当宽度小于前缀长度时，内容可能无法显示
   - 建议：设置最小有效宽度

3. **长单词处理**
   ```rust
   // 当前：FirstFit算法
   // 对于超长单词（如长URL），可能整行只有一个词
   ```

### 改进建议

1. **添加最小宽度保护**
   ```rust
   const MIN_EFFECTIVE_WIDTH: u16 = 20;
   let effective_width = width.max(MIN_EFFECTIVE_WIDTH);
   ```

2. **支持单词断行**
   ```rust
   // 对于超长单词，考虑使用断行字符
   .wrap_algorithm(textwrap::WrapAlgorithm::OptimalFit)
   .word_splitter(textwrap::WordSplitter::NoHyphenation)
   ```

3. **动态前缀**
   - 根据内容类型动态调整前缀
   - 代码块使用不同前缀，引用使用 `>` 等

4. **可见的换行指示**
   ```rust
   // 续行添加视觉指示
   "  ↳ "  // 而不是简单的 "  "
   ```

### 相关测试
| 测试名称 | 描述 |
|---------|------|
| `single_line_command_compact_when_fits` | 单行不折行 |
| `single_line_command_wraps_with_four_space_continuation` | 单行折行 |
| `multiline_command_wraps_with_extra_indent_on_subsequent_lines` | 多行命令 |
