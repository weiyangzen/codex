# codex-rs/execpolicy-legacy 深度研究文档

## 概述

`codex-execpolicy-legacy` 是 OpenAI Codex 项目中原始的执行策略（exec policy）引擎实现，用于验证和分类提议的 `execv(3)` 命令调用的安全性。该 crate 已被标记为 "legacy"，因为新的前缀规则引擎（prefix-rule engine）已迁移至 `codex-execpolicy` crate。

---

## 场景与职责

### 核心职责

该 crate 的核心目标是将提议的 `execv(3)` 命令分类为以下四种状态之一：

| 状态 | 含义 | 处理建议 |
|------|------|----------|
| `safe` | 命令被验证为安全，可直接执行 | 允许执行 |
| `match` | 命令匹配策略规则，但可能涉及文件写入 | 调用方需根据写入文件决定是否安全 |
| `forbidden` | 命令被明确禁止执行 | 拒绝执行 |
| `unverified` | 无法确定安全性 | 需用户决定或进一步验证 |

### 使用场景

1. **AI Agent 沙箱安全**：当 Codex AI Agent 需要执行 shell 命令时，通过此引擎验证命令是否安全
2. **命令行工具**：提供 CLI 工具用于手动检查命令安全性
3. **策略定义与测试**：使用 Starlark 语言定义程序执行策略，并内置单元测试验证

### 安全哲学

> "安全"并不意味着命令一定会成功执行。例如 `cat /Users/mbolin/code/codex/README.md` 可能被认为是"安全"的（如果系统允许读取该目录），但如果文件不存在，运行时仍会失败。这种"安全"是指代理不会读取未被授权的文件。

---

## 功能点目的

### 1. 策略定义系统（Policy Definition）

使用 Starlark 语言（Python-like 语法）定义程序执行规则，相比 JSON/YAML 支持宏定义且保持安全性和可复现性。

**核心函数**：
- `define_program()` - 定义程序执行规则
- `flag()` - 定义无参选项
- `opt()` - 定义带值选项
- `forbid_substrings()` - 禁止包含特定子串的参数
- `forbid_program_regex()` - 禁止匹配正则的程序名

### 2. 参数匹配系统（Argument Matching）

支持多种参数类型匹配：

| 匹配器 | 说明 | 基数 |
|--------|------|------|
| `ARG_OPAQUE_VALUE` | 非文件路径的不透明值 | One |
| `ARG_RFILE` | 单个可读文件 | One |
| `ARG_WFILE` | 单个可写文件 | One |
| `ARG_RFILES` | 一个或多个可读文件 | AtLeastOne |
| `ARG_RFILES_OR_CWD` | 可读文件列表或空（暗示 CWD） | ZeroOrMore |
| `ARG_POS_INT` | 正整数 | One |
| `ARG_SED_COMMAND` | 安全的 sed 命令 | One |
| `ARG_UNVERIFIED_VARARGS` | 未验证的变长参数 | ZeroOrMore |

### 3. 文件系统安全检查

`ExecvChecker` 提供运行时文件系统安全检查：
- 验证可读文件路径是否在允许的读取目录内
- 验证可写文件路径是否在允许的写入目录内
- 自动解析相对路径为绝对路径
- 检查系统路径中的可执行文件

### 4. 内置程序支持

默认策略 (`default.policy`) 预定义了常用安全程序：
- `ls`, `cat`, `cp`, `head`, `pwd` - 基础文件操作
- `printenv` - 环境变量查看
- `rg` (ripgrep) - 代码搜索
- `sed` - 有限制的流编辑器（仅安全命令）
- `which` - 程序路径查询

---

## 具体技术实现

### 关键数据结构

#### ExecCall
```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,
    pub args: Vec<String>,
}
```
代表一次程序调用请求。

#### ProgramSpec
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
    should_match: Vec<Vec<String>>,      // 正向测试用例
    should_not_match: Vec<Vec<String>>,  // 负向测试用例
}
```

#### ValidExec
```rust
pub struct ValidExec {
    pub program: String,
    pub flags: Vec<MatchedFlag>,
    pub opts: Vec<MatchedOpt>,
    pub args: Vec<MatchedArg>,
    pub system_path: Vec<String>,
}
```
表示通过策略验证的执行调用。

#### MatchedExec（验证结果）
```rust
pub enum MatchedExec {
    Match { exec: ValidExec },
    Forbidden { cause: Forbidden, reason: String },
}
```

### 关键流程

#### 1. 策略解析流程

```
PolicyParser::parse()
├── 创建 Starlark Evaluator
├── 注册内置常量 (ARG_RFILE, ARG_WFILE, etc.)
├── 执行 .policy 文件
│   └── 调用 define_program() / forbid_substrings() / forbid_program_regex()
│       └── 构建 PolicyBuilder
└── PolicyBuilder::build()
    └── 创建 Policy 实例
```

**代码路径**: `src/policy_parser.rs:37-71`

#### 2. 命令检查流程

```
Policy::check(exec_call)
├── 1. 检查程序名是否匹配禁止正则
├── 2. 检查参数是否包含禁止子串
└── 3. 查找程序对应的 ProgramSpec 列表
    └── 对每个 spec 执行 ProgramSpec::check()
        ├── 解析选项和标志
        ├── 验证必需选项
        ├── 解析位置参数（支持 vararg）
        └── 返回 MatchedExec
```

**代码路径**: `src/policy.rs:44-86`, `src/program.rs:94-195`

#### 3. 参数解析流程

位置参数解析支持复杂的模式匹配，包括前缀、变长参数、后缀：

```
resolve_observed_args_with_patterns()
├── partition_args() - 将模式分为 prefix/vararg/suffix
├── 匹配 prefix 模式（固定基数）
├── 匹配 vararg 模式（变长）
├── 匹配 suffix 模式（固定基数）
└── 验证所有参数都被匹配
```

**代码路径**: `src/arg_resolver.rs:15-145`

#### 4. 文件系统安全检查流程

```
ExecvChecker::check(valid_exec, cwd, readable_folders, writeable_folders)
├── 遍历所有参数和选项
│   ├── ReadableFile → ensure_absolute_path() → check_file_in_folders()
│   └── WriteableFile → ensure_absolute_path() → check_file_in_folders()
└── 查找系统路径中的可执行文件
```

**代码路径**: `src/execv_checker.rs:44-99`

### Starlark 集成

使用 `starlark-rust` 库作为 Starlark 语言的 Rust 实现：

```rust
// 创建扩展方言，启用 f-strings
let mut dialect = Dialect::Extended.clone();
dialect.enable_f_strings = true;

// 解析 AST
let ast = AstModule::parse(&self.policy_source, self.unparsed_policy.clone(), &dialect)?;

// 创建全局环境，注册内置函数
let globals = GlobalsBuilder::extended_by(&[LibraryExtension::Typing])
    .with(policy_builtins)
    .build();
```

**内置函数注册** (`src/policy_parser.rs:121-226`):
- `define_program()` - 定义程序规则
- `forbid_substrings()` - 禁止子串
- `forbid_program_regex()` - 禁止程序正则
- `opt()` - 定义带值选项
- `flag()` - 定义标志选项

---

## 关键代码路径与文件引用

### 核心模块

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `src/lib.rs` | 库入口 | `get_default_policy()` |
| `src/main.rs` | CLI 入口 | `Args`, `Command`, `check_command()` |
| `src/policy.rs` | 策略执行 | `Policy::check()` |
| `src/policy_parser.rs` | 策略解析 | `PolicyParser::parse()` |
| `src/program.rs` | 程序规则定义 | `ProgramSpec`, `MatchedExec` |
| `src/arg_matcher.rs` | 参数匹配器 | `ArgMatcher` |
| `src/arg_resolver.rs` | 参数解析 | `resolve_observed_args_with_patterns()` |
| `src/arg_type.rs` | 参数类型 | `ArgType` |
| `src/opt.rs` | 选项定义 | `Opt`, `OptMeta` |
| `src/valid_exec.rs` | 验证结果 | `ValidExec`, `MatchedArg` |
| `src/execv_checker.rs` | 执行检查器 | `ExecvChecker` |
| `src/exec_call.rs` | 执行调用 | `ExecCall` |
| `src/error.rs` | 错误类型 | `Error` |
| `src/sed_command.rs` | Sed 命令解析 | `parse_sed_command()` |

### 默认策略文件

| 文件 | 说明 |
|------|------|
| `src/default.policy` | 内置默认策略，使用 Starlark 语法定义 |

### 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests/all.rs` | 测试入口 |
| `tests/suite/good.rs` | 验证正向测试用例 |
| `tests/suite/bad.rs` | 验证负向测试用例 |
| `tests/suite/ls.rs` | ls 命令测试 |
| `tests/suite/cp.rs` | cp 命令测试 |
| `tests/suite/head.rs` | head 命令测试 |
| `tests/suite/pwd.rs` | pwd 命令测试 |
| `tests/suite/sed.rs` | sed 命令测试 |
| `tests/suite/literal.rs` | 字面量参数测试 |
| `tests/suite/parse_sed_command.rs` | sed 命令解析测试 |

---

## 依赖与外部交互

### 内部依赖

该 crate 是独立的，不依赖其他 codex-rs 内部 crate。

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `starlark` | Starlark 语言解析和执行 |
| `serde` / `serde_json` | JSON 序列化/反序列化 |
| `clap` | CLI 参数解析 |
| `regex-lite` | 正则表达式匹配 |
| `multimap` | 多值映射（一个程序名对应多个规则） |
| `path-absolutize` | 路径绝对化 |
| `anyhow` | 错误处理 |
| `allocative` | 内存分配追踪 |
| `derive_more` | 派生宏 |
| `env_logger` / `log` | 日志 |

### 调用方

根据代码搜索，目前没有内部 crate 直接依赖 `codex-execpolicy-legacy`。新的执行策略引擎已迁移至 `codex-execpolicy` crate。

**相关 crate**:
- `codex-execpolicy` - 新的前缀规则引擎，替代本 crate

---

## 风险、边界与改进建议

### 已知限制与风险

1. **选项捆绑未实现** (`option_bundling`)
   - `-al` 形式的选项捆绑在代码中有字段但功能未实现
   - 当前会导致 `UnknownOption` 错误
   - **代码**: `src/program.rs:23`, `tests/suite/ls.rs:66-78`

2. **组合格式未实现** (`combined_format`)
   - `--option=value` 格式在代码中有字段但功能未实现
   - **代码**: `src/program.rs:24`

3. **双横线不支持** (`--`)
   - 明确不支持 `--` 参数分隔符
   - **代码**: `src/program.rs:116-119`

4. **Sed 命令限制严格**
   - 仅支持 `122,202p` 形式的打印命令
   - 任何其他 sed 命令都会被拒绝
   - **代码**: `src/sed_command.rs:4-17`

5. **Windows 可执行文件检查不完善**
   - Windows 平台仅检查文件是否存在，不检查执行权限
   - **代码**: `src/execv_checker.rs:132-136`

6. **已被标记为 Legacy**
   - 新的执行策略引擎在 `codex-execpolicy` 中实现
   - 本 crate 可能逐渐被淘汰

### 边界情况

1. **相对路径处理**
   - 需要传入 `cwd` 才能正确处理相对路径
   - 无 `cwd` 时相对路径会导致错误

2. **Vararg 模式限制**
   - 只允许一个 vararg 模式
   - 多个 vararg 会导致 `MultipleVarargPatterns` 错误

3. **路径规范化**
   - 使用 `path-absolutize` 而非 `std::fs::canonicalize`
   - 不检查文件是否存在，仅处理路径格式

### 改进建议

1. **迁移至新引擎**
   - 新项目应使用 `codex-execpolicy` crate
   - 本 crate 仅用于维护现有代码

2. **完善测试覆盖**
   - 添加更多边界情况测试
   - 测试 Windows 平台行为

3. **文档改进**
   - 添加更多使用示例
   - 明确标注未实现功能

4. **安全增强**
   - 考虑添加更多危险命令的检测
   - 增强 sed 命令的安全解析

---

## 使用示例

### CLI 使用

```bash
# 检查简单命令
cargo run -p codex-execpolicy-legacy -- check ls -l foo | jq

# 检查可能写入文件的命令
cargo run -p codex-execpolicy-legacy -- check cp src1 src2 dest | jq

# 使用自定义策略文件
cargo run -p codex-execpolicy-legacy -- --policy custom.policy check ls -la

# 要求安全（非安全命令返回非零退出码）
cargo run -p codex-execpolicy-legacy -- --require-safe check cp foo bar
echo $?  # 12 表示匹配但会写入文件
```

### 库使用

```rust
use codex_execpolicy_legacy::{get_default_policy, ExecCall, ExecvChecker};

let policy = get_default_policy()?;
let exec_call = ExecCall::new("ls", &["-l", "foo"]);

match policy.check(&exec_call) {
    Ok(MatchedExec::Match { exec }) => {
        if exec.might_write_files() {
            // 需要额外确认
        } else {
            // 安全执行
        }
    }
    Ok(MatchedExec::Forbidden { reason, .. }) => {
        // 禁止执行
    }
    Err(e) => {
        // 无法验证
    }
}
```

---

## 总结

`codex-execpolicy-legacy` 是一个设计良好的命令执行安全验证引擎，使用 Starlark 作为策略定义语言，提供了灵活且类型安全的参数匹配系统。然而，由于已被标记为 legacy，新项目应使用 `codex-execpolicy` 中的新前缀规则引擎。该 crate 仍可作为学习命令行安全验证策略的参考实现。
