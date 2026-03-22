# CommandExecutionRequestApprovalParams.json 研究文档

## 场景与职责

`CommandExecutionRequestApprovalParams` 是 Codex App-Server 协议中用于**命令执行审批请求**的核心参数结构。当 AI Agent 需要执行可能具有风险的 shell 命令时，服务器通过此结构向客户端发送审批请求，由用户决定是否允许执行。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `item/commandExecution/requestApproval`。

### 使用场景

1. **Shell 命令执行审批**：当 Agent 尝试执行 `shell` 或 `unified_exec` 工具调用时
2. **网络访问审批**：当命令涉及受控网络访问时（通过 `networkApprovalContext`）
3. **Zsh Exec Bridge 子命令审批**：支持多个回调关联到同一个父 `itemId` 的场景

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | ✅ | 所属线程标识 |
| `turnId` | string | ✅ | 所属回合标识 |
| `itemId` | string | ✅ | 审批项唯一标识 |
| `approvalId` | string \| null | ❌ | 特定回调标识（用于 zsh-exec-bridge 多回调场景） |
| `command` | string \| null | ❌ | 待执行的命令字符串 |
| `cwd` | string \| null | ❌ | 命令执行的工作目录 |
| `commandActions` | CommandAction[] \| null | ❌ | 解析后的命令动作（用于友好展示） |
| `reason` | string \| null | ❌ | 可选的解释原因（如网络访问请求） |
| `networkApprovalContext` | NetworkApprovalContext \| null | ❌ | 托管网络审批的上下文信息 |
| `proposedExecpolicyAmendment` | string[] \| null | ❌ | 建议的 execpolicy 修正案 |
| `proposedNetworkPolicyAmendments` | NetworkPolicyAmendment[] \| null | ❌ | 建议的网络策略修正案 |

### 决策类型（CommandExecutionApprovalDecision）

JSON Schema 中内联定义了用户可能的决策选项：

1. **`accept`** - 用户批准执行
2. **`acceptForSession`** - 批准并允许同一会话中的类似提示自动执行
3. **`acceptWithExecpolicyAmendment`** - 批准并应用 execpolicy 修正案
4. **`applyNetworkPolicyAmendment`** - 应用持久网络策略规则（允许/拒绝主机）
5. **`decline`** - 拒绝执行，但 Agent 继续回合
6. **`cancel`** - 拒绝执行并立即中断回合

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecutionRequestApprovalParams {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub approval_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub network_approval_context: Option<NetworkApprovalContext>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub command_actions: Option<Vec<CommandAction>>,
    // ... 实验性字段
}
```

### 命令动作类型（CommandAction）

支持四种命令解析类型：

```rust
pub enum CommandAction {
    Read { command: String, name: String, path: PathBuf },
    ListFiles { command: String, path: Option<String> },
    Search { command: String, query: Option<String>, path: Option<String> },
    Unknown { command: String },
}
```

### 网络审批上下文

```rust
pub struct NetworkApprovalContext {
    pub host: String,
    pub protocol: NetworkApprovalProtocol,  // http, https, socks5Tcp, socks5Udp
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5022-5089） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 枚举注册（行 736-739） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | CommandAction 定义（行 1436-1458） |

### 使用方（调用方）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 服务器端事件处理，构造审批请求 |
| `codex-rs/app-server/src/transport.rs` | 传输层处理 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 应用服务器请求处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 聊天组件处理审批 UI |

### 测试文件

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 单元测试（行 5904-6047） |
| `codex-rs/app-server-test-client/src/lib.rs` | 测试客户端 |

---

## 依赖与外部交互

### 依赖类型

```rust
// 来自 codex_protocol crate
use codex_protocol::approvals::NetworkApprovalContext as CoreNetworkApprovalContext;
use codex_protocol::approvals::NetworkPolicyAmendment as CoreNetworkPolicyAmendment;
use codex_protocol::parse_command::ParsedCommand as CoreParsedCommand;

// 来自 codex_utils_absolute_path crate
use codex_utils_absolute_path::AbsolutePathBuf;
```

### 序列化特性

- **serde**: 使用 `camelCase` 命名策略
- **schemars**: 自动生成 JSON Schema
- **ts_rs**: 自动生成 TypeScript 类型定义

### 实验性字段

以下字段被标记为实验性（`#[experimental(...)]`）：

- `additional_permissions` - 额外权限配置
- `skill_metadata` - Skill 元数据（包含 `pathToSkillsMd`）

这些字段在非实验性模式下会被 `strip_experimental_fields()` 方法移除。

---

## 风险、边界与改进建议

### 已知风险

1. **路径安全问题**：`AbsolutePathBuf` 需要设置基础路径才能正确反序列化相对路径，否则将失败
   ```rust
   // 错误示例：相对路径会失败
   "read": ["relative/path"]  // ❌ 失败
   ```

2. **实验性字段稳定性**：`additionalPermissions` 和 `skillMetadata` 字段处于实验阶段，API 可能变更

3. **Zsh Exec Bridge 复杂性**：`approvalId` 字段用于区分同一 `itemId` 下的多个回调，路由逻辑较复杂

### 边界情况

1. **空命令处理**：`command` 字段可为 `null`，客户端需要处理此情况
2. **网络上下文缺失**：非网络相关命令的 `networkApprovalContext` 为 `null`
3. **命令动作解析失败**：无法解析的命令会降级为 `Unknown` 类型

### 改进建议

1. **增强路径验证**：在序列化层添加更明确的路径格式错误提示

2. **统一决策模型**：当前 `CommandExecutionApprovalDecision` 与 v1 的 `ReviewDecision` 存在语义差异，建议统一：
   - v1: `approved`, `approved_execpolicy_amendment`, `denied`, `abort`
   - v2: `accept`, `acceptWithExecpolicyAmendment`, `decline`, `cancel`

3. **文档完善**：`grantRoot` 字段的文档标注为 "[UNSTABLE]" 且 "unclear if this is honored today"，需要明确其状态

4. **实验性字段 graduating**：考虑将成熟的实验性字段（如 macOS 权限）提升为稳定 API

5. **命令动作扩展**：当前仅支持 `read`, `listFiles`, `search`, `unknown`，可考虑添加更多常用命令类型（如 `write`, `delete`）
