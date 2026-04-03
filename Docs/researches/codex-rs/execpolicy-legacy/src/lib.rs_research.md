# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-execpolicy-legacy` crate 的库入口文件，负责：

1. **模块组织**：声明和导出所有子模块
2. **公共 API 暴露**：选择性地公开内部实现供外部使用
3. **默认策略提供**：嵌入并提供默认策略文件
4. **编译配置**：允许特定的 Clippy 警告

该文件定义了 crate 的公共接口，是外部使用者（CLI、测试、其他 crate）与内部实现的边界。

## 功能点目的

### 1. 模块声明

```rust
mod arg_matcher;
mod arg_resolver;
mod arg_type;
mod error;
mod exec_call;
mod execv_checker;
mod opt;
mod policy;
mod policy_parser;
mod program;
mod sed_command;
mod valid_exec;
```

所有模块默认私有，通过 `pub use` 选择性公开。

### 2. 公共 API 导出

**核心类型**：
```rust
pub use arg_matcher::ArgMatcher;
pub use arg_resolver::PositionalArg;
pub use arg_type::ArgType;
pub use error::Error;
pub use error::Result;
pub use exec_call::ExecCall;
pub use execv_checker::ExecvChecker;
pub use opt::Opt;
pub use policy::Policy;
pub use policy_parser::PolicyParser;
```

**程序相关类型**：
```rust
pub use program::Forbidden;
pub use program::MatchedExec;
pub use program::NegativeExamplePassedCheck;
pub use program::PositiveExampleFailedCheck;
pub use program::ProgramSpec;
```

**验证结果类型**：
```rust
pub use sed_command::parse_sed_command;
pub use valid_exec::MatchedArg;
pub use valid_exec::MatchedFlag;
pub use valid_exec::MatchedOpt;
pub use valid_exec::ValidExec;
```

### 3. 默认策略嵌入

```rust
const DEFAULT_POLICY: &str = include_str!("default.policy");

pub fn get_default_policy() -> starlark::Result<Policy> {
    let parser = PolicyParser::new("#default", DEFAULT_POLICY);
    parser.parse()
}
```

- 使用 `include_str!` 在编译时嵌入策略文件
- 提供便捷的默认策略加载函数

### 4. 编译配置

```rust
#![allow(clippy::type_complexity)]
#![allow(clippy::too_many_arguments)]
```

允许特定类型的复杂性，避免无意义的 Clippy 警告。

```rust
#[macro_use]
extern crate starlark;
```

引入 Starlark 宏（如 `starlark_module`）。

## 具体技术实现

### 模块导出策略

**完全公开**：
- `ArgMatcher`, `ArgType`, `ExecCall`
- `Policy`, `PolicyParser`
- `Error`, `Result`

**部分公开**：
- `program` 模块：只公开特定类型，隐藏实现细节
- `valid_exec` 模块：公开结果类型，隐藏构造细节

**实现隐藏**：
- `arg_resolver`：只公开 `PositionalArg`
- `opt`：只公开 `Opt`
- `sed_command`：只公开 `parse_sed_command` 函数

### 默认策略加载

```rust
const DEFAULT_POLICY: &str = include_str!("default.policy");

pub fn get_default_policy() -> starlark::Result<Policy> {
    let parser = PolicyParser::new("#default", DEFAULT_POLICY);
    parser.parse()
}
```

**设计考量**：
- 使用 `"#default"` 作为策略源标识
- 返回 `starlark::Result` 而非自定义 Result，因为解析错误是 Starlark 错误
- 编译时嵌入确保策略文件始终可用

### 编译时嵌入

`include_str!` 宏在编译时将文件内容作为字符串字面量嵌入：
- 优点：无需运行时文件访问，单二进制文件部署
- 缺点：策略文件更新需要重新编译

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/lib.rs`

### 子模块文件
- `codex-rs/execpolicy-legacy/src/arg_matcher.rs`
- `codex-rs/execpolicy-legacy/src/arg_resolver.rs`
- `codex-rs/execpolicy-legacy/src/arg_type.rs`
- `codex-rs/execpolicy-legacy/src/error.rs`
- `codex-rs/execpolicy-legacy/src/exec_call.rs`
- `codex-rs/execpolicy-legacy/src/execv_checker.rs`
- `codex-rs/execpolicy-legacy/src/opt.rs`
- `codex-rs/execpolicy-legacy/src/policy.rs`
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`
- `codex-rs/execpolicy-legacy/src/program.rs`
- `codex-rs/execpolicy-legacy/src/sed_command.rs`
- `codex-rs/execpolicy-legacy/src/valid_exec.rs`

### 嵌入文件
- `codex-rs/execpolicy-legacy/src/default.policy`

### 使用者

**CLI（main.rs）**：
```rust
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::PolicyParser;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

**测试**：
```rust
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

## 依赖与外部交互

### 外部 crate
- `starlark`：提供 `starlark_module` 等宏

### 内部依赖
- 所有子模块

### 模块依赖图

```
lib.rs
├── arg_matcher -> arg_type, error
├── arg_resolver -> arg_matcher, error, valid_exec
├── arg_type -> error, sed_command
├── error
├── exec_call
├── execv_checker -> policy, valid_exec, arg_type, exec_call, error, policy_parser
├── opt -> arg_type
├── policy -> program, error, policy_parser
├── policy_parser -> opt, arg_matcher, program, policy
├── program -> arg_matcher, arg_resolver, error, opt, valid_exec
├── sed_command -> error
└── valid_exec -> arg_type, error
```

## 风险、边界与改进建议

### 风险点

1. **API 稳定性**
   - 当前导出大量内部类型
   - 任何内部更改都可能破坏公共 API
   - 建议：明确标记实验性 API

2. **默认策略耦合**
   - `get_default_policy()` 硬编码使用 `default.policy`
   - 无法在不重新编译的情况下使用其他默认策略

3. **错误类型不一致**
   - `get_default_policy()` 返回 `starlark::Result`
   - 其他函数返回 `crate::Result`
   - 调用者需要处理两种错误类型

4. **模块可见性**
   - 所有模块都声明为 `mod`，即使只公开部分内容
   - 内部实现细节可能通过文档泄露

### 边界情况

1. **默认策略解析失败**
   ```rust
   // 如果 default.policy 有语法错误
   // 编译成功，但 get_default_policy() 运行时失败
   ```

2. **空策略**
   ```rust
   // 如果 default.policy 为空
   // get_default_policy() 返回空 Policy
   // 所有检查都会返回 NoSpecForProgram
   ```

3. **循环依赖风险**
   - 当前模块间依赖较复杂
   - 新增功能时容易引入循环依赖

### 改进建议

1. **预编译策略**
   ```rust
   // 在 build.rs 中预解析策略，生成 Rust 代码
   // 避免运行时解析开销和错误
   ```

2. **统一错误类型**
   ```rust
   pub fn get_default_policy() -> Result<Policy> {
       let parser = PolicyParser::new("#default", DEFAULT_POLICY);
       parser.parse().map_err(|e| Error::PolicyParseError(e.to_string()))
   }
   ```

3. **API 版本控制**
   ```rust
   // 使用 feature flag 控制 API 暴露
   #![cfg_attr(feature = "unstable", feature(...))]
   
   #[cfg(feature = "unstable")]
   pub use internal::ExperimentalType;
   ```

4. **模块重组**
   ```rust
   // 将公共类型提取到 types.rs
   pub mod types {
       pub use crate::exec_call::ExecCall;
       pub use crate::valid_exec::ValidExec;
       // ...
   }
   
   // 将解析相关提取到 parser 模块
   pub mod parser {
       pub use crate::policy_parser::PolicyParser;
       // ...
   }
   ```

5. **文档改进**
   ```rust
   //! # codex-execpolicy-legacy
   //!
   //! 执行策略验证库，用于验证 execv 调用的安全性。
   //!
   //! ## 快速开始
   //!
   //! ```rust
   //! use codex_execpolicy_legacy::{get_default_policy, ExecCall};
   //!
   //! let policy = get_default_policy()?;
   //! let result = policy.check(&ExecCall::new("ls", &["-l"]));
   //! ```
   ```

6. **条件编译优化**
   ```rust
   // 为不同平台提供不同默认策略
   #[cfg(target_os = "macos")]
   const DEFAULT_POLICY: &str = include_str!("macos.policy");
   
   #[cfg(target_os = "linux")]
   const DEFAULT_POLICY: &str = include_str!("linux.policy");
   ```

7. **测试支持**
   ```rust
   #[cfg(test)]
   pub fn get_test_policy(source: &str) -> starlark::Result<Policy> {
       PolicyParser::new("#test", source).parse()
   }
   ```
