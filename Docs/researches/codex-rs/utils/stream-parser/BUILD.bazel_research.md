# BUILD.bazel 研究文档

## 场景与职责

此文件是 Bazel 构建系统的构建配置，用于定义 `codex-utils-stream-parser` crate 的构建规则。它是 `codex-rs/utils/stream-parser` 目录的构建入口点，将该 Rust crate 集成到整个项目的 Bazel 构建体系中。

## 功能点目的

1. **加载构建规则**: 从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏
2. **定义构建目标**: 使用标准化的宏创建名为 `stream-parser` 的 Rust crate
3. **指定 crate 名称**: 将 Rust crate 名称设置为 `codex_utils_stream_parser`（遵循 AGENTS.md 中规定的 `codex-` 前缀规范）

## 具体技术实现

### 构建规则结构

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "stream-parser",
    crate_name = "codex_utils_stream_parser",
)
```

### 关键配置说明

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `stream-parser` | Bazel 目标名称，用于内部引用 |
| `crate_name` | `codex_utils_stream_parser` | 实际的 Rust crate 名称，使用下划线命名法 |

### 构建系统集成

- 使用项目自定义的 `codex_rust_crate` 宏，该宏封装了 Rust 编译的通用配置
- 自动处理依赖解析、编译标志、测试运行等
- 与 `MODULE.bazel` 和 `MODULE.bazel.lock` 中的依赖管理集成

## 关键代码路径与文件引用

### 相关文件

- `//:defs.bzl` - 定义 `codex_rust_crate` 宏的根级构建定义文件
- `MODULE.bazel` - Bazel 模块定义，声明外部依赖
- `Cargo.toml` - Cargo 构建配置（与 Bazel 并行使用）
- `codex-rs/Cargo.toml` - 工作区级别的 Cargo 配置

### 构建输出

Bazel 构建输出位于 `bazel-bin/codex-rs/utils/stream-parser/` 目录下，包括：
- `.rlib` 文件（Rust 库）
- 测试二进制文件
- 文档生成输出

## 依赖与外部交互

### 上游依赖（输入）

| 依赖 | 来源 | 用途 |
|------|------|------|
| `defs.bzl` | 项目根目录 | 提供 `codex_rust_crate` 宏 |
| `codex-rs/Cargo.toml` | 工作区 | 提供版本、edition、lints 等共享配置 |
| `pretty_assertions` | 开发依赖 | 测试断言美化（来自 Cargo.toml） |

### 下游依赖（输出）

| 消费者 | 路径 | 用途 |
|--------|------|------|
| `codex-core` | `codex-rs/core` | 使用 stream-parser 处理模型输出流 |

### 依赖关系图

```
codex-core (Cargo.toml)
    ↓
codex-utils-stream-parser = { workspace = true }
    ↓
stream-parser/BUILD.bazel
    ↓
//:defs.bzl (codex_rust_crate)
```

## 风险、边界与改进建议

### 风险点

1. **双构建系统维护**: 项目同时使用 Cargo 和 Bazel，需要保持 `Cargo.toml` 和 `BUILD.bazel` 的依赖同步
2. **锁文件漂移**: 根据 AGENTS.md，修改依赖后需要运行 `just bazel-lock-update` 更新 `MODULE.bazel.lock`

### 边界条件

1. **最小化配置**: 此 BUILD 文件极度精简，所有复杂逻辑封装在 `codex_rust_crate` 宏中
2. **无自定义编译标志**: 该 crate 没有特殊的编译器标志或条件编译配置
3. **纯 Rust 代码**: 没有 C/C++ 依赖或构建脚本（build.rs）

### 改进建议

1. **文档注释**: 可添加 Bazel 目标描述注释，便于 `bazel query` 输出
   ```bazel
   codex_rust_crate(
       name = "stream-parser",
       crate_name = "codex_utils_stream_parser",
       # 建议添加: description = "Streaming text parser for hidden markup tags"
   )
   ```

2. **可见性控制**: 当前使用默认可见性，可显式设置为公开
   ```bazel
   visibility = ["//visibility:public"]
   ```

3. **测试配置**: 如需特殊测试配置（如环境变量、资源文件），可在此文件中扩展
