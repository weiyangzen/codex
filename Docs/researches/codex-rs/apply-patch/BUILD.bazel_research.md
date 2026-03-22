# BUILD.bazel 研究文档

## 场景与职责

此 BUILD.bazel 文件是 Bazel 构建系统中 `codex-rs/apply-patch` crate 的构建配置。它定义了如何将 apply-patch 模块编译为 Rust crate，并管理其编译时依赖的资源文件。

## 功能点目的

### 1. 加载构建规则
```bazel
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载自定义的 Rust crate 构建规则 `codex_rust_crate`，这是项目内部封装的 Bazel 构建宏。

### 2. 导出文件
```bazel
exports_files(["apply_patch_tool_instructions.md"])
```
将 `apply_patch_tool_instructions.md` 文件标记为可导出，允许其他 Bazel 目标引用此文件。这是必要的，因为该文件包含在编译时被嵌入到二进制中的工具使用说明。

### 3. Crate 定义
```bazel
codex_rust_crate(
    name = "apply-patch",
    crate_name = "codex_apply_patch",
    compile_data = [
        "apply_patch_tool_instructions.md",
    ],
)
```

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `apply-patch` | Bazel 目标名称 |
| `crate_name` | `codex_apply_patch` | 编译后的 Rust crate 名称（使用下划线） |
| `compile_data` | `apply_patch_tool_instructions.md` | 编译时数据依赖，通过 `include_str!` 嵌入 |

## 具体技术实现

### 编译时资源嵌入
在 `src/lib.rs` 中，工具说明文档通过以下方式嵌入：
```rust
pub const APPLY_PATCH_TOOL_INSTRUCTIONS: &str = include_str!("../apply_patch_tool_instructions.md");
```

这要求 BUILD.bazel 必须将 `apply_patch_tool_instructions.md` 声明为 `compile_data`，确保 Bazel 在编译时将此文件放入正确的位置。

### Bazel 与 Cargo 的对应关系

| Bazel | Cargo |
|-------|-------|
| `codex_rust_crate` | `[[bin]]` + `[lib]` |
| `compile_data` | `include_str!` 依赖的文件 |
| `exports_files` | 无直接对应，Bazel 特有 |

## 关键代码路径与文件引用

```
codex-rs/apply-patch/
├── BUILD.bazel              # 本文件
├── Cargo.toml               # Cargo 配置（用于非 Bazel 构建）
├── apply_patch_tool_instructions.md  # 编译时嵌入的工具说明
└── src/
    ├── lib.rs               # 使用 include_str! 嵌入说明文档
    ├── main.rs              # 二进制入口
    └── ...
```

## 依赖与外部交互

### 内部依赖
- `//:defs.bzl` - 项目级 Bazel 构建规则定义
- `apply_patch_tool_instructions.md` - 同目录下的工具说明文档

### 被依赖方
- `codex-rs/arg0` - 通过 `CODEX_CORE_APPLY_PATCH_ARG1` 调用 apply-patch
- `codex-rs/core` - 使用 `codex_apply_patch` crate 处理补丁
- `codex-rs/exec` - 执行 apply-patch 操作

## 风险、边界与改进建议

### 风险
1. **资源文件路径变更**：如果 `apply_patch_tool_instructions.md` 移动位置，需要同步更新 BUILD.bazel 和 lib.rs 中的路径
2. **Bazel/Cargo 同步**：Cargo.toml 和 BUILD.bazel 需要保持同步，否则可能导致构建不一致

### 边界
- 此 BUILD.bazel 仅适用于 Bazel 构建系统，Cargo 构建使用 Cargo.toml
- `compile_data` 仅包含单个文件，如需添加更多编译时资源需要手动扩展

### 改进建议
1. 考虑使用自动化工具（如 `cargo-gazelle`）从 Cargo.toml 生成 BUILD.bazel，减少维护负担
2. 可以添加 `visibility` 属性控制 crate 的可见性范围
3. 考虑为测试目标添加单独的 `codex_rust_test` 规则定义
