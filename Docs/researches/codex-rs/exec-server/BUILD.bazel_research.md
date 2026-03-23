# codex-rs/exec-server/BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建定义文件，负责定义 `codex-exec-server` crate 的构建配置。它是连接 Cargo 生态与 Bazel 构建系统的桥梁，使用项目根目录定义的 `codex_rust_crate` 宏来标准化 Rust crate 的构建流程。

## 功能点目的

1. **标准化构建定义**：通过 `codex_rust_crate` 宏复用构建逻辑，避免重复定义
2. **指定 crate 元数据**：
   - `name`: Bazel 目标名称 `"exec-server"`
   - `crate_name`: Cargo crate 名称 `"codex_exec_server"`
3. **测试沙箱配置**：设置 `test_tags = ["no-sandbox"]` 禁用测试沙箱，允许测试执行外部进程（如启动真实的 exec-server 二进制文件）

## 具体技术实现

### 关键配置解析

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "exec-server",
    crate_name = "codex_exec_server",
    test_tags = ["no-sandbox"],
)
```

### codex_rust_crate 宏行为

根据 `defs.bzl` 的定义，该宏会自动：

1. **检测源码文件**：通过 `native.glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
2. **创建库目标**：构建 `rust_library`（因为 `src/` 目录存在）
3. **创建二进制目标**：根据 `Cargo.toml` 中的 `[[bin]]` 定义创建 `rust_binary`
4. **创建测试目标**：
   - 单元测试：`exec-server-unit-tests`
   - 集成测试：自动发现 `tests/*.rs` 文件并创建对应测试目标
5. **处理构建脚本**：如果存在 `build.rs`，自动配置 `cargo_build_script`

### 测试沙箱禁用原因

`test_tags = ["no-sandbox"]` 是必需的，因为：
- 集成测试需要启动真实的 `codex-exec-server` 进程
- 测试使用 `tokio::process::Command` 派生子进程
- 测试需要建立 WebSocket 连接到本地端口
- 沙箱会限制这些网络/进程操作

## 关键代码路径与文件引用

### 依赖文件
- `//:defs.bzl` - 定义 `codex_rust_crate` 宏
- `@crates//:data.bzl` - 提供 `DEP_DATA` 依赖数据
- `@crates//:defs.bzl` - 提供 `all_crate_deps` 函数

### 生成的目标
| 目标名称 | 类型 | 说明 |
|---------|------|------|
| `exec-server` | rust_library | 主库目标 |
| `codex-exec-server` | rust_binary | CLI 二进制文件 |
| `exec-server-unit-tests` | test | 单元测试 |
| `exec-server-initialize-test` | test | initialize.rs 集成测试 |
| `exec-server-process-test` | test | process.rs 集成测试 |
| `exec-server-websocket-test` | test | websocket.rs 集成测试 |

### 源码文件发现
```
src/
├── bin/codex-exec-server.rs    # 二进制入口
├── lib.rs                      # 库入口
├── client.rs                   # 客户端实现
├── client_api.rs               # 客户端 API
├── client/local_backend.rs     # 本地后端
├── connection.rs               # JSON-RPC 连接
├── protocol.rs                 # 协议定义
├── rpc.rs                      # RPC 客户端
└── server/
    ├── mod.rs                  # 服务器模块
    ├── handler.rs              # 请求处理器
    ├── jsonrpc.rs              # JSON-RPC 工具
    ├── processor.rs            # 连接处理器
    ├── transport.rs            # WebSocket 传输
    └── transport_tests.rs      # 传输层测试
```

## 依赖与外部交互

### Bazel 外部依赖
- `@rules_rust//rust:defs.bzl` - Rust 规则
- `@rules_platform//platform_data:defs.bzl` - 平台数据规则
- `@crates` - Cargo 依赖解析

### Cargo 依赖（通过 `@crates`）
- `clap` - CLI 参数解析
- `codex-app-server-protocol` - 共享协议
- `futures` - 异步流处理
- `serde`/`serde_json` - 序列化
- `thiserror` - 错误处理
- `tokio` - 异步运行时
- `tokio-tungstenite` - WebSocket 实现
- `tracing` - 日志追踪

## 风险、边界与改进建议

### 风险

1. **沙箱禁用风险**：`no-sandbox` 标签意味着测试在 Bazel 沙箱外运行，可能导致：
   - 测试间资源冲突（端口占用）
   - 非确定性测试结果
   - 安全风险（测试可访问整个系统）

2. **端口冲突**：集成测试使用 `ws://127.0.0.1:0`（随机端口），但理论上仍可能冲突

### 边界

1. **平台限制**：集成测试使用 `#![cfg(unix)]` 限制，仅支持 Unix 系统
2. **Cargo/Bazel 双构建**：需要保持 `Cargo.toml` 和 `BUILD.bazel` 同步

### 改进建议

1. **考虑使用 Bazel 测试固定端口**：当前使用 `:0` 随机端口，可考虑使用 Bazel 的端口分配机制

2. **细化沙箱标签**：可以细化 `no-sandbox` 为更具体的标签：
   ```bazel
   test_tags = [
       "no-sandbox",
       "requires-network",
       "requires-process",
   ]
   ```

3. **添加构建验证**：考虑添加 CI 检查确保 BUILD.bazel 与 Cargo.toml 一致

4. **文档化宏行为**：在文件中添加注释说明 `codex_rust_crate` 宏的具体行为，便于新开发者理解
