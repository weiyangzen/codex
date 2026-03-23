# bash.rs 深度研究文档

## 场景与职责

`bash.rs` 是 `codex-shell-command` crate 的核心模块，负责使用 tree-sitter 解析器对 Bash/Zsh shell 脚本进行安全解析和分析。该模块的主要职责包括：

1. **Shell 脚本解析**：使用 `tree-sitter-bash` 语法解析器将 shell 脚本转换为抽象语法树（AST）
2. **安全命令提取**：从 `bash -lc "..."` 或 `zsh -lc "..."` 格式的命令中提取可安全解析的命令序列
3. **命令安全验证**：通过白名单机制验证脚本是否只包含安全的命令结构（无变量扩展、命令替换、重定向等危险操作）
4. **Heredoc 支持**：支持解析 heredoc 风格的单命令脚本（如 `python3 <<'PY'`）

该模块是 Codex 执行策略（exec policy）和命令安全检测的基础组件，直接影响哪些 shell 命令可以被自动批准执行。

## 功能点目的

### 1. `try_parse_shell` - 基础解析入口
- **目的**：将 shell 脚本源码解析为 tree-sitter Tree 结构
- **输入**：shell 脚本字符串
- **输出**：`Option<Tree>` - 成功时返回 AST，失败返回 None
- **关键依赖**：`tree_sitter_bash::LANGUAGE`

### 2. `try_parse_word_only_commands_sequence` - 安全命令序列解析
- **目的**：解析仅包含"纯词"命令的脚本，拒绝任何危险构造
- **允许的操作符**：`&&`, `||`, `;`, `|`
- **拒绝的构造**：
  - 括号/子 shell（`(ls)`）
  - 重定向（`>`, `<`, `>>`）
  - 命令替换（`$(...)`, `` `...` ``）
  - 变量扩展（`$VAR`, `${VAR}`）
  - 控制流（if/for/while）
  - 变量赋值前缀（`FOO=bar cmd`）

### 3. `extract_bash_command` - 命令提取器
- **目的**：从命令数组中提取 shell 和脚本部分
- **支持的格式**：`[shell, -lc/-c, script]`
- **支持的 shell**：bash, zsh, sh（通过 `shell_detect` 模块识别）

### 4. `parse_shell_lc_plain_commands` - 主入口函数
- **目的**：组合 `extract_bash_command` 和 `try_parse_word_only_commands_sequence`
- **返回**：解析后的命令序列 `Vec<Vec<String>>`
- **使用场景**：执行策略检查、命令安全验证

### 5. `parse_shell_lc_single_command_prefix` - Heredoc 单命令解析
- **目的**：解析包含 heredoc 的单命令脚本
- **特点**：
  - 要求脚本中只有一个命令节点
  - 允许 heredoc 重定向（`<<`, `<<<`）
  - 允许文件重定向（`>`, `>>`）作为命令的附属
  - 拒绝包含变量扩展或命令替换的命令参数

## 具体技术实现

### 关键数据结构

```rust
// 允许的节点类型白名单
const ALLOWED_KINDS: &[&str] = &[
    "program", "list", "pipeline",     // 顶层容器
    "command", "command_name",         // 命令结构
    "word", "string", "string_content", // 词和字符串
    "raw_string", "number", "concatenation", // 原始字符串、数字、连接
];

// 允许的标点符号
const ALLOWED_PUNCT_TOKENS: &[&str] = &["&&", "||", ";", "|", "\"", "'"];
```

### 核心算法流程

#### `try_parse_word_only_commands_sequence` 流程：
1. 检查根节点是否有解析错误
2. 深度优先遍历 AST（使用栈实现）
3. 对每个命名节点检查是否在 `ALLOWED_KINDS` 白名单中
4. 对匿名节点（标点符号）检查是否在 `ALLOWED_PUNCT_TOKENS` 中
5. 收集所有 `command` 节点
6. 按源码位置排序命令节点
7. 逐个解析命令节点的参数

#### 命令参数解析 (`parse_plain_command_from_node`)：
- **command_name**：提取第一个词作为命令名
- **word/number**：直接提取文本
- **string**：解析双引号字符串，要求只包含 `string_content`（无插值）
- **raw_string**：解析单引号字符串，去除首尾引号
- **concatenation**：处理连接表达式（如 `-g"*.py"`），递归解析各部分

#### Heredoc 命令解析 (`parse_heredoc_command_words`)：
- 只允许纯字面量词和数字
- 检查 `is_literal_word_or_number` 确保无子节点（无扩展）
- 允许 `variable_assignment` 和 `comment` 作为附属
- 允许特定的重定向节点类型

### 安全机制

1. **白名单机制**：只允许明确列出的节点类型
2. **字面量验证**：`is_literal_word_or_number` 确保词节点无子节点（无扩展）
3. **字符串内容验证**：`parse_double_quoted_string` 拒绝包含非 `string_content` 的字符串（如 `$VAR` 会产生 `expansion` 节点）
4. **连接验证**：递归验证连接表达式的每个部分

## 关键代码路径与文件引用

### 内部调用关系
```
try_parse_shell
├── tree_sitter::Parser (tree-sitter crate)
└── tree_sitter_bash::LANGUAGE

try_parse_word_only_commands_sequence
├── try_parse_shell
├── parse_plain_command_from_node
│   ├── parse_double_quoted_string
│   └── parse_raw_string
└── has_named_descendant_kind (辅助检查)

parse_shell_lc_plain_commands
├── extract_bash_command
│   └── detect_shell_type (shell_detect.rs)
└── try_parse_word_only_commands_sequence

parse_shell_lc_single_command_prefix
├── extract_bash_command
├── try_parse_shell
├── has_named_descendant_kind (检查 heredoc_redirect)
├── find_single_command_node
└── parse_heredoc_command_words
```

### 外部调用方

| 调用方文件 | 使用的函数 | 用途 |
|-----------|-----------|------|
| `parse_command.rs` | `extract_bash_command`, `try_parse_shell`, `try_parse_word_only_commands_sequence` | 命令解析和元数据提取 |
| `command_safety/is_dangerous_command.rs` | `parse_shell_lc_plain_commands` | 危险命令检测 |
| `command_safety/is_safe_command.rs` | `parse_shell_lc_plain_commands` | 安全命令验证 |
| `core/src/exec_policy.rs` | `parse_shell_lc_plain_commands`, `parse_shell_lc_single_command_prefix` | 执行策略评估 |
| `core/src/command_canonicalization.rs` | `extract_bash_command`, `parse_shell_lc_plain_commands` | 命令规范化 |
| `core/src/tools/runtimes/shell/unix_escalation.rs` | `parse_shell_lc_plain_commands`, `parse_shell_lc_single_command_prefix` | Unix 权限提升 |
| `tui/src/exec_cell/render.rs` | `extract_bash_command` | UI 显示优化 |
| `tui_app_server/src/exec_cell/render.rs` | `extract_bash_command` | UI 显示优化 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tree-sitter` | 通用语法解析框架 |
| `tree-sitter-bash` | Bash 语法定义 |
| `shell_detect` (内部) | Shell 类型检测 |

### 与 `shell_detect` 的交互
- `detect_shell_type` 用于识别 shell 类型（bash/zsh/sh）
- 通过 `ShellType` 枚举区分不同 shell

### 与 `parse_command` 的交互
- `parse_command.rs` 调用 `extract_bash_command` 提取脚本内容
- 调用 `try_parse_word_only_commands_sequence` 解析安全命令序列
- 用于生成 `ParsedCommand` 元数据（Read/Search/ListFiles 等）

### 与执行策略的交互
- `exec_policy.rs` 使用解析结果进行命令安全评估
- `is_dangerous_command.rs` 和 `is_safe_command.rs` 基于解析结果判断命令安全性

## 风险、边界与改进建议

### 已知风险

1. **解析器限制**：
   - tree-sitter-bash 可能无法处理某些复杂的 bash 语法
   - 解析失败时返回 None，可能导致命令被降级处理（视为未知命令）

2. **白名单遗漏**：
   - 新版本的 bash 可能引入新的语法结构
   - 某些合法的 shell 构造可能被错误地拒绝

3. **安全绕过风险**：
   - 虽然拒绝了明显的危险构造，但复杂的 shell 解析 edge cases 可能存在绕过
   - 例如：某些 Unicode 字符处理、特殊引号组合等

### 边界情况

1. **空脚本**：`bash -lc ""` - 返回空命令列表
2. **语法错误**：`ls &&` - 根节点 `has_error()` 返回 true，拒绝解析
3. **复杂连接**：`-g"*.py"` - 正确处理 flag 和引号值的连接
4. **多行字符串**：`"line1\nline2"` - 正确保留换行符
5. **混合引号**：`"/usr"'/'"local"` - 正确处理混合引号连接

### 改进建议

1. **增强错误报告**：
   - 当前解析失败只返回 None，可以增加错误原因信息
   - 帮助用户理解为什么某个命令不能被自动批准

2. **扩展支持的构造**：
   - 考虑支持更多安全的 shell 构造（如简单的变量赋值）
   - 在确保安全的前提下增加灵活性

3. **性能优化**：
   - 对于大量命令的批量解析，考虑缓存解析器实例
   - tree-sitter Parser 的创建和语言设置可以复用

4. **测试覆盖**：
   - 增加更多 edge case 的测试用例
   - 特别是 Unicode、特殊字符、复杂嵌套等场景

5. **文档完善**：
   - 增加更多内部实现细节的注释
   - 说明每个白名单节点类型的具体含义

### 相关测试

模块包含 30+ 个单元测试，覆盖：
- 基本命令解析（单命令、多命令、操作符）
- 引号处理（单引号、双引号、混合引号）
- 拒绝危险构造（括号、重定向、替换、扩展）
- Heredoc 解析（支持和不支持的情况）
- 连接表达式（flag 与值的连接）
- Edge cases（空命令、语法错误、算术扩展）

测试使用 `pretty_assertions` 提供清晰的差异输出，便于调试。
