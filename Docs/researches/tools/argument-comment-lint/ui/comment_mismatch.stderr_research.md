# comment_mismatch.stderr 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试的预期错误输出文件，与 `comment_mismatch.rs` 配套使用。

在 Dylint UI 测试框架中，`.stderr` 文件用于存储编译器警告/错误的预期输出格式。测试运行时，实际编译输出会与该文件进行精确对比，任何差异都会导致测试失败。

## 功能点目的

定义 `argument_comment_mismatch` lint 在检测到注释不匹配时的标准输出格式，包括：
1. 警告级别和消息格式
2. 源代码位置标注（文件名、行号、列号）
3. 代码片段高亮显示
4. 帮助信息格式

## 具体技术实现

### 文件内容分析

```
warning: argument comment `/*api_base*/` does not match parameter `base_url`
  --> $DIR/comment_mismatch.rs:9:44
   |
LL |     let _ = create_openai_url(/*api_base*/ None);
   |                                            ^^^^
   |
   = help: use `/*base_url*/`
note: the lint level is defined here
  --> $DIR/comment_mismatch.rs:1:9
   |
LL | #![warn(argument_comment_mismatch)]
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^

warning: 1 warning emitted
```

### 输出格式解析

#### 1. 警告头部
```
warning: argument comment `/*api_base*/` does not match parameter `base_url`
```
- 级别：`warning`（由 `declare_lint!` 中的 `Warn` 决定）
- 消息：动态生成，包含实际的注释内容和期望的参数名

#### 2. 主位置标注
```
  --> $DIR/comment_mismatch.rs:9:44
   |
LL |     let _ = create_openai_url(/*api_base*/ None);
   |                                            ^^^^
```
- `$DIR/`：UI 测试框架的占位符，表示测试文件所在目录
- `9:44`：第 9 行，第 44 列（`None` 的开始位置）
- `^^^`：高亮 `arg.span` 指向的代码区域

#### 3. 帮助信息
```
   = help: use `/*base_url*/`
```
- 由 `span_lint_and_help` 的最后一个参数生成
- 提供可操作的修复建议

#### 4. Lint 级别注释
```
note: the lint level is defined here
  --> $DIR/comment_mismatch.rs:1:9
   |
LL | #![warn(argument_comment_mismatch)]
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^
```
- 自动添加，指向 lint 属性的位置
- 帮助开发者了解警告来源

#### 5. 总结
```
warning: 1 warning emitted
```
- 编译器生成的警告计数

### 与代码的对应关系

| stderr 元素 | 源代码位置 | 生成函数 |
|------------|-----------|---------|
| 警告消息 | `src/lib.rs:207-209` | `format!` in `span_lint_and_help` |
| 高亮位置 | `src/lib.rs:206` | `arg.span` 参数 |
| 帮助信息 | `src/lib.rs:211` | `format!` 最后一个参数 |

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/comment_mismatch.stderr` | 本预期输出文件 |
| `tools/argument-comment-lint/ui/comment_mismatch.rs` | 对应的测试源文件 |
| `tools/argument-comment-lint/src/lib.rs:201-214` | 警告生成代码 |

## 依赖与外部交互

### Dylint Testing 框架
- `dylint_testing::ui_test` 执行测试时：
  1. 编译 `.rs` 文件
  2. 捕获 stderr 输出
  3. 与 `.stderr` 文件内容对比
  4. 使用 `$DIR` 占位符处理路径差异

### Rustc 诊断格式
- 遵循 Rust 编译器的标准诊断输出格式
- 支持 `--error-format` 和 `--json` 等选项的底层格式

## 风险、边界与改进建议

### 当前边界
1. **精确匹配要求**：UI 测试要求 stderr 输出与预期文件完全一致，包括空格和换行
2. **路径占位符**：`$DIR` 是唯一的变量处理，其他内容必须固定
3. **行号敏感**：代码修改可能导致行号变化，需要同步更新 `.stderr` 文件

### 维护风险
1. **代码漂移**：源文件修改后，容易忘记更新对应的 `.stderr` 文件
2. **平台差异**：不同平台的路径分隔符可能不同（但 `$DIR` 处理了大部分情况）
3. **Rust 版本**：编译器诊断格式可能在不同 Rust 版本间变化

### 改进建议
1. **自动化更新**：使用 `BLESS=1 cargo test` 模式自动接受新的输出
2. **模糊匹配**：对行号使用通配符，减少维护负担
3. **注释说明**：在 `.stderr` 文件顶部添加注释说明其用途
4. **合并测试**：考虑使用 `//~^ WARN` 注释直接在源文件中标记预期警告，减少文件数量

### 相关测试模式对比

| 模式 | 优点 | 缺点 |
|-----|------|------|
| 独立 `.stderr` 文件 | 输出完整、可读 | 维护成本高 |
| 源文件内 `//~` 注释 | 维护简单 | 无法验证完整格式 |
| 快照测试（insta） | 自动更新 | 需要额外依赖 |

本项目使用独立 `.stderr` 文件是 Dylint 测试的标准做法，与 Rust 编译器测试保持一致。
