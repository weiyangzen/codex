# DIR codex-rs/docs 研究文档

## 概述

`codex-rs/docs` 目录是 Codex Rust 项目的技术文档中心，包含三个关键文档文件，分别涵盖构建系统（Bazel）、MCP 服务器接口和核心协议规范。这些文档为开发者提供了理解 Codex 架构、API 和使用方式的关键信息。

---

## 场景与职责

### 1. 文档定位

| 文档 | 职责 | 目标读者 |
|------|------|----------|
| `bazel.md` | Bazel 构建系统使用指南 | Rust 开发者、构建维护者 |
| `codex_mcp_interface.md` | MCP 服务器接口规范 | MCP 客户端开发者、IDE 集成者 |
| `protocol_v1.md` | 核心协议 v1 规范 | 核心开发者、UI 实现者 |

### 2. 使用场景

- **构建系统迁移**：当开发者需要从纯 Cargo 迁移到 Bazel 构建时参考 `bazel.md`
- **MCP 集成**：第三方工具（如 VSCode 扩展）需要集成 Codex MCP 服务器时参考 `codex_mcp_interface.md`
- **协议实现**：实现自定义 UI 或客户端时需要理解 SQ/EQ 模型和 Op/Event 协议时参考 `protocol_v1.md`

---

## 功能点目的

### 1. bazel.md - Bazel 构建系统文档

**目的**：说明如何在 codex-rs 中使用 Bazel 进行构建，同时保持与 Cargo 的兼容性。

**关键要点**：
- Bazel 提供 hermetic builds、工具链管理和跨平台构建产物
- Cargo 仍然是 crate 和 features 的源头（source of truth）
- 实验性设置（截至 2026-01-09 仍在稳定化中）

**核心命令**：
```bash
# 更新 Bzlmod lockfile
just bazel-lock-update

# 验证 lockfile 对齐
just bazel-lock-check
```

### 2. codex_mcp_interface.md - MCP 服务器接口文档

**目的**：定义 Codex 的实验性 MCP（Model Context Protocol）服务器接口规范。

**关键要点**：
- 状态：实验性，可能随时变更
- 服务器二进制：`codex mcp-server` 或 `codex-mcp-server`
- 传输：标准 MCP over stdio（JSON-RPC 2.0，行分隔）

**主要 API 分类**：

| 类别 | 方法示例 |
|------|----------|
| v2 线程 API | `thread/start`, `thread/resume`, `thread/fork`, `thread/read`, `thread/list` |
| v2 回合 API | `turn/start`, `turn/steer`, `turn/interrupt` |
| v2 账户 API | `account/read`, `account/login/start`, `account/logout` |
| v2 配置 API | `config/read`, `config/value/write`, `config/batchWrite` |
| v2 模型/应用 API | `model/list`, `app/list`, `collaborationMode/list` |
| v1 兼容 API | `getConversationSummary`, `getAuthStatus`, `gitDiffToRemote`, `fuzzyFileSearch/*` |
| 通知 | `thread/started`, `turn/completed`, `account/login/completed`, `codex/event/*` |
| 审批请求 | `applyPatchApproval`, `execCommandApproval` |

### 3. protocol_v1.md - 核心协议 v1 规范

**目的**：定义 Codex 核心系统的协议规范，包括实体定义、接口规范和示例流程。

**核心实体定义**：

| 实体 | 定义 |
|------|------|
| `Model` | OpenAI Responses REST API |
| `Codex` | 核心引擎，通过 SQ/EQ 队列对与 UI 通信 |
| `Session` | Codex 的当前配置和状态 |
| `Task` | Codex 执行用户输入的工作单元 |
| `Turn` | Task 中的一个迭代周期 |

**SQ/EQ 通信模型**：
- **SQ (Submission Queue)**：UI → Codex 的请求队列
- **EQ (Event Queue)**：Codex → UI 的事件队列
- 支持双向流式传输：跨线程通道、IPC、stdin/stdout、TCP、HTTP2、gRPC

**核心 Op 类型**：
- `Op::UserTurn` - 用户输入启动 Turn
- `Op::Interrupt` - 中断运行中的 Turn
- `Op::ExecApproval` - 批准/拒绝代码执行
- `Op::UserInputAnswer` - 响应 `request_user_input` 工具调用

**核心 EventMsg 类型**：
- `EventMsg::AgentMessage` - 模型消息
- `EventMsg::AgentMessageContentDelta` - 流式助手文本
- `EventMsg::PlanDelta` - 流式计划文本
- `EventMsg::ExecApprovalRequest` - 执行审批请求
- `EventMsg::TurnStarted` / `EventMsg::TurnComplete` - Turn 生命周期事件

---

## 具体技术实现

### 1. Bazel 集成架构

**文件层级**：
```
/
├── MODULE.bazel              # 定义 Bazel 依赖和 Rust 工具链
├── defs.bzl                  # 提供 codex_rust_crate 宏
├── codex-rs/
│   ├── Cargo.toml            # Cargo workspace 定义
│   ├── Cargo.lock            # Cargo 依赖锁定
│   └── */BUILD.bazel         # 各 crate 的 Bazel 构建定义
```

**关键宏 `codex_rust_crate`**（defs.bzl:89-140）：
- 包装 `rust_library`, `rust_binary`, `rust_test`
- 对齐 Bazel targets 与 Cargo 约定
- 支持 build scripts、compile data、test data 等

**依赖管理流程**：
1. 修改 `Cargo.toml` / `Cargo.lock`
2. 运行 `just bazel-lock-update` 更新 `MODULE.bazel.lock`
3. 提交 lockfile 变更

**特殊注解示例**（MODULE.bazel:68-82）：
```bzl
crate.annotation(
    crate = "aws-lc-sys",
    build_script_env = {"AWS_LC_SYS_NO_JITTER_ENTROPY": "1"},
    patch_args = ["-p1"],
    patches = ["//patches:aws-lc-sys_memcmp_check.patch"],
)
```

### 2. MCP 服务器实现

**代码位置**：`codex-rs/mcp-server/`

**核心文件**：
- `src/lib.rs` - MCP 服务器主入口
- `src/message_processor.rs` - JSON-RPC 消息处理
- `src/codex_tool_config.rs` - Codex 工具配置
- `src/codex_tool_runner.rs` - 工具执行器
- `src/exec_approval.rs` / `src/patch_approval.rs` - 审批处理

**启动流程**（mcp-server/src/lib.rs:54-150）：
1. 解析 CLI 配置覆盖
2. 加载 Config
3. 初始化 OpenTelemetry
4. 设置 tracing subscriber
5. 创建输入/输出通道（channel capacity = 128）
6. 启动三个并发任务：
   - stdin 读取器：解析 JSON-RPC 消息
   - 消息处理器：处理请求/响应/通知
   - stdout 写入器：序列化输出消息

**协议类型定义**：`app-server-protocol/src/protocol/`
- `common.rs` - 共享类型和宏
- `v1.rs` - v1 API 类型
- `v2.rs` - v2 API 类型（活跃开发）

**关键宏**：`client_request_definitions!`（common.rs:85-150）
- 生成 `ClientRequest` enum
- 支持实验性 API 标记
- 自动生成 method 名称映射

### 3. 核心协议实现

**代码位置**：`codex-rs/protocol/src/protocol.rs`

**Submission 结构**（protocol.rs:101-110）：
```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
pub struct Submission {
    pub id: String,           // 唯一 ID，用于关联 Events
    pub op: Op,               // 操作负载
    pub trace: Option<W3cTraceContext>,  // 可选 W3C trace
}
```

**Op enum**（protocol.rs:206-400+）：
- `Interrupt` - 中断当前任务
- `UserTurn` - 用户输入（推荐方式）
- `UserInput` - 遗留用户输入
- `OverrideTurnContext` - 覆盖 Turn 上下文
- `ExecApproval` / `PatchApproval` - 审批操作
- `ResolveElicitation` - 解析 MCP 诱导请求
- `UserInputAnswer` - 响应用户输入请求

**Event 结构**（protocol.rs 后续）：
```rust
pub struct Event {
    pub id: String,           // 匹配 Submission id
    pub msg: EventMsg,        // 事件负载
}
```

**EventMsg 变体**：
- `AgentMessage` / `AgentMessageContentDelta` - 代理消息
- `PlanDelta` - 计划增量
- `ExecApprovalRequest` - 执行审批请求
- `TurnStarted` / `TurnComplete` - Turn 生命周期
- `Error` / `Warning` - 错误和警告

**传输实现**：
- 非帧传输（stdio/TCP）使用换行分隔 JSON
- 支持双向流式

---

## 关键代码路径与文件引用

### 文档到代码的映射

| 文档 | 引用的代码文件 |
|------|---------------|
| `bazel.md` | `/MODULE.bazel`, `/defs.bzl`, `codex-rs/Cargo.toml`, `codex-rs/Cargo.lock`, `codex-rs/*/BUILD.bazel` |
| `codex_mcp_interface.md` | `codex-rs/app-server-protocol/src/protocol/common.rs`, `codex-rs/app-server-protocol/src/protocol/v1.rs`, `codex-rs/app-server-protocol/src/protocol/v2.rs`, `codex-rs/mcp-server/src/lib.rs`, `codex-rs/app-server/README.md` |
| `protocol_v1.md` | `codex-rs/protocol/src/protocol.rs`, `codex-rs/core/src/agent.rs` |

### 关键文件引用详情

**协议类型定义**：
- `codex-rs/protocol/src/protocol.rs:1-500` - Op/Event 定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs:1-100` - v2 API 类型导入
- `codex-rs/app-server-protocol/src/protocol/common.rs:85-150` - 请求定义宏

**MCP 服务器实现**：
- `codex-rs/mcp-server/src/lib.rs:54-150` - 主运行循环
- `codex-rs/mcp-server/src/message_processor.rs` - 消息处理逻辑

**Bazel 配置**：
- `/MODULE.bazel:1-100` - 模块定义和工具链
- `/defs.bzl:89-150` - codex_rust_crate 宏

---

## 依赖与外部交互

### 1. Bazel 依赖

**外部依赖**（MODULE.bazel）：
- `platforms` - 平台检测
- `llvm` - LLVM 工具链
- `apple_support` - macOS 支持
- `rules_cc` - C/C++ 规则
- `rules_platform` - 平台数据规则
- `rules_rs` (v0.0.43) - Rust 规则
- `zstd`, `bzip2`, `zlib` - 压缩库

**crate 注解**：
- `zstd-sys` - 禁用 build script，使用外部 zstd
- `aws-lc-sys` - 设置环境变量，应用补丁
- `bzip2-sys` / `libz-sys` - 类似处理

### 2. MCP 协议依赖

**内部 crate 依赖**：
- `codex_protocol` - 核心协议类型
- `codex_app_server_protocol` - app-server 协议定义
- `codex_core` - 核心功能
- `codex_arg0` - Arg0 调度路径
- `codex_utils_cli` - CLI 配置覆盖

**外部 crate**：
- `rmcp` - MCP 协议实现
- `serde_json` - JSON 序列化
- `tokio` - 异步运行时
- `tracing` - 日志和追踪

### 3. 协议依赖

**核心协议 crate**：
- `schemars` - JSON Schema 生成
- `serde` - 序列化
- `ts_rs` - TypeScript 类型生成
- `strum_macros` - 枚举工具

---

## 风险、边界与改进建议

### 1. 风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| Bazel 实验性 | Bazel 支持仍处于实验阶段 | 保持 Cargo 作为源头，定期运行 `just bazel-lock-check` |
| MCP 接口不稳定 | `codex_mcp_interface.md` 标记为实验性 | 客户端实现需做好向后不兼容准备 |
| 协议版本混乱 | v1 和 v2 API 并存 | 新开发优先使用 v2，v1 仅用于兼容 |
| 文档与代码不同步 | `protocol_v1.md` 注明可能与代码不完全匹配 | 以代码实现为准，定期审查文档 |

### 2. 边界条件

**Bazel 构建**：
- 不支持嵌套沙箱（Seatbelt 测试需要 `test_tags = ["no-sandbox"]`）
- 某些 crate 需要特殊注解（aws-lc-sys, zstd-sys 等）
- 跨平台构建需要特定 platform triples

**MCP 服务器**：
- 仅支持 stdio 传输（稳定）
- WebSocket 传输实验性且不支持
- 通道容量固定为 128 消息

**协议限制**：
- 每个 Session 同时只能有一个 Task 运行
- 并行任务需要多个 Codex 实例
- `Op` 和 `EventMsg` 是 `non_exhaustive`，未来可能添加变体

### 3. 改进建议

**文档改进**：
1. **添加版本历史**：为每个文档添加变更日志，追踪与代码的同步状态
2. **示例代码**：`protocol_v1.md` 可添加更多实际代码示例
3. **错误处理**：文档中增加常见错误和解决方案
4. **架构图**：添加整体架构图，显示三个文档之间的关系

**Bazel 改进**：
1. **稳定化路线图**：明确 Bazel 支持稳定化的标准和时间线
2. **CI 集成**：增加 Bazel 构建的 CI 检查
3. **文档自动化**：考虑从代码自动生成部分 Bazel 文档

**MCP 接口改进**：
1. **版本控制**：为实验性 API 添加版本标记
2. **迁移指南**：v1 到 v2 的迁移文档
3. **兼容性测试**：增加 MCP 接口的兼容性测试套件

**协议改进**：
1. **正式规范**：考虑将 `protocol_v1.md` 升级为更正式的规范文档
2. **兼容性保证**：明确协议的向后兼容性承诺
3. **性能基准**：添加协议性能基准和限制说明

---

## 附录：文档间关系图

```
codex-rs/docs/
├── bazel.md
│   ├── 引用: /MODULE.bazel
│   ├── 引用: /defs.bzl
│   └── 引用: codex-rs/Cargo.toml
│
├── codex_mcp_interface.md
│   ├── 引用: app-server-protocol/src/protocol/{common,v1,v2}.rs
│   ├── 引用: mcp-server/src/lib.rs
│   └── 引用: app-server/README.md
│
└── protocol_v1.md
    ├── 引用: protocol/src/protocol.rs
    └── 引用: core/src/agent.rs
```

---

## 参考链接

- [Bazel 官方文档](https://bazel.build/)
- [Bzlmod 模块系统](https://bazel.build/external/overview)
- [rules_rust](https://github.com/bazelbuild/rules_rust)
- [rules_rs](https://github.com/bazelbuild/rules_rs)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [app-server README](codex-rs/app-server/README.md)
