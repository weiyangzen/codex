# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中用于定义 `codex-windows-sandbox` crate 构建规则的构建配置文件。该文件位于 `codex-rs/windows-sandbox-rs/` 目录下，负责声明 Rust crate 的构建元数据、依赖关系和编译时资源。

## 功能点目的

### 1. Crate 定义与命名
- **crate_name**: `codex_windows_sandbox` - 这是 crate 的 Rust 内部名称
- **name**: `windows-sandbox-rs` - 这是 Bazel 目标名称
- **crate_edition**: `2021` - 使用 Rust 2021 Edition 语法

### 2. 构建脚本数据声明
通过 `build_script_data` 声明了构建脚本 (`build.rs`) 在编译时需要的文件：
- `Cargo.toml` - 用于读取 crate 元数据
- `codex-windows-sandbox-setup.manifest` - Windows 应用程序清单文件

这些文件会被 Bazel 在构建时提供给 `build.rs` 使用。

## 具体技术实现

### Bazel 宏调用
```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "windows-sandbox-rs",
    crate_name = "codex_windows_sandbox",
    build_script_data = [
        "Cargo.toml",
        "codex-windows-sandbox-setup.manifest",
    ],
    crate_edition = "2021",
)
```

### 关键配置解析

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `windows-sandbox-rs` | Bazel 目标标识符 |
| `crate_name` | `codex_windows_sandbox` | Rust crate 名称（下划线分隔） |
| `crate_edition` | `2021` | Rust 语言版本 |
| `build_script_data` | `[Cargo.toml, manifest]` | 构建脚本依赖的文件 |

## 关键代码路径与文件引用

### 依赖关系
- **调用方**: 根目录 `defs.bzl` 中的 `codex_rust_crate` 宏
- **被调用文件**:
  - `Cargo.toml` - crate 元数据和依赖声明
  - `codex-windows-sandbox-setup.manifest` - Windows UAC 清单
  - `build.rs` - 构建脚本（由 Bazel 自动调用）

### 构建输出
该配置会生成两个二进制文件：
1. `codex-windows-sandbox-setup.exe` - 沙箱设置工具（需要管理员权限）
2. `codex-command-runner.exe` - 命令执行器（在沙箱用户下运行）

## 依赖与外部交互

### Bazel 工作空间依赖
- `//:defs.bzl` - 项目自定义的 Rust crate 构建规则

### 文件系统依赖
- `Cargo.toml` - 必须在同一目录下存在
- `codex-windows-sandbox-setup.manifest` - Windows 清单文件

### 与 Cargo 的互操作
该 `BUILD.bazel` 与 `Cargo.toml` 保持同步：
- `crate_name` 对应 `Cargo.toml` 中的 `package.name`（将 `-` 替换为 `_`）
- `crate_edition` 对应 `Cargo.toml` 中的 `package.edition`
- `build_script_data` 中的文件是 `Cargo.toml` 中 `[package] build = "build.rs"` 所需的

## 风险、边界与改进建议

### 风险点
1. **路径硬编码**: `build_script_data` 中的文件名是硬编码的，如果 `Cargo.toml` 中的 `build` 字段修改，这里也需要同步更新
2. **平台限制**: 该 crate 是 Windows 专用的，但 Bazel 配置中没有显式的平台限制

### 边界条件
- 仅在 Windows 平台上实际可用（代码中有 `#[cfg(target_os = "windows")]` 保护）
- 需要 Windows SDK 和相关的系统库才能编译

### 改进建议
1. **添加平台约束**: 可以考虑添加 `target_compatible_with` 来标记 Windows 专用
   ```bazel
   target_compatible_with = ["@platforms//os:windows"],
   ```

2. **动态读取 Cargo.toml**: 考虑使用 `cargo_build_script` 规则自动处理构建脚本依赖

3. **文档注释**: 添加注释说明 `build_script_data` 中每个文件的用途

4. **版本同步**: 考虑使用自动化工具保持 `BUILD.bazel` 和 `Cargo.toml` 的同步
