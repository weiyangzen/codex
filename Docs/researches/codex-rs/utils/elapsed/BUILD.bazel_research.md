# BUILD.bazel 研究文档

## 文件信息

- **文件路径**: `codex-rs/utils/elapsed/BUILD.bazel`
- **文件大小**: 123 bytes
- **所属 Crate**: `codex-utils-elapsed`

---

## 场景与职责

此文件是 Bazel 构建系统的构建定义文件，用于定义 `codex-utils-elapsed` crate 的构建规则。该 crate 是一个小型工具库，专门用于格式化时间间隔（elapsed time）为人类可读的字符串形式。

### 在整体架构中的位置

```
codex-rs/
├── utils/
│   ├── elapsed/           <-- 本 crate
│   │   ├── BUILD.bazel    <-- 本文件
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   ├── cargo-bin/
│   ├── git/
│   ├── cache/
│   └── ... (其他工具 crate)
├── core/
├── tui/
├── exec/
└── ... (其他主要 crate)
```

`utils/elapsed` 是一个底层工具 crate，被多个上层 crate 依赖，包括：
- `codex-exec` - 命令行执行工具
- `codex-tui` - 终端用户界面
- `codex-tui-app-server` - TUI 应用服务器
- `codex-core` - 核心库

---

## 功能点目的

### 核心功能

该 Bazel 构建文件定义了如何将 Rust 源代码编译为可重用的库 crate，使得其他 crate 可以通过 Bazel 依赖系统使用 `codex_utils_elapsed` 提供的功能。

### 构建规则说明

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "elapsed",
    crate_name = "codex_utils_elapsed",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"elapsed"` | Bazel 目标名称，用于在 BUILD 文件中引用 |
| `crate_name` | `"codex_utils_elapsed"` | Rust crate 名称，用于 `extern crate` 和 `use` 语句 |

---

## 具体技术实现

### 1. 加载的宏定义

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 文件加载 `codex_rust_crate` 宏。该宏是项目自定义的 Bazel 规则，封装了 Rust 构建的复杂性。

### 2. codex_rust_crate 宏的行为

根据 `defs.bzl` 中的定义（第 89-265 行），`codex_rust_crate` 宏会：

1. **自动发现源码**: 使用 `native.glob(["src/**/*.rs"])` 自动收集 `src/` 目录下的所有 Rust 文件
2. **创建库目标**: 调用 `rust_library` 规则创建 Rust 库
3. **生成单元测试**: 创建 `rust_test` 目标用于运行 `#[cfg(test)]` 模块中的测试
4. **设置可见性**: 设置 `visibility = ["//visibility:public"]` 使其他包可以访问

### 3. 依赖解析

该 crate 没有显式声明依赖（`deps_extra` 为空），但会通过 `all_crate_deps()` 自动解析 `Cargo.toml` 中声明的依赖。由于 `Cargo.toml` 中也没有外部依赖，这是一个**零依赖**的纯 Rust 标准库 crate。

---

## 关键代码路径与文件引用

### 本 crate 内部结构

```
codex-rs/utils/elapsed/
├── BUILD.bazel          <-- 本文件（Bazel 构建定义）
├── Cargo.toml           <-- Cargo 包定义
└── src/
    └── lib.rs           <-- 实际实现（时间格式化逻辑）
```

### 依赖关系图

```
// 被以下 crate 使用（通过 Bazel 依赖）
codex-exec
  └── codex_utils_elapsed (format_duration, format_elapsed)

codex-tui
  └── codex_utils_elapsed (format_duration)

codex-tui-app-server
  └── codex_utils_elapsed (format_duration)

codex-core
  └── 间接使用（通过其他组件）
```

### Bazel 依赖声明示例

在使用方的 `BUILD.bazel` 文件中，依赖声明如下：

```bazel
# codex-rs/exec/BUILD.bazel (示例)
rust_library(
    name = "exec",
    deps = [
        "//codex-rs/utils/elapsed",  # 引用本 crate
        # ... 其他依赖
    ],
)
```

---

## 依赖与外部交互

### 外部依赖

| 类型 | 依赖 | 说明 |
|------|------|------|
| 构建工具 | Bazel | 通过 `rules_rust` 规则构建 |
| 构建工具 | Cargo | 用于本地开发和依赖解析 |
| 标准库 | `std::time` | 使用 `Duration` 和 `Instant` 类型 |

### 零外部依赖设计

该 crate 是一个设计良好的工具 crate：
- **无第三方 crate 依赖**: 仅使用 Rust 标准库
- **轻量级**: 代码量小（约 78 行，包含测试）
- **高可移植性**: 不依赖平台特定代码

---

## 风险、边界与改进建议

### 当前风险

1. **无显式依赖声明**
   - 风险：虽然当前无外部依赖，但如果未来添加依赖，需要同时在 `Cargo.toml` 和 `BUILD.bazel` 中更新
   - 缓解：项目使用 `all_crate_deps()` 自动从 Cargo.lock 解析

2. **Bazel/Cargo 双构建系统维护**
   - 风险：两个构建系统需要保持一致
   - 现状：项目通过 `MODULE.bazel.lock` 和自动化脚本（`just bazel-lock-update`）保持同步

### 边界情况

1. **平台兼容性**
   - `std::time::Instant` 在不同平台上的实现略有差异
   - 在 WebAssembly 等目标上可能需要特殊处理（当前未处理）

2. **时间格式化边界**
   - 超过 1 小时的时间显示为 "60m 00s" 而非 "1h 00m 00s"
   - 这是有意的设计选择，但可能不符合所有使用场景

### 改进建议

1. **文档增强**
   ```bazel
   # 建议添加 crate 用途注释
   # 时间格式化工具库 - 将 Duration/Instant 格式化为人类可读字符串
   codex_rust_crate(
       name = "elapsed",
       crate_name = "codex_utils_elapsed",
   )
   ```

2. **考虑添加特性标志**（如需要）
   ```bazel
   # 如果未来需要可选功能
   codex_rust_crate(
       name = "elapsed",
       crate_name = "codex_utils_elapsed",
       crate_features = ["std"],  # 或其他特性
   )
   ```

3. **测试覆盖率**
   - 当前单元测试覆盖基本场景
   - 建议添加边界测试：非常大的 duration、负值处理（虽然 Duration 不能为负）

### 相关文件引用

| 文件 | 用途 |
|------|------|
| `//:defs.bzl` | 定义 `codex_rust_crate` 宏 |
| `codex-rs/utils/elapsed/Cargo.toml` | Cargo 包定义 |
| `codex-rs/utils/elapsed/src/lib.rs` | 实际实现代码 |
| `MODULE.bazel` | 工作空间级 Bazel 配置 |
