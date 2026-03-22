# FileChangeRequestApprovalResponse.json 研究文档

## 场景与职责

`FileChangeRequestApprovalResponse` 是 Codex App-Server 协议中用于**响应文件变更审批请求**的结构。当客户端收到 `item/fileChange/requestApproval` 请求后，通过此结构向服务器返回用户的审批决策。

该类型属于 **Client → Server** 的响应流，是 `FileChangeRequestApproval` 请求的预期响应类型。

### 使用场景

1. **批准文件变更**：用户同意执行文件写入/修改操作
2. **批准并自动后续变更**：用户批准当前变更及同一会话中对相同文件的后续变更
3. **拒绝文件变更**：用户拒绝执行文件变更

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `decision` | FileChangeApprovalDecision | ✅ | 用户的审批决策 |

### 决策类型（FileChangeApprovalDecision）

`FileChangeApprovalDecision` 是一个 `oneOf` 枚举，支持以下值：

| 值 | 描述 |
|------|------|
| `"accept"` | 用户批准文件变更 |
| `"acceptForSession"` | 批准变更，同一会话中对相同文件的后续变更自动执行 |
| `"decline"` | 用户拒绝变更，Agent 继续回合 |
| `"cancel"` | 用户拒绝变更，立即中断回合 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum FileChangeApprovalDecision {
    /// User approved the file changes.
    Accept,
    /// User approved the file changes and future changes to the same files should run without prompting.
    AcceptForSession,
    /// User denied the file changes. The agent will continue the turn.
    Decline,
    /// User denied the file changes. The turn will also be immediately interrupted.
    Cancel,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub struct FileChangeRequestApprovalResponse {
    pub decision: FileChangeApprovalDecision,
}
```

### 与 CommandExecutionApprovalDecision 的对比

| 决策 | FileChangeApprovalDecision | CommandExecutionApprovalDecision |
|------|---------------------------|----------------------------------|
| 简单批准 | `accept` | `accept` |
| 会话级批准 | `acceptForSession` | `acceptForSession` |
| 带策略修正 | ❌ 不支持 | `acceptWithExecpolicyAmendment` |
| 网络策略 | ❌ 不支持 | `applyNetworkPolicyAmendment` |
| 拒绝（继续） | `decline` | `decline` |
| 拒绝（中断） | `cancel` | `cancel` |

**注意**：文件变更审批不支持 `acceptWithExecpolicyAmendment` 和 `applyNetworkPolicyAmendment`，因为文件变更不涉及命令执行策略或网络访问。

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5121-5125） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | FileChangeApprovalDecision 枚举（行 1204-1213） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 742-746） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 处理文件变更审批响应 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 聊天组件构造响应 |

---

## 依赖与外部交互

### 依赖类型

无外部 crate 依赖，仅使用标准库类型。

### 序列化特性

- 使用 `#[serde(rename_all = "camelCase")]` 确保 JSON 字段名为 camelCase
- 简单枚举使用字符串形式序列化

---

## 风险、边界与改进建议

### 已知风险

1. **功能简化**：相比命令执行审批，文件变更审批缺少策略修正功能，可能限制高级用例

2. **acceptForSession 语义**："相同文件"的定义不明确（是绝对路径匹配？还是相对于工作目录？）

### 边界情况

1. **部分批准**：当前不支持只批准部分文件变更（全有或全无）
2. **重命名/移动**：文件重命名或移动操作的审批语义未明确

### 改进建议

1. **细化 acceptForSession**：明确 "相同文件" 的匹配规则：
   ```rust
   pub enum FileChangeApprovalDecision {
       Accept,
       AcceptForSession {
           file_matching_strategy: FileMatchingStrategy,  // Exact, Basename, Directory
       },
       // ...
   }
   ```

2. **部分批准支持**：允许用户选择性地批准部分文件变更：
   ```rust
   pub struct FileChangeRequestApprovalResponse {
       pub decision: FileChangeApprovalDecision,
       pub approved_files: Option<Vec<PathBuf>>,  // 仅当 decision 为 PartialAccept 时使用
   }
   ```

3. **变更预览**：在审批请求中添加变更预览的引用，帮助用户做出决策

4. **与 v1 对比**：v1 的 `ApplyPatchApprovalResponse` 使用 `ReviewDecision`，v2 使用专门的 `FileChangeApprovalDecision`，这是设计上的改进
