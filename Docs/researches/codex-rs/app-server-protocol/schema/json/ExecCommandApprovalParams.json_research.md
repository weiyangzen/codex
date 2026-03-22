# ExecCommandApprovalParams.json 研究文档

## 场景与职责

`ExecCommandApprovalParams` 是 Codex App-Server 协议 v1 中用于**执行命令审批请求**的参数结构。这是 v1 API 的遗留类型，用于向后兼容旧的命令审批流程。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `execCommandApproval`（v1）。

### 使用场景

1. **遗留 API 支持**：为使用 `SendUserTurn` 或 `SendUserMessage`（v1 API）启动的回合提供命令审批
2. **迁移过渡期**：在客户端从 v1 迁移到 v2 期间保持兼容性

### 与 v2 的关系

v2 引入了 `CommandExecutionRequestApprovalParams` 作为替代，但 `ExecCommandApprovalParams` 仍保留用于：
- v1 客户端的向后兼容
- 与 `ExecCommandBeginEvent` / `ExecCommandEndEvent` 的关联

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `callId` | string | ✅ | 调用标识，用于关联 ExecCommandBeginEvent/ExecCommandEndEvent |
| `command` | string[] | ✅ | 命令参数数组（argv 格式） |
| `conversationId` | string | ✅ | 会话标识 |
| `cwd` | string | ✅ | 工作目录 |
| `parsedCmd` | ParsedCommand[] | ✅ | 解析后的命令信息 |
| `approvalId` | string \| null | ❌ | 特定回调标识 |
| `reason` | string \| null | ❌ | 可选解释原因 |

### 与 v2 的字段差异

| 字段 | v1 (ExecCommandApprovalParams) | v2 (CommandExecutionRequestApprovalParams) |
|------|-------------------------------|-------------------------------------------|
| 命令格式 | `command: string[]` (argv) | `command: string \| null` (完整命令行) |
| 会话标识 | `conversationId` | `threadId` |
| 命令解析 | `parsedCmd: ParsedCommand[]` | `commandActions: CommandAction[] \| null` |
| 网络上下文 | ❌ 不支持 | ✅ `networkApprovalContext` |
| 策略修正 | ❌ 不支持 | ✅ `proposedExecpolicyAmendment` |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v1.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ExecCommandApprovalParams {
    pub conversation_id: ThreadId,
    /// Use to correlate this with [codex_protocol::protocol::ExecCommandBeginEvent]
    /// and [codex_protocol::protocol::ExecCommandEndEvent].
    pub call_id: String,
    /// Identifier for this specific approval callback.
    pub approval_id: Option<String>,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub parsed_cmd: Vec<ParsedCommand>,
}
```

### ParsedCommand 类型

```rust
// 来自 codex_protocol::parse_command
pub enum ParsedCommand {
    Read { cmd: String, name: String, path: String },
    ListFiles { cmd: String, path: Option<String> },
    Search { cmd: String, path: Option<String>, query: Option<String> },
    Unknown { cmd: String },
}
```

### ServerRequest 注册（v1）

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    /// DEPRECATED APIs below
    ExecCommandApproval {
        params: v1::ExecCommandApprovalParams,
        response: v1::ExecCommandApprovalResponse,
    },
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | 主类型定义（行 143-156） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 786-789） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 服务器端处理 |
| `codex-rs/app-server-protocol/src/lib.rs` | 公开导出 |

---

## 依赖与外部交互

### 依赖类型

```rust
use codex_protocol::ThreadId;
use codex_protocol::parse_command::ParsedCommand;
use std::path::PathBuf;
```

### 与 v2 类型的转换关系

虽然没有直接的 `From` 实现，但在服务器逻辑中存在隐式转换：
- v1 的 `conversationId` 对应 v2 的 `threadId`
- v1 的 `parsedCmd` 对应 v2 的 `commandActions`
- v1 的 `command: Vec<String>` 需要拼接为 v2 的 `command: String`

---

## 风险、边界与改进建议

### 已知风险

1. **弃用状态**：该类型已被标记为 DEPRECATED，新客户端应使用 v2 API
2. **功能限制**：不支持网络审批上下文、策略修正等 v2 功能

### 边界情况

1. **命令数组为空**：`command: []` 的行为未明确定义
2. **路径解析**：`cwd` 是相对路径还是绝对路径取决于调用方

### 改进建议

1. **明确弃用时间表**：在文档中明确该类型的移除计划

2. **迁移指南**：提供从 v1 到 v2 的迁移指南：
   ```markdown
   ## 迁移检查清单
   - [ ] 将 `conversationId` 重命名为 `threadId`
   - [ ] 将 `command: string[]` 改为 `command: string`
   - [ ] 将 `parsedCmd` 重命名为 `commandActions`
   - [ ] 处理新的 `networkApprovalContext` 字段
   ```

3. **兼容性层**：考虑在服务器端添加自动转换层，将 v1 请求透明转换为 v2

4. **功能回传**：评估是否需要在 v1 中支持关键的 v2 功能（如网络审批）
