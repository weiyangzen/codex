# codex-rs/execpolicy/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中定义 `codex-execpolicy` crate 的构建配置文件。该文件位于 `codex-rs/execpolicy/` 目录下，负责声明 Rust crate 的构建规则，使 Bazel 能够正确编译和打包 `codex-execpolicy` 库和二进制文件。

该 crate 是 Codex 项目的执行策略引擎，提供基于 Starlark 的策略规则解析和命令执行决策功能。

## 功能点目的

1. **Crate 构建声明**: 使用项目统一的 `codex_rust_crate` 宏定义 Rust crate 构建规则
2. **库与二进制输出**: 同时生成 `codex_execpolicy` 库和 `codex-execpolicy` 可执行文件
3. **构建标准化**: 遵循项目统一的 Bazel 构建规范，确保与其他 crate 的构建一致性

## 具体技术实现

### 构建规则定义

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "execpolicy",
    crate_name = "codex_execpolicy",
)
```

### 关键配置项

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `"execpolicy"` | Bazel 目标名称，用于构建引用 |
| `crate_name` | `"codex_execpolicy"` | Rust crate 名称，生成 `libcodex_execpolicy.rlib` 和 `codex-execpolicy` 二进制 |

### 构建输出

- **库文件**: `libcodex_execpolicy.rlib` - 供其他 crate 依赖使用
- **二进制文件**: `codex-execpolicy` - 独立的 CLI 工具，用于策略检查和验证

## 关键代码路径与文件引用

### 源文件结构

```
codex-rs/execpolicy/
├── BUILD.bazel              # 本文件：Bazel 构建配置
├── Cargo.toml               # Cargo 构建配置
├── src/
│   ├── lib.rs               # 库入口，导出公共 API
│   ├── main.rs              # 二进制入口，CLI 实现
│   ├── policy.rs            # Policy 核心结构体和评估逻辑
│   ├── rule.rs              # 规则定义（PrefixRule, NetworkRule）
│   ├── parser.rs            # Starlark 策略文件解析器
│   ├── decision.rs          # Decision 枚举（Allow/Prompt/Forbidden）
│   ├── error.rs             # 错误类型定义
│   ├── execpolicycheck.rs   # execpolicy check 命令实现
│   ├── amend.rs             # 策略文件修改（添加规则）
│   └── executable_name.rs   # 可执行文件名处理（跨平台）
└── tests/
    └── basic.rs             # 集成测试
```

### 依赖关系

**被依赖方**（调用本 crate 的 crate）：
- `codex-rs/cli` - 通过 `ExecPolicyCheckCommand` 提供 `codex execpolicy check` 子命令
- `codex-rs/core` - 使用 `Policy`, `PolicyParser`, `Decision` 等核心类型进行执行策略管理

**依赖方**（本 crate 依赖的 crate）：
- `codex-utils-absolute-path` - 绝对路径处理
- 外部 crate: `anyhow`, `clap`, `multimap`, `serde`, `serde_json`, `shlex`, `starlark`, `thiserror`

## 依赖与外部交互

### Cargo.toml 依赖映射

`BUILD.bazel` 本身不直接声明依赖，依赖关系通过 `codex_rust_crate` 宏从 `Cargo.toml` 自动推导：

```toml
[dependencies]
anyhow = { workspace = true }
clap = { workspace = true, features = ["derive"] }
codex-utils-absolute-path = { workspace = true }
multimap = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
shlex = { workspace = true }
starlark = { workspace = true }
thiserror = { workspace = true }
```

### Bazel 工作区集成

- 使用 `//:defs.bzl` 中定义的 `codex_rust_crate` 宏，确保与项目其他 Rust crate 的构建一致性
- 继承项目根目录的 `.bazelrc` 和 `MODULE.bazel` 中的全局构建配置

## 风险、边界与改进建议

### 风险点

1. **构建工具双维护**: 项目同时使用 Cargo 和 Bazel 两种构建系统，需要确保 `Cargo.toml` 和 `BUILD.bazel` 的依赖声明保持一致
2. **Starlark 依赖**: 依赖 `starlark` crate 进行策略解析，该依赖较重，可能增加编译时间
3. **跨平台兼容性**: `executable_name.rs` 中有条件编译（`#[cfg(windows)]`），需要确保 Bazel 构建正确处理平台差异

### 边界条件

1. **最小配置**: 本文件是 Bazel 构建的最小配置，所有复杂逻辑都封装在 `codex_rust_crate` 宏中
2. **无测试声明**: 测试目标通过 `codex_rust_crate` 宏自动处理，无需在 `BUILD.bazel` 中显式声明
3. **无特性标志**: 当前 crate 没有条件编译特性，所有功能始终启用

### 改进建议

1. **添加文档注释**: 可以在文件中添加更多注释说明 `codex_rust_crate` 宏的行为和参数含义
2. **考虑拆分**: 如果 crate 继续增长，可以考虑将 CLI 二进制部分拆分为单独的 crate（`codex-execpolicy-cli`）
3. **构建优化**: 考虑使用 Bazel 的远程缓存和增量构建特性来加速 `starlark` 依赖的编译
4. **平台特定配置**: 如果 Windows 支持增强，可能需要在 `BUILD.bazel` 中添加平台特定的编译选项
