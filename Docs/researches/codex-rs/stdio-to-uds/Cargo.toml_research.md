# Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 `codex-stdio-to-uds` crate 的包清单文件，定义了 crate 的元数据、构建配置、依赖关系和目标产物。该 crate 是一个桥接工具，用于将标准输入输出（stdio）与 Unix Domain Socket（UDS）进行双向转发。

## 功能点目的

1. **定义包元数据**：名称、版本、Rust 版本、许可证
2. **声明双目标产物**：
   - 库（`lib.rs`）：提供可复用的 `run()` 函数
   - 二进制（`main.rs`）：提供可执行的命令行工具
3. **管理依赖**：核心依赖 `anyhow`，Windows 平台特定依赖 `uds_windows`
4. **统一工作区配置**：版本、版本号、许可证继承自工作区根配置

## 具体技术实现

### 包配置

```toml
[package]
name = "codex-stdio-to-uds"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承工作区 Rust 版本（2021）
license.workspace = true      # 继承工作区许可证
```

### 双目标定义

```toml
# 二进制目标 - 命令行入口
[[bin]]
name = "codex-stdio-to-uds"
path = "src/main.rs"

# 库目标 - 可编程 API
[lib]
name = "codex_stdio_to_uds"
path = "src/lib.rs"
```

这种设计允许：
- **命令行使用**：`codex-stdio-to-uds /tmp/mcp.sock`
- **库集成**：其他 Rust 代码可通过 `codex_stdio_to_uds::run()` 调用

### 依赖管理

```toml
[dependencies]
anyhow = { workspace = true }  # 错误处理，工作区统一版本

# Windows 平台特定依赖
[target.'cfg(target_os = "windows")'.dependencies]
uds_windows = { workspace = true }  # Windows UDS 支持
```

### 开发依赖

```toml
[dev-dependencies]
codex-utils-cargo-bin = { workspace = true }  # 测试工具：定位二进制文件
pretty_assertions = { workspace = true }      # 测试断言美化
tempfile = { workspace = true }               # 临时文件/目录
```

### Lint 配置

```toml
[lints]
workspace = true  # 继承工作区统一的 clippy 规则
```

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `src/lib.rs` | 库实现，包含 `run()` 函数 |
| `src/main.rs` | 二进制入口，解析命令行参数 |
| `tests/stdio_to_uds.rs` | 集成测试 |

### 工作区引用

- `../Cargo.toml`（工作区根）- 定义共享的依赖版本和元数据
- `../.cargo/config.toml`（如存在）- 可能包含构建配置

## 依赖与外部交互

### 运行时依赖

| Crate | 用途 | 平台 |
|-------|------|------|
| `anyhow` | 错误处理和传播 | 全平台 |
| `uds_windows` | Windows 平台的 `UnixStream`/`UnixListener` | Windows only |

### 开发依赖

| Crate | 用途 |
|-------|------|
| `codex-utils-cargo-bin` | 在测试中定位编译后的二进制文件 |
| `pretty_assertions` | 提供带颜色差异的断言输出 |
| `tempfile` | 创建临时目录存放测试用的 Unix socket |

### 条件编译

Rust 标准库在 Windows 上不支持 UDS（参见 [rust#56533](https://github.com/rust-lang/rust/issues/56533)），因此使用 `uds_windows` crate 作为 polyfill：

```rust
#[cfg(unix)]
use std::os::unix::net::UnixStream;

#[cfg(windows)]
use uds_windows::UnixStream;
```

## 风险、边界与改进建议

### 风险

1. **Windows UDS 兼容性**：依赖第三方 crate `uds_windows` 填补标准库空白，该 crate 的维护状态和行为一致性需要关注
2. **平台差异**：虽然代码通过条件编译统一了接口，但底层实现（标准库 vs `uds_windows`）可能存在微妙差异

### 边界

- **单一职责**：该 crate 功能单一，仅做 stdio ↔ UDS 的双向转发
- **无异步**：使用同步 I/O 和线程，适用于简单场景但不适合高并发
- **无配置**：除 socket 路径外无其他配置选项

### 改进建议

1. **版本锁定**：考虑为 `uds_windows` 指定更精确的版本约束，避免意外破坏
2. **特性标志**：如果未来需要支持其他传输方式，可引入 Cargo features 进行条件编译
3. **文档依赖**：在 README 中明确说明 Windows 依赖 `uds_windows` 的具体版本要求
4. **MSRV 声明**：虽然继承了工作区 edition，但可考虑显式声明最低支持的 Rust 版本（MSRV）
