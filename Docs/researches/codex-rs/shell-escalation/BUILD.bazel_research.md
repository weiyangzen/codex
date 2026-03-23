# codex-rs/shell-escalation/BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建配置文件，用于定义 `codex-shell-escalation` crate 的构建规则。它是整个 shell-escalation 模块的构建入口点，负责将 Rust 源代码编译成可执行二进制文件 `codex-execve-wrapper` 和库 crate。

## 功能点目的

1. **定义 Rust Crate 构建规则**: 使用项目自定义的 `codex_rust_crate` 宏来标准化 Rust crate 的构建流程
2. **导出可执行文件**: 构建 `codex-execve-wrapper` 二进制文件，这是 execve 拦截机制的关键组件
3. **库导出**: 将 shell-escalation 协议实现作为库导出，供其他 crate（如 codex-core）依赖使用

## 具体技术实现

### 构建规则定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "shell-escalation",
    crate_name = "codex_shell_escalation",
)
```

- `name`: Bazel 目标名称，用于在构建图中引用
- `crate_name`: 实际的 Rust crate 名称，使用下划线命名规范（`codex_shell_escalation`）

### 与 Cargo.toml 的对应关系

该 Bazel 构建配置与 `Cargo.toml` 中的定义相对应：
- `Cargo.toml` 中定义了 `name = "codex-shell-escalation"`（kebab-case）
- `BUILD.bazel` 中使用 `crate_name = "codex_shell_escalation"`（snake_case）
- 二进制目标 `codex-execve-wrapper` 在 `Cargo.toml` 的 `[[bin]]` 节中定义

## 关键代码路径与文件引用

### 依赖关系

```
BUILD.bazel
├── 依赖 defs.bzl (项目级构建宏定义)
├── 引用 codex-rs/shell-escalation/src/ 下的所有 .rs 文件
└── 输出 codex_shell_escalation crate 和 codex-execve-wrapper 二进制文件
```

### 相关文件

| 文件 | 作用 |
|------|------|
| `defs.bzl` | 项目级 Bazel 宏定义，包含 `codex_rust_crate` 规则 |
| `Cargo.toml` | Cargo 构建配置，与 Bazel 配置并行维护 |
| `MODULE.bazel` | Bazel 模块依赖声明 |

## 依赖与外部交互

### 内部依赖（通过 Cargo.toml 间接指定）

- `codex-protocol`: 协议定义
- `codex-utils-absolute-path`: 绝对路径工具
- `anyhow`, `async-trait`, `clap`, `libc`, `serde`, `serde_json`: 基础库
- `socket2`, `tokio`, `tokio-util`, `tracing`: 异步运行时和网络

### 外部系统交互

- 该 crate 构建的二进制文件 `codex-execve-wrapper` 通过 `EXEC_WRAPPER` 环境变量被 patched bash 调用
- 通过 Unix domain socket 与 escalation server 通信

## 风险、边界与改进建议

### 风险点

1. **双构建系统维护成本**: 项目同时使用 Bazel 和 Cargo，需要保持 `BUILD.bazel` 和 `Cargo.toml` 的同步
2. **平台限制**: 该 crate 仅在 Unix 平台有效，非 Unix 平台的构建会生成空实现

### 边界条件

1. **Unix 专属**: 整个 shell-escalation 模块使用 `#[cfg(unix)]` 条件编译
2. **Bash 依赖**: 需要 patched bash 支持 `EXEC_WRAPPER` 环境变量

### 改进建议

1. **自动化同步**: 考虑使用工具自动生成 `BUILD.bazel` 或验证与 `Cargo.toml` 的一致性
2. **文档完善**: 在 BUILD.bazel 中添加注释说明与 Cargo.toml 的对应关系
3. **平台检测**: 考虑在 Bazel 层面添加平台检测，非 Unix 平台跳过构建或提供清晰的错误信息
