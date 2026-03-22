# BUILD.bazel 研究文档

## 场景与职责

此 BUILD.bazel 文件位于 `codex-rs/app-server-client/` 目录，是 Bazel 构建系统中用于定义 Rust crate 构建规则的构建配置文件。它使用项目根目录 `defs.bzl` 中定义的 `codex_rust_crate` 宏来标准化 Rust crate 的构建配置。

该 crate 的名称为 `app-server-client`，对应的 Rust crate 名称为 `codex_app_server_client`。

## 功能点目的

1. **标准化构建配置**: 通过复用 `codex_rust_crate` 宏，确保所有 Rust crate 遵循一致的构建规则
2. **库目标定义**: 定义 Rust 库目标，供其他 crate 依赖
3. **测试目标生成**: 自动生成单元测试和集成测试目标
4. **与 Cargo 兼容**: 通过 Bazel 的 Cargo 集成保持与 Cargo 构建系统的兼容性

## 具体技术实现

### 关键构建规则

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "app-server-client",
    crate_name = "codex_app_server_client",
)
```

### 参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"app-server-client"` | Bazel 目标名称，使用目录名 |
| `crate_name` | `"codex_app_server_client"` | Rust crate 名称，使用下划线命名规范 |

### codex_rust_crate 宏功能

根据 `defs.bzl` 中的定义，`codex_rust_crate` 宏会自动：

1. **库构建**: 如果 `src/` 目录存在，创建 `rust_library` 目标
2. **构建脚本支持**: 如果存在 `build.rs`，自动配置构建脚本
3. **单元测试**: 创建 `rust_test` 目标运行单元测试
4. **workspace_root_test**: 配置测试运行环境，设置 `INSTA_WORKSPACE_ROOT` 等环境变量
5. **二进制目标**: 如果配置中有二进制文件定义，创建对应的 `rust_binary` 目标
6. **集成测试**: 自动发现 `tests/*.rs` 文件并创建集成测试目标

## 关键代码路径与文件引用

### 直接依赖的文件

| 文件 | 用途 |
|------|------|
| `//:defs.bzl` | 加载 `codex_rust_crate` 宏定义 |
| `src/lib.rs` | 库的主入口文件（由宏自动发现） |
| `src/remote.rs` | 远程客户端实现（由宏自动发现） |

### 间接依赖

- `@crates//:data.bzl` - Cargo 依赖数据
- `@rules_rust//rust:defs.bzl` - Rust Bazel 规则

## 依赖与外部交互

### 构建时依赖

该 BUILD.bazel 本身不直接声明依赖，依赖通过以下方式解析：

1. **Cargo.toml 依赖**: 由 `codex_rust_crate` 宏通过 `@crates` 仓库解析
2. **workspace 依赖**: 继承自根工作空间的依赖配置

### 运行时依赖（来自 Cargo.toml）

- `codex-app-server` - 应用服务器核心
- `codex-app-server-protocol` - 协议定义
- `codex-arg0` - argv0 处理
- `codex-core` - 核心功能
- `codex-feedback` - 反馈系统
- `codex-protocol` - 协议实现
- `futures` - 异步编程
- `serde`/`serde_json` - 序列化
- `tokio` - 异步运行时
- `tokio-tungstenite` - WebSocket 支持
- `toml` - TOML 解析
- `tracing` - 日志追踪
- `url` - URL 处理

## 风险、边界与改进建议

### 风险

1. **宏依赖风险**: 构建逻辑高度依赖 `codex_rust_crate` 宏，宏的变更会影响所有使用它的 crate
2. **隐式文件发现**: 宏使用 `native.glob` 自动发现源文件，可能导致意外文件被包含
3. **无显式依赖声明**: 依赖全部通过 Cargo.toml 和 `@crates` 间接解析，Bazel 层面缺乏可见性

### 边界

1. **单配置构建**: 根据宏文档，crate 在整个工作空间中只以单一配置编译（启用所有特性）
2. **无自定义特性**: 当前配置未指定 `crate_features`，使用默认特性集
3. **无额外数据文件**: 未配置 `compile_data` 或 `build_script_data`

### 改进建议

1. **添加注释说明**: 可以添加注释说明该 crate 的用途和关键配置
   ```starlark
   # Shared in-process app-server client for CLI surfaces (tui, exec)
   codex_rust_crate(
       name = "app-server-client",
       crate_name = "codex_app_server_client",
   )
   ```

2. **考虑显式 srcs**: 如果源文件结构复杂，可以考虑显式指定 `crate_srcs` 而非依赖 glob

3. **文档生成**: 可以配置 `rust_doc` 目标自动生成文档

4. **特性管理**: 如果未来需要条件编译特性，应添加 `crate_features` 参数
