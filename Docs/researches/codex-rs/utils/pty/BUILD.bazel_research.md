# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中定义 `codex-utils-pty` crate 的构建配置文件。该文件位于 `codex-rs/utils/pty/` 目录下，负责声明 Rust 库的构建目标、依赖关系和测试配置。

## 功能点目的

### 1. 加载构建规则
```starlark
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载自定义的 `codex_rust_crate` 宏。该宏封装了 Bazel 构建 Rust crate 的标准模式，包括：
- 库目标 (`rust_library`)
- 二进制目标 (`rust_binary`)
- 单元测试 (`rust_test`)
- 集成测试

### 2. 定义 crate 构建目标
```starlark
codex_rust_crate(
    name = "pty",
    crate_name = "codex_utils_pty",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"pty"` | Bazel 目标名称，用于命令行引用 (`//codex-rs/utils/pty:pty`) |
| `crate_name` | `"codex_utils_pty"` | Rust crate 名称，用于 `extern crate` 和导入路径 |

## 具体技术实现

### 构建规则继承
`codex_rust_crate` 宏会自动：
1. **检测源码结构**：扫描 `src/` 目录下的 `.rs` 文件
2. **解析 Cargo.toml**：读取 `package.name`、`dependencies`、`dev-dependencies` 等
3. **生成 Bazel 目标**：
   - `rust_library`：主库目标
   - `rust_test`：单元测试（基于 `src/lib.rs` 中的 `#[cfg(test)]` 模块）
   - 可选的 `rust_binary`：如果 `src/bin/` 存在

### 依赖解析
依赖通过 `MODULE.bazel` 中的 `crate.from_cargo` 从 `Cargo.lock` 解析：
- `anyhow`
- `portable-pty`
- `tokio`
- `libc` (Unix)
- `winapi` (Windows)
- `filedescriptor` (Windows)
- `shared_library` (Windows)
- `lazy_static` (Windows)
- `log` (Windows)

### 平台特定依赖
通过 `select()` 机制处理平台特定依赖：
```starlark
# 伪代码示意
deps = select({
    "@platforms//os:linux": ["@crates//:libc"],
    "@platforms//os:macos": ["@crates//:libc"],
    "@platforms//os:windows": [
        "@crates//:winapi",
        "@crates//:filedescriptor",
        ...
    ],
})
```

## 关键代码路径与文件引用

### 相关文件
| 文件 | 关系 | 说明 |
|------|------|------|
| `defs.bzl` | 被加载 | 定义 `codex_rust_crate` 宏 |
| `Cargo.toml` | 并行配置 | Cargo 依赖声明，Bazel 从中解析 |
| `MODULE.bazel` | 根配置 | 定义外部 crate 仓库 |
| `MODULE.bazel.lock` | 锁定文件 | 依赖版本锁定 |

### 构建命令
```bash
# Bazel 构建
bazel build //codex-rs/utils/pty:pty

# Bazel 测试
bazel test //codex-rs/utils/pty:all

# Cargo 构建（开发时）
cargo build -p codex-utils-pty
```

## 依赖与外部交互

### 内部依赖
- `codex-utils-pty` 不依赖其他内部 crate，是底层工具 crate

### 外部依赖（通过 Bazel `@crates` 仓库）
| Crate | 用途 |
|-------|------|
| `portable-pty` | 跨平台 PTY 抽象 |
| `tokio` | 异步运行时 |
| `anyhow` | 错误处理 |
| `libc` | Unix 系统调用 |
| `winapi` | Windows API 绑定 |

### 调用方（反向依赖）
以下 crate 通过 Bazel 依赖 `codex-utils-pty`：
- `codex-core`：统一执行流程 (`unified_exec/process.rs`)
- `codex-app-server`：命令执行 (`command_exec.rs`)
- `codex-rmcp-client`：RMCP 客户端实现
- `codex-tui`：终端 UI
- `codex-tui-app-server`：TUI 应用服务器

## 风险、边界与改进建议

### 风险
1. **平台差异**：Windows 和 Unix 的依赖差异大，需确保 `select()` 正确配置
2. **版本锁定**：`MODULE.bazel.lock` 需与 `Cargo.lock` 保持同步
3. **构建脚本**：如果添加 `build.rs`，需在 `codex_rust_crate` 中启用 `build_script_enabled`

### 边界
- 该 crate 是**叶节点工具 crate**，无内部依赖，适合作为基础组件
- Windows 实现依赖 vendored 代码（来自 WezTerm），需注意许可证合规

### 改进建议
1. **显式声明 deps**：当前依赖通过 `crate.from_cargo` 隐式解析，可考虑显式声明以提高可读性
2. **添加编译数据**：如果代码使用 `include_str!` 或 `include_bytes!`，需添加 `compile_data`
3. **测试标签**：如需特殊测试配置（如沙箱测试），可添加 `test_tags`

### 示例改进
```starlark
codex_rust_crate(
    name = "pty",
    crate_name = "codex_utils_pty",
    # 如需显式依赖
    deps_extra = select({
        "@platforms//os:windows": ["//third_party:wezterm_license"],
    }),
    # 如需特殊测试标签
    test_tags = ["requires-pty"],
)
```
