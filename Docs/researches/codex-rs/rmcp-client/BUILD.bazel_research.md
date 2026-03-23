# BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建配置，定义了 `codex-rmcp-client` crate 的构建规则。它是根目录 `defs.bzl` 中自定义宏 `codex_rust_crate` 的简单调用封装。

## 功能点目的

1. **定义 Rust Crate 构建目标**：通过 `codex_rust_crate` 宏声明一个名为 `rmcp-client` 的构建目标
2. **指定 Crate 名称**：将内部 crate 名称映射为 `codex_rmcp_client`（符合 AGENTS.md 中提到的 `codex-` 前缀规范）

## 具体技术实现

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "rmcp-client",
    crate_name = "codex_rmcp_client",
)
```

### 关键流程

1. `load("//:defs.bzl", "codex_rust_crate")` - 从项目根目录加载自定义 Rust crate 构建宏
2. 调用 `codex_rust_crate` 宏，传入：
   - `name`: Bazel 目标名称（用于 `bazel build //codex-rs/rmcp-client:rmcp-client`）
   - `crate_name`: 实际 Rust crate 名称（用于 `extern crate codex_rmcp_client`）

### 依赖关系

该 BUILD 文件本身不声明具体依赖，依赖关系由以下方式管理：
- 源码中的 `use` 语句
- `Cargo.toml` 中的依赖声明
- `codex_rust_crate` 宏内部逻辑（可能自动处理 Cargo.toml 依赖映射）

## 关键代码路径与文件引用

| 文件 | 关系 | 说明 |
|------|------|------|
| `//:defs.bzl` | 被加载 | 根目录构建宏定义 |
| `Cargo.toml` | 隐式依赖 | 实际依赖声明位置 |
| `src/lib.rs` | 源文件 | crate 入口点 |

## 依赖与外部交互

### 上游依赖（通过 codex_rust_crate 宏处理）
- `rmcp` - Model Context Protocol Rust SDK
- `oauth2` - OAuth 2.0 客户端实现
- `reqwest` - HTTP 客户端
- `keyring` - 系统密钥环访问
- `axum` - HTTP 服务器框架（测试用）
- `tokio` - 异步运行时

### 下游使用者
- `codex-rs/cli` - CLI 工具
- `codex-rs/core` - 核心库
- `codex-rs/tui` - TUI 界面
- `codex-rs/app-server` - 应用服务器

## 风险、边界与改进建议

### 风险
1. **宏抽象风险**：`codex_rust_crate` 宏的具体行为不透明，可能导致依赖解析问题难以调试
2. **Bazel/Cargo 双构建系统**：项目同时使用 Bazel 和 Cargo，可能导致构建结果不一致

### 边界
1. 该文件仅适用于 Bazel 构建，不影响 `cargo build`
2. 所有实际依赖配置在 `Cargo.toml` 中

### 改进建议
1. 考虑添加注释说明 `codex_rust_crate` 宏的功能
2. 如需特殊编译选项（如 feature flags），可在此文件扩展
