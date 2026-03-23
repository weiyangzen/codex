# codex-rs/mcp-server/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统的配置文件，定义了 `codex-mcp-server` crate 的构建规则。该文件位于 `codex-rs/mcp-server/` 目录下，负责声明如何将 Rust 源代码编译成可执行的二进制文件和库。

### 项目定位

`codex-mcp-server` 是一个 **MCP (Model Context Protocol) 服务器**实现，它允许外部客户端通过标准化的 JSON-RPC 协议与 Codex AI 系统进行交互。该服务器将 Codex 的核心功能封装为 MCP 工具，使任何支持 MCP 的客户端（如 Claude Desktop、Cursor 等）都能调用 Codex 的 AI 能力。

## 功能点目的

### 1. Bazel 构建规则定义

该 BUILD 文件使用项目自定义的 `codex_rust_crate` 宏来定义构建规则：

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "mcp-server",
    crate_name = "codex_mcp_server",
)
```

**关键参数说明：**

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"mcp-server"` | Bazel 目标名称，用于构建命令（如 `bazel build //codex-rs/mcp-server`） |
| `crate_name` | `"codex_mcp_server"` | Rust crate 名称，对应 `Cargo.toml` 中的 `[lib]` 和 `[[bin]]` 定义的 name |

### 2. 与 Cargo 的集成

`codex_rust_crate` 宏会自动：
- 从 `Cargo.toml` 读取依赖信息
- 生成 `rust_library` 目标（库 crate）
- 生成 `rust_binary` 目标（二进制可执行文件 `codex-mcp-server`）
- 生成单元测试和集成测试目标

## 具体技术实现

### 构建流程

```
BUILD.bazel
    │
    ▼
codex_rust_crate 宏 (defs.bzl)
    │
    ├──► 解析 Cargo.toml 依赖
    │
    ├──► 创建 rust_library
    │    └── name: "mcp-server"
    │    └── crate_name: "codex_mcp_server"
    │
    ├──► 创建 rust_binary  
    │    └── name: "codex-mcp-server"
    │    └── src: src/main.rs
    │
    └──► 创建测试目标
         └── 单元测试 (src/**/*.rs 中的 #[cfg(test)])
         └── 集成测试 (tests/**/*.rs)
```

### 依赖解析

`codex_rust_crate` 宏通过 `MODULE.bazel.lock` 中定义的 `DEP_DATA` 字典来解析依赖。对于 `codex-mcp-server`，主要依赖包括：

**内部依赖（workspace crates）：**
- `codex-core`: 核心 Codex 功能
- `codex-protocol`: 协议类型定义
- `codex-arg0`: 参数 0 分发路径处理
- `codex-utils-cli`: CLI 工具函数
- `codex-utils-json-to-toml`: JSON 到 TOML 转换
- `codex-shell-command`: 命令解析

**外部依赖（crates.io）：**
- `rmcp`: MCP 协议 Rust 实现
- `tokio`: 异步运行时
- `serde`/`serde_json`: 序列化
- `schemars`: JSON Schema 生成
- `tracing`/`tracing-subscriber`: 日志和追踪

## 关键代码路径与文件引用

### 相关文件

```
codex-rs/mcp-server/
├── BUILD.bazel              # 本文件：Bazel 构建配置
├── Cargo.toml               # Cargo 配置，定义依赖和 crate 元数据
├── src/
│   ├── main.rs              # 二进制入口点
│   ├── lib.rs               # 库入口点，包含 run_main 函数
│   ├── message_processor.rs # MCP 消息处理器
│   ├── codex_tool_runner.rs # Codex 工具执行器
│   ├── codex_tool_config.rs # 工具配置结构体
│   ├── outgoing_message.rs  # 消息发送管理
│   ├── exec_approval.rs     # 执行审批处理
│   └── patch_approval.rs    # 补丁审批处理
└── tests/
    ├── all.rs               # 集成测试入口
    ├── suite/
    │   └── codex_tool.rs    # Codex 工具测试
    └── common/
        ├── lib.rs            # 测试公共库
        ├── mcp_process.rs    # MCP 进程测试工具
        ├── mock_model_server.rs # Mock 模型服务器
        └── responses.rs      # 测试响应构造器
```

### 调用关系

```
// Bazel 构建
bazel build //codex-rs/mcp-server:mcp-server
    │
    ▼
// 生成二进制文件
bazel-bin/codex-rs/mcp-server/codex-mcp-server
    │
    ▼
// 运行时调用链
main.rs::main()
    │
    ▼
lib.rs::run_main()
    │
    ├──► 初始化配置和 OpenTelemetry
    │
    ├──► 启动三个并发任务：
    │    ├── stdin_reader: 从 stdin 读取 JSON-RPC 消息
    │    ├── processor: 处理消息（MessageProcessor）
    │    └── stdout_writer: 向 stdout 写入响应
    │
    └──► 等待任务完成
```

## 依赖与外部交互

### 上游依赖（被调用方）

| 依赖 | 用途 |
|------|------|
| `codex-core` | 提供 `ThreadManager`, `AuthManager`, `Config` 等核心类型 |
| `codex-protocol` | 提供 `ThreadId`, `Event`, `Submission`, `Op` 等协议类型 |
| `rmcp` | 提供 MCP 协议模型（`JsonRpcMessage`, `ClientRequest`, `CallToolRequestParams` 等） |
| `tokio` | 异步运行时，用于并发任务管理 |

### 下游调用（调用方）

`codex-mcp-server` 作为独立二进制，主要被以下方式调用：

1. **直接执行**：`./codex-mcp-server`（通过 stdin/stdout 通信）
2. **MCP 客户端**：如 Claude Desktop 通过 MCP 配置启动
3. **测试框架**：`McpProcess` 测试工具启动子进程

### MCP 协议交互

```
┌─────────────────┐     JSON-RPC      ┌──────────────────┐
│   MCP Client    │ ◄────────────────► │ codex-mcp-server │
│ (Claude Desktop)│    over stdio     │                  │
└─────────────────┘                    └────────┬─────────┘
                                                │
                                                ▼
                                       ┌──────────────────┐
                                       │   codex-core     │
                                       │ (ThreadManager)  │
                                       └────────┬─────────┘
                                                │
                                                ▼
                                       ┌──────────────────┐
                                       │  OpenAI API      │
                                       │  (responses API) │
                                       └──────────────────┘
```

## 风险、边界与改进建议

### 当前风险

1. **简单的构建配置**
   - 当前 BUILD 文件非常简单，只传递了基本参数
   - 如果 crate 需要特殊的编译选项或特性标志，当前配置可能不足

2. **隐式依赖**
   - 通过 `codex_rust_crate` 宏隐式处理大量逻辑
   - 调试构建问题时需要理解宏的内部实现

3. **测试标签缺失**
   - 没有指定 `test_tags`，无法对测试进行分类（如网络测试、沙箱测试等）

### 边界情况

1. **平台兼容性**
   - 代码中使用了平台特定的逻辑（如 Windows PowerShell 命令）
   - 但 BUILD 文件没有平台特定的配置

2. **特性标志**
   - 当前没有启用任何 `crate_features`
   - 如果未来需要条件编译，需要修改此文件

### 改进建议

1. **添加测试标签**

```starlark
codex_rust_crate(
    name = "mcp-server",
    crate_name = "codex_mcp_server",
    test_tags = [
        "requires-network",  # 某些测试需要网络
        "cpu:4",             # 建议 CPU 资源
    ],
)
```

2. **添加编译数据（如果需要）**

```starlark
codex_rust_crate(
    name = "mcp-server",
    crate_name = "codex_mcp_server",
    compile_data = [
        # 如果包含配置文件或模板
    ],
)
```

3. **文档生成**

```starlark
# 添加 rust_doc 目标生成文档
load("@rules_rust//rust:defs.bzl", "rust_doc")

rust_doc(
    name = "mcp-server-doc",
    crate = ":mcp-server",
)
```

### 维护注意事项

1. **Cargo.toml 变更同步**
   - 修改 `Cargo.toml` 后需要运行 `just bazel-lock-update` 更新 `MODULE.bazel.lock`
   - 确保 Bazel 和 Cargo 的依赖保持一致

2. **版本管理**
   - 版本号在 `Cargo.toml` 中定义，通过 `version.workspace = true` 继承工作区版本
   - 发布新版本时需要更新工作区级别的版本

3. **测试执行**
   - 单元测试：`cargo test -p codex-mcp-server`
   - 集成测试：`cargo test -p codex-mcp-server --test all`
   - Bazel 测试：`bazel test //codex-rs/mcp-server/...`
