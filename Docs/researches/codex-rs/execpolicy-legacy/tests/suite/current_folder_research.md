# DIR codex-rs/execpolicy-legacy/tests/suite 研究文档

## 场景与职责

`codex-rs/execpolicy-legacy/tests/suite` 是 `codex-execpolicy-legacy` crate 的集成测试套件目录。该目录包含了对遗留执行策略引擎（legacy exec policy engine）的全面测试，用于验证命令行执行调用的安全性检查功能。

### 核心职责

1. **验证默认策略的正确性**：测试 `default.policy` 中定义的各种程序规则是否能正确匹配/拒绝命令
2. **验证策略解析器**：测试 Starlark 格式的策略文件解析功能
3. **验证参数匹配逻辑**：测试各种参数类型（文件、标志、选项等）的匹配和验证
4. **验证安全边界**：确保危险命令被拒绝，安全命令被正确识别

### 与主 crate 的关系

- **被测试库**: `codex-rs/execpolicy-legacy/src/` 下的所有模块
- **测试类型**: 集成测试（使用 `#[test]` 属性的单元测试风格）
- **测试数据**: 依赖 `src/default.policy` 作为默认策略源

---

## 功能点目的

### 测试模块概览

| 测试文件 | 测试目标 | 核心功能 |
|---------|---------|---------|
| `mod.rs` | 模块聚合 | 声明所有子模块，作为测试入口 |
| `bad.rs` | 负面示例验证 | 验证 `should_not_match` 列表中的命令确实被拒绝 |
| `good.rs` | 正面示例验证 | 验证 `should_match` 列表中的命令确实被接受 |
| `cp.rs` | cp 命令测试 | 测试文件复制命令的各种参数组合 |
| `head.rs` | head 命令测试 | 测试文件头读取命令及正整数选项验证 |
| `ls.rs` | ls 命令测试 | 测试目录列表命令的标志和文件参数 |
| `pwd.rs` | pwd 命令测试 | 测试工作目录命令的无参和标志模式 |
| `sed.rs` | sed 命令测试 | 测试流编辑器命令的安全子集 |
| `parse_sed_command.rs` | sed 解析测试 | 测试 sed 命令字符串的安全解析 |
| `literal.rs` | 字面量测试 | 测试子命令字面量匹配功能 |

### 测试覆盖的功能领域

1. **命令分类验证**
   - `safe`: 命令完全安全，可以直接执行
   - `match`: 命令匹配策略，但需要调用方根据文件写入情况决定
   - `forbidden`: 命令被禁止执行
   - `unverified`: 无法确定安全性，需要用户决定

2. **参数类型验证**
   - `ReadableFile` / `ReadableFiles`: 可读文件参数
   - `WriteableFile`: 可写文件参数
   - `Literal`: 字面量匹配（如子命令）
   - `PositiveInteger`: 正整数选项值
   - `SedCommand`: 安全的 sed 命令子集

3. **选项(flag/opt)验证**
   - 无值标志（flag）: 如 `ls -a`, `ls -l`
   - 有值选项（opt）: 如 `head -n 100`
   - 必需选项验证
   - 未知选项拒绝

---

## 具体技术实现

### 关键数据结构

#### 1. ExecCall - 执行调用表示

```rust
// src/exec_call.rs
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,
    pub args: Vec<String>,
}

impl ExecCall {
    pub fn new(program: &str, args: &[&str]) -> Self
}
```

测试中使用 `ExecCall::new("program", &["arg1", "arg2"])` 构造测试输入。

#### 2. MatchedExec - 匹配结果枚举

```rust
// src/program.rs
pub enum MatchedExec {
    Match { exec: ValidExec },
    Forbidden { cause: Forbidden, reason: String },
}
```

测试断言主要验证返回的 `MatchedExec` 变体是否正确。

#### 3. ValidExec - 验证通过的执行

```rust
// src/valid_exec.rs
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct ValidExec {
    pub program: String,
    pub flags: Vec<MatchedFlag>,
    pub opts: Vec<MatchedOpt>,
    pub args: Vec<MatchedArg>,
    pub system_path: Vec<String>,
}
```

包含匹配的标志、选项和参数详情。

#### 4. MatchedArg - 匹配的参数

```rust
// src/valid_exec.rs
pub struct MatchedArg {
    pub index: usize,      // 参数在原始命令中的索引
    pub r#type: ArgType,   // 参数类型
    pub value: String,     // 参数值
}
```

#### 5. Error - 错误类型

```rust
// src/error.rs
pub enum Error {
    NoSpecForProgram { program: String },
    UnknownOption { program: String, option: String },
    UnexpectedArguments { program: String, args: Vec<PositionalArg> },
    NotEnoughArgs { program: String, args: Vec<PositionalArg>, arg_patterns: Vec<ArgMatcher> },
    VarargMatcherDidNotMatchAnything { program: String, matcher: ArgMatcher },
    LiteralValueDidNotMatch { expected: String, actual: String },
    InvalidPositiveInteger { value: String },
    MissingRequiredOptions { program: String, options: Vec<String> },
    SedCommandNotProvablySafe { command: String },
    // ... 其他变体
}
```

### 关键流程

#### 1. 策略加载流程

```rust
// src/lib.rs
const DEFAULT_POLICY: &str = include_str!("default.policy");

pub fn get_default_policy() -> starlark::Result<Policy> {
    let parser = PolicyParser::new("#default", DEFAULT_POLICY);
    parser.parse()
}
```

策略文件在编译时嵌入，运行时通过 Starlark 解析器解析。

#### 2. 命令检查流程

```rust
// src/policy.rs
pub fn check(&self, exec_call: &ExecCall) -> Result<MatchedExec> {
    // 1. 检查禁止的程序正则
    for forbidden_regex in &self.forbidden_program_regexes {
        if regex.is_match(program) {
            return Ok(MatchedExec::Forbidden { ... });
        }
    }
    
    // 2. 检查禁止的子字符串
    for arg in args {
        if forbidden_substrings_pattern.is_match(arg) {
            return Ok(MatchedExec::Forbidden { ... });
        }
    }
    
    // 3. 查找程序规格并逐个尝试匹配
    if let Some(spec_list) = self.programs.get_vec(program) {
        for spec in spec_list {
            match spec.check(exec_call) {
                Ok(matched_exec) => return Ok(matched_exec),
                Err(err) => last_err = Err(err),
            }
        }
    }
    last_err  // 返回最后一个错误（无匹配规格）
}
```

#### 3. 程序规格检查流程

```rust
// src/program.rs
pub fn check(&self, exec_call: &ExecCall) -> Result<MatchedExec> {
    // 1. 解析选项和参数
    for (index, arg) in exec_call.args.iter().enumerate() {
        if arg.starts_with("-") {
            // 处理标志或选项
            match self.allowed_options.get(arg) {
                Some(opt) => {
                    match &opt.meta {
                        OptMeta::Flag => { /* 记录标志 */ },
                        OptMeta::Value(arg_type) => { /* 期待下一个参数作为值 */ },
                    }
                }
                None => return Err(Error::UnknownOption { ... }),
            }
        } else {
            // 记录位置参数
            args.push(PositionalArg { index, value: arg.clone() });
        }
    }
    
    // 2. 解析位置参数（使用 ArgMatcher 模式）
    let matched_args = resolve_observed_args_with_patterns(...)?;
    
    // 3. 验证必需选项
    if !matched_opt_names.is_superset(&self.required_options) {
        return Err(Error::MissingRequiredOptions { ... });
    }
    
    // 4. 返回结果（Match 或 Forbidden）
}
```

#### 4. 参数解析算法

```rust
// src/arg_resolver.rs
pub fn resolve_observed_args_with_patterns(
    program: &str,
    args: Vec<PositionalArg>,
    arg_patterns: &Vec<ArgMatcher>,
) -> Result<Vec<MatchedArg>> {
    // 1. 分区：前缀模式、可变参数模式、后缀模式
    let ParitionedArgs { 
        num_prefix_args, 
        num_suffix_args, 
        prefix_patterns, 
        suffix_patterns, 
        vararg_pattern 
    } = partition_args(program, arg_patterns)?;
    
    // 2. 匹配前缀参数
    for pattern in prefix_patterns { ... }
    
    // 3. 匹配可变参数（如果存在）
    if let Some(pattern) = vararg_pattern {
        match pattern.cardinality() {
            AtLeastOne => { /* 确保至少一个 */ },
            ZeroOrMore => { /* 允许零个 */ },
        }
    }
    
    // 4. 匹配后缀参数
    for pattern in suffix_patterns { ... }
    
    // 5. 检查是否有未匹配的参数
    if matched_args.len() < args.len() {
        return Err(Error::UnexpectedArguments { ... });
    }
}
```

### 策略文件格式 (Starlark)

```python
# src/default.policy 示例
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],  # 一个或多个可读文件 + 一个可写文件
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],
    should_not_match=[["foo"]],
)
```

内置的 ArgMatcher 常量：
- `ARG_OPAQUE_VALUE`: 非文件的不透明值
- `ARG_RFILE`: 单个可读文件
- `ARG_WFILE`: 单个可写文件
- `ARG_RFILES`: 一个或多个可读文件
- `ARG_RFILES_OR_CWD`: 零个或多个可读文件（空表示当前目录）
- `ARG_POS_INT`: 正整数
- `ARG_SED_COMMAND`: 安全的 sed 命令
- `ARG_UNVERIFIED_VARARGS`: 未验证的可变参数

### Sed 命令安全解析

```rust
// src/sed_command.rs
pub fn parse_sed_command(sed_command: &str) -> Result<()> {
    // 仅允许格式如 "122,202p" 的打印命令
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

**安全考虑**: GNU sed 支持 `e` 标志可以执行任意 shell 命令（如 `s/y/echo hi/e`），因此需要严格限制允许的命令格式。

---

## 关键代码路径与文件引用

### 测试文件详细分析

#### 1. `mod.rs` - 模块入口
```rust
// Aggregates all former standalone integration tests as modules.
mod bad;
mod cp;
mod good;
mod head;
mod literal;
mod ls;
mod parse_sed_command;
mod pwd;
mod sed;
```

#### 2. `good.rs` - 正面示例验证
```rust
#[test]
fn verify_everything_in_good_list_is_allowed() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_good_list_individually();
    assert_eq!(Vec::<PositiveExampleFailedCheck>::new(), violations);
}
```
遍历所有 `define_program` 中的 `should_match` 示例，确保都能通过检查。

#### 3. `bad.rs` - 负面示例验证
```rust
#[test]
fn verify_everything_in_bad_list_is_rejected() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_bad_list_individually();
    assert_eq!(Vec::<NegativeExamplePassedCheck>::new(), violations);
}
```
遍历所有 `define_program` 中的 `should_not_match` 示例，确保都被拒绝。

#### 4. `cp.rs` - cp 命令详细测试
测试场景：
- 无参数：`cp` → `NotEnoughArgs` 错误
- 单参数：`cp foo/bar` → `VarargMatcherDidNotMatchAnything` 错误
- 双参数：`cp foo/bar ../baz` → 成功匹配（可读文件 + 可写文件）
- 多参数：`cp foo bar baz` → 成功匹配（多个可读文件 + 可写文件）

#### 5. `head.rs` - head 命令详细测试
测试场景：
- 无参数：`head` → 拒绝（需要至少一个可读文件）
- 单文件：`head src/extension.ts` → 成功
- 带选项：`head -n 100 src/extension.ts` → 成功，验证 `-n` 选项值类型
- 无效选项值：`head -n 0`, `head -n 1.5`, `head -n -1` → 各种错误

#### 6. `ls.rs` - ls 命令详细测试
测试场景：
- 无参数：`ls` → 成功（允许空参数）
- 多标志：`ls -a -l` → 成功
- 未知标志：`ls -z` → `UnknownOption` 错误
- 标志组合：`ls -al` → 当前失败（TODO: 待实现 `option_bundling`）
- 文件参数：`ls foo bar baz` → 成功，标记为可读文件
- 标志位置：`ls foo -l` → 当前成功（TODO: 某些命令不允许标志在参数后）

#### 7. `pwd.rs` - pwd 命令详细测试
测试场景：
- 无参数：`pwd` → 成功
- `-L` 标志：`pwd -L` → 成功
- `-P` 标志：`pwd -P` → 成功
- 多余参数：`pwd foo bar` → `UnexpectedArguments` 错误

#### 8. `sed.rs` - sed 命令安全测试
测试场景：
- 打印特定行：`sed -n "122,202p" hello.txt` → 成功
- 使用 `-e` 标志：`sed -n -e "122,202p" hello.txt` → 成功
- 危险命令：`sed -e "s/y/echo hi/e" hello.txt` → `SedCommandNotProvablySafe` 错误
- 缺少必需选项：`sed "122,202p"` → `MissingRequiredOptions` 错误（需要 `-e` 或 `-n`）

#### 9. `parse_sed_command.rs` - sed 解析单元测试
```rust
#[test]
fn parses_simple_print_command() {
    assert_eq!(parse_sed_command("122,202p"), Ok(()));
}

#[test]
fn rejects_malformed_print_command() {
    assert_eq!(parse_sed_command("122,202"), Err(...));  // 缺少 p 后缀
    assert_eq!(parse_sed_command("122202"), Err(...));   // 缺少逗号
}
```

#### 10. `literal.rs` - 字面量子命令测试
```rust
#[test]
fn test_invalid_subcommand() -> Result<()> {
    // 定义一个带子命令的程序规则
    let unparsed_policy = r#"
define_program(
    program="fake_executable",
    args=["subcommand", "sub-subcommand"],
)
"#;
    // 测试匹配和不匹配的情况
}
```

### 被测试的源文件映射

| 测试文件 | 主要测试的源文件 | 相关功能 |
|---------|----------------|---------|
| `good.rs`, `bad.rs` | `src/policy.rs`, `src/program.rs` | `check_each_good_list_individually()`, `check_each_bad_list_individually()` |
| `cp.rs`, `head.rs`, `ls.rs`, `pwd.rs`, `sed.rs` | `src/policy.rs`, `src/program.rs` | `Policy::check()`, `ProgramSpec::check()` |
| `literal.rs` | `src/policy_parser.rs` | `PolicyParser::parse()` |
| `parse_sed_command.rs` | `src/sed_command.rs` | `parse_sed_command()` |

---

## 依赖与外部交互

### 内部依赖

```
tests/suite/
├── mod.rs (聚合模块)
├── bad.rs ───────────────┐
├── cp.rs ────────────────┤
├── good.rs ──────────────┤
├── head.rs ──────────────┤
├── literal.rs ───────────┼──> codex_execpolicy_legacy (lib)
├── ls.rs ────────────────┤      ├── src/policy.rs
├── parse_sed_command.rs ─┤      ├── src/program.rs
├── pwd.rs ───────────────┤      ├── src/exec_call.rs
└── sed.rs ───────────────┤      ├── src/valid_exec.rs
tests/mod.rs (测试入口) ────┘      ├── src/error.rs
                                   ├── src/arg_matcher.rs
                                   ├── src/arg_resolver.rs
                                   ├── src/arg_type.rs
                                   ├── src/policy_parser.rs
                                   ├── src/sed_command.rs
                                   ├── src/opt.rs
                                   └── src/default.policy
```

### 外部 crate 依赖

**被测试库依赖** (`Cargo.toml`):
- `starlark`: Starlark 语言解析（Google 的配置语言，类似 Python）
- `regex-lite`: 轻量级正则表达式
- `multimap`: 多值映射
- `serde` / `serde_json`: 序列化
- `anyhow`: 错误处理
- `clap`: CLI 解析
- `path-absolutize`: 路径绝对化
- `allocative`, `derive_more`: 派生宏

**测试依赖**:
- `tempfile`: 临时文件（用于可能的文件系统测试）

### 策略文件依赖

测试直接依赖编译时嵌入的 `src/default.policy` 文件，该文件定义了：
- `ls`, `cat`, `cp`, `head`, `printenv`, `pwd`, `rg`, `sed`, `which` 等程序的安全规则
- 每个程序的允许选项、参数模式、系统路径
- 正面和负面测试示例

---

## 风险、边界与改进建议

### 已知限制与 TODO

1. **选项组合（Option Bundling）**
   - 当前 `ls -al` 会失败，因为未实现 `-al` → `-a -l` 的展开
   - `ProgramSpec.option_bundling` 字段存在但默认为 `false`
   - 代码位置：`src/program.rs:22`

2. **组合格式（Combined Format）**
   - 未支持 `--option=value` 格式
   - 当前只支持 `--option value` 格式
   - 代码位置：`src/program.rs:23`

3. **双横线（Double Dash）**
   - `--` 用于分隔选项和参数的功能未实现
   - 当前会返回 `DoubleDashNotSupportedYet` 错误
   - 代码位置：`src/program.rs:116-119`

4. **标志位置限制**
   - 某些命令（如 `ls`）实际上不允许标志出现在文件参数之后
   - 当前策略无法表达这种限制
   - 相关 TODO: `src/program.rs:TODO(mbolin)`

### 安全风险

1. **Sed 命令解析限制**
   - 当前只允许 `"数字,数字p"` 格式的打印命令
   - GNU sed 的 `e` 标志可以执行任意命令，必须严格限制
   - 改进建议：考虑使用白名单而非黑名单方式

2. **路径解析**
   - 测试中使用相对路径（如 `foo/bar`）
   - 实际安全决策需要结合 `getcwd()` 和 `realpath()` 解析
   - 库返回的是结构化结果，调用方负责最终安全决策

3. **正则表达式安全**
   - `forbidden_program_regexes` 使用 regex-lite，相对安全
   - 但复杂的正则仍可能有 ReDoS 风险

### 测试覆盖建议

1. **增加边界测试**
   - 空字符串参数
   - 特殊字符文件名
   - 极长的参数列表
   - Unicode 文件名

2. **增加错误路径测试**
   - `PrefixOverlapsSuffix` 错误场景
   - `RangeStartExceedsEnd` 错误场景
   - `InternalInvariantViolation` 错误场景

3. **增加策略解析测试**
   - 语法错误的策略文件
   - 重复的选项定义
   - 无效的 ArgMatcher 组合

### 代码质量改进

1. **测试辅助函数**
   - 当前每个测试文件都有重复的 `setup()` 函数
   - 建议提取到公共测试工具模块

2. **断言可读性**
   - 复杂的 `assert_eq!` 可以提取为自定义断言宏
   - 错误消息的格式化可以更清晰

3. **测试文档**
   - 添加更多内联注释解释测试意图
   - 特别是安全相关的测试用例

### 架构演进

根据 README 说明：
> This crate hosts the original execpolicy implementation. The newer prefix-rule engine lives in `codex-execpolicy`.

这表明 `codex-execpolicy-legacy` 是遗留实现，新项目应该使用 `codex-execpolicy`（基于前缀规则的新引擎）。测试套件的价值在于：
1. 确保遗留实现的稳定性
2. 作为新实现的兼容性参考
3. 记录已知的安全边界和限制

---

## 附录：测试运行方式

```bash
# 运行所有测试
cargo test -p codex-execpolicy-legacy

# 运行特定测试
cargo test -p codex-execpolicy-legacy test_cp_one_file
cargo test -p codex-execpolicy-legacy test_head_invalid_n_as_0

# 使用 nextest（如果已安装）
just test -p codex-execpolicy-legacy
```

## 附录：策略调试 CLI

```bash
# 检查命令并查看 JSON 输出
cargo run -p codex-execpolicy-legacy -- check ls -l foo | jq

# 使用自定义策略文件
cargo run -p codex-execpolicy-legacy -- --policy custom.policy check cp src dest
```
