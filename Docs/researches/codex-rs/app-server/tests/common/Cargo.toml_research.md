# Cargo.toml 研究文档

## 场景与职责

该文件是 Rust 包管理工具 Cargo 的配置文件，定义了 `app_test_support` 这个测试支持库的元数据和依赖关系。它是 `codex-rs/app-server/tests/common/` 目录下所有测试辅助代码的 crate 配置，为 app-server 的集成测试提供基础设施支持。

## 功能点目的

1. **定义 Crate 元数据**：指定 crate 名称、版本、Rust 版本和许可证信息
2. **配置库入口**：指定 `lib.rs` 作为库的入口点
3. **声明依赖关系**：列出该测试支持库所需的所有外部依赖
4. **Workspace 集成**：通过 `workspace = true` 继承工作空间的统一配置

## 具体技术实现

### 包元数据配置

```toml
[package]
name = "app_test_support"
version.workspace = true      # 继承工作空间版本
edition.workspace = true      # 继承工作空间 Rust 版本（2021/2024）
license.workspace = true      # 继承工作空间许可证
```

### 库配置

```toml
[lib]
path = "lib.rs"               # 库入口文件
```

### 依赖项分析

| 依赖 | 来源 | 用途 |
|------|------|------|
| `anyhow` | workspace | 错误处理 |
| `base64` | workspace | Base64 编解码（JWT token 生成） |
| `chrono` | workspace | 日期时间处理 |
| `codex-app-server-protocol` | workspace | App Server 协议类型定义 |
| `codex-core` | workspace | 核心功能（auth、models 等） |
| `codex-protocol` | workspace | 协议定义（ThreadId、SessionMeta 等） |
| `codex-utils-cargo-bin` | workspace | 测试二进制文件路径解析 |
| `serde` | workspace | 序列化/反序列化 |
| `serde_json` | workspace | JSON 处理 |
| `tokio` | workspace | 异步运行时（多线程、进程、宏） |
| `uuid` | workspace | UUID 生成 |
| `wiremock` | workspace | HTTP mock 服务器 |
| `core_test_support` | path | 核心测试支持库（相对路径） |
| `shlex` | workspace | Shell 命令解析 |

### Tokio 特性配置

```toml
tokio = { workspace = true, features = [
    "io-std",        # 标准 IO 支持
    "macros",        # 异步宏支持
    "process",       # 子进程管理（McpProcess 需要）
    "rt-multi-thread", # 多线程运行时
] }
```

## 关键代码路径与文件引用

- **当前文件**: `codex-rs/app-server/tests/common/Cargo.toml`
- **库入口**: `codex-rs/app-server/tests/common/lib.rs`
- **父级工作空间配置**: `codex-rs/Cargo.toml`
- **核心测试支持依赖**: `codex-rs/core/tests/common/`（相对路径 `../../../core/tests/common`）

## 依赖与外部交互

### 内部依赖（Codex 项目内）

```
app_test_support
├── codex-app-server-protocol  (协议类型)
├── codex-core                 (核心功能)
├── codex-protocol             (协议定义)
├── codex-utils-cargo-bin      (工具)
└── core_test_support          (核心测试支持)
    └── codex-rs/core/tests/common
```

### 外部依赖
- **wiremock**: 用于创建模拟 HTTP 服务器（mock model server、analytics server）
- **tokio**: 异步运行时，支持进程间通信
- **serde/serde_json**: 协议消息的序列化

### 使用方
该 crate 被 `codex-rs/app-server` 的集成测试使用，测试代码通过以下方式引用：

```rust
use app_test_support::McpProcess;
use app_test_support::create_mock_responses_server_sequence;
// ... 其他导出项
```

## 风险、边界与改进建议

### 风险
1. **路径依赖风险**：`core_test_support` 使用相对路径 `../../../core/tests/common`，如果目录结构变动会失效
2. **Workspace 版本漂移**：依赖 workspace 配置意味着该 crate 的版本与工作空间绑定，独立发布困难

### 边界
- 该 crate 仅用于测试，不应被生产代码依赖
- 依赖 `codex-utils-cargo-bin` 意味着测试需要预编译的二进制文件

### 改进建议
1. **路径依赖优化**：考虑使用 workspace 成员路径替代相对路径，例如 `{ path = "@codex//core/tests/common" }`（如果 Bazel 支持）
2. **dev-dependencies 分离**：部分依赖（如 wiremock）可能更适合标记为 dev-dependencies
3. **特性门控**：考虑为不同测试场景添加可选特性，减少编译时间
4. **文档依赖**：添加注释说明每个依赖的具体用途，便于维护
