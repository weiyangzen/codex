# ApplyPatchApprovalParams.json 研究文档

## 场景与职责

`ApplyPatchApprovalParams` 是 Codex App Server Protocol v1 API 中用于**文件变更审批请求**的核心参数结构。当 AI Agent 尝试应用代码补丁（Patch）修改用户文件系统时，通过此结构向客户端发起审批请求，等待用户确认或拒绝。

**关键场景：**
- 用户通过 `SendUserTurn` 或 `SendUserMessage` 等遗留 API 发起对话
- AI 生成代码修改建议（文件增删改）
- 系统需要用户显式授权才能执行文件写入操作
- 支持沙箱安全策略和权限管理

## 功能点目的

### 1. 文件变更审批流程
该参数结构支持完整的文件变更审批生命周期：
- **请求发起**：Server 向 Client 发送 `ApplyPatchApproval` 请求
- **变更展示**：包含所有待修改文件的详细变更信息
- **用户决策**：用户可选择批准、拒绝或中止操作
- **权限提升**：支持请求额外的写入根目录权限

### 2. 文件变更类型支持
通过 `FileChange` 定义支持三种文件操作：
- **Add**：新增文件（含内容）
- **Delete**：删除文件（含内容备份）
- **Update**：修改文件（统一 diff 格式，可选移动路径）

### 3. 安全与审计
- `callId` 用于关联 `PatchApplyBeginEvent` 和 `PatchApplyEndEvent`
- `grantRoot` 支持请求会话级写入权限
- `reason` 字段记录审批请求的额外说明

## 具体技术实现

### 数据结构定义

**JSON Schema 结构：**
```json
{
  "properties": {
    "callId": { "type": "string" },
    "conversationId": { "$ref": "#/definitions/ThreadId" },
    "fileChanges": {
      "additionalProperties": { "$ref": "#/definitions/FileChange" },
      "type": "object"
    },
    "grantRoot": { "type": ["string", "null"] },
    "reason": { "type": ["string", "null"] }
  },
  "required": ["callId", "conversationId", "fileChanges"]
}
```

**Rust 源码定义**（`codex-rs/app-server-protocol/src/protocol/v1.rs`）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ApplyPatchApprovalParams {
    pub conversation_id: ThreadId,
    /// Use to correlate this with [codex_protocol::protocol::PatchApplyBeginEvent]
    /// and [codex_protocol::protocol::PatchApplyEndEvent].
    pub call_id: String,
    pub file_changes: HashMap<PathBuf, FileChange>,
    /// Optional explanatory reason (e.g. request for extra write access).
    pub reason: Option<String>,
    /// When set, the agent is asking the user to allow writes under this root
    /// for the remainder of the session (unclear if this is honored today).
    pub grant_root: Option<PathBuf>,
}
```

### 关键流程

**1. 审批请求生成**（`bespoke_event_handling.rs` 第 452-478 行）：
```rust
EventMsg::ApplyPatchApprovalRequest(ApplyPatchApprovalRequestEvent {
    call_id, turn_id, changes, reason, grant_root,
}) => {
    match api_version {
        ApiVersion::V1 => {
            let params = ApplyPatchApprovalParams {
                conversation_id, call_id: call_id.clone(),
                file_changes: changes.clone(), reason, grant_root,
            };
            let (_pending_request_id, rx) = outgoing
                .send_request(ServerRequestPayload::ApplyPatchApproval(params))
                .await;
            tokio::spawn(async move {
                on_patch_approval_response(call_id, rx, conversation).await
            });
        }
        // V2 使用 FileChangeRequestApprovalParams...
    }
}
```

**2. 请求注册与路由**（`common.rs` 第 778-783 行）：
```rust
server_request_definitions! {
    ApplyPatchApproval {
        params: v1::ApplyPatchApprovalParams,
        response: v1::ApplyPatchApprovalResponse,
    },
    // ...
}
```

### 协议版本演进

| 版本 | 审批参数类型 | 状态 |
|------|-------------|------|
| V1 | `ApplyPatchApprovalParams` | **已弃用**（用于遗留 API） |
| V2 | `FileChangeRequestApprovalParams` | 活跃使用 |

V2 版本将文件变更作为一等公民（First-class Item），通过 `ItemStarted`/`ItemCompleted` 通知提供更细粒度的生命周期管理。

## 关键代码路径与文件引用

### 核心定义文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | Rust 结构定义（第 124-135 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 枚举注册（第 778-783 行） |
| `codex-rs/app-server-protocol/src/lib.rs` | 公开导出（第 18 行） |

### 调用方实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理，生成审批请求（第 452-478 行） |
| `codex-rs/app-server/src/outgoing_message.rs` | 请求发送基础设施 |

### 客户端处理
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | TUI 适配器处理 ServerRequest |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs` | 审批 UI 覆盖层 |
| `codex-rs/mcp-server/src/patch_approval.rs` | MCP Server 补丁审批处理 |

### 生成文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/ApplyPatchApprovalParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/ApplyPatchApprovalParams.json` | JSON Schema 定义 |

## 依赖与外部交互

### 上游依赖
1. **codex_protocol::protocol::FileChange** - 核心文件变更类型定义
2. **codex_protocol::ThreadId** - 会话标识符
3. **ApplyPatchApprovalRequestEvent** - 核心层审批请求事件

### 下游消费者
1. **TUI Client** - 显示文件变更 diff，收集用户决策
2. **VSCode Extension** - 在 IDE 中展示审批界面
3. **MCP Server** - 代理审批请求到外部客户端

### 相关响应类型
- `ApplyPatchApprovalResponse` - 用户决策响应（含 `ReviewDecision`）

## 风险、边界与改进建议

### 已知限制
1. **grantRoot 未完全实现**：注释明确说明 "unclear if this is honored today"
2. **V1 已弃用**：新开发应使用 V2 的 `FileChangeRequestApprovalParams`
3. **路径序列化**：`HashMap<PathBuf, FileChange>` 在跨平台场景下可能存在路径编码问题

### 安全风险
1. **内容暴露**：Delete 类型的 `content` 字段包含被删文件完整内容，大文件可能导致消息膨胀
2. **Diff 注入**：`unified_diff` 字段未验证格式，恶意客户端可能注入伪造 diff

### 改进建议
1. **迁移到 V2**：新功能开发应使用 `FileChangeRequestApprovalParams`，支持更细粒度的 Item 生命周期
2. **添加大小限制**：对 `fileChanges` 总大小和单个文件内容添加上限
3. **增量 Diff**：大文件考虑使用增量 diff 或哈希校验替代完整内容传输
4. **权限细化**：完善 `grantRoot` 实现或移除未使用的字段

### 测试覆盖
- 集成测试位于 `codex-rs/app-server/tests/`
- MCP 场景测试位于 `codex-rs/mcp-server/tests/`
- 审批决策边界测试覆盖 `ReviewDecision` 所有变体
