# BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统中用于定义 `mcp_test_support` 测试支持库的构建配置。它位于 `codex-rs/mcp-server/tests/common/` 目录下，是 Codex MCP 服务器集成测试基础设施的一部分。

## 功能点目的

1. **定义测试支持库**: 将 `mcp-server/tests/common/` 目录下的 Rust 源文件打包成一个名为 `mcp_test_support` 的 crate
2. **Bazel/Cargo 互操作**: 通过 `codex_rust_crate` 宏实现与 Cargo 构建系统的兼容性
3. **测试依赖管理**: 为 MCP 服务器的集成测试提供共享的测试工具和辅助函数

## 具体技术实现

### 构建规则

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "common",
    crate_name = "mcp_test_support",
    crate_srcs = glob(["*.rs"]),
)
```

### 关键配置

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `common` | Bazel 目标名称 |
| `crate_name` | `mcp_test_support` | Rust crate 名称，与 Cargo.toml 中的 `name` 字段一致 |
| `crate_srcs` | `glob(["*.rs"])` | 包含目录下所有 `.rs` 文件 |

### 与 Cargo.toml 的映射关系

```toml
# Cargo.toml
[package]
name = "mcp_test_support"
```

Bazel 的 `crate_name` 必须与 Cargo.toml 的 `name` 保持一致，以确保两种构建工具生成的 crate 具有相同的标识符。

## 关键代码路径与文件引用

### 依赖关系

```
codex-rs/mcp-server/tests/common/BUILD.bazel
├── 引入: //:defs.bzl (codex_rust_crate 宏)
├── 包含源文件:
│   ├── lib.rs
│   ├── mcp_process.rs
│   ├── mock_model_server.rs
│   └── responses.rs
└── 被依赖:
    └── codex-rs/mcp-server/tests/suite/codex_tool.rs (通过 mcp_test_support crate)
```

### defs.bzl 中的 codex_rust_crate 宏

该宏定义在 `//:defs.bzl` 中（项目根目录），提供以下功能：
- 创建 `rust_library` 目标
- 生成单元测试目标
- 处理二进制文件依赖
- 设置 Cargo 兼容性环境变量

## 依赖与外部交互

### 上游依赖

1. **构建系统**:
   - Bazel 构建规则 (`rules_rust`)
   - 自定义 `codex_rust_crate` 宏

2. **源文件**:
   - `lib.rs` - 库入口
   - `mcp_process.rs` - MCP 进程管理
   - `mock_model_server.rs` - 模拟模型服务器
   - `responses.rs` - SSE 响应构建器

### 下游消费者

1. **集成测试**:
   - `codex-rs/mcp-server/tests/suite/codex_tool.rs` - 使用 `mcp_test_support` 进行 MCP 工具测试

2. **Cargo 工作区**:
   - 通过 `Cargo.toml` 被其他 crate 引用

## 风险、边界与改进建议

### 风险

1. **名称不一致风险**: 如果 `crate_name` 与 `Cargo.toml` 中的 `name` 不匹配，会导致 Bazel 和 Cargo 构建结果不一致
2. **glob 模式风险**: `glob(["*.rs"])` 会包含所有 `.rs` 文件，如果添加新的非库源文件可能导致意外包含

### 边界情况

1. **空目录**: 如果目录中没有 `.rs` 文件，`glob` 返回空列表，但 Bazel 不会报错
2. **平台兼容性**: 该构建配置在所有支持的平台（Linux、macOS、Windows）上通用

### 改进建议

1. **显式源文件列表**: 考虑将 `glob(["*.rs"])` 替换为显式文件列表，以提高可预测性：
   ```bazel
   crate_srcs = [
       "lib.rs",
       "mcp_process.rs",
       "mock_model_server.rs",
       "responses.rs",
   ],
   ```

2. **添加测试标签**: 如果该库仅用于测试，可以添加 `testonly = True` 属性

3. **文档生成**: 考虑添加 `rust_doc` 目标以生成 API 文档
