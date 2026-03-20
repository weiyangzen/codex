# Research: codex-rs/execpolicy-legacy/tests

## 概述

`codex-rs/execpolicy-legacy/tests` 是 `codex-execpolicy-legacy` crate 的集成测试目录，负责验证 Legacy 执行策略引擎的核心功能。该测试套件确保命令执行策略（Policy）能够正确分类和验证各种 shell 命令的安全性。

---

## 场景与职责

### 核心职责

1. **策略验证测试**：验证 `default.policy` 中定义的规则能够正确匹配预期命令
2. **命令分类测试**：测试命令被正确分类为 `safe`/`match`/`forbidden`/`unverified`
3. **参数解析测试**：验证各种命令行参数（flags、options、positional args）的解析逻辑
4. **边界情况测试**：测试错误处理、非法输入、边界条件

### 测试场景

| 场景 | 描述 |
|------|------|
| Good List 验证 | 验证 `should_match` 列表中的命令都能被策略接受 |
| Bad List 验证 | 验证 `should_not_match` 列表中的命令都被策略拒绝 |
| 具体命令测试 | 针对 `cp`、`ls`、`head`、`pwd`、`sed` 等命令的详细测试 |
| Sed 命令解析 | 专门测试 sed 命令的安全性解析逻辑 |
| 字面量匹配 | 测试子命令和字面量参数匹配 |

---

## 功能点目的

### 1. 集成测试入口 (`all.rs`)

```rust
// Single integration test binary that aggregates all test modules.
// The submodules live in `tests/suite/`.
mod suite;
```

- 作为单一集成测试二进制文件的入口点
- 聚合 `tests/suite/` 下的所有测试子模块

### 2. 测试套件组织 (`suite/mod.rs`)

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

将测试按功能划分为独立模块，每个模块专注于特定命令或功能点。

### 3. Good/Bad List 验证

**`good.rs`** - 验证正面示例：
```rust
#[test]
fn verify_everything_in_good_list_is_allowed() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_good_list_individually();
    assert_eq!(Vec::<PositiveExampleFailedCheck>::new(), violations);
}
```

**`bad.rs`** - 验证负面示例：
```rust
#[test]
fn verify_everything_in_bad_list_is_rejected() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_bad_list_individually();
    assert_eq!(Vec::<NegativeExamplePassedCheck>::new(), violations);
}
```

### 4. 具体命令测试

#### `cp.rs` - 复制命令测试

测试场景：
- `test_cp_no_args`：无参数调用应失败（需要源文件和目标文件）
- `test_cp_one_arg`：单参数调用应失败
- `test_cp_one_file`：标准两参数调用（可读文件 + 可写文件）
- `test_cp_multiple_files`：多源文件复制到目标

核心验证点：
```rust
assert_eq!(
    Err(Error::NotEnoughArgs {
        program: "cp".to_string(),
        args: vec![],
        arg_patterns: vec![ArgMatcher::ReadableFiles, ArgMatcher::WriteableFile]
    }),
    policy.check(&cp)
)
```

#### `ls.rs` - 列表命令测试

测试场景：
- `test_ls_no_args`：无参数调用（合法）
- `test_ls_dash_a_dash_l`：多个 flag 组合
- `test_ls_dash_z`：未知选项应被拒绝
- `test_ls_dash_al`：选项捆绑（当前失败，待实现 `option_bundling=True`）
- `test_ls_one_file_arg` / `test_ls_multiple_file_args`：文件参数
- `test_flags_after_file_args`：文件参数后的 flag（TODO：可能需要配置支持）

#### `head.rs` - 文件头命令测试

测试场景：
- `test_head_no_args`：无参数（当前返回错误，因为需要至少一个可读文件）
- `test_head_one_file_no_flags`：单文件无选项
- `test_head_one_flag_one_file`：`-n` 选项 + 正整数参数
- 正整数验证：`test_head_invalid_n_as_0`、`test_head_invalid_n_as_nonint_float`、`test_head_invalid_n_as_negative_int`

#### `pwd.rs` - 工作目录命令测试

测试场景：
- `test_pwd_no_args`：无参数调用
- `test_pwd_capital_l` / `test_pwd_capital_p`：`-L` 和 `-P` flag
- `test_pwd_extra_args`：额外参数应被拒绝

#### `sed.rs` - 流编辑器命令测试

测试场景：
- `test_sed_print_specific_lines`：`sed -n '122,202p' file.txt` 格式
- `test_sed_print_specific_lines_with_e_flag`：使用 `-e` 选项
- `test_sed_reject_dangerous_command`：拒绝包含 `e` 标志的危险命令（如 `s/y/echo hi/e`）
- `test_sed_verify_e_or_pattern_is_required`：验证需要 `-e` 或模式

#### `literal.rs` - 字面量匹配测试

测试自定义策略中的子命令匹配：
```rust
let unparsed_policy = r#"
define_program(
    program="fake_executable",
    args=["subcommand", "sub-subcommand"],
)
"#;
```

验证：
- 完全匹配的字面量参数通过
- 不匹配的字面量参数返回 `LiteralValueDidNotMatch` 错误

#### `parse_sed_command.rs` - Sed 命令解析测试

直接测试 `parse_sed_command` 函数：
```rust
#[test]
fn parses_simple_print_command() {
    assert_eq!(parse_sed_command("122,202p"), Ok(()));
}

#[test]
fn rejects_malformed_print_command() {
    assert_eq!(
        parse_sed_command("122,202"),
        Err(Error::SedCommandNotProvablySafe { ... })
    );
}
```

---

## 具体技术实现

### 关键数据结构

#### `ExecCall` - 执行调用表示
```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,
    pub args: Vec<String>,
}

impl ExecCall {
    pub fn new(program: &str, args: &[&str]) -> Self {
        Self {
            program: program.to_string(),
            args: args.iter().map(|&s| s.into()).collect(),
        }
    }
}
```

#### `MatchedExec` - 匹配结果
```rust
pub enum MatchedExec {
    Match { exec: ValidExec },
    Forbidden { cause: Forbidden, reason: String },
}
```

#### `ValidExec` - 验证通过的执行
```rust
pub struct ValidExec {
    pub program: String,
    pub flags: Vec<MatchedFlag>,
    pub opts: Vec<MatchedOpt>,
    pub args: Vec<MatchedArg>,
    pub system_path: Vec<String>,
}
```

#### `ArgMatcher` - 参数匹配器
```rust
pub enum ArgMatcher {
    Literal(String),
    OpaqueNonFile,
    ReadableFile,
    WriteableFile,
    ReadableFiles,
    ReadableFilesOrCwd,
    PositiveInteger,
    SedCommand,
    UnverifiedVarargs,
}
```

### 关键流程

#### 测试设置流程
```rust
#[expect(clippy::expect_used)]
fn setup() -> Policy {
    get_default_policy().expect("failed to load default policy")
}
```

所有测试模块使用 `get_default_policy()` 加载 `src/default.policy` 中定义的默认策略。

#### 策略检查流程
```rust
let policy = setup();
let cp = ExecCall::new("cp", &["foo/bar", "../baz"]);
let result = policy.check(&cp);
```

#### 验证流程（Good List）
```rust
pub fn check_each_good_list_individually(&self) -> Vec<PositiveExampleFailedCheck> {
    let mut violations = Vec::new();
    for (_program, spec) in self.programs.flat_iter() {
        violations.extend(spec.verify_should_match_list());
    }
    violations
}
```

#### 验证流程（Bad List）
```rust
pub fn check_each_bad_list_individually(&self) -> Vec<NegativeExamplePassedCheck> {
    let mut violations = Vec::new();
    for (_program, spec) in self.programs.flat_iter() {
        violations.extend(spec.verify_should_not_match_list());
    }
    violations
}
```

### 策略文件格式 (Starlark)

`default.policy` 使用 Starlark 语言定义规则：

```python
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[
        ["foo", "bar"],
    ],
    should_not_match=[
        ["foo"],
    ],
)
```

### 预定义参数匹配器常量

| 常量 | 对应 ArgMatcher | 说明 |
|------|----------------|------|
| `ARG_OPAQUE_VALUE` | `OpaqueNonFile` | 非文件值 |
| `ARG_RFILE` | `ReadableFile` | 单个可读文件 |
| `ARG_WFILE` | `WriteableFile` | 单个可写文件 |
| `ARG_RFILES` | `ReadableFiles` | 一个或多个可读文件 |
| `ARG_RFILES_OR_CWD` | `ReadableFilesOrCwd` | 可读文件或当前目录 |
| `ARG_POS_INT` | `PositiveInteger` | 正整数 |
| `ARG_SED_COMMAND` | `SedCommand` | Sed 命令 |
| `ARG_UNVERIFIED_VARARGS` | `UnverifiedVarargs` | 未验证可变参数 |

---

## 关键代码路径与文件引用

### 测试文件结构

```
codex-rs/execpolicy-legacy/tests/
├── all.rs                      # 测试入口
└── suite/
    ├── mod.rs                  # 测试模块聚合
    ├── bad.rs                  # Bad list 验证
    ├── cp.rs                   # cp 命令测试
    ├── good.rs                 # Good list 验证
    ├── head.rs                 # head 命令测试
    ├── literal.rs              # 字面量匹配测试
    ├── ls.rs                   # ls 命令测试
    ├── parse_sed_command.rs    # sed 命令解析测试
    ├── pwd.rs                  # pwd 命令测试
    └── sed.rs                  # sed 命令测试
```

### 被测试的源代码

```
codex-rs/execpolicy-legacy/src/
├── lib.rs                    # 库入口，导出公共 API
├── main.rs                   # CLI 二进制入口
├── policy.rs                 # Policy 结构体和检查逻辑
├── policy_parser.rs          # Starlark 策略解析
├── program.rs                # ProgramSpec 和匹配逻辑
├── arg_matcher.rs            # ArgMatcher 枚举
├── arg_resolver.rs           # 参数解析逻辑
├── arg_type.rs               # ArgType 枚举和验证
├── valid_exec.rs             # ValidExec、MatchedArg 等
├── exec_call.rs              # ExecCall 结构体
├── execv_checker.rs          # ExecvChecker（文件系统检查）
├── sed_command.rs            # Sed 命令解析
├── opt.rs                    # Opt 和 OptMeta 定义
├── error.rs                  # Error 枚举
└── default.policy            # 默认策略定义
```

### 关键代码路径

1. **策略加载路径**：
   ```
   get_default_policy() 
   -> PolicyParser::new("#default", DEFAULT_POLICY)
   -> PolicyParser::parse()
   -> starlark 解析
   -> PolicyBuilder 构建 Policy
   ```

2. **命令检查路径**：
   ```
   Policy::check(exec_call)
   -> 检查 forbidden_program_regexes
   -> 检查 forbidden_substrings
   -> 查找 program 对应的 ProgramSpec 列表
   -> 逐个尝试 ProgramSpec::check()
   -> 返回 MatchedExec 或 Error
   ```

3. **参数匹配路径**：
   ```
   ProgramSpec::check()
   -> 解析 flags 和 options
   -> resolve_observed_args_with_patterns()
   -> 匹配 prefix patterns
   -> 匹配 vararg pattern
   -> 匹配 suffix patterns
   -> 验证 required options
   -> 返回 MatchedExec
   ```

---

## 依赖与外部交互

### 测试依赖

**`Cargo.toml` 中的 dev-dependencies：**
```toml
[dev-dependencies]
tempfile = { workspace = true }
```

`tempfile` 用于 `execv_checker.rs` 中的单元测试（创建临时目录和文件）。

### 运行时依赖

**核心依赖：**
- `starlark` (0.13.0)：策略文件解析
- `regex-lite` (0.1.8)：正则表达式匹配（禁止的程序名模式）
- `multimap` (0.10.0)：一个程序名可能对应多个 ProgramSpec
- `path-absolutize` (3.1.1)：路径绝对化
- `serde` / `serde_json`：序列化/反序列化
- `clap`：CLI 参数解析

### 外部交互

1. **策略文件**：`src/default.policy`（编译时嵌入）
2. **文件系统**：`ExecvChecker` 检查可读/可写文件夹（测试中模拟）
3. **CLI 接口**：支持自定义策略文件路径 (`--policy`)

### 调用方

- `codex-execpolicy-legacy` CLI 工具（`src/main.rs`）
- `ExecvChecker` 用于更高级的文件系统权限检查
- 其他 crates 可能通过依赖使用策略检查功能

---

## 风险、边界与改进建议

### 当前风险

1. **Sed 命令安全性**
   - 当前仅支持简单的 `122,202p` 格式打印命令
   - GNU sed 的 `e` 标志可以执行任意命令，存在安全风险
   - 解析逻辑过于简单，可能遗漏其他危险模式

2. **选项捆绑未实现**
   ```rust
   // ls.rs 中的 TODO
   // This currently fails, but it should pass once option_bundling=True is implemented.
   let ls_al = ExecCall::new("ls", &["-al"]);
   ```

3. **双横线支持**
   ```rust
   // program.rs
   else if arg == "--" {
       return Err(Error::DoubleDashNotSupportedYet {
           program: self.program.clone(),
       });
   }
   ```

4. **`--option=value` 格式**
   - `combined_format` 标记为 PLANNED，尚未实现

### 边界情况

1. **空文件名**：`ArgType::ReadableFile` 和 `WriteableFile` 验证非空
2. **正整数验证**：`0`、`1.5`、`1.0`、`-1` 都被正确拒绝
3. **相对路径**：需要 `cwd` 上下文才能正确解析
4. **参数位置**：flags 在文件参数后的行为可能因命令而异

### 改进建议

1. **扩展 Sed 支持**
   - 实现更完整的 sed 命令解析器
   - 建立明确的允许/拒绝命令白名单/黑名单

2. **实现选项捆绑**
   ```python
   define_program(
       program="ls",
       option_bundling=True,  # 启用 -al 作为 -a -l
       ...
   )
   ```

3. **支持 `--` 参数终止**
   - 允许 `--` 后的参数被视为位置参数而非选项

4. **支持 `--option=value` 格式**
   - 实现 `combined_format` 配置

5. **增强错误信息**
   - 提供更多上下文帮助用户理解为什么命令被拒绝

6. **策略热重载**
   - 当前策略在编译时嵌入，考虑支持运行时策略更新

7. **更多测试覆盖**
   - 添加模糊测试（fuzzing）发现边界情况
   - 测试更多复杂命令组合

8. **性能优化**
   - 对于大量规则，考虑使用 Trie 或类似结构加速匹配

---

## 总结

`codex-rs/execpolicy-legacy/tests` 是一个设计良好的集成测试套件，通过模块化组织测试各种命令执行场景。测试覆盖了策略验证的核心功能，包括 Good/Bad List 验证、具体命令测试和边界情况处理。该测试套件确保了 Legacy 执行策略引擎的正确性和安全性，是 Codex 项目安全基础设施的重要组成部分。

测试与源代码紧密对应，通过 `ExecCall`、`Policy`、`ArgMatcher` 等核心抽象，建立了清晰的测试接口。策略使用 Starlark 语言定义，提供了灵活而安全的配置方式。
