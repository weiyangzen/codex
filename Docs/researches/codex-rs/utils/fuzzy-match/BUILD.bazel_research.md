# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/utils/fuzzy-match` crate 的 Bazel 构建配置，定义了如何将这个 Rust 工具 crate 集成到项目的 Bazel 构建系统中。它是连接 Cargo 生态与 Bazel 构建系统的桥梁。

## 功能点目的

1. **统一构建规则**: 通过 `load("//:defs.bzl", "codex_rust_crate")` 引入项目统一的 Rust crate 构建宏，确保所有 Rust crate 遵循一致的构建规范
2. **简化配置**: 仅需指定 `name` 和 `crate_name` 两个参数，其余构建细节由 `codex_rust_crate` 宏统一处理
3. **Bazel/Cargo 互操作**: 使该 crate 既能通过 Cargo 构建，也能通过 Bazel 构建

## 具体技术实现

### 关键配置项

```starlark
codex_rust_crate(
    name = "fuzzy-match",           # Bazel 目标名称
    crate_name = "codex_utils_fuzzy_match",  # Rust crate 名称（下划线格式）
)
```

### 构建宏行为（来自 defs.bzl）

`codex_rust_crate` 宏会自动处理：

1. **源码收集**: 自动 glob `src/**/*.rs` 文件
2. **依赖解析**: 从 `@crates` 外部仓库解析 Cargo 依赖
3. **构建脚本**: 自动检测并处理 `build.rs`
4. **测试目标**: 自动生成单元测试和集成测试目标
5. **多平台支持**: 支持跨平台构建（Linux/macOS/Windows）

### 依赖关系

- **加载依赖**: `//:defs.bzl` - 项目级 Bazel 定义
- **外部依赖**: `@crates//:data.bzl`, `@crates//:defs.bzl` - Cargo 依赖解析
- **规则依赖**: `@rules_rust//rust:defs.bzl` - Rust Bazel 规则

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/utils/fuzzy-match/BUILD.bazel` - 本配置文件

### 相关文件
- `/home/sansha/Github/codex/defs.bzl` - 定义 `codex_rust_crate` 宏
- `/home/sansha/Github/codex/codex-rs/utils/fuzzy-match/Cargo.toml` - Cargo 构建配置
- `/home/sansha/Github/codex/codex-rs/utils/fuzzy-match/src/lib.rs` - 库源码

### 构建命令示例
```bash
# Bazel 构建
bazel build //codex-rs/utils/fuzzy-match

# Bazel 测试
bazel test //codex-rs/utils/fuzzy-match:unit-tests
```

## 依赖与外部交互

### 上游依赖（构建时）
| 依赖 | 来源 | 用途 |
|------|------|------|
| `//:defs.bzl` | 项目根目录 | 统一构建宏 |
| `@crates` | Bazel 外部仓库 | Cargo 依赖解析 |
| `@rules_rust` | Bazel 外部仓库 | Rust 构建规则 |

### 下游使用者
| 使用者 | 路径 | 用途 |
|--------|------|------|
| codex-tui | `//codex-rs/tui` | 模糊匹配技能/命令 |
| codex-tui-app-server | `//codex-rs/tui_app_server` | 模糊匹配功能 |
| codex-file-search | `//codex-rs/file-search` | 文件搜索匹配 |

## 风险、边界与改进建议

### 风险点
1. **名称不一致**: `name` 使用 kebab-case (`fuzzy-match`)，而 `crate_name` 使用 snake_case (`codex_utils_fuzzy_match`)，手动维护容易出错
2. **宏依赖**: 重度依赖 `codex_rust_crate` 宏的实现细节，宏变更会影响所有 crate

### 边界条件
1. 该 crate 无外部依赖（纯 Rust 标准库实现），因此 `codex_rust_crate` 不会引入额外的 `@crates` 依赖
2. 无 `build.rs`，因此构建脚本相关逻辑不会触发
3. 无二进制目标，仅作为库使用

### 改进建议
1. **名称校验**: 在 `codex_rust_crate` 宏中添加 `name` 和 `crate_name` 的格式校验，确保命名规范一致性
2. **文档生成**: 考虑添加 `rust_doc` 目标自动生成文档
3. **可见性控制**: 当前 `visibility = ["//visibility:public"]` 由宏统一设置，如需细粒度控制可能需要扩展宏参数
