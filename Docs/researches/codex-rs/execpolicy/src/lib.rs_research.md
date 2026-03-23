# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-execpolicy` crate 的**库入口模块**，负责：

1. **模块组织**：声明和暴露子模块
2. **公共 API 导出**：选择性地重新导出类型，定义库的公共接口
3. **模块可见性控制**：使用 `pub`/`pub(crate)`/`mod` 控制访问权限

该模块遵循 Rust 库设计的最佳实践，提供清晰、一致的公共 API。

## 功能点目的

### 1. 模块声明

```rust
pub mod amend;           // 策略修改（追加规则）
pub mod decision;        // 决策枚举
pub mod error;           // 错误类型
pub mod execpolicycheck; // CLI 命令
mod executable_name;     // 可执行文件名处理（内部使用）
pub mod parser;          // 策略解析器
pub mod policy;          // 策略引擎
pub mod rule;            // 规则定义
```

可见性设计：
- `pub`：公共 API，库用户可直接访问
- `mod executable_name`：仅内部使用，不暴露

### 2. 公共 API 重新导出

```rust
pub use amend::AmendError;
pub use amend::blocking_append_allow_prefix_rule;
pub use amend::blocking_append_network_rule;
pub use decision::Decision;
pub use error::Error;
pub use error::ErrorLocation;
pub use error::Result;
pub use error::TextPosition;
pub use error::TextRange;
pub use execpolicycheck::ExecPolicyCheckCommand;
pub use parser::PolicyParser;
pub use policy::Evaluation;
pub use policy::MatchOptions;
pub use policy::Policy;
pub use rule::NetworkRuleProtocol;
pub use rule::Rule;
pub use rule::RuleMatch;
pub use rule::RuleRef;
```

重新导出的目的：
1. **便利性**：用户只需 `use codex_execpolicy::Decision` 而非 `use codex_execpolicy::decision::Decision`
2. **API 稳定性**：可以在不破坏用户代码的情况下重构内部模块结构
3. **发现性**：用户通过查看 `lib.rs` 即可了解库的主要功能

## 具体技术实现

### 模块层次结构

```
codex_execpolicy
├── amend
│   └── AmendError, blocking_append_*
├── decision
│   └── Decision
├── error
│   └── Error, ErrorLocation, TextPosition, TextRange, Result
├── execpolicycheck
│   └── ExecPolicyCheckCommand
├── executable_name (private)
├── parser
│   └── PolicyParser
├── policy
│   └── Policy, Evaluation, MatchOptions
└── rule
    └── Rule, RuleMatch, RuleRef, NetworkRuleProtocol
```

### 设计决策

1. **`executable_name` 私有**：这是纯内部工具模块，用户不应直接依赖
2. **`rule` 模块公共**：虽然 `Rule` 是 trait，但用户可能需要 `RuleMatch` 等类型
3. **错误类型全部导出**：便于用户进行错误处理
4. **`Result` 类型别名**：统一使用 crate 的 `Result` 类型

## 依赖与外部交互

### 作为库的依赖方

其他 crate 通过以下方式使用：

```toml
[dependencies]
codex-execpolicy = { path = "../execpolicy" }
```

```rust
use codex_execpolicy::{Decision, Policy, PolicyParser};
```

### 内部模块依赖关系

```
lib.rs
├── amend → decision, rule
├── decision → error
├── error → (仅标准库)
├── execpolicycheck → decision, policy, parser, rule
├── executable_name → (仅标准库)
├── parser → decision, error, executable_name, policy, rule
├── policy → decision, error, executable_name, rule
└── rule → decision, error, policy
```

注意：存在一些循环依赖风险（`policy` ↔ `rule`），目前通过仔细的设计避免。

## 风险、边界与改进建议

### 风险点

1. **API 膨胀**：重新导出过多类型可能导致 API 表面过大，维护困难
2. **模块重构**：内部模块结构变更可能影响重新导出的路径
3. **文档分散**：类型文档分布在各模块，需要确保 `lib.rs` 有良好概述

### 边界条件

1. **二进制 + 库**：crate 同时提供库和二进制，`lib.rs` 和 `main.rs` 分离清晰
2. **模块可见性**：`executable_name` 的私有性确保内部实现细节不泄露

### 改进建议

1. **预lude 模块**：考虑添加 `prelude` 模块，包含最常用的类型：
   ```rust
   pub mod prelude {
       pub use crate::{Decision, Policy, PolicyParser, Error, Result};
   }
   ```

2. **功能门控**：如果 crate 变大，考虑使用 Cargo features 分隔功能：
   ```toml
   [features]
   default = ["cli"]
   cli = ["clap"]
   ```

3. **文档组织**：在 `lib.rs` 顶部添加 crate 级别的文档注释：
   ```rust
   //! # codex-execpolicy
   //! 
   //! Policy engine for command execution decisions.
   //! 
   //! ## Example
   //! ```
   //! use codex_execpolicy::{PolicyParser, Decision};
   //! ```
   ```

4. **重新导出审查**：定期审查重新导出的类型，移除不再需要的

5. **版本兼容性**：遵循语义化版本控制，公共 API 变更需要版本升级

### 与 Cargo.toml 的关系

```toml
[lib]
name = "codex_execpolicy"
path = "src/lib.rs"
```

库名称使用下划线（`codex_execpolicy`），符合 Rust 命名规范。包名使用连字符（`codex-execpolicy`），符合 Cargo 规范。
