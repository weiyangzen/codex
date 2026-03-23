# BUILD.bazel 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/BUILD.bazel`
- **大小**: 242 bytes
- **所属模块**: codex-rs/core/tests/common (core_test_support)

---

## 场景与职责

此 BUILD.bazel 文件是 Bazel 构建系统中用于定义 `core_test_support` 测试支持库的构建配置。它位于 `codex-rs/core/tests/common/` 目录下，负责将测试公共模块打包成一个独立的 Rust crate，供其他集成测试使用。

### 核心职责
1. **定义测试支持库**: 将 common 目录下的所有 Rust 源文件打包成名为 `core_test_support` 的 crate
2. **管理额外数据依赖**: 声明对模型可用性 NUX (New User Experience) fixtures 的依赖
3. **统一测试基础设施**: 为 codex-rs/core 的所有集成测试提供共享的测试工具和辅助函数

---

## 功能点目的

### 1. Crate 定义与命名
```bazel
codex_rust_crate(
    name = "common",
    crate_name = "core_test_support",
    ...
)
```
- **name**: Bazel 构建目标名称，在 BUILD 文件内标识此规则
- **crate_name**: 实际生成的 Rust crate 名称，其他 crate 通过 `use core_test_support::...` 引用

### 2. 源文件收集
```bazel
crate_srcs = glob(["*.rs"])
```
- 使用 glob 模式自动收集目录下所有 `.rs` 文件
- 包含的模块：lib.rs, responses.rs, streaming_sse.rs, test_codex.rs, test_codex_exec.rs, context_snapshot.rs, apps_test_server.rs, process.rs, tracing.rs, zsh_fork.rs

### 3. 数据依赖
```bazel
lib_data_extra = [
    "//codex-rs/core:model_availability_nux_fixtures",
]
```
- 引入模型可用性相关的 fixture 文件
- 这些 fixtures 用于测试模型发现和可用性通知功能

---

## 具体技术实现

### 构建规则分析

该文件使用项目自定义的 `codex_rust_crate` 宏（定义在 `//:defs.bzl`），这是一个封装了 `rust_library` 和 `rust_test` 的高级构建规则。

#### 依赖传递
通过 `codex_rust_crate` 宏，此 crate 自动继承以下依赖（来自 Cargo.toml 的定义）：
- **核心依赖**: codex-core, codex-protocol
- **工具依赖**: codex-utils-absolute-path, codex-utils-cargo-bin
- **测试工具**: wiremock, tempfile, tokio, futures
- **序列化**: serde_json
- **压缩**: zstd

#### 与 Cargo 的互操作
虽然使用 Bazel 构建，但此配置与 Cargo.toml 保持一致：
- crate_name 与 Cargo.toml 中的 `[package].name` 匹配
- 源文件模式与 Cargo.toml 中的 `[lib].path` 配置兼容

---

## 关键代码路径与文件引用

### 引用关系图
```
codex-rs/core/tests/common/BUILD.bazel
    ├── 定义: core_test_support crate
    ├── 依赖: //codex-rs/core:model_availability_nux_fixtures
    └── 被引用:
        ├── codex-rs/core/tests/all.rs (集成测试入口)
        ├── codex-rs/core/tests/suite/*.rs (各测试套件)
        └── codex-rs/exec/tests/suite/*.rs (exec 模块测试)
```

### 实际使用示例
在 `codex-rs/core/tests/suite/client.rs` 中：
```rust
use core_test_support::apps_test_server::AppsTestServer;
use core_test_support::load_default_config_for_test;
use core_test_support::responses::{mount_sse_once, sse};
use core_test_support::test_codex::{TestCodex, test_codex};
use core_test_support::wait_for_event;
```

---

## 依赖与外部交互

### 内部依赖
| 依赖路径 | 用途 |
|---------|------|
| //codex-rs/core | 被测试的核心库 |
| //codex-rs/protocol | 协议定义 |
| //codex-rs/utils/* | 工具函数 |

### 外部依赖 (通过 Cargo)
| Crate | 用途 |
|-------|------|
| wiremock | HTTP mock 服务器 |
| tokio | 异步运行时 |
| tempfile | 临时目录管理 |
| serde_json | JSON 序列化 |
| zstd | 压缩支持 |

---

## 风险、边界与改进建议

### 潜在风险
1. **glob 模式风险**: 使用 `glob(["*.rs"])` 可能意外包含不需要的文件，建议显式列出关键模块
2. **fixture 依赖**: 对 `model_availability_nux_fixtures` 的硬编码路径依赖可能在重构时失效

### 边界条件
- 此 crate 仅用于测试，不应被生产代码依赖
- 在 Bazel 沙箱环境中运行时，某些文件系统相关测试可能需要特殊处理

### 改进建议
1. **显式源文件列表**: 考虑将 `glob(["*.rs"])` 改为显式文件列表，提高可维护性：
   ```bazel
   crate_srcs = [
       "lib.rs",
       "responses.rs",
       "streaming_sse.rs",
       # ... 其他文件
   ]
   ```

2. **文档注释**: 添加 BUILD.bazel 文件头注释说明其用途

3. **依赖版本锁定**: 确保与 Cargo.lock 的版本一致性，避免 Bazel 和 Cargo 构建结果差异

---

## 相关文件
- `codex-rs/core/tests/common/Cargo.toml` - Cargo 配置
- `codex-rs/core/tests/common/lib.rs` - 库入口
- `codex-rs/defs.bzl` - 自定义 Bazel 规则定义
