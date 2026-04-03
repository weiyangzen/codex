# FileChangeRequestApprovalParams.ts 研究文档

## 场景与职责

`FileChangeRequestApprovalParams.ts` 定义了文件变更审批请求的参数类型，用于服务器向客户端请求对文件变更的审批。这是 Codex 安全审批流程的核心部分，确保用户对文件修改有完全的控制权。

该类型在文件修改审批、安全控制、权限提升等场景中发挥关键作用。

## 功能点目的

1. **审批请求**: 请求用户确认文件变更
2. **上下文提供**: 提供变更的原因和上下文
3. **权限请求**: 支持请求额外的写入权限

## 具体技术实现

### 数据结构定义

```typescript
export type FileChangeRequestApprovalParams = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  /**
   * Optional explanatory reason (e.g. request for extra write access).
   */
  reason?: string | null, 
  /**
   * [UNSTABLE] When set, the agent is asking the user to allow writes under this root
   * for the remainder of the session (unclear if this is honored today).
   */
  grantRoot?: string | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 所属线程 ID |
| `turnId` | `string` | 所属回合 ID |
| `itemId` | `string` | 文件变更项 ID |
| `reason` | `string \| null` | 请求审批的原因说明（如需要额外写入权限） |
| `grantRoot` | `string \| null` | [不稳定] 请求允许在指定根目录下写入（会话期间） |

### 使用示例

```typescript
// 处理文件变更审批请求
client.onRequest('fileChange/requestApproval', (params: FileChangeRequestApprovalParams) => {
  const { threadId, turnId, itemId, reason, grantRoot } = params;
  
  // 显示审批对话框
  return showApprovalDialog({
    title: '文件变更审批',
    message: reason || '请求修改文件',
    extraAccess: grantRoot ? `请求访问: ${grantRoot}` : undefined,
    onApprove: () => ({ decision: 'accept' }),
    onDecline: () => ({ decision: 'decline' })
  });
});
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
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
    pub grant_root: Option<String>,
}
```

### 审批决策

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1201-1213)

```rust
pub enum FileChangeApprovalDecision {
    Accept,
    AcceptForSession,
    Decline,
    Cancel,
}
```

### 文件变更项

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4176-4180)

```rust
FileChange {
    id: String,
    changes: Vec<FileUpdateChange>,
    status: PatchApplyStatus,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 审批界面**: 显示文件变更审批对话框
- **VS Code 扩展**: 集成审批流程
- **权限系统**: 处理 `grantRoot` 权限请求

## 风险、边界与改进建议

### 已知风险

1. **grantRoot 不稳定**: `grantRoot` 字段标记为不稳定，行为可能变化
2. **原因缺失**: `reason` 可能为 null，用户不了解审批原因
3. **权限提升**: 自动权限提升可能存在安全风险

### 边界情况

1. **超时处理**: 审批请求可能超时
2. **并发审批**: 多个文件同时请求审批
3. **会话结束**: 会话结束时 `grantRoot` 权限的处理

### 改进建议

1. **稳定 grantRoot**: 稳定化 `grantRoot` 功能或移除
2. **详细上下文**: 增加变更的详细 diff 信息
3. **批量审批**: 支持一次性审批多个相关变更
4. **权限细化**: 支持更细粒度的权限控制
5. **审批历史**: 记录审批决策历史
6. **自动规则**: 支持用户设置自动审批规则

### 扩展示例

```typescript
export type FileChangeRequestApprovalParams = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  reason?: string | null,
  grantRoot?: string | null,
  // 新增字段
  changes: FileChange[],  // 详细的变更列表
  riskLevel: 'low' | 'medium' | 'high',  // 风险等级
  estimatedImpact: {  // 估计影响
    filesModified: number;
    linesChanged: number;
  },
};
```
