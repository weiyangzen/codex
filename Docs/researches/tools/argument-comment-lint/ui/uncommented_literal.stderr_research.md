# uncommented_literal.stderr 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试的预期错误输出文件，与 `uncommented_literal.rs` 配套使用。

该文件展示了 `uncommented_anonymous_literal_argument` lint 在检测到未注释的匿名字面量参数时的完整输出格式，包括警告消息、代码位置、修复建议等。

## 功能点目的

定义 `uncommented_anonymous_literal_argument` lint 的标准输出格式，验证：
1. 多个警告的正确排序和分组
2. 自动修复建议的格式（`span_lint_and_sugg`）
3. 不同参数类型的处理方式
4. 函数调用和方法调用的一致性输出

## 具体技术实现

### 文件内容分析

```
warning: anonymous literal-like argument for parameter `base_url`
  --> $DIR/uncommented_literal.rs:16:31
   |
LL |     let _ = create_openai_url(None, 3);
   |                               ^^^^ help: prepend the parameter name comment: `/*base_url*/ None`
   |
   = note: the lint level is defined here
  --> $DIR/uncommented_literal.rs:1:9
   |
LL | #![warn(uncommented_anonymous_literal_argument)]
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

warning: anonymous literal-like argument for parameter `retry_count`
  --> $DIR/uncommented_literal.rs:16:37
   |
LL |     let _ = create_openai_url(None, 3);
   |                                     ^ help: prepend the parameter name comment: `/*retry_count*/ 3`

warning: anonymous literal-like argument for parameter `enabled`
  --> $DIR/uncommented_literal.rs:17:21
   |
LL |     client.set_flag(true);
   |                     ^^^^ help: prepend the parameter name comment: `/*enabled*/ true`

warning: 3 warnings emitted
```

### 输出结构解析

#### 警告 1：`None` 参数
```
warning: anonymous literal-like argument for parameter `base_url`
```
- 参数名：`base_url`
- 问题：`None` 缺少注释
- 位置：第 16 行，第 31 列

```
   |                               ^^^^ help: prepend the parameter name comment: `/*base_url*/ None`
```
- 高亮：`None` 的 4 个字符
- 帮助：建议添加 `/*base_url*/ None`

#### 警告 2：`3` 参数
```
warning: anonymous literal-like argument for parameter `retry_count`
```
- 同一行上的第二个警告
- 位置：第 16 行，第 37 列
- 高亮：`3` 的 1 个字符（`^`）

#### 警告 3：`true` 参数（方法调用）
```
warning: anonymous literal-like argument for parameter `enabled`
```
- 方法调用场景
- 位置：第 17 行，第 21 列
- 证明 lint 同时适用于函数调用和方法调用

### 与 `span_lint_and_sugg` 的对应

在 `src/lib.rs` 第 221-229 行：

```rust
span_lint_and_sugg(
    cx,
    UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT,
    arg.span,
    format!("anonymous literal-like argument for parameter `{expected_name}`"),
    "prepend the parameter name comment",
    format!("/*{expected_name}*/ {arg_text}"),
    Applicability::MachineApplicable,
);
```

| stderr 部分 | 对应参数 |
|------------|---------|
| `warning: anonymous literal-like argument for parameter ...` | 第 4 个参数（消息） |
| `help: prepend the parameter name comment` | 第 5 个参数（帮助文本） |
| `/*base_url*/ None` | 第 6 个参数（建议替换文本） |
| `Applicability::MachineApplicable` | 机器可应用的修复级别 |

### 与 `comment_mismatch.stderr` 的区别

| 特性 | `comment_mismatch.stderr` | `uncommented_literal.stderr` |
|-----|--------------------------|------------------------------|
| Lint 类型 | `argument_comment_mismatch` | `uncommented_anonymous_literal_argument` |
| 生成函数 | `span_lint_and_help` | `span_lint_and_sugg` |
| 修复建议 | 仅帮助文本（`help:`） | 可应用建议（`help:` + 替换文本） |
| 适用场景 | 注释不匹配 | 缺少注释 |

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/uncommented_literal.stderr` | 本预期输出文件 |
| `tools/argument-comment-lint/ui/uncommented_literal.rs` | 对应的测试源文件 |
| `tools/argument-comment-lint/src/lib.rs:221-229` | `span_lint_and_sugg` 调用 |

## 依赖与外部交互

### Clippy Utils 诊断 API
- `span_lint_and_sugg` vs `span_lint_and_help`：
  - `sugg` 提供可自动应用的代码替换
  - `help` 仅提供文本提示

### Rustc Applicability
- `Applicability::MachineApplicable`：表示修复可以安全地自动应用
- 其他级别：`HasPlaceholders`, `MaybeIncorrect`, `Unspecified`

## 风险、边界与改进建议

### 当前边界
1. **行内显示**：修复建议直接显示在代码行下方，可能较长时换行
2. **字符级高亮**：使用 `^` 精确标记问题位置
3. **多警告排序**：按源代码位置排序

### 输出格式风险
1. **终端宽度**：长参数名可能导致帮助文本换行，影响可读性
2. **颜色代码**：实际输出包含 ANSI 颜色代码，`.stderr` 文件中是纯文本
3. **路径变化**：文件路径变化会破坏测试

### 改进建议
1. **多行建议格式化**：对于复杂表达式，考虑多行格式化建议
2. **分组显示**：同一函数调用的多个警告可以分组显示
3. **统计信息**：在末尾添加更详细的统计（如按文件分组）
4. **快速修复代码**：提供可用于 `sed` 或 IDE 的纯文本修复命令

### 测试维护建议
1. **自动化更新**：使用 `BLESS=1` 环境变量自动接受输出变化
2. **最小化测试**：每个测试文件专注于一个场景，减少输出体积
3. **注释说明**：在 `.stderr` 文件顶部添加生成说明

### 与其他 lint 工具的对比

| 工具 | 输出风格 | 自动修复 |
|-----|---------|---------|
| `argument_comment_lint` | 标准 rustc 格式 | 建议级别 |
| Clippy | 类似 rustc，更详细 | 部分支持 |
| ESLint | 可配置格式 | 插件支持 |
| RuboCop | 详细描述 | 支持 |

本项目遵循 Rust 生态的标准诊断格式，与编译器和其他工具保持一致。
