# comment_parser.rs 研究文档

## 场景与职责

`comment_parser.rs` 是 `argument-comment-lint` 工具的核心解析模块，负责从 Rust 源代码中提取和验证 `/*param*/` 形式的参数注释。该模块是 Dylint 自定义 lint 的基础组件，用于支持代码风格检查中对参数注释的解析需求。

### 定位
- **文件路径**: `tools/argument-comment-lint/src/comment_parser.rs`
- **所属模块**: `argument-comment-lint` crate 的私有子模块
- **被调用方**: `lib.rs` 中的 `ArgumentCommentLint` 结构体

## 功能点目的

本模块提供两个核心解析函数，用于从不同位置提取参数注释：

1. **`parse_argument_comment`** - 解析参数前的尾随注释（位于参数与前一个 token 之间的间隙）
2. **`parse_argument_comment_prefix`** - 解析参数前的行内前缀注释（位于参数表达式开头）

### 设计目标
- **精确匹配**: 严格识别 `/*identifier*/` 格式，拒绝任何变形（如带空格、带等号等）
- **标识符验证**: 确保注释内容符合 Rust 标识符规范
- **轻量高效**: 基于字符串操作，无需完整词法分析

## 具体技术实现

### 关键数据结构

本模块无复杂数据结构，核心是基于 `&str` 的字符串切片操作：

```rust
// 输入: 源代码文本片段
// 输出: Option<&str> - 提取的标识符或 None
```

### 核心函数实现

#### 1. `parse_argument_comment` - 尾随注释解析

```rust
pub fn parse_argument_comment(text: &str) -> Option<&str> {
    let trimmed = text.trim_end();
    let comment_start = trimmed.rfind("/*")?;
    let comment = &trimmed[comment_start..];
    let name = comment.strip_prefix("/*")?.strip_suffix("*/")?;
    is_identifier(name).then_some(name)
}
```

**算法流程**:
1. `trim_end()` - 去除尾部空白
2. `rfind("/*")` - 从右向左查找最后一个 `/*`
3. `strip_prefix("/*")` + `strip_suffix("*/")` - 去除注释标记
4. `is_identifier()` - 验证是否为合法标识符

**适用场景**:
```rust
create_openai_url(/*base_url*/ None, /*retry_count*/ 3);
//               ^^^^^^^^^^^^^^ gap_text 包含此注释
```

#### 2. `parse_argument_comment_prefix` - 前缀注释解析

```rust
pub fn parse_argument_comment_prefix(text: &str) -> Option<&str> {
    let trimmed = text.trim_start();
    let comment = trimmed.strip_prefix("/*")?;
    let (name, _) = comment.split_once("*/")?;
    is_identifier(name).then_some(name)
}
```

**算法流程**:
1. `trim_start()` - 去除前导空白
2. `strip_prefix("/*")` - 确认以 `/*` 开头
3. `split_once("*/")` - 分割注释结束标记
4. `is_identifier()` - 验证标识符合法性

**适用场景**:
```rust
run_git_for_stdout(
    "/tmp/repo",
    vec!["rev-parse", "HEAD"],
    /*env*/ None,  // 多行参数，注释在表达式开头
);
```

#### 3. `is_identifier` - 标识符验证

```rust
fn is_identifier(text: &str) -> bool {
    let mut chars = text.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first == '_' || first.is_ascii_alphabetic()) {
        return false;
    }
    chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
}
```

**验证规则**:
- 首字符：下划线 `_` 或 ASCII 字母
- 后续字符：下划线、ASCII 字母或数字
- 空字符串拒绝

### 测试覆盖

模块内嵌单元测试覆盖以下场景：

| 测试函数 | 验证内容 |
|---------|---------|
| `parses_trailing_comment` | 正常尾随注释解析（含泛型方法调用场景） |
| `rejects_non_matching_shapes` | 拒绝变形注释（空格、等号、数字开头等） |
| `parses_prefix_comment` | 前缀注释解析（含前导换行） |

**测试用例示例**:
```rust
// 合法
assert_eq!(parse_argument_comment("(/*base_url*/ "), Some("base_url"));
assert_eq!(parse_argument_comment_prefix("/*env*/ None"), Some("env"));

// 非法
assert_eq!(parse_argument_comment("(/* base_url*/ "), None);  // 前有空格
assert_eq!(parse_argument_comment("(/*base_url */ "), None);  // 后有空格
assert_eq!(parse_argument_comment("(/*base_url=*/ "), None);  // 含等号
assert_eq!(parse_argument_comment("(/*1base_url*/ "), None);  // 数字开头
```

## 关键代码路径与文件引用

### 调用关系

```
lib.rs:ArgumentCommentLint::check_call
    ├──> parse_argument_comment(gap_text)      // 尝试间隙注释
    ├──> parse_argument_comment(lookbehind_text) // 尝试回溯注释
    └──> parse_argument_comment_prefix(arg_text) // 尝试前缀注释
```

### 源码位置

| 函数 | 行号 | 用途 |
|-----|------|------|
| `parse_argument_comment` | 1-7 | 解析尾随注释 |
| `parse_argument_comment_prefix` | 9-14 | 解析前缀注释 |
| `is_identifier` | 16-25 | 标识符验证 |
| 单元测试 | 27-63 | 功能验证 |

### 使用场景（来自 lib.rs）

```rust
// lib.rs:194-199
let lookbehind_start = BytePos(arg.span.lo().0.saturating_sub(64));
let lookbehind_text =
    snippet(cx, arg.span.shrink_to_lo().with_lo(lookbehind_start), "");
let argument_comment = parse_argument_comment(gap_text.as_ref())
    .or_else(|| parse_argument_comment(lookbehind_text.as_ref()))
    .or_else(|| parse_argument_comment_prefix(arg_text.as_ref()));
```

## 依赖与外部交互

### 内部依赖
- 无（纯字符串处理模块）

### 标准库使用
| 特性 | 用途 |
|-----|------|
| `str::trim_end` / `str::trim_start` | 空白处理 |
| `str::rfind` | 反向查找注释开始 |
| `str::strip_prefix` / `str::strip_suffix` | 去除注释标记 |
| `str::split_once` | 分割注释内容 |
| `char::is_ascii_alphabetic` / `char::is_ascii_alphanumeric` | 标识符验证 |

### 与 lib.rs 的契约

1. **输入保证**: `lib.rs` 提供从代码片段提取的文本（可能包含空白、换行、其他 token）
2. **输出语义**: 
   - `Some(name)`: 成功提取合法参数名注释
   - `None`: 无有效注释（可能是格式错误或不存在）
3. **错误处理**: 本模块不区分"无注释"和"格式错误"，统一返回 `None`

## 风险、边界与改进建议

### 已知限制

1. **严格格式要求**:
   - 不接受 `/* name */`（带空格）
   - 不接受 `/*name=*/`（带等号，类似 Python 关键字参数风格）
   - 不接受 `/*123*/`（数字开头）
   
   这些限制是**有意设计**，强制统一的代码风格。

2. **无嵌套注释支持**:
   ```rust
   /*outer/*inner*/outer*/  // 无法正确解析
   ```

3. **回溯长度限制**:
   `lib.rs` 中硬编码 64 字节回溯窗口，超长注释可能无法检测。

### 边界情况

| 输入 | 输出 | 说明 |
|-----|------|------|
 `""` | `None` | 空字符串 |
 `"/*"` | `None` | 不完整注释 |
 `"/**/` | `None` | 空注释内容 |
 `"/*_*/"` | `Some("_")` | 单下划线（合法标识符） |
 `"/*_name*/"` | `Some("_name")` | 下划线开头 |
 `"/*name123*/"` | `Some("name123")` | 数字结尾 |
 `"/*Name*/"` | `Some("Name")` | 大写字母开头 |

### 改进建议

1. **性能优化**: 当前实现使用 `rfind` 和多次字符串操作，对于高频调用场景可考虑:
   - 使用 `memchr` 进行快速字节搜索
   - 预编译查找模式

2. **错误信息增强**: 当前统一返回 `None`，可考虑返回具体错误类型:
   ```rust
   enum ParseError {
       NoComment,
       InvalidFormat(&'static str),  // "contains whitespace"
       InvalidIdentifier(&'static str),  // "starts with digit"
   }
   ```

3. **配置化**: 允许通过配置放宽/收紧规则（如允许带空格注释）。

4. **文档补充**: 添加更多关于 `/*param*/` 风格设计决策的注释（为何拒绝空格等）。

### 安全风险

- **无内存安全问题**: 纯 Rust 代码，无 unsafe 块
- **无拒绝服务风险**: 输入长度受限于源代码行长度，无复杂回溯

### 维护建议

- 该模块逻辑稳定，变更频率低
- 任何对解析规则的修改需同步更新 `lib.rs` 中的 lint 逻辑和 UI 测试
- 建议保持当前严格性，避免风格漂移
