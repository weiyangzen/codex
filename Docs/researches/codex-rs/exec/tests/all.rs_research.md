# all.rs 研究文档

## 场景与职责

`all.rs` 是 `codex-exec` crate 的集成测试入口文件，采用 Rust 的「单二进制集成测试」模式（single integration test binary pattern）。该文件将所有集成测试模块聚合到一个统一的测试二进制文件中，避免为每个测试文件生成独立的二进制，从而显著减少编译时间和磁盘占用。

**核心职责：**
1. 作为 `cargo test` 在 `tests/` 目录下的唯一入口点
2. 聚合 `tests/suite/` 子目录中的所有测试模块
3. 显式引入独立的测试文件（如 `event_processor_with_json_output.rs`）

## 功能点目的

### 1. 模块聚合机制

```rust
// Single integration test binary that aggregates all test modules.
// The submodules live in `tests/suite/`.
mod suite;

mod event_processor_with_json_output;
```

- `mod suite;`：聚合 `tests/suite/mod.rs` 及其子模块（add_dir, apply_patch, auth_env 等）
- `mod event_processor_with_json_output;`：单独引入事件处理器测试（因其测试内容庞大，独立成文件）

### 2. 测试组织结构

| 模块路径 | 测试内容 |
|---------|---------|
| `suite::add_dir` | 额外可写目录功能测试 |
| `suite::apply_patch` | 补丁应用功能测试 |
| `suite::auth_env` | 认证环境变量测试 |
| `suite::ephemeral` | 临时会话模式测试 |
| `suite::mcp_required_exit` | MCP 服务器必需性测试 |
| `suite::originator` | 请求来源标识测试 |
| `suite::output_schema` | 输出模式验证测试 |
| `suite::resume` | 会话恢复功能测试 |
| `suite::sandbox` | 沙箱策略测试 |
| `suite::server_error_exit` | 服务器错误退出码测试 |
| `event_processor_with_json_output` | JSONL 事件处理器单元测试 |

## 具体技术实现

### 文件结构

```
codex-rs/exec/tests/
├── all.rs                          # 本文件：测试入口
├── event_processor_with_json_output.rs  # 独立的事件处理器测试
└── suite/
    ├── mod.rs                      # suite 模块聚合器
    ├── add_dir.rs
    ├── apply_patch.rs
    ├── auth_env.rs
    ├── ephemeral.rs
    ├── mcp_required_exit.rs
    ├── originator.rs
    ├── output_schema.rs
    ├── resume.rs
    ├── sandbox.rs
    └── server_error_exit.rs
```

### 编译配置

在 `Cargo.toml` 中，测试依赖包括：
- `assert_cmd`：CLI 测试断言
- `codex-utils-cargo-bin`：工作空间二进制文件定位
- `core_test_support`：核心测试支持库
- `pretty_assertions`：美观的断言输出
- `tempfile`：临时文件/目录管理
- `wiremock`：HTTP mock 服务器

## 关键代码路径与文件引用

### 被测试的主要代码

| 被测试模块 | 路径 |
|-----------|------|
| `EventProcessorWithJsonOutput` | `codex-rs/exec/src/event_processor_with_jsonl_output.rs` |
| CLI 参数解析 | `codex-rs/exec/src/cli.rs` |
| 主执行逻辑 | `codex-rs/exec/src/lib.rs` |
| 事件定义 | `codex-rs/exec/src/exec_events.rs` |

### 测试调用链

```
cargo test -p codex-exec
    └── 编译 tests/all.rs
        ├── 链接 suite/mod.rs
        │   ├── suite/add_dir.rs
        │   ├── suite/apply_patch.rs
        │   └── ...
        └── 链接 event_processor_with_json_output.rs
```

## 依赖与外部交互

### 运行时依赖

- `codex-exec` 二进制文件（通过 `codex_utils_cargo_bin::cargo_bin` 定位）
- 临时文件系统（通过 `tempfile` crate）
- Mock HTTP 服务器（通过 `wiremock`，用于模拟 API 响应）

### 测试环境要求

- 部分测试需要有效的 Git 仓库环境
- 部分测试涉及沙箱执行，需要 Linux 环境或特定沙箱配置
- MCP 相关测试需要模拟 MCP 服务器

## 风险、边界与改进建议

### 当前风险

1. **测试隔离性**：所有测试共享同一个二进制，全局状态可能影响测试隔离
2. **编译耦合**：修改任一测试模块会触发整个测试二进制重新编译
3. **环境依赖**：部分集成测试依赖外部环境（Git、沙箱、网络）

### 边界情况

1. `event_processor_with_json_output` 测试独立在 `suite/` 外，因其是单元测试而非集成测试
2. `suite/mod.rs` 中未包含 `event_processor_with_json_output`，避免重复引入

### 改进建议

1. **文档化**：建议在 `all.rs` 顶部添加更详细的注释，说明为何 `event_processor_with_json_output` 单独引入
2. **分类清晰**：考虑将 `event_processor_with_json_output` 移至 `suite/unit/` 子目录，明确区分单元测试和集成测试
3. **条件编译**：对于需要特定环境的测试（如沙箱测试），可使用 `#[cfg(target_os = "linux")]` 条件编译
