# FileChangeRequestApprovalParams.json 研究文档

## 场景与职责

`FileChangeRequestApprovalParams` 是 Codex App-Server 协议中用于**文件变更审批请求**的参数结构。当 AI Agent 需要执行文件写入/修改操作时，服务器通过此结构向客户端发送审批请求。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `item/fileChange/requestApproval`。

### 使用场景

1. **文件写入审批**：Agent 尝试写入或修改文件时
2. **目录创建审批**：Agent 尝试创建新目录时
3. **批量变更审批**：一次性审批多个文件的变更

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `itemId` | string | ✅ | 审批项唯一标识 |
| `threadId` | string | ✅ | 所属线程标识 |
| `turnId` | string | ✅ | 所属回合标识 |
| `reason` | string \| null | ❌ | 可选解释原因 |
| `grantRoot` | string \| null | ❌ | [UNSTABLE] 请求允许在此根目录下写入 |

### 字段设计意图

- **`grantRoot`**：允许 Agent 在指定根目录及其子目录下进行写操作，避免频繁审批。注意：文档标注此字段为 "[UNSTABLE]" 且 "unclear if this is honored today"，表明其实现状态不确定。

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FileChangeRequestApprovalParams {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    /// Optional explanatory reason (e.g. request for extra write access).
    #[ts(optional = nullable)]
    pub reason: Option<String>,
    /// [UNSTABLE] When set, the agent is asking the user to allow writes under this root
    /// for the remainder of the session (unclear if this is honored today).
    #[ts(optional = nullable)]
    pub grant_root: Option<PathBuf>,
}
```

### ServerRequest 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    /// Sent when approval is requested for a specific file change.
    /// This request is used for Turns started via turn/start.
    FileChangeRequestApproval => "item/fileChange/requestApproval" {
        params: v2::FileChangeRequestApprovalParams,
        response: v2::FileChangeRequestApprovalResponse,
    },
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5105-5119） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 742-746） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/outgoing_message.rs` | 服务器构造文件变更审批请求 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 处理文件变更审批 UI |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 应用服务器请求处理 |
| `codex-rs/app-server-test-client/src/lib.rs` | 测试客户端 |

---

## 依赖与外部交互

### 依赖类型

```rust
use std::path::PathBuf;
```

### 响应类型

对应的响应类型为 `FileChangeRequestApprovalResponse`：

```rust
pub struct FileChangeRequestApprovalResponse {
    pub decision: FileChangeApprovalDecision,
}

pub enum FileChangeApprovalDecision {
    Accept,
    AcceptForSession,
    Decline,
    Cancel,
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **grantRoot 不稳定**：`grantRoot` 字段被标记为 "[UNSTABLE]"，其实现状态不确定，客户端不应依赖此功能

2. **缺少详细变更信息**：与 `ExecCommandApprovalParams` 不同，此类型不包含具体的文件变更详情（如变更内容、文件路径列表），客户端需要从其他通知获取这些信息

### 边界情况

1. **空 reason**：`reason` 为 `null` 时，客户端需要显示通用提示
2. **grantRoot 路径格式**：路径应为绝对路径，但协议未强制验证

### 改进建议

1. **明确 grantRoot 状态**：
   - 确定是否支持 `grantRoot` 功能
   - 如支持，完善实现并移除 "[UNSTABLE]" 标记
   - 如不支持，考虑移除该字段或明确标记为废弃

2. **添加变更详情**：考虑添加字段描述具体的文件变更：
   ```rust
   pub struct FileChangeRequestApprovalParams {
       // ... 现有字段
       pub changes: Vec<FileChange>,
   }
   
   pub struct FileChange {
       pub path: PathBuf,
       pub change_type: FileChangeType,  // Create, Modify, Delete
       pub preview: Option<String>,      // 变更内容预览
   }
   ```

3. **批量审批优化**：对于大量文件变更，考虑支持：
   - 分组审批（按目录分组）
   - 差异预览
   - 选择性批准（批准部分文件，拒绝其他文件）

4. **与 v1 对比**：v1 的 `ApplyPatchApprovalParams` 包含 `file_changes: HashMap<PathBuf, FileChange>`，v2 可以考虑添加类似功能
