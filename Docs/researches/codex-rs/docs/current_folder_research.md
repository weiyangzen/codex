# DIR codex-rs/docs 研究文档

## 概述

`codex-rs/docs` 目录是 Codex Rust 项目的文档中心，包含关于构建系统、MCP 服务器接口和核心协议的技术文档。这些文档为开发者提供了理解 Codex 架构、API 和使用方式的关键信息。

---

## 场景与职责

### 1. 构建系统文档 (`bazel.md`)

**场景**: 开发者需要理解如何在 codex-rs 中使用 Bazel 构建系统，或者需要添加/修改 Rust crate 的依赖。

**职责**:
- 说明 Bazel 与 Cargo 的协作方式
- 指导如何更新依赖和 lockfile
- 提供创建新 crate 的 BUILD.bazel 配置指南
- 解释常见构建问题的解决方案

### 2. MCP 服务器接口文档 (`codex_mcp_interface.md`)

**场景**: 开发者需要集成 Codex 的 MCP (Model Context Protocol) 服务器功能，或开发基于 MCP 的客户端应用。

**职责**:
- 定义 MCP 服务器的 JSON-RPC API 规范
- 说明线程 (Thread) 和轮次 (Turn) 的管理 API
- 描述事件流通知机制
- 定义审批流程 (applyPatchApproval, execCommandApproval)
- 提供认证相关的 API 文档

### 3. 核心协议文档 (`protocol_v1.md`)

**场景**: 开发者需要理解 Codex 内部的核心实体、消息协议和交互流程。

**职责**:
- 定义核心实体概念 (Model, Codex, Session, Task, Turn)
- 说明 Submission Queue (SQ) 和 Event Queue (EQ) 的通信机制
- 描述 `Op` (操作) 和 `EventMsg` (事件消息) 的变体
- 提供序列图示例展示典型交互流程

---

## 功能点目的

### bazel.md

| 功能点 | 目的 |
|--------|------|
| Bazel 高阶布局说明 | 让开发者理解 MODULE.bazel、defs.bzl、crate 依赖的关系 |
| 依赖更新流程 | 指导 `just bazel-lock-update` 和 `just bazel-lock-check` 的使用 |
| 新 crate 创建指南 | 确保新 crate 的 BUILD.bazel 配置符合项目规范 |
| 测试标签说明 | 解释 `no-sandbox` 标签的使用场景（如 Seatbelt 测试） |

### codex_mcp_interface.md

| 功能点 | 目的 |
|--------|------|
| v2 RPC API | 提供线程管理 (`thread/*`)、轮次管理 (`turn/*`)、账户管理 (`account/*`) 等核心 API |
| v1 兼容 API | 保留旧版 API (`getConversationSummary`, `getAuthStatus` 等) 的兼容性说明 |
| 通知机制 | 定义服务器向客户端推送的事件类型 (`thread/started`, `turn/completed` 等) |
| 审批流程 | 说明服务器如何向客户端请求执行命令或应用补丁的权限 |
| 模型列表 API | 提供获取可用模型及其配置的能力 |

### protocol_v1.md

| 功能点 | 目的 |
|--------|------|
| 实体定义 | 建立共享词汇表：Model, Codex, Session, Task, Turn |
| 通信接口 | 说明 SQ/EQ 双向队列的通信模式 |
| Op 枚举 | 定义 UI 向 Codex 发送的操作类型 |
| EventMsg 枚举 | 定义 Codex 向 UI 发送的事件类型 |
| 序列图 | 可视化展示配置、任务执行、中断等典型流程 |

---

## 具体技术实现

### 1. Bazel 构建系统架构

**关键文件**:
- `../MODULE.bazel` - 定义 Bazel 依赖和 Rust 工具链
- `../defs.bzl` - 提供 `codex_rust_crate` 宏，包装 rust_library/rust_binary/rust_test
- `codex-rs/Cargo.toml` 和 `Cargo.lock` - Cargo 依赖的单一事实来源
- `MODULE.bazel.lock` - Bzlmod 的 lockfile

**依赖管理流程**:
```
Cargo.toml/Cargo.lock (Cargo 事实来源)
    ↓
crate.from_cargo(...) (通过 rules_rs 导入)
    ↓
@crates (Bazel 可用的第三方 crate)
```

**关键命令**:
```bash
just bazel-lock-update   # 更新 MODULE.bazel.lock
just bazel-lock-check    # 本地验证 lockfile 一致性
```

### 2. MCP 服务器协议

**传输层**: JSON-RPC 2.0 over stdio (行分隔)

**核心 API 结构**:
```
thread/
  - start, resume, fork, read, list

turn/
  - start, steer, interrupt

account/
  - read, login/start, login/cancel, logout, rateLimits/read

config/
  - read, value/write, batchWrite

model/
  - list

app/
  - list

collaborationMode/
  - list
```

**通知类型**:
- `codex/event/*` - 实时代理事件流
- `thread/started`, `turn/completed` - 生命周期事件
- `account/login/completed` - 认证事件

**审批请求** (Server → Client):
- `applyPatchApproval` - 请求批准应用代码补丁
- `execCommandApproval` - 请求批准执行命令

### 3. 核心协议实体

**实体层次**:
```
Model (OpenAI Responses REST API)
  ↑
Codex (本地核心引擎)
  ├── Session (配置和状态)
  │     └── Task (执行中的工作)
  │           └── Turn (单次迭代循环)
  ↑↓
UI (CLI/TUI/GUI)
```

**通信机制**:
- **SQ (Submission Queue)**: UI → Codex，包含带 `sub_id` 的 `Op` 消息
- **EQ (Event Queue)**: Codex → UI，包含 `Event` 消息，`Event.id` 匹配 `sub_id`

**Op 变体**:
- `UserTurn` - 用户输入启动新 Turn
- `UserInput` - 旧版用户输入（已弃用）
- `Interrupt` - 中断当前 Turn
- `ExecApproval` - 批准/拒绝执行
- `UserInputAnswer` - 回答工具调用的用户输入请求
- `ListSkills` - 请求技能列表

**EventMsg 变体**:
- `AgentMessage` - 模型返回的消息
- `AgentMessageContentDelta` - 流式助手文本
- `PlanDelta` - 计划模式下的流式计划文本
- `ExecApprovalRequest` - 执行审批请求
- `RequestUserInput` - 请求用户输入
- `TurnStarted` - Turn 开始元数据
- `TurnComplete` - Turn 完成（含 `response_id` 书签）
- `Error`, `Warning` - 错误和警告

**传输协议**:
- 支持双向流传输：线程通道、IPC、stdin/stdout、TCP、HTTP2、gRPC
- 非帧传输使用换行分隔的 JSON (NDJSON)

---

## 关键代码路径与文件引用

### 文档到代码的映射

| 文档 | 引用的代码路径 | 说明 |
|------|----------------|------|
| `bazel.md` | `../MODULE.bazel` | Bazel 模块定义 |
| `bazel.md` | `../defs.bzl` | `codex_rust_crate` 宏定义 |
| `bazel.md` | `codex-rs/*/BUILD.bazel` | 各 crate 的构建配置 |
| `codex_mcp_interface.md` | `app-server-protocol/src/protocol/{common,v1,v2}.rs` | 协议类型定义 |
| `codex_mcp_interface.md` | `app-server/` | 服务器实现 |
| `codex_mcp_interface.md` | `app-server/README.md` | 详细 API 文档 |
| `protocol_v1.md` | `protocol/src/protocol.rs` | Op 和 EventMsg 定义 |
| `protocol_v1.md` | `core/src/agent.rs` | Agent 实现 |

### 相关脚本和命令

| 脚本/命令 | 位置 | 用途 |
|-----------|------|------|
`just bazel-lock-update` | `justfile` | 更新 Bazel lockfile |
`just bazel-lock-check` | `justfile` | 验证 lockfile |
`just write-app-server-schema` | `justfile` | 重新生成协议 schema |
`just write-config-schema` | `justfile` | 生成 config.toml schema |

---

## 依赖与外部交互

### Bazel 文档依赖

**内部依赖**:
- `MODULE.bazel` - 根模块配置
- `defs.bzl` - 构建宏定义
- `codex-rs/Cargo.toml` - Cargo 工作区配置

**外部依赖**:
- `rules_rs` - 从 Cargo 导入 crate 到 Bazel
- `rules_rust` - Rust 规则集
- LLVM 工具链 - 编译器工具链

### MCP 接口文档依赖

**内部依赖**:
- `app-server-protocol` crate - 协议类型定义
- `app-server` crate - 服务器实现
- `app-server/README.md` - 详细文档

**外部交互**:
- MCP 客户端（如 `@modelcontextprotocol/inspector`）
- OpenAI API（模型后端）

### 协议文档依赖

**内部依赖**:
- `protocol` crate - `protocol.rs` 中的 Op/EventMsg 定义
- `core` crate - Agent 实现 (`agent.rs`)

**外部交互**:
- OpenAI Responses API
- UI 实现（TUI、CLI、VSCode 扩展等）

---

## 风险、边界与改进建议

### 风险

1. **文档与代码不同步**
   - `protocol_v1.md` 明确说明："代码可能不完全匹配此规范"
   - 建议：建立文档与代码的同步检查机制

2. **MCP 接口实验性**
   - `codex_mcp_interface.md` 标记为 experimental，可能随时变更
   - 风险：外部集成可能因 API 变更而中断

3. **Bazel 构建实验性**
   - `bazel.md` 说明截至 2026/1/9 仍处于实验阶段
   - 风险：构建配置可能不稳定

### 边界

1. **协议版本边界**
   - v1 API 仅保留兼容性，新功能应使用 v2
   - v2 使用 camelCase，配置相关 API 使用 snake_case（匹配 config.toml）

2. **传输边界**
   - 核心协议支持多种传输，但 MCP 仅支持 stdio
   - 非帧传输必须使用 NDJSON

3. **沙箱边界**
   - 测试使用 `no-sandbox` 标签时需要特殊处理（如 Seatbelt 测试）

### 改进建议

1. **文档改进**
   - 为 `protocol_v1.md` 添加版本号和最后更新时间
   - 在代码变更时自动检查文档是否需要更新
   - 为 MCP API 添加更多使用示例

2. **流程改进**
   - 建立文档审查流程，确保新功能同步更新文档
   - 考虑使用 OpenAPI/AsyncAPI 等标准格式描述协议

3. **工具改进**
   - 为 `just write-app-server-schema` 添加 CI 检查，确保 schema 是最新的
   - 考虑生成 API 文档网站，替代手动维护的 markdown

---

## 总结

`codex-rs/docs` 目录包含三个关键文档：

1. **bazel.md** - 构建系统指南，说明 Bazel 与 Cargo 的协作方式
2. **codex_mcp_interface.md** - MCP 服务器 API 规范，面向外部集成
3. **protocol_v1.md** - 核心协议规范，定义内部实体和通信机制

这些文档是理解 Codex 架构和开发扩展的关键资源，但需要注意部分文档标记为实验性，可能存在变更风险。
