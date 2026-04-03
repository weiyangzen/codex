# 研究文档：超大输入错误事件快照测试

## 场景与职责

该快照测试验证了 `new_error_event` 函数在处理超大输入错误消息时的渲染行为。当用户输入的消息超过系统允许的最大长度限制时，系统会返回错误提示，UI 需要清晰、醒目地展示这类错误信息。

### 业务场景
用户尝试向 Codex 发送超长的消息：
- 系统设置的最大消息长度为 1,048,576 字符（1MB）
- 用户提供的消息长度为 1,048,577 字符（超出 1 字符）
- 系统拒绝处理并返回错误提示

### 错误类型
这是典型的**输入验证错误**，属于客户端/服务端交互中的边界保护机制。

## 功能点目的

### 核心功能
- **错误提示展示**：清晰展示输入超限错误
- **视觉强调**：使用红色和特殊符号（■）突出错误性质
- **精确信息**：展示具体的限制值和实际值

### 预期输出
```
■ Message exceeds the maximum length of 1048576 characters (1048577 provided).
```

### 设计特点
1. **错误符号**：使用实心方块（■）作为错误标记
2. **颜色标识**：红色文本表示错误状态
3. **精确数字**：展示具体的字符数限制和实际输入数
4. **单行展示**：简洁明了，不占用过多空间

## 具体技术实现

### 函数定义

```rust
pub(crate) fn new_error_event(message: String) -> PlainHistoryCell {
    // 使用 hair space (U+200A) 创建微妙的间距
    // VS16 被有意省略，以在 Ghostty 等终端中保持更紧凑的间距
    let lines: Vec<Line<'static>> = vec![vec![format!("■ {message}").red()].into()];
    PlainHistoryCell { lines }
}
```

### 测试构建

```rust
#[test]
fn error_event_oversized_input_snapshot() {
    let cell = new_error_event(
        "Message exceeds the maximum length of 1048576 characters (1048577 provided)."
            .to_string(),
    );
    // 使用较宽宽度（120）确保单行展示
    let rendered = render_lines(&cell.display_lines(120)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 样式细节

```rust
// 错误标记和消息的样式
format!("■ {message}").red()

// 等效于
Line::from(vec![
    Span::styled(format!("■ {message}"), Style::default().fg(Color::Red))
])
```

### 字符说明

| 字符 | Unicode | 用途 |
|------|---------|------|
| ■ | U+25A0 | 实心方块，错误标记 |
| | U+200A | Hair space，微妙间距 |

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 2861-2868 行）
   - 测试用例 `error_event_oversized_input_snapshot`
   - 验证超大输入错误的展示

2. **`tui/src/history_cell.rs`**（第 1976-1982 行）
   - `new_error_event` 函数实现
   - 错误事件单元格创建

### 相关结构
```rust
pub(crate) struct PlainHistoryCell {
    lines: Vec<Line<'static>>,
}

impl HistoryCell for PlainHistoryCell {
    fn display_lines(&self, _width: u16) -> Vec<Line<'static>> {
        self.lines.clone()  // 简单返回预构建的行
    }
}
```

### 相关快照
- `tui/src/snapshots/codex_tui__history_cell__tests__error_event_oversized_input_snapshot.snap`

## 依赖与外部交互

### 渲染依赖
- `ratatui::style::Color::Red` - 红色错误标识
- `ratatui::style::Stylize::red` - 样式扩展方法
- `ratatui::text::Line` - 文本行类型
- `ratatui::text::Span` - 文本片段类型

### 辅助函数
```rust
fn render_lines(lines: &[Line<'static>]) -> Vec<String>
// 将 Line 转换为可比较的字符串
```

### 对比其他错误类型
| 函数 | 标记 | 颜色 | 用途 |
|------|------|------|------|
| `new_error_event` | ■ | 红色 | 一般错误 |
| `new_warning_event` | ⚠ | 黄色 | 警告 |
| `new_info_event` | • | 默认 | 信息 |
| `new_deprecation_notice` | ⚠ | 红色 | 弃用通知 |

## 风险、边界与改进建议

### 当前风险

1. **错误信息长度**
   - 风险：错误消息本身可能很长，导致换行
   - 现状：测试使用 120 宽度确保单行展示
   - 建议：考虑错误消息的截断或换行处理

2. **特殊字符处理**
   - 风险：错误消息包含特殊字符可能影响渲染
   - 示例：包含 ANSI 转义序列的消息
   - 现状：直接拼接，无转义处理

3. **国际化支持**
   - 风险：硬编码的英文错误消息
   - 现状：消息由调用方提供，函数本身不处理

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 空错误消息 | 显示 "■ " | ⚠️ 不够友好 |
| 超长错误消息 | 可能换行 | ⚠️ 需处理 |
| 包含换行符 | 不处理，直接显示 | ⚠️ 可能破坏布局 |
| 包含 emoji | 正常显示 | ✅ |
| 极窄宽度 | 可能截断 | ⚠️ 需测试 |

### 改进建议

1. **错误分类**
   ```rust
   pub enum ErrorType {
       InputValidation,   // ■
       Network,           // 🌐
       Permission,        // 🔒
       Internal,          // ⚙️
   }
   
   pub fn new_error_event(message: String, error_type: ErrorType) -> PlainHistoryCell
   ```

2. **错误代码支持**
   ```
   ■ [E1001] Message exceeds the maximum length of 1048576 characters
   ```

3. **可展开详情**
   - 对于长错误消息，默认显示摘要
   - 支持展开查看完整信息

4. **操作提示**
   ```
   ■ Message exceeds the maximum length of 1048576 characters (1048577 provided).
     Press Ctrl+C to copy this message, or press Esc to dismiss.
   ```

5. **消息格式化**
   ```rust
   // 对长数字添加千位分隔符
   format!("{:,}", 1048576)  // "1,048,576"
   ```

6. **宽度自适应**
   ```rust
   pub(crate) fn new_error_event(message: String) -> Box<dyn HistoryCell> {
       // 返回动态类型，支持根据宽度调整展示
       Box::new(WrappingErrorCell { message })
   }
   ```

### 相关测试建议

- [ ] 空错误消息的处理
- [ ] 包含换行符的错误消息
- [ ] 包含 ANSI 转义序列的错误消息
- [ ] 极窄宽度（<20）下的渲染
- [ ] 包含 CJK 字符的错误消息
- [ ] 数字格式化（千位分隔符）

### 与系统其他部分的关联

1. **输入验证层**
   - 错误消息通常在 `codex-core` 或 `codex-protocol` 层生成
   - UI 层负责展示，不生成错误内容

2. **错误处理流程**
   ```
   用户输入 -> 长度检查 -> 生成错误 -> new_error_event -> 渲染
   ```

3. **日志记录**
   - 错误事件应同时记录到日志系统
   - 便于问题排查
