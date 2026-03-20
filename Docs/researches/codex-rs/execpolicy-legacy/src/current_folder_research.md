# codex-rs/execpolicy-legacy/src 深度研究文档

## 概述

`codex-execpolicy-legacy` 是 OpenAI Codex 项目中原始的执行策略（exec policy）引擎实现，用于验证和分类提议的 `execv(3)` 命令调用的安全性。该 crate 已被标记为 "legacy"，因为新的前缀规则引擎（prefix-rule engine）已迁移至 `codex-execpolicy` crate。

---

## 1. 场景与职责

### 1.1 核心目标

该 crate 的核心目标是将提议的 `execv(3)` 命令分类为以下四种状态之一：

| 状态 | 含义 | 处理建议 |
|------|------|----------|
| `safe` | 命令被验证为安全 | 可以直接执行 |
| `match` | 命令匹配策略规则，但调用方需要基于写入的文件决定是否安全 | 需要调用方根据文件写入权限判断 |
| `forbidden` | 命令被禁止执行 | 拒绝执行 |
| `unverified` | 无法确定安全性 | 需要用户决定 |

### 1.2 使用场景

1. **AI 代理安全执行**：当 Codex AI 代理需要执行 shell 命令时，通过此引擎验证命令安全性
2. **沙箱环境**：在受限环境中验证命令是否符合安全策略
3. **命令行工具**：提供 CLI 工具用于手动验证命令

### 1.3 设计哲学

- **结构化结果**：不返回简单的布尔值，而是返回包含详细信息的结构化结果
- **上下文感知**：安全性判断需要额外的上下文（如当前工作目录、文件路径等）
- **策略驱动**：使用 Starlark 语言定义安全策略，支持宏和复用

---

## 2. 功能点目的

### 2.1 主要模块功能

| 模块 | 文件 | 职责 |
|------|------|------|
| `lib.rs` | 库入口 | 模块组织、公共 API 导出、默认策略加载 |
| `main.rs` | CLI 入口 | 命令行参数解析、命令检查执行、JSON 输出 |
| `policy.rs` | 策略引擎 | 策略结构定义、命令匹配检查、禁止规则验证 |
| `policy_parser.rs` | 策略解析器 | Starlark 策略文件解析、内置函数定义 |
| `program.rs` | 程序规范 | 程序规则定义、参数匹配验证、正/负例测试 |
| `execv_checker.rs` | execv 检查器 | 文件路径验证、可读/可写文件夹检查、可执行文件查找 |
| `exec_call.rs` | 执行调用 | execv 调用数据结构定义 |
| `arg_matcher.rs` | 参数匹配器 | 参数匹配模式定义（Starlark 集成） |
| `arg_resolver.rs` | 参数解析器 | 位置参数与模式匹配解析 |
| `arg_type.rs` | 参数类型 | 参数类型定义与验证 |
| `valid_exec.rs` | 有效执行 | 验证通过的执行命令结构定义 |
| `opt.rs` | 选项定义 | 命令行选项（flag/opt）定义（Starlark 集成） |
| `sed_command.rs` | Sed 命令解析 | 安全的 sed 命令解析验证 |
| `error.rs` | 错误定义 | 错误类型枚举定义 |

### 2.2 默认策略文件

`default.policy` 定义了常见 Unix 命令的安全规则：

- `ls`: 支持 `-1`, `-a`, `-l` 标志，参数为可读文件或当前目录
- `cat`: 支持 `-b`, `-n`, `-t` 标志，参数为可读文件
- `cp`: 支持 `-r`, `-R`, `--recursive` 标志，参数为源文件列表和目标文件
- `head`: 支持 `-c`, `-n` 选项（正整数），参数为可读文件
- `printenv`: 无参数或单个不透明值参数
- `pwd`: 支持 `-L`, `-P` 标志，无参数
- `rg` (ripgrep): 支持多种选项和参数
- `sed`: 受限支持，仅允许安全的 sed 命令
- `which`: 支持 `-a`, `-s` 标志

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 ExecCall - 执行调用请求

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,
    pub args: Vec<String>,
}
```

表示一个待验证的 execv 调用，包含程序名和参数列表。

#### 3.1.2 Policy - 策略

```rust
pub struct Policy {
    programs: MultiMap<String, ProgramSpec>,
    forbidden_program_regexes: Vec<ForbiddenProgramRegex>,
    forbidden_substrings_pattern: Option<Regex>,
}
```

策略包含：
- 程序规范映射（程序名 -> 规则列表）
- 禁止的程序名正则表达式列表
- 禁止的子字符串正则模式

#### 3.1.3 ProgramSpec - 程序规范

```rust
pub struct ProgramSpec {
    pub program: String,
    pub system_path: Vec<String>,
    pub option_bundling: bool,
    pub combined_format: bool,
    pub allowed_options: HashMap<String, Opt>,
    pub arg_patterns: Vec<ArgMatcher>,
    forbidden: Option<String>,
    required_options: HashSet<String>,
    should_match: Vec<Vec<String>>,
    should_not_match: Vec<Vec<String>>,
}
```

定义单个程序的安全规则，包括：
- 允许的选项和标志
- 位置参数匹配模式
- 系统路径（推荐的可执行文件路径）
- 禁止标记（如果设置，匹配此规则的命令将被禁止）
- 正例/负例测试用例

#### 3.1.4 ArgMatcher - 参数匹配器

```rust
pub enum ArgMatcher {
    Literal(String),           // 字面量匹配
    OpaqueNonFile,             // 非文件的不透明值
    ReadableFile,              // 可读文件
    WriteableFile,             // 可写文件
    ReadableFiles,             // 可读文件列表（至少一个）
    ReadableFilesOrCwd,        // 可读文件列表或当前目录
    PositiveInteger,           // 正整数
    SedCommand,                // 安全的 sed 命令
    UnverifiedVarargs,         // 未验证的可变参数
}
```

#### 3.1.5 MatchedExec - 匹配结果

```rust
pub enum MatchedExec {
    Match { exec: ValidExec },
    Forbidden { cause: Forbidden, reason: String },
}
```

### 3.2 关键流程

#### 3.2.1 策略加载流程

```
1. 读取 .policy 文件内容
2. 使用 Starlark 解析器解析 AST
3. 注册内置函数（define_program, flag, opt, forbid_substrings, forbid_program_regex）
4. 执行 Starlark 代码，构建 PolicyBuilder
5. 验证正例/负例测试用例
6. 返回 Policy 实例
```

代码路径：`policy_parser.rs::PolicyParser::parse()`

#### 3.2.2 命令检查流程

```
1. 检查程序名是否匹配禁止的正则表达式
2. 检查参数是否包含禁止的子字符串
3. 查找程序对应的规则列表
4. 遍历规则列表，尝试匹配：
   a. 解析选项（flags 和 opts）
   b. 解析位置参数
   c. 验证必需选项是否存在
   d. 检查是否为禁止规则
5. 返回匹配结果
```

代码路径：`policy.rs::Policy::check()` -> `program.rs::ProgramSpec::check()`

#### 3.2.3 参数解析流程

```
1. 遍历参数列表
2. 识别选项（以 - 开头）：
   - 查找允许的选项定义
   - 如果是 flag，记录匹配
   - 如果是 opt，期待下一个参数作为值
3. 识别位置参数：
   - 与 arg_patterns 进行匹配
   - 处理前缀模式、可变参数模式、后缀模式
4. 验证所有必需选项已提供
```

代码路径：`program.rs::ProgramSpec::check()` -> `arg_resolver.rs::resolve_observed_args_with_patterns()`

#### 3.2.4 文件路径验证流程（ExecvChecker）

```
1. 遍历所有参数（包括选项值）
2. 对于 ReadableFile 类型：
   - 转换为绝对路径
   - 验证路径在可读文件夹列表内
3. 对于 WriteableFile 类型：
   - 转换为绝对路径
   - 验证路径在可写文件夹列表内
4. 查找可执行文件路径
5. 返回验证通过的路径
```

代码路径：`execv_checker.rs::ExecvChecker::check()`

### 3.3 Starlark 集成

使用 `starlark-rust` 库作为 Starlark 语言的 Rust 实现。

#### 3.3.1 内置函数

| 函数 | 用途 |
|------|------|
| `define_program(...)` | 定义程序安全规则 |
| `flag(name)` | 定义无值标志 |
| `opt(name, type, required?)` | 定义带值选项 |
| `forbid_substrings(strings)` | 定义禁止的子字符串 |
| `forbid_program_regex(regex, reason)` | 定义禁止的程序名正则 |

#### 3.3.2 预定义常量

| 常量 | 对应的 ArgMatcher |
|------|-------------------|
| `ARG_OPAQUE_VALUE` | `OpaqueNonFile` |
| `ARG_RFILE` | `ReadableFile` |
| `ARG_WFILE` | `WriteableFile` |
| `ARG_RFILES` | `ReadableFiles` |
| `ARG_RFILES_OR_CWD` | `ReadableFilesOrCwd` |
| `ARG_POS_INT` | `PositiveInteger` |
| `ARG_SED_COMMAND` | `SedCommand` |
| `ARG_UNVERIFIED_VARARGS` | `UnverifiedVarargs` |

### 3.4 Sed 命令安全验证

由于 GNU sed 支持 `e` 标志（可以执行任意 shell 命令），该 crate 实现了专门的 sed 命令验证：

```rust
pub fn parse_sed_command(sed_command: &str) -> Result<()> {
    // 仅允许形如 `122,202p` 的打印命令
    if let Some(stripped) = sed_command.strip_suffix("p")
        && let Some((first, rest)) = stripped.split_once(",")
        && first.parse::<u64>().is_ok()
        && rest.parse::<u64>().is_ok()
    {
        return Ok(());
    }
    Err(Error::SedCommandNotProvablySafe { ... })
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 库使用入口

```rust
// 加载默认策略
use codex_execpolicy_legacy::get_default_policy;
let policy = get_default_policy()?;

// 创建执行调用
use codex_execpolicy_legacy::ExecCall;
let exec_call = ExecCall::new("ls", &["-l", "foo"]);

// 检查命令
match policy.check(&exec_call) {
    Ok(MatchedExec::Match { exec }) => { /* 处理匹配 */ }
    Ok(MatchedExec::Forbidden { cause, reason }) => { /* 处理禁止 */ }
    Err(err) => { /* 处理错误/未验证 */ }
}
```

### 4.2 CLI 使用

```bash
# 基本检查
cargo run -p codex-execpolicy-legacy -- check ls -l foo

# JSON 输出
cargo run -p codex-execpolicy-legacy -- check ls -l foo | jq

# 使用自定义策略
cargo run -p codex-execpolicy-legacy -- --policy custom.policy check ls -la

# 要求安全（非安全命令返回非零退出码）
cargo run -p codex-execpolicy-legacy -- --require-safe check cp foo bar

# JSON 输入模式
cargo run -p codex-execpolicy-legacy -- check-json '{"program":"ls","args":["-l"]}'
```

### 4.3 核心文件路径

| 文件 | 路径 |
|------|------|
| 库入口 | `codex-rs/execpolicy-legacy/src/lib.rs` |
| CLI 入口 | `codex-rs/execpolicy-legacy/src/main.rs` |
| 默认策略 | `codex-rs/execpolicy-legacy/src/default.policy` |
| 策略引擎 | `codex-rs/execpolicy-legacy/src/policy.rs` |
| 策略解析器 | `codex-rs/execpolicy-legacy/src/policy_parser.rs` |
| 程序规范 | `codex-rs/execpolicy-legacy/src/program.rs` |
| 执行检查器 | `codex-rs/execpolicy-legacy/src/execv_checker.rs` |
| 参数解析 | `codex-rs/execpolicy-legacy/src/arg_resolver.rs` |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `starlark` | Starlark 语言解析和执行 |
| `regex-lite` | 正则表达式支持 |
| `multimap` | 多值映射（程序名 -> 多个规则） |
| `serde`/`serde_json` | 序列化/反序列化 |
| `clap` | CLI 参数解析 |
| `path-absolutize` | 路径绝对化 |
| `allocative` | 内存分配跟踪 |
| `derive_more` | 派生宏 |
| `anyhow` | 错误处理 |
| `log`/`env_logger` | 日志记录 |

### 5.2 内部依赖

根据代码搜索，目前没有内部 crate 直接依赖 `codex-execpolicy-legacy`。新的执行策略引擎已迁移至 `codex-execpolicy` crate。

### 5.3 测试依赖

| Crate | 用途 |
|-------|------|
| `tempfile` | 临时文件/目录创建（测试用） |

---

## 6. 风险、边界与改进建议

### 6.1 已知限制

1. **选项捆绑不支持**：`ls -al` 形式的选项捆绑当前会失败（`option_bundling` 标记为 PLANNED）
2. **组合格式不支持**：`--option=value` 格式当前不完全支持
3. **双横线不支持**：`--` 参数分隔符当前会报错
4. **Sed 命令限制**：仅支持简单的行范围打印命令（如 `122,202p`）
5. **Legacy 状态**：该 crate 已被标记为 legacy，不再活跃开发

### 6.2 安全风险

1. **路径遍历**：需要调用方确保 `readable_folders` 和 `writeable_folders` 已经是规范化路径
2. **符号链接**：路径验证时需要 `realpath` 解析符号链接
3. **竞争条件**：验证和执行之间可能存在 TOCTOU（Time-of-check to time-of-use）风险
4. **正则表达式**：禁止规则使用正则表达式，可能存在 ReDoS 风险（使用 `regex-lite` 缓解）

### 6.3 边界情况

1. **相对路径**：需要 `cwd` 参数才能验证相对路径
2. **空参数列表**：某些命令（如 `ls`）允许空参数，其他（如 `cp`）不允许
3. **参数顺序**：当前实现允许标志出现在文件参数之后（某些命令实际不支持）
4. **Unicode/特殊字符**：文件名中的特殊字符可能影响验证

### 6.4 改进建议

1. **迁移至新引擎**：新项目应使用 `codex-execpolicy` crate 中的前缀规则引擎
2. **完善测试覆盖**：增加更多边界情况的测试用例
3. **文档完善**：增加更多使用示例和策略编写指南
4. **性能优化**：对于大量规则的场景，考虑使用更高效的数据结构
5. **错误信息**：提供更详细的错误信息，帮助用户理解为什么命令被拒绝

### 6.5 测试覆盖

测试文件位于 `codex-rs/execpolicy-legacy/tests/suite/`：

| 测试文件 | 覆盖内容 |
|----------|----------|
| `cp.rs` | cp 命令的各种参数组合 |
| `ls.rs` | ls 命令的标志和文件参数 |
| `head.rs` | head 命令的选项验证（正整数） |
| `pwd.rs` | pwd 命令的无参数和标志 |
| `sed.rs` | sed 命令的安全验证 |
| `literal.rs` | 字面量参数匹配 |
| `good.rs` | 正例测试列表验证 |
| `bad.rs` | 负例测试列表验证 |
| `parse_sed_command.rs` | sed 命令解析器测试 |

---

## 7. 总结

`codex-execpolicy-legacy` 是一个设计良好的命令执行安全验证引擎，使用 Starlark 作为策略定义语言，提供了灵活且类型安全的参数匹配系统。然而，由于已被标记为 legacy，新项目应使用 `codex-execpolicy` 中的新前缀规则引擎。该 crate 仍可作为学习命令行安全验证策略的参考实现。

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/execpolicy-legacy/src*
