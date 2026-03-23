# 研究报告：`codex-rs/execpolicy-legacy/tests/all.rs`

## 1. 场景与职责

### 1.1 文件定位

`all.rs` 是 `codex-execpolicy-legacy` crate 的集成测试入口文件，位于 `codex-rs/execpolicy-legacy/tests/` 目录下。它采用 Rust 的集成测试模式，通过聚合子模块的方式组织测试代码。

### 1.2 核心职责

该文件的核心职责非常简单但关键：
- **作为单一集成测试二进制文件的入口点**
- **聚合所有测试子模块**（位于 `tests/suite/` 目录下）
- **确保 `default.policy` 策略文件的完整性通过单元测试验证**

### 1.3 项目背景

`codex-execpolicy-legacy` 是 Codex 项目的原始执行策略引擎，用于分类和验证 `execv(3)` 系统调用命令的安全性。根据 `README.md`，该引擎将命令分类为四种状态：
- `safe`: 命令安全可执行
- `match`: 命令匹配策略规则，但调用者需根据写入文件决定是否安全
- `forbidden`: 命令被禁止执行
- `unverified`: 安全性无法确定，需用户决定

### 1.4 测试架构设计

```
codex-rs/execpolicy-legacy/tests/
├── all.rs          # 测试入口（本文件）
└── suite/
    ├── mod.rs      # 子模块聚合器
    ├── bad.rs      # 验证 "should_not_match" 列表
    ├── good.rs     # 验证 "should_match" 列表
    ├── cp.rs       # cp 命令详细测试
    ├── head.rs     # head 命令详细测试
    ├── ls.rs       # ls 命令详细测试
    ├── pwd.rs      # pwd 命令详细测试
    ├── sed.rs      # sed 命令详细测试
    ├── literal.rs  # 字面量参数测试
    └── parse_sed_command.rs  # sed 命令解析测试
```

## 2. 功能点目的

### 2.1 测试覆盖范围

通过 `suite/mod.rs` 聚合的测试模块覆盖了以下功能点：

| 测试模块 | 功能目的 |
|---------|---------|
| `bad.rs` | 验证 `default.policy` 中所有 `should_not_match` 示例确实被拒绝 |
| `good.rs` | 验证 `default.policy` 中所有 `should_match` 示例确实被接受 |
| `cp.rs` | 测试 `cp` 命令的各种参数组合和边界情况 |
| `head.rs` | 测试 `head` 命令的选项（`-n`, `-c`）和正整数验证 |
| `ls.rs` | 测试 `ls` 命令的标志（`-a`, `-l`, `-1`）和文件参数处理 |
| `pwd.rs` | 测试 `pwd` 命令的简单标志（`-L`, `-P`）和多余参数拒绝 |
| `sed.rs` | 测试 `sed` 命令的安全命令解析和危险命令拒绝 |
| `literal.rs` | 测试字面量参数匹配（如子命令）的正确性 |
| `parse_sed_command.rs` | 测试 sed 命令字符串的安全解析逻辑 |

### 2.2 测试策略分类

#### 2.2.1 策略自验证测试（Policy Self-Validation）

`good.rs` 和 `bad.rs` 实现了策略文件的自验证机制：

```rust
// good.rs - 验证所有正面示例通过检查
#[test]
fn verify_everything_in_good_list_is_allowed() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_good_list_individually();
    assert_eq!(Vec::<PositiveExampleFailedCheck>::new(), violations);
}

// bad.rs - 验证所有负面示例被拒绝
#[test]
fn verify_everything_in_bad_list_is_rejected() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_bad_list_individually();
    assert_eq!(Vec::<NegativeExamplePassedCheck>::new(), violations);
}
```

这种设计使得策略文件 `default.policy` 中的每个 `define_program` 调用都可以内联测试示例，确保策略定义的正确性。

#### 2.2.2 命令特定功能测试

以 `cp.rs` 为例，测试覆盖了：
- 无参数调用（应返回 `NotEnoughArgs` 错误）
- 单参数调用（应返回 `VarargMatcherDidNotMatchAnything` 错误）
- 标准两参数调用（源文件 + 目标文件）
- 多源文件复制（多个可读文件 + 一个可写文件）

以 `head.rs` 为例，测试覆盖了：
- 无参数调用（从 stdin 读取，当前策略拒绝）
- 单文件参数
- 带 `-n` 选项和正整数的调用
- 各种无效的正整数输入（0、浮点数、负数）

### 2.3 与生产代码的关联

测试通过 `codex_execpolicy_legacy` crate 的公共 API 进行：
- `get_default_policy()`: 加载默认策略
- `Policy::check()`: 检查命令是否匹配策略
- `Policy::check_each_good_list_individually()`: 验证正面示例
- `Policy::check_each_bad_list_individually()`: 验证负面示例
- `ExecCall::new()`: 构建测试用的执行调用

## 3. 具体技术实现

### 3.1 测试模块组织

#### 3.1.1 all.rs

```rust
// Single integration test binary that aggregates all test modules.
// The submodules live in `tests/suite/`.
mod suite;
```

这是标准的 Rust 集成测试模式。根据 Cargo 的约定，`tests/` 目录下的每个 `.rs` 文件会被编译为独立的集成测试二进制文件。通过将测试代码放在 `tests/suite/` 子目录下，并在 `all.rs` 中通过 `mod suite` 引入，所有测试被聚合到单一二进制文件中执行。

#### 3.1.2 suite/mod.rs

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

该模块文件聚合了所有测试子模块，使得 `all.rs` 只需一行 `mod suite` 即可引入全部测试。

### 3.2 关键数据结构

#### 3.2.1 ExecCall（执行调用）

```rust
// src/exec_call.rs
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

测试中广泛使用 `ExecCall::new(program, args)` 构造测试用例。

#### 3.2.2 MatchedExec（匹配结果）

```rust
// src/program.rs
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub enum MatchedExec {
    Match { exec: ValidExec },
    Forbidden { cause: Forbidden, reason: String },
}
```

测试通过匹配 `MatchedExec::Match` 或特定 `Error` 来验证行为。

#### 3.2.3 ValidExec（有效执行）

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

测试验证解析后的命令结构是否符合预期。

#### 3.2.4 Error（错误类型）

```rust
// src/error.rs
#[derive(Debug, Eq, PartialEq, Serialize)]
#[serde(tag = "type")]
pub enum Error {
    NoSpecForProgram { program: String },
    UnknownOption { program: String, option: String },
    NotEnoughArgs { program: String, args: Vec<PositionalArg>, arg_patterns: Vec<ArgMatcher> },
    VarargMatcherDidNotMatchAnything { program: String, matcher: ArgMatcher },
    LiteralValueDidNotMatch { expected: String, actual: String },
    InvalidPositiveInteger { value: String },
    SedCommandNotProvablySafe { command: String },
    // ... 更多变体
}
```

测试通过精确匹配错误类型来验证失败场景。

### 3.3 关键测试模式

#### 3.3.1 标准测试模板

```rust
#[expect(clippy::expect_used)]
fn setup() -> Policy {
    get_default_policy().expect("failed to load default policy")
}

#[test]
fn test_xxx() -> Result<()> {
    let policy = setup();
    let exec_call = ExecCall::new("program", &["arg1", "arg2"]);
    assert_eq!(
        Ok(MatchedExec::Match { exec: ValidExec { ... } }),
        policy.check(&exec_call)
    );
    Ok(())
}
```

#### 3.3.2 错误验证模式

```rust
#[test]
fn test_invalid_input() {
    let policy = setup();
    let exec_call = ExecCall::new("program", &["invalid"]);
    assert_eq!(
        Err(Error::SpecificError { ... }),
        policy.check(&exec_call)
    );
}
```

### 3.4 策略文件格式

`default.policy` 使用 Starlark 语言定义策略规则：

```starlark
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],
    should_not_match=[["foo"]],
)
```

内置的 ArgMatcher 常量：
- `ARG_OPAQUE_VALUE`: 非文件的不透明值
- `ARG_RFILE`: 可读文件
- `ARG_WFILE`: 可写文件
- `ARG_RFILES`: 一个或多个可读文件
- `ARG_RFILES_OR_CWD`: 可读文件或当前工作目录
- `ARG_POS_INT`: 正整数
- `ARG_SED_COMMAND`: 安全的 sed 命令
- `ARG_UNVERIFIED_VARARGS`: 未验证的可变参数

## 4. 关键代码路径与文件引用

### 4.1 测试执行流程

```
all.rs
  └── mod suite;
      └── suite/mod.rs
          ├── mod bad;   → 调用 Policy::check_each_bad_list_individually()
          ├── mod good;  → 调用 Policy::check_each_good_list_individually()
          ├── mod cp;    → 调用 Policy::check() 进行具体验证
          ├── mod head;  → 调用 Policy::check() 进行具体验证
          ├── mod ls;    → 调用 Policy::check() 进行具体验证
          ├── mod pwd;   → 调用 Policy::check() 进行具体验证
          ├── mod sed;   → 调用 Policy::check() 进行具体验证
          ├── mod literal; → 调用 Policy::check() 进行具体验证
          └── mod parse_sed_command; → 直接测试 parse_sed_command()
```

### 4.2 核心调用链

#### 4.2.1 策略检查流程

```
Policy::check(exec_call)
  ├── 检查禁止的程序正则表达式
  ├── 检查参数中的禁止子串
  └── 遍历 ProgramSpec 列表
       └── ProgramSpec::check(exec_call)
            ├── 解析选项（flags 和 opts）
            ├── 收集位置参数
            ├── resolve_observed_args_with_patterns()
            │     └── 匹配 ArgMatcher 模式
            ├── 验证必需选项
            └── 返回 MatchedExec
```

#### 4.2.2 策略加载流程

```
get_default_policy()
  └── PolicyParser::new("#default", DEFAULT_POLICY).parse()
       └── 使用 starlark-rust 解析 .policy 文件
            └── 构建 Policy 对象
```

### 4.3 关键文件引用

| 文件 | 职责 | 测试关联 |
|-----|------|---------|
| `tests/all.rs` | 测试入口 | 本文件 |
| `tests/suite/mod.rs` | 测试模块聚合 | 被 all.rs 引用 |
| `tests/suite/bad.rs` | 负面示例验证 | 验证 should_not_match |
| `tests/suite/good.rs` | 正面示例验证 | 验证 should_match |
| `src/lib.rs` | 库入口，导出公共 API | 被测试使用 |
| `src/policy.rs` | Policy 实现 | `check()`, `check_each_*_list_individually()` |
| `src/program.rs` | ProgramSpec 实现 | `check()`, `verify_should_*_list()` |
| `src/policy_parser.rs` | Starlark 策略解析 | `PolicyParser::parse()` |
| `src/arg_matcher.rs` | 参数匹配器 | `ArgMatcher` 枚举 |
| `src/arg_resolver.rs` | 参数解析 | `resolve_observed_args_with_patterns()` |
| `src/valid_exec.rs` | 有效执行结构 | `ValidExec`, `MatchedArg` 等 |
| `src/error.rs` | 错误类型 | `Error` 枚举 |
| `src/default.policy` | 默认策略定义 | 被测试验证 |

## 5. 依赖与外部交互

### 5.1 测试依赖（Cargo.toml）

```toml
[dev-dependencies]
tempfile = { workspace = true }
```

`tempfile` 用于 `execv_checker.rs` 中的单元测试创建临时目录和文件。

### 5.2 生产依赖

| 依赖 | 用途 |
|-----|------|
| `starlark` | 解析 `.policy` 文件（Starlark 语言） |
| `regex-lite` | 禁止程序名称的正则匹配 |
| `multimap` | 一个程序名可能对应多个 ProgramSpec |
| `serde` / `serde_json` | 结果序列化 |
| `clap` | CLI 参数解析 |
| `path-absolutize` | 路径绝对化 |

### 5.3 外部交互

测试本身是纯单元/集成测试，不依赖外部系统。但 `ExecvChecker`（在 `src/execv_checker.rs` 中）提供了与文件系统交互的能力：

- 检查文件路径是否在允许的读写目录内
- 验证系统路径中的可执行文件存在性

这些功能在 `execv_checker.rs` 的 `#[cfg(test)]` 模块中使用 `tempfile` 进行测试。

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 测试覆盖边界

1. **未实现功能未测试**：
   - `option_bundling`（选项捆绑，如 `-al` 代表 `-a -l`）在 `ls.rs` 中被标记为 TODO 且已知失败
   - `combined_format`（`--option=value` 格式）标记为 PLANNED
   - `--` 双横线分隔符不被支持（会返回 `DoubleDashNotSupportedYet` 错误）

2. **平台特定代码**：
   - `execv_checker.rs` 中的 `is_executable_file()` 函数有 Unix 和 Windows 的不同实现
   - 测试主要覆盖 Unix 路径

3. **Sed 命令解析限制**：
   - 仅支持简单的行范围打印命令（如 `122,202p`）
   - GNU sed 的 `e` 标志（执行替换结果）被明确禁止，但解析器可能不够健壮

#### 6.1.2 策略文件风险

1. **硬编码默认策略**：`default.policy` 通过 `include_str!` 嵌入二进制文件，运行时无法修改
2. **策略语言演进**：Starlark DSL 仍在演进中，向后兼容性未保证

### 6.2 改进建议

#### 6.2.1 测试改进

1. **增加选项捆绑测试**：当 `option_bundling` 实现后，应添加 `ls -al` 等测试用例
2. **增加 `--option=value` 格式测试**：验证 `combined_format` 功能
3. **增加错误消息验证**：当前测试主要验证错误类型，可扩展验证错误消息内容
4. **增加边界条件测试**：
   - 超长参数
   - 特殊字符文件名
   - Unicode 参数

#### 6.2.2 代码改进

1. **测试辅助函数**：提取公共的 `assert_match()` 和 `assert_error()` 辅助宏，减少重复代码
2. **参数化测试**：对于类似的命令（如 `cp`, `mv` 等），可使用参数化测试减少代码量
3. **快照测试**：考虑使用 `insta` crate 进行复杂的 JSON 输出快照测试（与 TUI 测试保持一致）

#### 6.2.3 文档改进

1. **测试文档**：为每个测试模块添加文档注释说明测试目的
2. **策略文档**：在 `default.policy` 中为每个程序规则添加更详细的注释

### 6.3 架构考虑

根据 `README.md`，`codex-execpolicy-legacy` 是原始实现，新的前缀规则引擎位于 `codex-execpolicy`。这意味着：

1. **维护模式**：该 crate 可能进入维护模式，重点应放在稳定性而非新功能
2. **迁移路径**：如果新引擎完全替代，这些测试可能需要迁移或废弃
3. **向后兼容**：在过渡期间，保持测试通过对于确保行为一致性至关重要

### 6.4 具体代码问题

1. **`ls.rs` 中的 TODO**：
   ```rust
   // TODO(mbolin): While this is "safe" in that it will not do anything bad
   // to the user's machine, it will fail because apparently `ls` does not
   // allow flags after file arguments...
   ```
   这个测试实际上通过了，但注释表明行为可能与真实 `ls` 不一致。

2. **`head.rs` 中的 stdin 注释**：
   ```rust
   // It is actually valid to call `head` without arguments: it will read from
   // stdin instead of from a file. Though recall that a command rejected by
   // the policy is not "unsafe:"...
   ```
   这表明策略拒绝某些技术上有效的命令，因为它们无法被证明安全。

---

*文档生成时间：2026-03-23*
*基于 commit：当前工作目录状态*
