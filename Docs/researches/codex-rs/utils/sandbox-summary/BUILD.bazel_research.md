# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/utils/sandbox-summary` crate 的 Bazel 构建定义文件，负责声明如何在 Bazel 构建系统中编译和打包 `sandbox-summary` 工具库。该库是 Codex 项目中用于生成沙箱策略和配置摘要的实用工具 crate。

## 功能点目的

1. **定义 Bazel 构建目标**: 使用项目自定义的 `codex_rust_crate` 宏来声明 Rust crate 的构建规则
2. **指定 crate 名称**: 将 Bazel 目标名称 `sandbox-summary` 映射到 Cargo crate 名称 `codex_utils_sandbox_summary`
3. **统一构建配置**: 通过中央宏确保所有 Rust crate 遵循一致的构建约定（编译标志、测试配置、依赖解析等）

## 具体技术实现

### 构建规则结构

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "sandbox-summary",
    crate_name = "codex_utils_sandbox_summary",
)
```

### 关键配置项

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `"sandbox-summary"` | Bazel 目标名称，用于命令行引用（如 `bazel build //codex-rs/utils/sandbox-summary`） |
| `crate_name` | `"codex_utils_sandbox_summary` | Cargo crate 名称，用于 Rust 代码中的 `extern crate` 和依赖引用 |

### 底层宏行为（codex_rust_crate）

根据项目根目录 `defs.bzl` 的定义，`codex_rust_crate` 宏执行以下操作：

1. **自动发现源码**: 使用 `native.glob(["src/**/*.rs"])` 自动收集 `src/` 目录下的所有 Rust 源文件
2. **构建脚本支持**: 如果存在 `build.rs`，自动配置 cargo 构建脚本
3. **库目标生成**: 使用 `rust_library` 规则生成库目标
4. **单元测试目标**: 使用 `rust_test` 规则生成单元测试二进制文件
5. **依赖解析**: 通过 `all_crate_deps()` 从 `@crates` 外部仓库解析 Cargo.toml 中声明的依赖

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sandbox-summary/BUILD.bazel` - 本构建定义文件

### 依赖的构建定义
- `//:defs.bzl` - 项目根目录的 Bazel 宏定义，包含 `codex_rust_crate` 实现

### 相关源码文件（由该 BUILD 文件管理构建）
- `codex-rs/utils/sandbox-summary/src/lib.rs` - 库入口，导出两个公共函数
- `codex-rs/utils/sandbox-summary/src/config_summary.rs` - 配置摘要生成实现
- `codex-rs/utils/sandbox-summary/src/sandbox_summary.rs` - 沙箱策略摘要生成实现

### Cargo 配置（依赖来源）
- `codex-rs/utils/sandbox-summary/Cargo.toml` - 定义了依赖 `codex-core` 和 `codex-protocol`

## 依赖与外部交互

### Bazel 外部依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `@crates` | Bazel 外部仓库 | 提供所有 Cargo 依赖的预解析版本 |
| `//:defs.bzl` | 项目内部 | 提供 `codex_rust_crate` 宏 |

### Cargo 依赖（通过 Bazel 转换）

根据 `Cargo.toml`，该 crate 依赖：
- `codex-core` (workspace = true) - 提供 `Config` 和 `WireApi` 类型
- `codex-protocol` (workspace = true) - 提供 `SandboxPolicy` 和 `NetworkAccess` 类型

### 反向依赖（调用方）

该库被以下组件使用：
- `codex-rs/tui` - TUI 状态卡片显示配置摘要
- `codex-rs/tui_app_server` - TUI 应用服务器状态显示
- `codex-rs/exec` - 事件处理器生成人类可读的输出

## 风险、边界与改进建议

### 当前风险

1. **命名不一致风险**: Bazel 目标名使用 kebab-case (`sandbox-summary`)，而 crate 名使用 snake_case (`codex_utils_sandbox_summary`)，可能导致跨系统引用时的混淆

2. **隐式依赖风险**: 通过 `codex_rust_crate` 宏隐式处理大量构建逻辑，新开发者可能不了解完整的构建流程

3. **测试环境配置**: 宏自动设置 `INSTA_WORKSPACE_ROOT` 和 `INSTA_SNAPSHOT_PATH` 环境变量用于快照测试，如果目录结构变化可能导致测试失败

### 边界情况

1. **空 src 目录处理**: 如果 `src/` 目录为空或不存在，`codex_rust_crate` 宏会跳过库目标生成（`if lib_srcs:` 判断）

2. **平台兼容性**: 构建规则通过 `PLATFORMS` 列表支持多平台（Linux musl、macOS、Windows），但 sandbox-summary 的功能可能与特定平台相关

3. **Bazel/Cargo 同步**: 必须保持 `Cargo.toml` 和 `MODULE.bazel.lock` 的同步，否则可能导致依赖解析不一致

### 改进建议

1. **文档注释**: 在 BUILD.bazel 中添加注释说明该 crate 的用途和主要使用方

2. **可见性控制**: 当前 `visibility = ["//visibility:public"]` 允许任何目标依赖，如果这是内部工具库，可以考虑限制可见性

3. **测试标签**: 如果该 crate 的测试需要特殊环境（如禁用沙箱），可以通过 `test_tags` 参数添加标签

4. **显式源码声明**: 对于小型 crate，可以考虑显式声明 `crate_srcs` 而非依赖 glob，提高构建的可预测性

5. **依赖分析**: 定期检查 `codex-core` 的依赖重量，因为该 crate 只使用了 `Config` 和 `WireApi`，如果 `codex-core` 过于庞大，可以考虑将配置类型提取到更小的 crate
