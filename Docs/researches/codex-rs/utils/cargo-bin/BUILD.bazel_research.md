# BUILD.bazel 研究文档

## 场景与职责

该 BUILD.bazel 文件定义了 `codex-utils-cargo-bin` crate 的 Bazel 构建配置，位于 `codex-rs/utils/cargo-bin/` 目录。它是 Codex 项目中 Cargo 与 Bazel 双构建系统兼容性的关键基础设施组件。

核心职责：
1. 导出 `repo_root.marker` 文件供其他 crate 依赖
2. 配置 `codex_rust_crate` 宏以生成 Rust 库
3. 设置编译期环境变量 `CODEX_REPO_ROOT_MARKER` 用于运行时定位仓库根目录

## 功能点目的

### 1. exports_files - 导出 repo_root.marker

```bazel
exports_files(
    ["repo_root.marker"],
    visibility = ["//visibility:public"],
)
```

**目的**：将空的 `repo_root.marker` 文件导出为公共可见的 Bazel 目标。该文件作为仓库根目录的标记物，用于在运行时通过 runfiles 系统解析仓库根路径。

**使用场景**：
- `defs.bzl` 中的 `workspace_root_test` 规则引用此文件
- `codex_rust_crate` 宏为所有测试目标注入 `workspace_root_marker`
- `repo_root()` 函数在运行时使用此标记文件向上回溯 4 层目录找到仓库根

### 2. codex_rust_crate - 定义 Rust crate

```bazel
codex_rust_crate(
    name = "cargo-bin",
    crate_name = "codex_utils_cargo_bin",
    compile_data = ["repo_root.marker"],
    lib_data_extra = ["repo_root.marker"],
    test_data_extra = ["repo_root.marker"],
    rustc_env = {
        "CODEX_REPO_ROOT_MARKER": "$(rlocationpath :repo_root.marker)",
    },
)
```

**目的**：定义 `codex-utils-cargo-bin` crate 的构建规则。

**关键配置项**：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `cargo-bin` | Bazel 目标名称 |
| `crate_name` | `codex_utils_cargo_bin` | Rust crate 名称（下划线格式） |
| `compile_data` | `["repo_root.marker"]` | 编译期数据依赖 |
| `lib_data_extra` | `["repo_root.marker"]` | 库运行时数据依赖 |
| `test_data_extra` | `["repo_root.marker"]` | 测试运行时数据依赖 |
| `rustc_env` | `CODEX_REPO_ROOT_MARKER` | 编译期环境变量，值为 rlocation 路径 |

## 具体技术实现

### rlocationpath 机制

`$(rlocationpath :repo_root.marker)` 是 Bazel 的模板变量，在构建时会被替换为 runfiles 路径。该路径格式如：
- `_main/codex-rs/utils/cargo-bin/repo_root.marker`

在运行时，`runfiles::rlocation!` 宏使用该路径从 runfiles manifest 或目录中解析出绝对路径。

### 与 defs.bzl 的集成

在 `defs.bzl` 中，`codex_rust_crate` 宏为每个 crate 的测试目标配置：

```bazel
workspace_root_test(
    name = name + "-unit-tests",
    env = test_env,
    test_bin = ":" + unit_test_binary,
    workspace_root_marker = "//codex-rs/utils/cargo-bin:repo_root.marker",
    tags = test_tags,
)
```

这意味着所有单元测试都依赖 `repo_root.marker` 来正确设置 `INSTA_WORKSPACE_ROOT` 等环境变量。

## 关键代码路径与文件引用

### 本文件引用
- `repo_root.marker` - 空标记文件，作为仓库根定位的锚点

### 被引用方
- `defs.bzl` - 使用 `workspace_root_marker` 配置测试启动器
- `src/lib.rs` - 读取 `CODEX_REPO_ROOT_MARKER` 环境变量实现 `repo_root()` 函数

### 引用链
```
BUILD.bazel (exports repo_root.marker)
    ↓
//codex-rs/... 任意 crate 的 BUILD.bazel
    ↓
workspace_root_test (通过 workspace_root_marker 属性)
    ↓
workspace_root_test_launcher.sh.tpl / .bat.tpl
    ↓
测试进程 (INSTA_WORKSPACE_ROOT 环境变量)
```

## 依赖与外部交互

### Bazel 规则依赖
- `//:defs.bzl` - 项目自定义的 Rust crate 构建宏

### 运行时依赖
- `runfiles` crate - 解析 Bazel runfiles 路径
- `CODEX_REPO_ROOT_MARKER` 环境变量 - 编译期注入，运行时读取

### 跨平台考虑
- 使用 runfiles manifest 策略（而非目录策略）以支持 Windows
- 避免 Windows 路径长度限制问题
- 保持本地构建与远程构建行为一致

## 风险、边界与改进建议

### 风险

1. **路径硬编码风险**：`repo_root()` 函数假设从 `repo_root.marker` 向上回溯 4 层目录是仓库根。如果目录结构变化，此假设会失效。
   ```rust
   for _ in 0..4 {
       root = root.parent()?.to_path_buf();
   }
   ```

2. **空标记文件依赖**：`repo_root.marker` 是一个空文件，如果被误删除或修改，会导致运行时路径解析失败。

3. **环境变量缺失**：如果 `CODEX_REPO_ROOT_MARKER` 未在编译期设置，`repo_root()` 会返回错误。

### 边界情况

1. **Cargo 构建**：当使用 Cargo 而非 Bazel 构建时，`runfiles_available()` 返回 false，代码回退到 `CARGO_MANIFEST_DIR` 相对路径解析。

2. **Bazel 版本差异**：不同 Bazel 版本的 runfiles 路径格式可能有差异（如 `_main` vs 工作区名称）。

### 改进建议

1. **动态深度检测**：`repo_root()` 应该动态查找 `.git` 目录或 `MODULE.bazel` 文件来确定仓库根，而非硬编码 4 层回溯。

2. **验证标记文件内容**：可以在 `repo_root.marker` 中写入校验内容（如仓库名称哈希），运行时验证以防止错误定位。

3. **文档化目录结构假设**：在 README 或代码注释中明确说明目录深度假设，当移动此 crate 时需要同步修改。

4. **错误信息优化**：当 `repo_root()` 失败时，提供更详细的诊断信息，如尝试的路径、环境变量值等。
