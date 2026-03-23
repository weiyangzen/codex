# all.rs 研究文档

## 场景与职责

`all.rs` 是 Codex TUI 的集成测试入口文件，采用 Rust 的集成测试架构模式。它作为单一测试二进制文件的聚合器，将分散在 `tests/suite/` 目录下的各个测试模块统一编译到一个可执行文件中运行。

该文件的设计遵循了 Rust 测试最佳实践：
- 使用条件编译 (`#[cfg(feature = "vt100-tests")]`) 控制特定测试模块的启用
- 通过 `mod suite` 聚合所有子模块测试
- 保留 `codex_cli` 的 dev-dependency 引用以满足 cargo-shear 工具的要求

## 功能点目的

### 1. 测试模块聚合
```rust
mod suite;
```
将 `tests/suite/mod.rs` 中定义的所有测试模块统一引入，形成完整的测试套件。

### 2. 条件编译控制
```rust
#[cfg(feature = "vt100-tests")]
mod test_backend;
```
`test_backend` 模块（VT100 终端模拟后端）仅在启用 `vt100-tests` feature 时编译。这种设计允许：
- 快速测试：默认情况下跳过需要 VT100 模拟的测试
- 完整测试：显式启用 feature 时运行所有测试

### 3. Dev Dependency 保留
```rust
#[allow(unused_imports)]
use codex_cli as _;
```
虽然代码中未直接使用 `codex_cli`，但测试需要 spawn codex 二进制文件，因此需要保留该 dev-dependency。`cargo-shear` 工具会检查未使用的依赖，此处的显式引用告知工具该依赖是必需的。

## 具体技术实现

### 模块结构
```
codex-rs/tui/tests/
├── all.rs                 # 测试入口（本文件）
├── test_backend.rs        # VT100Backend 的测试模块重导出
└── suite/
    ├── mod.rs             # 测试套件聚合器
    ├── model_availability_nux.rs
    ├── no_panic_on_startup.rs
    ├── status_indicator.rs
    ├── vt100_history.rs
    └── vt100_live_commit.rs
```

### 条件编译机制
- `vt100-tests` feature 在 `Cargo.toml` 中定义：
  ```toml
  [features]
  vt100-tests = []
  ```
- 该 feature 控制是否编译依赖 VT100 终端模拟器的测试代码

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `tests/suite/mod.rs` | 测试套件模块聚合器，声明所有子测试模块 |
| `tests/test_backend.rs` | VT100Backend 的重导出模块 |
| `src/test_backend.rs` | VT100Backend 的实际实现 |
| `Cargo.toml` | Feature 定义和 dev-dependencies 声明 |

### 调用关系
```
all.rs
├── (conditionally) test_backend.rs ──► src/test_backend.rs (VT100Backend)
└── suite/mod.rs
    ├── model_availability_nux.rs
    ├── no_panic_on_startup.rs
    ├── status_indicator.rs
    ├── vt100_history.rs
    └── vt100_live_commit.rs
```

## 依赖与外部交互

### Dev Dependencies
- `codex_cli`: 测试需要 spawn codex 二进制文件
- `codex_utils_cargo_bin`: 用于在测试中定位二进制文件路径
- `codex_utils_pty`: PTY 伪终端工具，用于集成测试
- `vt100`: VT100 终端模拟器库

### Feature 依赖
- `vt100-tests`: 启用 VT100 相关的测试模块

## 风险、边界与改进建议

### 风险点
1. **Feature 门控遗漏**: 如果忘记启用 `vt100-tests`，相关测试将被静默跳过，可能导致回归问题未被发现
2. **Dev-dependency 误删**: `codex_cli` 的引用看似未使用，如果被移除会导致测试失败

### 边界情况
- Windows 平台：部分测试（如 PTY 测试）在 Windows 上不可用，测试代码中需要显式检查 `cfg!(windows)`

### 改进建议
1. **CI 配置**: 确保 CI 中同时运行默认测试和 `--features vt100-tests` 的完整测试
2. **文档**: 在 README 中说明如何运行完整测试套件
3. **测试发现**: 考虑使用 `test_each` 或类似工具改进测试组织
