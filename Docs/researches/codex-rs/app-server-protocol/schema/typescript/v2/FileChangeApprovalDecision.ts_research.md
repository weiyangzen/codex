# FileChangeApprovalDecision.ts 研究文档

## 场景与职责

`FileChangeApprovalDecision.ts` 定义了文件变更审批决策枚举，用于表示用户对文件变更（如代码补丁应用）的审批决定。这是 Codex 审批工作流的核心类型，控制文件修改的自动应用或人工确认。

该类型在文件变更审批、安全控制、批量操作等场景中发挥关键作用。

## 功能点目的

1. **审批控制**: 控制文件变更是否应用
2. **会话记忆**: 支持"本次会话记住"的便捷选项
3. **取消操作**: 允许中断当前操作

## 具体技术实现

### 数据结构定义

```typescript
export type FileChangeApprovalDecision = 
  | "accept"           // 接受变更
  | "acceptForSession" // 接受变更并记住选择（本次会话）
  | "decline"          // 拒绝变更（继续回合）
  | "cancel";          // 取消变更（中断回合）
```

### 决策说明

| 决策 | 值 | 说明 |
|------|------|------|
| 接受 | `"accept"` | 接受当前文件变更，应用补丁 |
| 会话接受 | `"acceptForSession"` | 接受变更并记住选择，同一会话中相同文件的变更自动应用 |
| 拒绝 | `"decline"` | 拒绝当前变更，回合继续但不应用此变更 |
| 取消 | `"cancel"` | 取消当前变更，立即中断回合 |

### 使用示例

```typescript
// 处理文件变更审批
function handleFileChangeApproval(change: FileChange): Promise<FileChangeApprovalDecision> {
  return showApprovalDialog({
    title: '文件变更确认',
    content: change.diff,
    buttons: [
      { label: '接受', value: 'accept', primary: true },
      { label: '接受并记住', value: 'acceptForSession' },
      { label: '拒绝', value: 'decline' },
      { label: '取消', value: 'cancel' }
    ]
  });
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1201-1213)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
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
```

### 请求参数

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub struct FileChangeRequestApprovalParams {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub reason: Option<String>,
    pub grant_root: Option<String>,
}
```

### 相关枚举

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 962-984)

```rust
pub enum CommandExecutionApprovalDecision {
    Accept,
    AcceptForSession,
    AcceptWithExecpolicyAmendment { execpolicy_amendment: ExecPolicyAmendment },
    ApplyNetworkPolicyAmendment { network_policy_amendment: NetworkPolicyAmendment },
    Decline,
    Cancel,
}
```

### 补丁应用状态

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
pub enum PatchApplyStatus {
    InProgress,
    Completed,
    Failed,
    Declined,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化（camelCase 命名） |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 审批界面**: 显示文件变更审批对话框
- **VS Code 扩展**: 集成文件变更确认
- **审批缓存**: 管理 `acceptForSession` 的会话级缓存

## 风险、边界与改进建议

### 已知风险

1. **会话边界**: `acceptForSession` 的会话定义可能不明确
2. **误操作**: 批量变更时可能误接受不希望的修改
3. **撤销困难**: 接受后撤销需要手动操作

### 边界情况

1. **文件冲突**: 变更可能与磁盘上的文件冲突
2. **权限问题**: 可能无权限修改某些文件
3. **大文件**: 大文件的 diff 展示可能有问题

### 改进建议

1. **粒度控制**: 支持按目录或文件类型设置审批策略
2. **预览模式**: 提供变更预览，支持选择性接受部分变更
3. **撤销支持**: 提供快速撤销已应用变更的功能
4. **差异对比**: 改进 diff 展示，支持语法高亮
5. **批量操作**: 支持一次性审批多个相关变更
6. **时间限制**: 为审批设置超时，超时后自动拒绝

### 扩展示例

```typescript
export type FileChangeApprovalDecision = 
  | { type: "accept"; files: string[] }  // 选择性接受
  | { type: "acceptForSession"; scope: "file" | "directory" | "extension" }
  | { type: "decline"; reason?: string }
  | { type: "cancel" }
  | { type: "preview" };  // 请求更多预览信息
```
