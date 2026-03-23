# codex-rs/skills/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-skills` crate 的构建配置。该 crate 负责 Codex 的 **系统技能（System Skills）** 管理，包括嵌入式技能的安装、缓存和指纹验证。

在 Codex 架构中，skills crate 是一个底层支持库，被 `codex-core` 依赖，用于在启动时将嵌入在二进制中的系统技能解压到用户目录。

## 功能点目的

该 Bazel 构建文件定义了以下构建目标：

1. **Rust Crate 目标**: 使用 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）创建名为 `skills` 的 Rust 库
2. **编译时数据包含**: 通过 `compile_data` 参数将 `src/assets/samples` 目录下的所有文件嵌入到二进制中

### 关键配置说明

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `skills` | Bazel 目标名称 |
| `crate_name` | `codex_skills` | 生成的 Rust crate 名称 |
| `compile_data` | `glob(["**"], exclude=[...])` | 编译时嵌入的数据文件 |

### 排除规则

`compile_data` 排除了以下文件：
- `**/* *` - 文件名包含空格的文件
- `BUILD.bazel` - Bazel 构建文件本身
- `Cargo.toml` - Cargo 配置文件

## 具体技术实现

### 1. 编译时数据嵌入机制

```bazel
compile_data = glob(
    include = ["**"],
    exclude = [
        "**/* *",
        "BUILD.bazel",
        "Cargo.toml",
    ],
    allow_empty = True,
)
```

这些编译时数据在 `src/lib.rs` 中通过 `include_dir!` 宏被嵌入：

```rust
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

### 2. 与 Cargo 构建的协作

- Bazel 构建时，`compile_data` 确保 `src/assets/samples` 下的文件对编译器可见
- Cargo 构建时，`build.rs` 负责监控这些文件的变更（通过 `cargo:rerun-if-changed`）

## 关键代码路径与文件引用

### 本文件
- `/home/sansha/Github/codex/codex-rs/skills/BUILD.bazel`

### 相关文件
- `/home/sansha/Github/codex/codex-rs/skills/src/lib.rs` - 使用 `include_dir!` 嵌入编译时数据
- `/home/sansha/Github/codex/codex-rs/skills/build.rs` - Cargo 构建脚本，监控文件变更
- `/home/sansha/Github/codex/codex-rs/skills/src/assets/samples/` - 嵌入式系统技能目录
- `/home/sansha/Github/codex/defs.bzl` - `codex_rust_crate` 宏定义

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/BUILD.bazel` - 依赖 `codex-skills`
- `/home/sansha/Github/codex/codex-rs/core/src/skills/system.rs` - 调用 `install_system_skills`

## 依赖与外部交互

### Bazel 依赖
- `//:defs.bzl` - 项目自定义的 Rust crate 构建宏

### 运行时依赖（通过 Cargo.toml）
- `codex-utils-absolute-path` - 绝对路径处理工具
- `include_dir` - 编译时目录嵌入
- `thiserror` - 错误处理宏

### 下游依赖
- `codex-core` - 核心库，使用 skills crate 安装系统技能

## 风险、边界与改进建议

### 风险点

1. **文件路径包含空格**: 构建配置明确排除了含空格的文件名，如果技能资源文件包含空格会被静默忽略
2. **空目录处理**: `allow_empty = True` 允许空目录，但如果 `src/assets/samples` 被意外清空，编译仍能成功但运行时功能缺失

### 边界情况

1. **Bazel vs Cargo 差异**: 
   - Bazel 使用 `compile_data` 嵌入文件
   - Cargo 使用 `include_dir` crate 和 `build.rs` 监控变更
   - 两者需要保持行为一致

2. **文件监控**: `build.rs` 递归监控 `src/assets/samples` 下的所有文件，文件数量过多可能影响增量编译性能

### 改进建议

1. **添加验证**: 在构建时验证 `src/assets/samples` 非空且包含预期的技能文件
2. **文档化**: 添加注释说明 `compile_data` 与 `include_dir` 的关系
3. **测试覆盖**: 添加构建测试确保嵌入的文件可以被正确读取
4. **性能优化**: 如果技能文件数量增长，考虑分层或压缩存储

### 相关测试

- `codex-rs/skills/src/lib.rs` 中的单元测试 `fingerprint_traverses_nested_entries` 验证了嵌入式目录的遍历
