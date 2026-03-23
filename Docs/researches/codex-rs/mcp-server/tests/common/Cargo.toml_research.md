# Cargo.toml 研究文档

## 场景与职责

该文件定义了 `mcp_test_support` crate 的元数据和依赖配置，是 Codex MCP 服务器集成测试的基础设施库。它提供了测试 MCP 服务器所需的共享工具和辅助函数，使测试代码能够与 MCP 服务器进程进行交互。

## 功能点目的

1. **定义测试支持库**: 创建一个独立的 crate，封装 MCP 测试所需的通用功能
2. **管理依赖关系**: 声明与 codex-core、codex-mcp-server、rmcp 等核心库的依赖
3. **支持跨平台测试**: 通过 workspace 继承确保版本一致性
4. **集成测试基础设施**: 为 `codex-rs/mcp-server/tests/suite/codex_tool.rs` 等测试提供支持

## 具体技术实现

### 包元数据

```toml
[package]
name = "mcp_test_support"
version.workspace = true      # 从工作区继承版本
edition.workspace = true      # 从工作区继承 Rust 版本
license.workspace = true      # 从工作区继承许可证
```

### 库配置

```toml
[lib]
path = "lib.rs"               # 显式指定库入口文件
```

### 依赖项分析

| 依赖 | 来源 | 用途 |
|------|------|------|
| `anyhow` | workspace | 错误处理 |
| `codex-core` | workspace | 核心 Codex 功能 |
| `codex-mcp-server` | workspace | MCP 服务器类型定义 |
| `codex-utils-cargo-bin` | workspace | 二进制文件路径解析 |
| `rmcp` | workspace | MCP 协议实现 |
| `os_info` | workspace | 操作系统信息获取 |
| `pretty_assertions` | workspace | 测试断言美化 |
| `serde` | workspace | 序列化/反序列化 |
| `serde_json` | workspace | JSON 处理 |
| `tokio` | workspace | 异步运行时 |
| `wiremock` | workspace | HTTP 模拟服务器 |
| `core_test_support` | path | 核心测试支持库 |
| `shlex` | workspace | Shell 命令解析 |

### Tokio 特性配置

```toml
tokio = { workspace = true, features = [
    "io-std",           # 标准输入输出异步操作
    "macros",           # 异步宏支持
    "process",          # 子进程管理
    "rt-multi-thread",  # 多线程运行时
] }
```

这些特性对于测试 MCP 服务器至关重要：
- `io-std`: 支持异步读写 stdin/stdout
- `process`: 支持启动和管理 MCP 服务器子进程
- `rt-multi-thread`: 支持多线程测试执行

## 关键代码路径与文件引用

### 目录结构

```
codex-rs/mcp-server/tests/common/
├── Cargo.toml           # 本文件
├── BUILD.bazel          # Bazel 构建配置
├── lib.rs               # 库入口，重新导出模块
├── mcp_process.rs       # MCP 进程管理实现
├── mock_model_server.rs # 模拟模型服务器
└── responses.rs         # SSE 响应构建器
```

### 依赖关系图

```
mcp_test_support (本 crate)
├── 依赖:
│   ├── codex-core
│   ├── codex-mcp-server
│   ├── rmcp (MCP 协议)
│   ├── core_test_support (../../../core/tests/common)
│   └── wiremock (HTTP 模拟)
└── 被依赖:
    └── codex-rs/mcp-server/tests/suite/codex_tool.rs
```

### 核心测试支持库路径

```toml
core_test_support = { path = "../../../core/tests/common" }
```

这个相对路径指向 `codex-rs/core/tests/common`，共享核心的测试工具函数。

## 依赖与外部交互

### 上游依赖

1. **Workspace 配置**:
   - 版本、edition、许可证从 workspace 继承
   - 依赖版本在 workspace 级别统一管理

2. **核心库**:
   - `codex-core`: 提供核心 Codex 功能
   - `codex-mcp-server`: 提供 MCP 服务器类型和配置
   - `rmcp`: Model Context Protocol 的 Rust 实现

3. **测试工具**:
   - `core_test_support`: 核心测试支持函数
   - `wiremock`: HTTP 服务器模拟
   - `pretty_assertions`: 更好的测试失败输出

### 下游消费者

1. **集成测试**:
   ```rust
   // tests/suite/codex_tool.rs
   use mcp_test_support::McpProcess;
   use mcp_test_support::create_mock_responses_server;
   ```

2. **Bazel 构建**:
   - `BUILD.bazel` 使用相同的 `crate_name = "mcp_test_support"`

## 风险、边界与改进建议

### 风险

1. **路径硬编码风险**: `core_test_support` 使用相对路径 `../../../core/tests/common`，如果目录结构变化会失效
2. **循环依赖风险**: 依赖 `codex-mcp-server` 可能导致循环依赖（虽然当前没有）
3. **workspace 版本漂移**: 如果 workspace 中的依赖版本更新，可能影响测试行为

### 边界情况

1. **平台差异**: 
   - `shlex` 主要用于类 Unix 系统，Windows 测试可能需要特殊处理
   - `os_info` 用于获取系统信息，但在某些容器环境可能受限

2. **并发测试**:
   - `tokio::process` 在并发测试中可能遇到端口冲突
   - `wiremock` 使用随机端口，但大量并发仍可能冲突

### 改进建议

1. **路径稳定性**: 考虑使用 workspace 级别的路径别名，而非相对路径：
   ```toml
   core_test_support = { path = "@codex_core//tests/common" }  # 如果 Bazel 支持
   ```

2. **特性隔离**: 考虑为不同测试场景添加可选特性：
   ```toml
   [features]
   default = []
   network-tests = []  # 需要网络的测试
   sandbox-tests = []  # 沙盒测试
   ```

3. **文档依赖**: 添加开发依赖说明：
   ```toml
   [dev-dependencies]
   # 如果测试需要额外的 mock 数据
   ```

4. **版本约束**: 考虑为关键依赖（如 `rmcp`）添加最小版本约束，以确保协议兼容性
