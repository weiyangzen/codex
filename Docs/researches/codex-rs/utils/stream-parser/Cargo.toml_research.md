# Cargo.toml 研究文档

## 场景与职责

此文件是 `codex-utils-stream-parser` crate 的 Cargo 包清单，定义了包的元数据、依赖和构建设置。作为工作区成员，它继承父工作区的共享配置，同时声明自身的特定依赖。

## 功能点目的

1. **包标识**: 定义 crate 名称、版本、edition 和许可证
2. **工作区集成**: 通过 `workspace = true` 继承共享配置
3. **lint 配置**: 使用工作区级别的 lint 规则
4. **开发依赖**: 声明仅用于测试的依赖项

## 具体技术实现

### 包元数据配置

```toml
[package]
name = "codex-utils-stream-parser"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承 Rust edition (2021)
license.workspace = true      # 继承许可证 (Apache-2.0)
```

### Lint 配置

```toml
[lints]
workspace = true              # 使用 codex-rs/Cargo.toml 中定义的 clippy 规则
```

工作区 lint 配置包括（来自 `codex-rs/Cargo.toml`）：
- `clippy::collapsible_if` - 合并可折叠的 if 语句
- `clippy::uninlined_format_args` - 内联 format! 参数
- `clippy::redundant_closure_for_method_calls` - 使用方法引用替代闭包

### 开发依赖

```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
```

`pretty_assertions` 用于生成更易读的测试失败输出，支持彩色 diff 显示。

## 关键代码路径与文件引用

### 相关文件

| 文件 | 路径 | 关系 |
|------|------|------|
| 工作区 Cargo.toml | `codex-rs/Cargo.toml` | 定义共享的 `workspace.dependencies` 和 `[workspace.lints]` |
| 根目录 Cargo.toml | `codex-rs/utils/stream-parser/Cargo.toml` | 当前文件 |
| 库入口 | `src/lib.rs` | 包的主库文件 |
| BUILD.bazel | `BUILD.bazel` | Bazel 构建配置（与 Cargo 并行） |

### 工作区依赖解析

在 `codex-rs/Cargo.toml` 中定义：
```toml
[workspace.dependencies]
pretty_assertions = "1.4"
# ... 其他共享依赖

[workspace.lints.clippy]
collapsible_if = "warn"
uninlined_format_args = "warn"
redundant_closure_for_method_calls = "warn"
```

## 依赖与外部交互

### 运行时依赖

本 crate **零运行时依赖**，是一个纯标准库实现。这是其设计目标之一：
> "Small, dependency-free utilities for parsing streamed text incrementally."

### 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `pretty_assertions` | 1.4 (工作区) | 测试断言美化 |

### 下游消费者

| 包 | 路径 | 使用方式 |
|----|------|---------|
| `codex-core` | `codex-rs/core` | `codex-utils-stream-parser = { workspace = true }` |

使用代码示例（来自 `codex-rs/core/src/stream_events_utils.rs`）：
```rust
use codex_utils_stream_parser::strip_citations;
use codex_utils_stream_parser::strip_proposed_plan_blocks;
```

## 风险、边界与改进建议

### 风险点

1. **版本漂移**: 虽然使用 `workspace = true`，但如果工作区版本更新，需要确保兼容性
2. **Edition 升级**: 当前使用工作区 edition，升级可能影响编译行为

### 边界条件

1. **无特性标志**: 本 crate 没有定义 `[features]` 部分，所有功能始终启用
2. **无构建脚本**: 没有 `build.rs`，纯 Rust 源码编译
3. **无平台特定依赖**: 没有 `[target.'cfg(...)'.dependencies]` 配置

### 改进建议

1. **添加描述和关键词**: 提高 crates.io 可发现性（如果未来发布）
   ```toml
   [package]
   description = "Streaming parser for hidden markup tags in LLM outputs"
   keywords = ["parser", "streaming", "markdown", "llm"]
   categories = ["text-processing", "parsing"]
   ```

2. **添加仓库链接**:
   ```toml
   repository = "https://github.com/openai/codex"
   ```

3. **考虑添加可选特性**: 如果未来需要serde支持，可添加可选特性
   ```toml
   [features]
   default = []
   serde = ["dep:serde"]
   ```

4. **文档测试**: 当前 `src/lib.rs` 没有 doctests，可考虑在关键公共 API 上添加
