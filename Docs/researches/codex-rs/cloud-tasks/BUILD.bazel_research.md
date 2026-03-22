# codex-rs/cloud-tasks/BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建配置文件，位于 `codex-rs/cloud-tasks` 目录下。`cloud-tasks` 是 Codex CLI 的云任务管理模块，提供与 Codex Cloud 服务交互的功能，包括任务列表查看、任务详情展示、diff 应用等操作。

该 BUILD 文件定义了 Rust crate 的构建规则，使用项目自定义的 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）来简化配置。

## 功能点目的

1. **定义 Rust Crate 构建目标**
   - 使用 `codex_rust_crate` 宏声明一个名为 `cloud-tasks` 的构建目标
   - 指定 crate 名称为 `codex_cloud_tasks`，与 Cargo.toml 中的 `name` 字段保持一致

2. **简化构建配置**
   - 通过自定义宏隐藏 Bazel 构建的复杂性
   - 自动处理依赖管理、编译选项、测试配置等

## 具体技术实现

### 构建规则

```bzl
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "cloud-tasks",
    crate_name = "codex_cloud_tasks",
)
```

### 关键配置项

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `cloud-tasks` | Bazel 构建目标名称 |
| `crate_name` | `codex_cloud_tasks` | Rust crate 名称（使用下划线） |

### 与 Cargo.toml 的对应关系

- `crate_name` 对应 `Cargo.toml` 中的 `[lib].name` 字段
- 依赖项在 `Cargo.toml` 中定义，Bazel 通过 `MODULE.bazel.lock` 或 `cargo-bazel` 工具同步

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/cloud-tasks/BUILD.bazel` - 本文件

### 相关文件
- `codex-rs/cloud-tasks/Cargo.toml` - Rust 包配置和依赖定义
- `codex-rs/cloud-tasks/src/lib.rs` - 库入口点，包含 CLI 和 TUI 实现
- `//:defs.bzl` - 项目级 Bazel 宏定义

### 依赖的 Crate（通过 Cargo.toml）
- `codex-cloud-tasks-client` - 云任务客户端库
- `codex-core` - 核心功能库
- `codex-tui` - TUI 组件库
- `codex-login` - 认证管理

## 依赖与外部交互

### Bazel 依赖
- 依赖项目根目录的 `defs.bzl` 文件中的 `codex_rust_crate` 宏
- 该宏封装了 Rust crate 的标准构建设置

### Cargo 依赖（通过 Cargo.toml）
- 运行时依赖：`anyhow`, `chrono`, `clap`, `ratatui`, `tokio` 等
- 内部依赖：`codex-cloud-tasks-client`, `codex-core`, `codex-tui`, `codex-login`

### 外部服务交互
本 BUILD 文件本身不直接处理外部交互，但构建的 crate 会与以下服务交互：
- Codex Cloud API (通过 `codex-cloud-tasks-client`)
- ChatGPT/Wham 后端 (用于认证和任务管理)

## 风险、边界与改进建议

### 风险点

1. **命名一致性**
   - `name` 使用连字符 (`cloud-tasks`) 符合 Bazel 惯例
   - `crate_name` 使用下划线 (`codex_cloud_tasks`) 符合 Rust 惯例
   - 需要确保两者映射正确，否则会导致链接错误

2. **依赖同步**
   - Bazel 和 Cargo 的依赖需要保持同步
   - 如果 `MODULE.bazel.lock` 未正确更新，可能导致构建不一致

### 边界条件

1. **功能特性控制**
   - 与 `cloud-tasks-client` 不同，本 crate 没有条件编译特性
   - 所有功能（mock + online）都在代码中通过运行时配置控制

2. **测试覆盖**
   - 单元测试位于 `src/lib.rs` 的 `#[cfg(test)]` 模块中
   - 集成测试位于 `tests/env_filter.rs`

### 改进建议

1. **文档增强**
   - 可以添加 `visibility` 属性明确指定哪些包可以依赖此 crate
   - 添加 `crate_features` 如果未来需要条件编译支持

2. **构建优化**
   - 考虑添加 `compile_data` 如果 crate 需要包含非代码资源
   - 对于大型 TUI 应用，可以考虑拆分构建目标

3. **测试配置**
   - 可以显式配置测试依赖和测试数据
   - 考虑添加针对 mock 和 online 模式的独立测试目标
