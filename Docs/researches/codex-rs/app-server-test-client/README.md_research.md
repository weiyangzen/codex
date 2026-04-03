# README.md 研究文档

## 场景与职责

`codex-rs/app-server-test-client/README.md` 是 `codex-app-server-test-client` crate 的使用文档，面向开发者和测试人员。该文档提供了快速入门指南、常用命令示例以及特定测试场景的操作说明。

该测试客户端是一个命令行工具，用于：
1. 启动和管理 Codex app-server 进程
2. 通过 WebSocket 或 stdio 与 app-server 交互
3. 执行端到端测试（如 thread 重连、elicitation 暂停等）
4. 监控和调试原始 JSON-RPC 消息流

## 功能点目的

### 1. 快速入门（Quickstart）

文档提供了三步快速开始流程：
- 构建 codex CLI 二进制文件
- 启动 WebSocket app-server
- 调用 `model-list` 命令验证连接

### 2. 实时监控（Watching Raw Inbound Traffic）

`watch` 命令用于调试，可打印所有入站的 JSON-RPC 消息，直到用户按 Ctrl+C 停止。

### 3. Thread 重连测试（Testing Thread Rejoin Behavior）

这是该工具的核心测试功能之一，用于验证：
- Thread 的持久化和恢复
- 多客户端同时连接同一 thread 的行为
- 流式响应的中断和恢复

## 具体技术实现

### 快速入门命令分析

```bash
# 1) 构建 debug codex 二进制
cargo build -p codex-cli --bin codex
```

构建产物位于 `./target/debug/codex`，这是后续 `--codex-bin` 参数的默认值。

```bash
# 2) 启动 WebSocket app-server
cargo run -p codex-app-server-test-client -- \
  --codex-bin ./target/debug/codex \
  serve --listen ws://127.0.0.1:4222 --kill
```

**技术细节**:
- `--codex-bin`: 指定 codex 二进制路径，工具会启动 `codex app-server` 子进程
- `serve`: 子命令，在后台启动 app-server
- `--listen ws://127.0.0.1:4222`: WebSocket 监听地址
- `--kill`: 强制终止占用同一端口的现有进程

```bash
# 3) 调用 model-list
cargo run -p codex-app-server-test-client -- model-list
```

默认连接到 `ws://127.0.0.1:4222`，可通过 `--url` 参数指定其他地址。

### Thread 重连测试流程

文档描述的测试流程涉及以下内部机制：

1. **创建 Thread**: `send-message-v2` 调用 `thread/start` 和 `turn/start` RPC 方法
2. **列出 Threads**: `thread-list` 调用 `thread/list` RPC 方法
3. **Resume Thread**: `thread-resume` 调用 `thread/resume` RPC 方法，建立对现有 thread 的监听

**并发测试设计**:
- Terminal A: 发送消息并等待流式响应
- Terminal B: 同时执行 `thread-resume`，验证服务器能正确处理并发连接

## 关键代码路径与文件引用

### 命令实现位置

| 文档命令 | 源码位置 | 实现函数 |
|---------|---------|---------|
| `serve` | `src/lib.rs:285-288` | `serve()` 函数，第 508-553 行 |
| `model-list` | `src/lib.rs:385-389` | `model_list()` 函数，第 1080-1091 行 |
| `send-message-v2` | `src/lib.rs:295-308` | `send_message_v2_endpoint()` 函数，第 666-690 行 |
| `thread-list` | `src/lib.rs:390-394` | `thread_list()` 函数，第 1093-1113 行 |
| `thread-resume` | `src/lib.rs:323-327` | `thread_resume_follow()` 函数，第 834-853 行 |
| `watch` | `src/lib.rs:328-332` | `watch()` 函数，第 855-864 行 |

### 核心数据结构

```rust
// src/lib.rs:425-428
enum Endpoint {
    SpawnCodex(PathBuf),    // 启动本地 codex 进程
    ConnectWs(String),      // 连接现有 WebSocket 服务器
}

// src/lib.rs:1367-1382
struct CodexClient {
    transport: ClientTransport,
    pending_notifications: VecDeque<JSONRPCNotification>,
    command_approval_behavior: CommandApprovalBehavior,
    // ... 状态跟踪字段
}
```

### 日志输出位置

文档提到 app-server 日志写入 `/tmp/codex-app-server-test-client/app-server.log`，对应源码：

```rust
// src/lib.rs:509-512
let runtime_dir = PathBuf::from("/tmp/codex-app-server-test-client");
fs::create_dir_all(&runtime_dir)?;
let log_path = runtime_dir.join("app-server.log");
```

## 依赖与外部交互

### 与 app-server 的协议交互

测试客户端通过 JSON-RPC 2.0 协议与 app-server 通信：

```
┌─────────────────────┐      WebSocket/stdio      ┌─────────────────┐
│ app-server-test-client │  <------------------->  │  codex app-server │
│    (测试客户端)        │    JSON-RPC 2.0          │   (被测服务)      │
└─────────────────────┘                          └─────────────────┘
```

### 关键 RPC 方法

| 方法 | 方向 | 用途 |
|------|------|------|
| `initialize` | Client → Server | 初始化连接，交换能力信息 |
| `thread/start` | Client → Server | 创建新 thread |
| `thread/resume` | Client → Server | 恢复现有 thread |
| `turn/start` | Client → Server | 开始新 turn（用户输入） |
| `thread/started` | Server → Client | Thread 创建通知 |
| `turn/started` | Server → Client | Turn 开始通知 |
| `turn/completed` | Server → Client | Turn 完成通知 |
| `item/started` | Server → Client | Item（命令执行等）开始 |
| `item/completed` | Server → Client | Item 完成 |

### 协议版本

主要使用 v2 API，定义在 `codex-app-server-protocol` crate 中：
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`

## 风险、边界与改进建议

### 风险

1. **端口冲突**: `--kill` 标志使用 `lsof` 和 `kill` 命令终止进程，在某些系统上可能需要 root 权限
2. **并发安全**: Thread 重连测试依赖特定的时序，在慢速系统上可能不稳定
3. **日志累积**: `/tmp/codex-app-server-test-client/app-server.log` 没有自动轮转，长期运行可能占用大量磁盘空间

### 边界

1. **平台限制**: 
   - `serve` 命令使用 `nohup` 和 shell 命令，在 Windows 上不可用
   - `live-elicitation-timeout-pause` 明确检查 `cfg!(windows)` 并返回错误

2. **网络依赖**:
   - 默认使用 `ws://127.0.0.1:4222`，仅支持本地连接
   - WebSocket 连接有 10 秒超时（`src/lib.rs:1465`）

3. **实验性 API**:
   - `send-message-v2` 默认启用 `experimental_api: true`
   - 部分功能依赖实验性 API，可能在未来版本中变化

### 改进建议

1. **文档增强**:
   - 添加 `--url` 参数的使用示例，说明如何连接远程服务器
   - 补充 `--dynamic-tools` 参数的使用说明
   - 添加退出码说明，便于脚本化测试

2. **功能改进**:
   - 为日志添加自动轮转或大小限制
   - 支持配置文件，避免重复输入常用参数
   - 添加 `--timeout` 参数控制连接和请求超时

3. **跨平台支持**:
   - 为 Windows 提供 `serve` 命令的替代实现
   - 使用跨平台的进程管理库替代 `nohup`

4. **测试覆盖**:
   - 文档中提到的测试场景可以自动化为集成测试
   - 添加性能基准测试命令

---

**相关文件引用**:
- 主实现: `/home/sansha/Github/codex/codex-rs/app-server-test-client/src/lib.rs`
- 入口点: `/home/sansha/Github/codex/codex-rs/app-server-test-client/src/main.rs`
- 辅助脚本: `/home/sansha/Github/codex/codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh`
- 协议定义: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
