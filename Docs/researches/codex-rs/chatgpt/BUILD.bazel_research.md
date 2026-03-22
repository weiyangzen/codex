# BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建配置文件，负责定义 `codex-chatgpt` crate 的构建规则。它是 Rust 项目使用 Bazel 构建系统的标准配置方式，通过调用项目根目录定义的 `codex_rust_crate` 宏来简化构建配置。

## 功能点目的

1. **构建规则定义**：定义了名为 `chatgpt` 的 Rust crate 构建目标
2. **crate 名称映射**：将内部名称 `chatgpt` 映射到外部 crate 名称 `codex_chatgpt`，符合项目命名规范（`codex-` 前缀）

## 具体技术实现

### 关键代码

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "chatgpt",
    crate_name = "codex_chatgpt",
)
```

### 实现细节

1. **加载规则**：从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏
2. **目标定义**：
   - `name`: Bazel 构建目标的内部标识符
   - `crate_name`: 编译后 Rust crate 的实际名称，使用下划线命名法

## 关键代码路径与文件引用

- **构建宏定义**：`/home/sansha/Github/codex/defs.bzl` - 包含 `codex_rust_crate` 宏的具体实现
- **Bazel 根配置**：`/home/sansha/Github/codex/MODULE.bazel` - 项目级 Bazel 模块配置
- **相关源码**：`codex-rs/chatgpt/src/*.rs` - crate 源代码文件

## 依赖与外部交互

1. **Bazel 构建系统**：依赖项目定义的 Rust 构建规则
2. **Cargo.toml**：与 `codex-rs/chatgpt/Cargo.toml` 中的配置保持一致
3. **workspace 依赖**：继承根目录 `codex-rs/Cargo.toml` 中定义的 workspace 配置

## 风险、边界与改进建议

### 风险

1. **命名不一致风险**：`name` 和 `crate_name` 必须保持对应关系，否则会导致依赖解析问题
2. **Bazel/Cargo 双构建系统**：项目同时支持 Bazel 和 Cargo 构建，需要确保两者配置同步

### 边界

1. 该文件仅包含构建配置，不包含实际业务逻辑
2. 依赖 `defs.bzl` 中的宏实现，如果宏变更需要同步更新

### 改进建议

1. 考虑添加自动化检查确保 Bazel 和 Cargo 配置的一致性
2. 可以在构建规则中添加测试目标配置，与 `Cargo.toml` 中的 `dev-dependencies` 保持同步
