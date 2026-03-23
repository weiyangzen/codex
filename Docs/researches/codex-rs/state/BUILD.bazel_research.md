# codex-rs/state/BUILD.bazel 研究文档

## 场景与职责

`codex-rs/state/BUILD.bazel` 是 Codex 项目中 `state` crate 的 Bazel 构建配置文件。该 crate 负责管理 Codex 的本地 SQLite 状态存储，包括线程元数据、日志记录、Agent 作业调度和记忆系统。BUILD.bazel 文件定义了如何将这个 Rust crate 集成到项目的 Bazel 构建系统中。

## 功能点目的

### 1. 构建目标声明
- **库目标**: 构建 `codex-state` crate 为 Rust 库
- **二进制目标**: 包含 `logs_client` 二进制工具用于日志查看
- **测试目标**: 自动生成单元测试和集成测试目标

### 2. 编译数据包含
通过 `compile_data` 参数包含 SQL 迁移文件：
- `logs_migrations/**`: 日志数据库的迁移脚本
- `migrations/**`: 状态数据库的迁移脚本

这些迁移文件在编译时被嵌入，供 `sqlx::migrate!` 宏在运行时执行数据库模式迁移。

## 具体技术实现

### 构建规则定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "state",
    crate_name = "codex_state",
    compile_data = glob(["logs_migrations/**", "migrations/**"]),
)
```

### 关键参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"state"` | Bazel 目标名称，用于构建命令如 `bazel build //codex-rs/state` |
| `crate_name` | `"codex_state"` | Rust crate 名称，遵循 `codex-*` 前缀命名约定 |
| `compile_data` | `glob([...])` | 编译时数据文件，包含 SQL 迁移脚本 |

### 底层构建逻辑

`codex_rust_crate` 宏（定义于 `//:defs.bzl`）为 `codex-state` 自动完成以下工作：

1. **库编译**: 使用 `rust_library` 规则编译 `src/lib.rs` 及所有子模块
2. **源码收集**: 通过 `glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
3. **依赖解析**: 从 `@crates` 外部仓库解析 `Cargo.toml` 中声明的依赖
4. **单元测试**: 创建 `state-unit-tests` 测试目标，运行 `src/` 中的 `#[cfg(test)]` 模块
5. **集成测试**: 自动发现并构建 `tests/*.rs` 中的集成测试
6. **二进制文件**: 自动检测并构建 `src/bin/*.rs` 中的二进制文件（如 `logs_client`）

### 迁移文件处理

```rust
// src/migrations.rs
pub(crate) static STATE_MIGRATOR: Migrator = sqlx::migrate!("./migrations");
pub(crate) static LOGS_MIGRATOR: Migrator = sqlx::migrate!("./logs_migrations");
```

`compile_data` 确保迁移文件在编译时可用，支持 `sqlx::migrate!` 宏的编译时路径解析。

## 关键代码路径与文件引用

### 构建相关
- **构建定义**: `//:defs.bzl`（项目根目录的构建宏，第 89-265 行定义 `codex_rust_crate`）
- **Cargo 配置**: `codex-rs/state/Cargo.toml`
- **库源码**: `codex-rs/state/src/lib.rs`

### 迁移文件
- **状态数据库迁移**: `codex-rs/state/migrations/*.sql`（20 个迁移文件）
- **日志数据库迁移**: `codex-rs/state/logs_migrations/*.sql`（2 个迁移文件）

### 二进制文件
- **日志客户端**: `codex-rs/state/src/bin/logs_client.rs`

## 依赖与外部交互

### Bazel 外部依赖
- `@crates`: 从 `Cargo.lock` 生成的 Rust 依赖集合
- `//:defs.bzl`: 项目自定义的 Rust crate 构建宏

### Cargo 依赖（通过 Cargo.toml）
- `sqlx`: 异步 SQL 工具包，用于 SQLite 操作
- `tokio`: 异步运行时
- `serde`/`serde_json`: 序列化/反序列化
- `chrono`: 日期时间处理
- `uuid`: UUID 生成
- `tracing`/`tracing-subscriber`: 日志和追踪
- `codex-protocol`: 内部协议 crate

### 数据库文件
- 状态数据库: `~/.codex/state_5.sqlite`
- 日志数据库: `~/.codex/logs_1.sqlite`

## 风险、边界与改进建议

### 当前风险

1. **迁移文件路径硬编码**: `sqlx::migrate!` 使用相对路径 `"./migrations"`，依赖于编译时的工作目录
2. **版本管理**: 数据库版本号（`STATE_DB_VERSION = 5`, `LOGS_DB_VERSION = 1`）需要在代码和迁移文件中同步维护

### 边界

1. **单数据库配置**: 当前 BUILD.bazel 仅支持基本的 `name` 和 `crate_name` 参数，未使用高级特性如 `crate_features`、`deps_extra` 等
2. **无条件编译**: 未使用 `select()` 进行平台特定的配置

### 改进建议

1. **添加注释**: 可以添加注释说明 `compile_data` 的用途和迁移文件的重要性
2. **版本检查**: 考虑添加构建时检查，确保代码中的版本号与迁移文件数量一致
3. **迁移验证**: 在 CI 中添加迁移文件语法验证步骤
4. **文档增强**: 添加关于数据库架构演进的文档说明

### 示例改进

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "state",
    crate_name = "codex_state",
    # SQL migrations embedded at compile time for sqlx::migrate!
    compile_data = glob([
        "logs_migrations/**",  # Logs DB schema (v1)
        "migrations/**",       # State DB schema (v5)
    ]),
)
```
