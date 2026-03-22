# ReviewDecision.ts 研究文档

## 1. 场景与职责

ReviewDecision 类型在 Codex 系统中用于表示用户对执行审批请求的决策。它在以下场景中发挥关键作用：

- **命令执行审批**: 用户批准或拒绝 AI 提出的 shell 命令执行
- **代码补丁审批**: 用户批准或拒绝文件修改操作
- **权限升级**: 用户批准临时或会话级别的权限提升
- **网络策略修改**: 用户批准网络访问规则的修改

## 2. 功能点目的

ReviewDecision 是一个灵活的决策类型，支持多种审批场景：

1. **简单批准**: `"approved"` - 单次批准当前请求
2. **策略修改批准**: 批准并修改执行策略（ExecPolicyAmendment）
3. **会话级批准**: `"approved_for_session"` - 批准当前及后续类似请求
4. **网络策略批准**: 批准并修改网络访问策略
5. **拒绝**: `"denied"` - 拒绝当前请求
6. **中止**: `"abort"` - 中止整个会话/任务

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ReviewDecision = 
  | "approved" 
  | { "approved_execpolicy_amendment": { proposed_execpolicy_amendment: ExecPolicyAmendment } } 
  | "approved_for_session" 
  | { "network_policy_amendment": { network_policy_amendment: NetworkPolicyAmendment } } 
  | "denied" 
  | "abort";
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` (lines 355-373, 以及相关类型定义)：

```rust
// ExecApproval 操作中的使用
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema)]
pub struct ExecApproval {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    pub decision: ReviewDecision,
}

// ReviewDecision 枚举定义
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum ReviewDecision {
    Approved,
    ApprovedExecpolicyAmendment { proposed_execpolicy_amendment: ExecPolicyAmendment },
    ApprovedForSession,
    NetworkPolicyAmendment { network_policy_amendment: NetworkPolicyAmendment },
    Denied,
    Abort,
}
```

### 相关类型

**ExecPolicyAmendment** (位于 approvals 模块):
```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
pub struct ExecPolicyAmendment {
    pub allowed_prefix: Vec<String>,
    pub duration: AmendmentDuration,
}
```

**NetworkPolicyAmendment**:
```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
pub struct NetworkPolicyAmendment {
    pub allowed_domains: Vec<String>,
    pub duration: AmendmentDuration,
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` | ReviewDecision 使用和上下文 (lines 355-373) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs` | ExecPolicyAmendment 和 NetworkPolicyAmendment 定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` | ApplyPatchApprovalResponse 和 ExecCommandApprovalResponse (lines 137-161) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ReviewDecision.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化，使用 snake_case 命名
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成

### 外部交互

- **审批系统**: 与 Guardian 审批子系统集成
- **执行策略**: 与 codex_execpolicy crate 交互修改执行策略
- **网络策略**: 与网络访问控制系统交互
- **会话管理**: 会话级批准影响后续请求的审批流程

## 6. 风险、边界与改进建议

### 风险

1. **策略冲突**: 多个策略修改可能产生冲突，需要明确的优先级规则
2. **持续时间管理**: AmendmentDuration 的处理需要精确的计时机制
3. **序列化兼容性**: 复杂的嵌套结构在不同版本间的兼容性

### 边界情况

1. **空策略**: ExecPolicyAmendment 的 allowed_prefix 为空时的行为
2. **过期策略**: 策略修改过期后的回退行为
3. **并发审批**: 多个并发请求的审批决策处理
4. **嵌套批准**: 批准一个已经批准的操作

### 改进建议

1. **审批历史**: 添加审批历史记录，便于审计和回溯
2. **策略预览**: 在批准前展示策略修改的具体影响
3. **批量审批**: 支持批量处理多个相似的审批请求
4. **自动批准规则**: 基于风险评估的自动批准机制
5. **撤销机制**: 支持撤销已批准的决策
6. **审批超时**: 添加审批超时处理，避免无限等待
7. **UI 优化**: 为不同类型的决策提供差异化的 UI 展示
