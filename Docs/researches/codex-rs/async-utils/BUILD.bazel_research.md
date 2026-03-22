# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/async-utils` crate 的 Bazel 构建配置，负责定义该 crate 在 Bazel 构建系统中的构建规则。它是连接 Rust 源代码与 Bazel 构建系统的桥梁，使得该 crate 可以被 Bazel 正确编译和链接。

## 功能点目的

### 1. 加载宏定义
```starlark
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏，这是一个封装好的 Rust crate 构建规则，统一处理库、二进制文件和测试目标的构建。

### 2. 定义 Rust Crate
```starlark
codex_rust_crate(
    name = "async-utils",
    crate_name = "codex_async_utils",
)
```
- `name`: Bazel 目标名称，使用目录名 `async-utils`
- `crate_name`: Rust crate 名称，使用下划线命名规范 `codex_async_utils`

## 具体技术实现

### 构建规则解析

`codex_rust_crate` 宏（定义在 `/home/sansha/Github/codex/defs.bzl`）会为该 crate 自动生成以下目标：

1. **库目标 (`rust_library`)**
   - 名称: `async-utils`
   - crate 名称: `codex_async_utils`
   - 源码: `src/**/*.rs`（自动 glob 匹配）
   - 依赖: 从 `@crates` 解析的依赖 + 构建脚本依赖

2. **单元测试目标**
   - `async-utils-unit-tests-bin`: 测试二进制文件
   - `async-utils-unit-tests`: 带 workspace root launcher 的测试包装器
   - 支持 Insta snapshot 测试框架的环境变量配置

3. **构建脚本处理**
   - 如果存在 `build.rs`，自动创建构建脚本目标
   - 构建脚本可以访问编译时数据文件

### 关键配置参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `async-utils` | Bazel 目标名 |
| `crate_name` | `codex_async_utils` | Rust crate 名（下划线规范） |
| `deps` | 自动解析 | 从 `@crates` 获取 |
| `srcs` | `src/**/*.rs` | 自动 glob |
| `visibility` | `//visibility:public` | 全局可见 |

## 关键代码路径与文件引用

### 相关文件
- **当前文件**: `/home/sansha/Github/codex/codex-rs/async-utils/BUILD.bazel`
- **宏定义**: `/home/sansha/Github/codex/defs.bzl` (第 89-265 行)
- **Cargo 配置**: `/home/sansha/Github/codex/codex-rs/async-utils/Cargo.toml`
- **源码**: `/home/sansha/Github/codex/codex-rs/async-utils/src/lib.rs`

### Bazel 工作区依赖
- `@crates//:data.bzl` - 依赖数据定义
- `@crates//:defs.bzl` - crate 依赖规则
- `@rules_rust//rust:defs.bzl` - Rust 规则定义
- `@rules_platform//platform_data:defs.bzl` - 平台数据规则

## 依赖与外部交互

### 输入依赖
1. **源码文件**: `src/lib.rs`（通过 glob 自动收集）
2. **Cargo.toml**: 定义 crate 元数据和依赖
3. **defs.bzl**: 项目级 Rust 构建宏
4. **外部 crates**: 通过 `@crates` 工作区解析

### 输出产物
1. Rust 库 rlib (`.rlib`)
2. 单元测试二进制文件
3. 供其他 crate 依赖的接口

### 消费方
- `codex-core` crate（在 `codex-rs/core/Cargo.toml` 中声明依赖）

## 风险、边界与改进建议

### 风险点
1. **命名不一致**: Bazel 目标名使用短横线 (`async-utils`)，而 crate 名使用下划线 (`codex_async_utils`)，需要确保两者映射正确
2. **依赖同步**: Bazel 和 Cargo 的依赖需要保持一致，修改 Cargo.toml 后需要更新 Bazel 锁文件

### 边界情况
1. **空 src 目录**: 如果 `src/` 目录为空或不存在，`lib_srcs` 将为空，库目标不会创建
2. **平台兼容性**: 通过 `defs.bzl` 中的 `PLATFORMS` 定义支持多平台构建（Linux musl、macOS、Windows）

### 改进建议
1. **显式 srcs**: 当前使用 `native.glob` 自动收集源文件，建议考虑显式列出关键源文件以提高构建可预测性
2. **文档生成**: 可以添加 `rust_doc` 目标自动生成文档
3. **特性标记**: 如果未来需要条件编译特性，可以通过 `crate_features` 参数扩展

### 维护注意事项
- 修改 `Cargo.toml` 依赖后，需要运行 `just bazel-lock-update` 更新 `MODULE.bazel.lock`
- 修改后应运行 `just bazel-lock-check` 验证锁文件一致性
