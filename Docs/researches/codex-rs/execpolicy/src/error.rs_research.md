# error.rs 研究文档

## 场景与职责

`error.rs` 是 `codex-execpolicy` crate 的错误处理基础设施模块，负责：

1. **定义统一的错误类型**：为整个 crate 提供一致的错误表示
2. **支持错误定位**：提供源代码位置信息（文件、行、列）
3. **与 Starlark 集成**：将 Starlark 解析错误转换为本地错误格式
4. **支持示例验证错误**：处理策略文件中 `match`/`not_match` 示例验证失败的情况

该模块的设计目标是提供**详细的错误上下文**，帮助用户快速定位策略文件中的问题。

## 功能点目的

### 1. 核心错误类型 (`Error`)

定义策略引擎可能遇到的各种错误：

| 错误变体 | 用途 |
|----------|------|
| `InvalidDecision` | 决策字符串解析失败 |
| `InvalidPattern` | 模式定义无效 |
| `InvalidExample` | 示例格式无效 |
| `InvalidRule` | 规则定义无效 |
| `ExampleDidNotMatch` | `match` 示例未能匹配任何规则 |
| `ExampleDidMatch` | `not_match` 示例意外匹配了规则 |
| `Starlark` | Starlark 解析/执行错误 |

### 2. 源代码定位

提供精确的错误位置信息：

```rust
pub struct TextPosition {
    pub line: usize,    // 1-based 行号
    pub column: usize,  // 1-based 列号
}

pub struct TextRange {
    pub start: TextPosition,
    pub end: TextPosition,
}

pub struct ErrorLocation {
    pub path: String,   // 文件路径
    pub range: TextRange,
}
```

### 3. 错误增强

支持为错误附加位置信息：

```rust
impl Error {
    pub fn with_location(self, location: ErrorLocation) -> Self;
    pub fn location(&self) -> Option<ErrorLocation>;
}
```

## 具体技术实现

### 错误类型定义

```rust
#[derive(Debug, Error)]
pub enum Error {
    #[error("invalid decision: {0}")]
    InvalidDecision(String),
    
    #[error("invalid pattern element: {0}")]
    InvalidPattern(String),
    
    #[error("invalid example: {0}")]
    InvalidExample(String),
    
    #[error("invalid rule: {0}")]
    InvalidRule(String),
    
    #[error("expected every example to match at least one rule...")]
    ExampleDidNotMatch {
        rules: Vec<String>,
        examples: Vec<String>,
        location: Option<ErrorLocation>,
    },
    
    #[error("expected example to not match rule `{rule}`: {example}")]
    ExampleDidMatch {
        rule: String,
        example: String,
        location: Option<ErrorLocation>,
    },
    
    #[error("starlark error: {0}")]
    Starlark(StarlarkError),
}
```

### 位置信息处理

#### 附加位置

```rust
pub fn with_location(self, location: ErrorLocation) -> Self {
    match self {
        Error::ExampleDidNotMatch { rules, examples, location: None } => {
            Error::ExampleDidNotMatch { rules, examples, location: Some(location) }
        }
        Error::ExampleDidMatch { rule, example, location: None } => {
            Error::ExampleDidMatch { rule, example, location: Some(location) }
        }
        other => other,
    }
}
```

只有示例验证错误支持附加位置，其他错误直接返回原值。

#### 提取位置

```rust
pub fn location(&self) -> Option<ErrorLocation> {
    match self {
        Error::ExampleDidNotMatch { location, .. }
        | Error::ExampleDidMatch { location, .. } => location.clone(),
        
        Error::Starlark(err) => err.span().map(|span| {
            let resolved = span.resolve_span();
            ErrorLocation {
                path: span.filename().to_string(),
                range: TextRange {
                    start: TextPosition {
                        line: resolved.begin.line + 1,      // 0-based → 1-based
                        column: resolved.begin.column + 1,
                    },
                    end: TextPosition {
                        line: resolved.end.line + 1,
                        column: resolved.end.column + 1,
                    },
                },
            }
        }),
        _ => None,
    }
}
```

关键转换：Starlark 使用 0-based 索引，对外暴露时转换为 1-based（更符合用户习惯）。

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `starlark` | `StarlarkError` 类型和源码位置信息 |
| `thiserror` | 错误类型派生宏 |

### 被依赖方

| 模块 | 用途 |
|------|------|
| `decision.rs` | 解析失败时返回错误 |
| `parser.rs` | 策略解析错误 |
| `rule.rs` | 规则验证错误 |
| `policy.rs` | 策略评估错误 |
| `amend.rs` | 独立的 `AmendError` 但也遵循相似模式 |

### 类型别名

```rust
pub type Result<T> = std::result::Result<T, Error>;
```

整个 crate 使用统一的 `Result` 类型。

## 风险、边界与改进建议

### 风险点

1. **位置信息可选**：`ExampleDidNotMatch` 和 `ExampleDidMatch` 的 `location` 是 `Option`，某些路径可能丢失位置信息
2. **Starlark 版本依赖**：错误位置提取依赖 Starlark crate 的内部 API，升级时可能需要调整
3. **错误消息硬编码**：错误消息是英文硬编码，不支持国际化

### 边界条件

1. **行号转换**：Starlark 返回 0-based，对外展示 1-based，转换逻辑必须正确
2. **空路径**：`ErrorLocation.path` 可能为空字符串（虽然罕见）
3. **大文件**：行号和列号使用 `usize`，理论上支持任意大小的文件

### 改进建议

1. **结构化错误**：考虑使用 `thiserror` 的 `#[error(transparent)]` 或自定义显示格式
2. **错误链**：支持 `source()` 方法提供错误链，帮助调试根因
3. **错误代码**：为每种错误分配唯一代码，便于程序化处理和文档引用
4. **建议提示**：在错误消息中提供修复建议，例如：
   ```
   invalid decision: "Allow". Did you mean "allow"?
   ```
5. **范围显示**：提供工具函数将 `TextRange` 格式化为 `"file.rules:10:5-12:8"` 形式
6. **测试辅助**：提供测试辅助函数，便于在测试中断言特定错误类型

### 代码示例

典型的错误处理流程（来自 `parser.rs`）：

```rust
let location = eval
    .call_stack_top_location()
    .map(error_location_from_file_span);

builder.add_pending_example_validation(
    rules.clone(),
    matches,
    not_matches,
    location,  // 可能为 None
);

// 后续验证时
validate_match_examples(&policy, &validation.rules, &validation.matches)
    .map_err(|error| attach_validation_location(error, validation.location.clone()))?;
```

这个流程展示了位置信息如何被捕获、传递和附加到错误上。
