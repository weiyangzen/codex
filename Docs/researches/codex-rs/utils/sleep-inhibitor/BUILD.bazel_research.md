# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/utils/sleep-inhibitor` crate 的 Bazel 构建配置，负责定义 Rust 库目标。它是 Bazel 构建系统识别和编译 sleep-inhibitor 模块的入口点。

## 功能点目的

- **定义 Bazel 构建目标**: 使用项目统一的 `codex_rust_crate` 宏来声明 Rust crate
- **统一构建规范**: 通过 `//:defs.bzl` 导入的宏确保所有 Rust crate 遵循一致的构建规则
- **指定 crate 名称**: 明确指定 Rust crate 名称为 `codex_utils_sleep_inhibitor`（符合 AGENTS.md 中提到的 `codex-` 前缀规范）

## 具体技术实现

### 构建规则结构

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "sleep-inhibitor",
    crate_name = "codex_utils_sleep_inhibitor",
)
```

### 关键参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"sleep-inhibitor"` | Bazel 目标名称，与目录名一致 |
| `crate_name` | `"codex_utils_sleep_inhibitor"` | Rust crate 名称，使用下划线分隔 |

### 底层宏行为

`codex_rust_crate` 宏（定义于 `//:defs.bzl`）会自动处理：
1. 检测 `src/` 目录存在时构建库目标
2. 自动发现并包含 `src/**/*.rs` 源文件
3. 从 `@crates` 解析 Cargo.lock 依赖
4. 创建单元测试和集成测试目标
5. 设置 `INSTA_WORKSPACE_ROOT` 和 `INSTA_SNAPSHOT_PATH` 环境变量用于快照测试
6. 配置 `CARGO_BIN_EXE_*` 环境变量供集成测试使用

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/utils/sleep-inhibitor/BUILD.bazel` - 本文件

### 依赖的构建定义
- `/home/sansha/Github/codex/defs.bzl` - 导入 `codex_rust_crate` 宏

### 源文件（自动发现）
- `src/lib.rs` - 主库入口
- `src/dummy.rs` - 非目标平台空实现
- `src/macos.rs` - macOS IOKit 实现
- `src/iokit_bindings.rs` - IOKit FFI 绑定
- `src/linux_inhibitor.rs` - Linux 子进程实现
- `src/windows_inhibitor.rs` - Windows Power API 实现

### Cargo 配置（依赖来源）
- `Cargo.toml` - 定义 crate 元数据和依赖

## 依赖与外部交互

### Bazel 外部依赖
- `@crates` - 解析自 Cargo.lock 的 Rust crate 依赖
- `//:defs.bzl` - 项目内部构建工具宏

### 条件编译依赖（通过 Cargo.toml 传递）
- `tracing` - 日志追踪（workspace 统一版本）
- `core-foundation` (macOS) - macOS Core Foundation 框架绑定
- `libc` (Linux) - Linux 系统调用
- `windows-sys` (Windows) - Windows API 绑定

## 风险、边界与改进建议

### 风险点
1. **平台特定依赖**: 该 crate 使用大量平台条件编译，Bazel 构建需要正确处理目标平台约束
2. **FFI 安全性**: 涉及系统级 FFI 调用（IOKit、Windows Power API、Linux prctl），构建配置需确保链接正确的系统库

### 边界情况
1. **多平台支持**: 当前支持 Linux、macOS、Windows，其他平台回退到 dummy 实现
2. **测试覆盖**: 单元测试在 `lib.rs` 中，主要验证状态切换不 panic，不涉及实际系统调用

### 改进建议
1. **显式 srcs**: 当前使用默认 `src/**/*.rs` 模式，如需更精确控制可考虑显式指定 `crate_srcs`
2. **构建脚本**: 如需生成代码（如 bindgen），可能需要启用 `build_script_enabled` 并配置 `build_script_data`
3. **平台特定测试标签**: 可考虑为平台特定测试添加 `test_tags` 以在 CI 中条件执行
