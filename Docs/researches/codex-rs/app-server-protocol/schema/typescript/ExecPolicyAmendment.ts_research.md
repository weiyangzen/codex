# ExecPolicyAmendment Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ExecPolicyAmendment` 是 Codex 协议中用于**执行策略修正**的类型，表示一个提议的 execpolicy 变更，允许以特定命令前缀开头的命令自动执行而无需审批。

**典型使用场景：**
- 用户批准执行 `git status` 命令时，选择"始终允许以 `git` 开头的命令"
- Agent 建议添加命令前缀规则以简化未来类似命令的审批流程
- 用户通过 UI 批量批准某类命令

**职责：**
- 封装命令前缀规则的数据结构
- 作为 `ReviewDecision::ApprovedExecpolicyAmendment` 的 payload
- 用于生成 execpolicy 的 `prefix_rule(..., decision="allow")` 配置

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **简化重复审批**：允许用户一次性批准某类命令，避免重复审批
2. **策略持久化**：将用户的信任决策持久化为 execpolicy 规则
3. **安全边界控制**：通过命令前缀限制自动批准的范围
4. **用户意图表达**：精确表达"允许此类命令"的用户意图

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
/**
 * Proposed execpolicy change to allow commands starting with this prefix.
 *
 * The `command` tokens form the prefix that would be added as an execpolicy
 * `prefix_rule(..., decision="allow")`, letting the agent bypass approval for
 * commands that start with this token sequence.
 */
export type ExecPolicyAmendment = Array<string>;
```

### Rust 定义

```rust
/// Proposed execpolicy change to allow commands starting with this prefix.
///
/// The `command` tokens form the prefix that would be added as an execpolicy
/// `prefix_rule(..., decision="allow")`, letting the agent bypass approval for
/// commands that start with this token sequence.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(transparent)]
#[ts(type = "Array<string>")]
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,
}
```

### 实现细节

1. **透明序列化**：使用 `#[serde(transparent)]` 使结构体在序列化时表现为内部字段（`command` 数组）
2. **TypeScript 映射**：通过 `#[ts(type = "Array<string>")]` 指定 TypeScript 类型为字符串数组
3. **前缀匹配**：命令前缀按 token 匹配，例如 `["git", "status"]` 匹配 `git status` 但不匹配 `git commit`

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `command` | `string[]` | 命令前缀 token 数组 |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ExecPolicyAmendment.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs` (lines 34-60)

### 相关类型
- `ReviewDecision::ApprovedExecpolicyAmendment` - 使用此类型的决策变体
- `ExecApprovalRequestEvent::proposed_execpolicy_amendment` - 提议的策略修正

### 使用位置

1. **审批请求**：`ExecApprovalRequestEvent` 中作为 `proposed_execpolicy_amendment` 字段
2. **审批响应**：`ReviewDecision::ApprovedExecpolicyAmendment` 的 payload
3. **默认决策生成**：`ExecApprovalRequestEvent::default_available_decisions()` 方法

### 代码示例

```rust
// 创建 ExecPolicyAmendment
let amendment = ExecPolicyAmendment::new(vec!["git".to_string(), "status".to_string()]);

// 转换为 ReviewDecision
let decision = ReviewDecision::ApprovedExecpolicyAmendment {
    proposed_execpolicy_amendment: amendment,
};
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 core protocol 类型（在 `protocol` crate 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 与 `codex_execpolicy` crate 集成

### 与 ExecPolicy 的关系

`ExecPolicyAmendment` 最终会被转换为 execpolicy 的 `prefix_rule`：

```rust
// 伪代码示例
policy.add_prefix_rule(
    &amendment.command,  // ["git", "status"]
    Decision::Allow
)?;
```

### 外部交互

1. **服务器 → 客户端**：在 `ExecApprovalRequestEvent` 中作为提议的策略修正
2. **客户端 → 服务器**：在 `ReviewDecision::ApprovedExecpolicyAmendment` 中确认应用
3. **持久化**：服务器将批准的规则写入用户的 execpolicy 配置

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **前缀匹配粒度**：
   - `["git"]` 会匹配所有 git 命令（包括潜在危险的 `git push --force`）
   - `["git", "status"]` 只匹配 `git status`，不匹配 `git status --short`
   - 需要平衡便利性和安全性

2. **透明序列化的限制**：
   - 由于使用 `#[serde(transparent)]`，无法在 JSON 中添加额外元数据
   - 未来扩展可能需要破坏性变更

3. **策略冲突**：
   - 新规则可能与现有规则冲突
   - 需要明确的规则优先级定义

4. **撤销机制**：
   - 当前类型不支持撤销已添加的规则
   - 用户需要通过配置文件手动删除规则

### 改进建议

1. **添加元数据字段**：
   ```rust
   pub struct ExecPolicyAmendment {
       pub command: Vec<String>,
       pub description: Option<String>,  // 规则描述
       pub created_at: Option<DateTime>, // 创建时间
   }
   ```

2. **支持通配符**：
   - 考虑支持 `*` 通配符，例如 `["git", "status", "*"]` 匹配所有 git status 变体

3. **添加过期时间**：
   - 支持临时规则，例如"允许本次会话"或"允许 24 小时"

4. **规则预览**：
   - 在 UI 中显示"此规则将影响以下命令"的预览

5. **审计日志**：
   - 记录所有策略修正的添加和删除操作

### 测试建议
- 验证前缀匹配的边界情况
- 测试透明序列化的正确性
- 验证与 execpolicy 的集成
- 测试复杂命令（带引号、管道等）的前缀提取

### 安全考虑
- 过于宽泛的前缀（如 `["sudo"]` 或 `["rm"]`）可能导致安全风险
- UI 应对宽泛前缀提供警告
- 考虑添加前缀复杂度验证（最少 token 数）
