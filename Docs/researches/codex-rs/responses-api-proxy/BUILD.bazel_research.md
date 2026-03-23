# BUILD.bazel 研究文档

## 场景与职责

此文件是 Bazel 构建系统的构建定义文件，用于定义 `codex-responses-api-proxy` crate 的构建目标。该 crate 是一个严格的 HTTP 代理服务器，专门用于将请求转发到 OpenAI API 的 `/v1/responses` 端点。

## 功能点目的

- **构建目标定义**: 使用项目自定义的 `codex_rust_crate` 宏定义 Rust crate 的构建规则
- **统一构建规范**: 通过共享的构建宏确保所有 Rust crate 遵循一致的构建配置
- **多平台支持**: 继承自 `defs.bzl` 的多平台构建能力，支持 Linux (x64/arm64)、macOS (x64/arm64)、Windows (x64/arm64)

## 具体技术实现

### 关键构建规则

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "responses-api-proxy",
    crate_name = "codex_responses_api_proxy",
)
```

### 构建宏行为 (`codex_rust_crate`)

根据 `defs.bzl` 中的定义，`codex_rust_crate` 宏会自动：

1. **库目标**: 构建 `src/lib.rs` 为 Rust 库 (crate_name: `codex_responses_api_proxy`)
2. **二进制目标**: 自动检测并构建 `src/main.rs` 中的二进制文件
3. **单元测试**: 创建单元测试目标 `{name}-unit-tests-bin`
4. **集成测试**: 如果存在 `tests/` 目录，创建集成测试目标
5. **构建脚本**: 如果存在 `build.rs`，自动配置构建脚本

### 依赖解析

依赖通过 `@crates` 工作区解析，从 `Cargo.lock` 生成：
- `anyhow` - 错误处理
- `clap` - 命令行解析
- `codex-process-hardening` - 进程加固
- `reqwest` - HTTP 客户端
- `serde`/`serde_json` - 序列化
- `tiny_http` - HTTP 服务器
- `zeroize` - 安全内存清零

## 关键代码路径与文件引用

- **构建定义**: `codex-rs/responses-api-proxy/BUILD.bazel`
- **构建宏**: `defs.bzl` (第 89-240 行定义 `codex_rust_crate`)
- **Cargo 配置**: `codex-rs/responses-api-proxy/Cargo.toml`
- **库源码**: `codex-rs/responses-api-proxy/src/lib.rs`
- **二进制入口**: `codex-rs/responses-api-proxy/src/main.rs`

## 依赖与外部交互

### Bazel 工作区依赖

| 依赖 | 用途 |
|------|------|
| `@crates` | 从 Cargo.lock 生成的 Rust crate 依赖 |
| `//:defs.bzl` | 项目共享的 Rust 构建宏 |
| `@rules_rust` | Bazel Rust 规则 |

### 跨 crate 依赖

- `codex-process-hardening` - 同仓库的进程加固库

## 风险、边界与改进建议

### 风险

1. **构建宏复杂性**: `codex_rust_crate` 宏封装了大量逻辑，可能导致构建问题难以调试
2. **隐式行为**: 自动检测 `src/main.rs` 和 `build.rs` 可能导致意外的构建目标生成

### 边界

1. **单 crate 配置**: 当前 BUILD.bazel 仅支持基本的 `name` 和 `crate_name` 参数，无法覆盖高级用例
2. **无自定义特性**: 未使用 `crate_features`、`deps_extra` 等可选参数

### 改进建议

1. **添加注释**: 可以添加注释说明此 crate 的特殊性（安全敏感的 API 密钥处理）
2. **显式声明**: 考虑显式声明 `extra_binaries` 或 `test_data_extra` 以提高可维护性
3. **多平台发布**: 可以配合 `multiplatform_binaries` 宏生成多平台发布二进制文件
