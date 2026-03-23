# Linux Sandbox 测试套件模块聚合文件研究文档

## 场景与职责

`mod.rs` 是 Codex Linux Sandbox 集成测试套件的模块聚合入口文件，职责非常简单但重要：

1. **模块组织**：将分散的测试文件组织为统一的测试套件
2. **条件编译**：确保测试仅在 Linux 平台上编译和运行
3. **命名空间管理**：为 `tests/suite/` 目录下的所有测试提供模块层次结构

该文件本身不包含测试逻辑，但作为测试架构的基础设施，它定义了测试代码的组织方式。

## 功能点目的

### 模块聚合

```rust
// Aggregates all former standalone integration tests as modules.
mod landlock;
mod managed_proxy;
```

将以下测试文件聚合为子模块：
- `landlock.rs`：文件系统和网络安全测试（766 行）
- `managed_proxy.rs`：托管代理模式测试（312 行）

### 平台隔离

该模块通过目录结构本身实现平台隔离：
- 路径 `codex-rs/linux-sandbox/tests/suite/` 暗示这是 Linux 专用测试
- 子模块文件（`landlock.rs`、`managed_proxy.rs`）使用 `#![cfg(target_os = "linux")]` 确保只在 Linux 编译

## 具体技术实现

### 模块声明

```rust
// 行1: 模块说明注释
// Aggregates all former standalone integration tests as modules.

// 行2-3: 子模块声明
mod landlock;
mod managed_proxy;
```

### 模块解析规则

Rust 编译器根据以下规则解析模块：

```
codex-rs/linux-sandbox/tests/suite/
├── mod.rs          # 当前文件，模块入口
├── landlock.rs     # 对应 mod landlock;
└── managed_proxy.rs # 对应 mod managed_proxy;
```

### 测试执行流程

```
cargo test -p codex-linux-sandbox
    ↓
tests/all.rs (测试入口)
    ↓
mod suite; (声明测试套件模块)
    ↓
tests/suite/mod.rs (本文件)
    ↓
├── mod landlock; → tests/suite/landlock.rs
└── mod managed_proxy; → tests/suite/managed_proxy.rs
```

## 关键代码路径与文件引用

### 测试架构层次

```
codex-rs/linux-sandbox/tests/
├── all.rs                    # 测试入口，声明 suite 模块
└── suite/
    ├── mod.rs               # 本文件：模块聚合
    ├── landlock.rs          # 文件系统/网络安全测试
    └── managed_proxy.rs     # 托管代理模式测试
```

### 相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/linux-sandbox/tests/all.rs` | 测试套件入口 |
| `codex-rs/linux-sandbox/tests/suite/mod.rs` | 本文件：模块聚合 |
| `codex-rs/linux-sandbox/tests/suite/landlock.rs` | Landlock/Bubblewrap 测试 |
| `codex-rs/linux-sandbox/tests/suite/managed_proxy.rs` | 托管代理测试 |

## 依赖与外部交互

### 编译时依赖

该文件本身没有直接的 `use` 语句或外部依赖，但子模块依赖：

```rust
// landlock.rs 依赖
codex_core::config::types::ShellEnvironmentPolicy
codex_core::exec::ExecParams
codex_core::exec::process_exec_tool_call
codex_protocol::protocol::SandboxPolicy
tokio::test

// managed_proxy.rs 依赖
codex_core::exec_env::create_env
codex_protocol::protocol::SandboxPolicy
tokio::process::Command
tokio::test
```

### 测试框架集成

- **测试运行器**：通过 `cargo test` 调用
- **异步运行时**：`tokio::test` 属性宏
- **断言库**：`pretty_assertions`

## 风险、边界与改进建议

### 当前限制

1. **平台单一**：当前仅支持 Linux，未来可能需要支持其他平台
2. **模块扁平**：只有两个子模块，如果测试增长可能需要更复杂的组织结构
3. **无公共代码**：没有提取共享的测试辅助函数到 `mod.rs`

### 改进建议

1. **添加模块文档**：
   ```rust
   //! Linux Sandbox 集成测试套件
   //!
   //! 本模块包含 codex-linux-sandbox 的集成测试，验证：
   //! - 文件系统隔离（Landlock/Bubblewrap）
   //! - 网络访问控制（seccomp）
   //! - 托管代理模式
   
   mod landlock;
   mod managed_proxy;
   ```

2. **提取共享代码**：
   如果子模块间有共享的辅助函数，可以在 `mod.rs` 中定义：
   ```rust
   // 共享的测试辅助函数
   pub(crate) fn create_test_env() -> HashMap<String, String> {
       // ...
   }
   
   pub(crate) const TEST_TIMEOUT_MS: u64 = 5_000;
   ```

3. **添加条件编译**：
   虽然子模块已有 `cfg(target_os = "linux")`，但模块声明也可以添加：
   ```rust
   #[cfg(target_os = "linux")]
   mod landlock;
   
   #[cfg(target_os = "linux")]
   mod managed_proxy;
   ```

4. **未来扩展结构**：
   如果测试增长，可以考虑：
   ```rust
   // 按功能分组
   pub mod fs;           // 文件系统测试
   pub mod network;      // 网络测试
   pub mod proxy;        // 代理测试
   pub mod security;     // 安全边界测试
   ```

### 维护注意事项

1. **模块命名**：保持与文件名一致（`landlock` 对应 `landlock.rs`）
2. **添加新测试**：新增测试文件时需要在 `mod.rs` 中声明
3. **删除测试**：删除子模块文件时记得更新 `mod.rs`
4. **文档同步**：如果修改模块结构，更新 `AGENTS.md` 中的测试说明
