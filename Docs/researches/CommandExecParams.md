# CommandExecParams 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecParams` 是 app-server-protocol v2 API 中用于执行独立命令的核心请求参数结构。它允许客户端在服务器沙箱中运行命令而不需要创建线程或回合（thread/turn），适用于以下场景：

- **独立命令执行**：执行一次性命令如 `ls`、`git status`、`npm install` 等
- **交互式终端会话**：通过 PTY 模式启动 vim、less、node repl 等交互式程序
- **后台任务执行**：运行耗时较长的编译、测试等任务
- **文件系统操作**：通过命令行工具执行批量文件操作
- **开发工具集成**：与构建工具、包管理器、代码检查工具等集成

### 核心职责
1. **命令配置**：定义要执行的命令参数向量（argv）、工作目录、环境变量
2. **流控制**：配置 stdin/stdout/stderr 的流式传输行为
3. **PTY 支持**：启用伪终端模式以支持交互式应用程序
4. **资源限制**：设置输出大小上限、超时时间等资源约束
5. **安全沙箱**：指定命令执行的沙箱策略

## 2. 功能点目的

### 设计目标
- **灵活性**：支持从简单的一次性命令到复杂的交互式会话
- **安全性**：所有命令在沙箱中执行，限制文件系统和网络访问
- **可控性**：提供丰富的控制选项（超时、输出限制、流控制）
- **兼容性**：支持传统命令行工具和交互式 TUI 应用程序

### 关键特性
| 特性 | 说明 |
|------|------|
| PTY 模式 | 支持伪终端，可运行 vim、tmux 等交互式程序 |
| 流式 I/O | 可选的 stdin 输入和 stdout/stderr 实时流式输出 |
| 输出上限 | 防止内存溢出，支持按流设置字节上限 |
| 超时控制 | 防止命令无限期运行 |
| 沙箱策略 | 可配置只读、工作区写入、完全访问等多种策略 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecParams {
    /// Command argv vector. Empty arrays are rejected.
    pub command: Vec<String>,
    /// Optional client-supplied, connection-scoped process id.
    #[ts(optional = nullable)]
    pub process_id: Option<String>,
    /// Enable PTY mode. This implies `streamStdin` and `streamStdoutStderr`.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub tty: bool,
    /// Allow follow-up `command/exec/write` requests to write stdin bytes.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub stream_stdin: bool,
    /// Stream stdout/stderr via `command/exec/outputDelta` notifications.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub stream_stdout_stderr: bool,
    /// Optional per-stream stdout/stderr capture cap in bytes.
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub output_bytes_cap: Option<usize>,
    /// Disable stdout/stderr capture truncation for this request.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub disable_output_cap: bool,
    /// Disable the timeout entirely for this request.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub disable_timeout: bool,
    /// Optional timeout in milliseconds.
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub timeout_ms: Option<i64>,
    /// Optional working directory. Defaults to the server cwd.
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    /// Optional environment overrides.
    #[ts(optional = nullable)]
    pub env: Option<HashMap<String, Option<String>>>,
    /// Optional initial PTY size in character cells.
    #[ts(optional = nullable)]
    pub size: Option<CommandExecTerminalSize>,
    /// Optional sandbox policy for this command.
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>,
}

/// PTY size definition
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecTerminalSize {
    /// Terminal height in character cells.
    pub rows: u16,
    /// Terminal width in character cells.
    pub cols: u16,
}
```

### 沙箱策略定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum SandboxPolicy {
    DangerFullAccess,
    ReadOnly {
        #[serde(default)]
        access: ReadOnlyAccess,
        #[serde(default)]
        network_access: bool,
    },
    ExternalSandbox {
        #[serde(default)]
        network_access: NetworkAccess,
    },
    WorkspaceWrite {
        #[serde(default)]
        writable_roots: Vec<AbsolutePathBuf>,
        #[serde(default)]
        read_only_access: ReadOnlyAccess,
        #[serde(default)]
        network_access: bool,
        #[serde(default)]
        exclude_tmpdir_env_var: bool,
        #[serde(default)]
        exclude_slash_tmp: bool,
    },
}

#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ReadOnlyAccess {
    Restricted {
        #[serde(default = "default_include_platform_defaults")]
        include_platform_defaults: bool,
        #[serde(default)]
        readable_roots: Vec<AbsolutePathBuf>,
    },
    #[default]
    FullAccess,
}
```

### JSON Schema 片段

```json
{
  "description": "Run a standalone command (argv vector) in the server sandbox without creating a thread or turn.",
  "properties": {
    "command": {
      "description": "Command argv vector. Empty arrays are rejected.",
      "items": { "type": "string" },
      "type": "array"
    },
    "cwd": {
      "description": "Optional working directory. Defaults to the server cwd.",
      "type": ["string", "null"]
    },
    "disableOutputCap": {
      "description": "Disable stdout/stderr capture truncation for this request.",
      "type": "boolean"
    },
    "disableTimeout": {
      "description": "Disable the timeout entirely for this request.",
      "type": "boolean"
    },
    "env": {
      "additionalProperties": { "type": ["string", "null"] },
      "description": "Optional environment overrides merged into the server-computed environment.",
      "type": ["object", "null"]
    },
    "outputBytesCap": {
      "description": "Optional per-stream stdout/stderr capture cap in bytes.",
      "format": "uint",
      "minimum": 0,
      "type": ["integer", "null"]
    },
    "processId": {
      "description": "Optional client-supplied, connection-scoped process id.",
      "type": ["string", "null"]
    },
    "sandboxPolicy": {
      "$ref": "#/definitions/SandboxPolicy",
      "description": "Optional sandbox policy for this command."
    },
    "size": {
      "$ref": "#/definitions/CommandExecTerminalSize",
      "description": "Optional initial PTY size in character cells. Only valid when `tty` is true."
    },
    "streamStdin": {
      "description": "Allow follow-up `command/exec/write` requests to write stdin bytes.",
      "type": "boolean"
    },
    "streamStdoutStderr": {
      "description": "Stream stdout/stderr via `command/exec/outputDelta` notifications.",
      "type": "boolean"
    },
    "timeoutMs": {
      "description": "Optional timeout in milliseconds.",
      "format": "int64",
      "type": ["integer", "null"]
    },
    "tty": {
      "description": "Enable PTY mode. This implies `streamStdin` and `streamStdoutStderr`.",
      "type": "boolean"
    }
  },
  "required": ["command"],
  "title": "CommandExecParams",
  "type": "object"
}
```

### 字段详细说明

| 字段名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `command` | string[] | 是 | - | 命令参数向量，空数组会被拒绝 |
| `processId` | string \| null | 否 | null | 连接作用域进程标识符，流式操作必需 |
| `tty` | boolean | 否 | false | 启用 PTY 模式，自动启用流式 I/O |
| `streamStdin` | boolean | 否 | false | 允许后续写入 stdin |
| `streamStdoutStderr` | boolean | 否 | false | 流式输出 stdout/stderr |
| `outputBytesCap` | integer \| null | 否 | 服务器默认 | 每流输出字节上限 |
| `disableOutputCap` | boolean | 否 | false | 禁用输出上限（不能与 outputBytesCap 共用） |
| `disableTimeout` | boolean | 否 | false | 禁用超时（不能与 timeoutMs 共用） |
| `timeoutMs` | integer \| null | 否 | 服务器默认 | 超时时间（毫秒） |
| `cwd` | string \| null | 否 | 服务器 cwd | 工作目录 |
| `env` | object \| null | 否 | - | 环境变量覆盖，null 值表示删除 |
| `size` | CommandExecTerminalSize \| null | 否 | - | PTY 初始大小（tty=true 时有效） |
| `sandboxPolicy` | SandboxPolicy \| null | 否 | 用户配置 | 沙箱策略 |

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2280-2360 行） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `CommandExecTerminalSize` 定义（第 2270-2278 行） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `SandboxPolicy` 定义（第 1271-1381 行） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `ReadOnlyAccess` 定义（第 1224-1269 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 456-460 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecParams.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    /// Execute a standalone command (argv vector) under the server's sandbox.
    OneOffCommandExec => "command/exec" {
        params: v2::CommandExecParams,
        response: v2::CommandExecResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecResponse` - 命令执行结果响应
- `CommandExecWriteParams` - 向 stdin 写入数据
- `CommandExecResizeParams` - 调整 PTY 大小
- `CommandExecTerminateParams` - 终止进程
- `CommandExecOutputDeltaNotification` - 流式输出通知

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecParams
├── CommandExecTerminalSize (结构体)
├── SandboxPolicy (枚举)
│   ├── ReadOnlyAccess (枚举)
│   ├── NetworkAccess (枚举)
│   └── AbsolutePathBuf (类型)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── std::path::PathBuf (标准库)
```

### 外部交互

1. **与沙箱系统的交互**：
   - 根据 `sandboxPolicy` 配置沙箱权限
   - 使用 `codex_protocol::protocol::SandboxPolicy` 进行核心沙箱操作

2. **与进程管理的交互**：
   - 启动子进程执行命令
   - 管理进程生命周期（超时、终止）

3. **与 PTY 系统的交互**（当 `tty=true`）：
   - 分配伪终端设备
   - 设置终端大小
   - 处理终端信号

### 生成产物

- TypeScript 类型定义（`v2/CommandExecParams.ts`）
- JSON Schema（`schema/json/v2/CommandExecParams.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **命令注入**：
   - 虽然参数以向量形式传递避免了 shell 注入，但仍需注意命令本身的参数处理
   - 建议对 `command` 内容进行验证

2. **资源耗尽**：
   - `disableOutputCap` 和 `disableTimeout` 可能导致资源无限占用
   - 服务器应设置绝对上限作为安全网

3. **PTY 安全风险**：
   - PTY 模式可能暴露更多攻击面
   - 某些逃逸技术可能利用 TTY 特性

### 边界情况

| 场景 | 行为 |
|------|------|
| 空 command 数组 | 请求被拒绝 |
| processId 缺失但启用流式 | 请求被拒绝 |
| tty=true 但未提供 size | 使用默认终端大小 |
| 环境变量值为 null | 从继承环境中删除该变量 |
| 同时设置 disableOutputCap 和 outputBytesCap | 请求被拒绝（互斥） |
| 同时设置 disableTimeout 和 timeoutMs | 请求被拒绝（互斥） |

### 改进建议

1. **命令白名单**：
   - 添加可选的允许命令列表配置
   - 支持正则匹配或精确匹配

2. **资源配额**：
   - 添加 CPU 时间限制
   - 添加内存使用限制
   - 添加文件描述符限制

3. **审计日志**：
   - 记录所有执行的命令
   - 记录沙箱策略和权限变更

4. **信号处理**：
   - 支持向进程发送特定信号（SIGINT、SIGTERM 等）
   - 当前仅支持终止操作

5. **退出码映射**：
   - 标准化不同平台的退出码
   - 区分沙箱错误和命令错误

6. **流控优化**：
   - 实现背压机制防止客户端缓冲区溢出
   - 支持输出速率限制
