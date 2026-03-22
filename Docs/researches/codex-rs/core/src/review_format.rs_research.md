# review_format.rs 研究文档

## 场景与职责

本文件负责**代码审查结果的格式化输出**，将结构化的审查数据转换为人类可读的文本格式。它是 Codex 代码审查功能的**展示层**，连接后端审查逻辑与用户界面。

**核心职责**：
- 将 `ReviewFinding` 结构体格式化为可读的文本块
- 支持选择状态标记（checkbox）用于交互式 UI
- 生成用户友好的审查摘要
- 保持与 UI 层解耦（返回纯字符串，由上层决定样式）

## 功能点目的

### 1. 审查发现格式化 (`format_review_findings_block`)
将多个审查发现格式化为统一的文本块：
- 单数/复数标题自动切换（"Review comment:" vs "Full review comments:"）
- 每个发现包含标题、位置、正文
- 支持选择状态标记（`[x]`/`[ ]`）用于交互式确认

### 2. 位置格式化 (`format_location`)
将代码位置格式化为标准路径格式：
```
/path/to/file.rs:10-25
```

### 3. 审查输出渲染 (`render_review_output_text`)
生成完整的审查摘要，包含：
- 总体解释（overall_explanation）
- 格式化后的发现列表
- 回退消息（当没有内容时）

## 具体技术实现

### 数据结构

```rust
// 来自 protocol.rs
pub struct ReviewOutputEvent {
    pub findings: Vec<ReviewFinding>,
    pub overall_correctness: String,
    pub overall_explanation: String,
    pub overall_confidence_score: f32,
}

pub struct ReviewFinding {
    pub title: String,
    pub body: String,
    pub confidence_score: f32,
    pub priority: i32,
    pub code_location: ReviewCodeLocation,
}

pub struct ReviewCodeLocation {
    pub absolute_file_path: PathBuf,
    pub line_range: ReviewLineRange,
}
```

### 关键函数

#### `format_review_findings_block`
```rust
pub fn format_review_findings_block(
    findings: &[ReviewFinding],
    selection: Option<&[bool]>,  // None = 无选择标记, Some = 带 checkbox
) -> String
```

**输出示例**：
```markdown
Full review comments:

- [x] Potential null pointer dereference — src/main.rs:45-52
  Consider adding a null check before dereferencing `ptr`.
  This could cause a crash in edge cases.

- [ ] Unused import — src/lib.rs:10-10
  Remove the unused `std::collections::HashMap` import.
```

#### `render_review_output_text`
```rust
pub fn render_review_output_text(output: &ReviewOutputEvent) -> String
```

**输出示例**：
```markdown
The code changes look mostly correct, but there are a few issues to address:

Full review comments:
- Potential null pointer dereference — src/main.rs:45-52
  Consider adding a null check...
```

### 设计决策

1. **UI 无关性**
   - 不直接输出颜色或样式
   - 使用纯文本标记（`-`、`[x]`）
   - 上层（TUI/GUI）可添加样式

2. **防御性编程**
   - 选择数组越界时默认选中（`unwrap_or(true)`）
   - 空内容时提供回退消息

## 关键代码路径与文件引用

### 调用关系
```
tasks/review.rs
  ├── format_review_findings_block()  [显示审查结果]
  └── render_review_output_text()     [生成摘要]

app-server/src/bespoke_event_handling.rs
  └── render_review_output_text()     [服务器端渲染]
```

### 依赖的数据定义
```rust
// protocol/src/protocol.rs
pub struct ReviewOutputEvent { ... }
pub struct ReviewFinding { ... }
pub struct ReviewCodeLocation { ... }
pub struct ReviewLineRange { ... }
```

### 测试覆盖
- `core/tests/suite/review.rs` - 端到端审查测试
- 使用 `insta` 快照测试验证输出格式

## 依赖与外部交互

### 输入依赖
| 来源 | 类型 | 用途 |
|-----|------|------|
| `protocol::ReviewFinding` | 结构体 | 单个审查发现数据 |
| `protocol::ReviewOutputEvent` | 结构体 | 完整审查输出 |

### 输出消费者
| 消费者 | 用途 |
|-------|------|
| `tasks/review.rs` | 在 TUI 中显示审查结果 |
| `app-server` | 服务器端审查响应格式化 |

### 无外部 IO
- 纯函数设计，无副作用
- 不访问文件系统、网络或环境变量

## 风险、边界与改进建议

### 潜在风险

1. **格式兼容性问题**
   - 如果 `ReviewFinding` 结构变更，格式化逻辑需要同步更新
   - 多行正文处理依赖 `lines()` 方法，可能受平台换行符影响

2. **国际化缺失**
   - 当前为英文硬编码（"Review comment:"、"Full review comments:"）
   - 无本地化支持

3. **长内容处理**
   - 正文内容过长时无截断机制
   - 可能导致 UI 性能问题

### 边界限制

1. **无样式控制**
   - 无法直接输出颜色、字体样式
   - 依赖上层添加（如 TUI 使用 `ratatui` 样式）

2. **无交互逻辑**
   - 仅负责格式化，不处理用户选择
   - 选择状态由调用方传入

3. **固定格式**
   - 输出格式相对固定，无自定义模板支持

### 改进建议

1. **国际化支持**
   - 使用 `i18n` 框架支持多语言
   - 提取字符串常量到资源文件

2. **可配置格式**
   - 支持自定义模板（如 Markdown、HTML、JSON）
   - 允许配置行宽、缩进等

3. **性能优化**
   - 对大量发现（>1000）考虑分页或截断
   - 使用 `String::with_capacity` 预分配内存

4. **增强功能**
   - 支持 severity 级别的颜色标记（通过 ANSI 转义码选项）
   - 添加代码片段引用（显示相关代码行）
   - 支持分组/过滤（按文件、优先级）

5. **测试增强**
   - 增加边界测试（空 findings、超长字符串）
   - 增加快照测试覆盖更多格式变体
