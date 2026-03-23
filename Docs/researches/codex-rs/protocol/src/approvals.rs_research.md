# approvals.rs 研究文档

## 场景与职责

`approvals.rs` 是 Codex 协议层中负责**审批流程**的核心模块，定义了所有与用户审批交互相关的数据结构和事件类型。该模块是 Codex 安全模型的关键组成部分，处理以下场景的审批请求：

1. **命令执行审批** - 沙箱逃逸、敏感命令执行前的用户确认
2. **网络访问审批** - 被阻止的网络请求的用户授权
3. **补丁应用审批** - 文件变更（增删改）的用户确认
4. **引导式输入请求 (Elicitation)** - MCP 工具需要额外用户输入时的交互
5. **Guardian 风险评估** - AI 辅助的安全审查流程

在 Codex 架构中，该模块位于协议层，被 `core` 和 `TUI` 层共同依赖：
- `core` 层生成审批请求事件
- `TUI` 层渲染审批界面并收集用户决策
- `protocol.rs` 重新导出主要类型供外部使用

## 功能点目的

### 1. 权限相关结构

#### `Permissions` / `EscalationPermissions`
定义命令执行所需的权限集合：
- `SandboxPolicy` - 沙箱策略
- `FileSystemSandboxPolicy` - 文件系统访问策略
- `NetworkSandboxPolicy` - 网络访问策略
- `MacOsSeatbeltProfileExtensions` - macOS Seatbelt 扩展配置

#### `ExecPolicyAmendment`
允许用户批准一类命令（前缀匹配），避免重复审批：
```rust
pub struct ExecPolicyAmendment {
    pub command: Vec<String>, // 命令前缀令牌序列
}
```

### 2. 网络审批类型

#### `NetworkApprovalProtocol`
支持的网络协议类型：
- `Http` / `Https` - HTTP/HTTPS 代理
- `Socks5Tcp` / `Socks5Udp` - SOCKS5 代理

#### `NetworkApprovalContext`
网络审批的上下文信息：
```rust
pub struct NetworkApprovalContext {
    pub host: String,                  // 目标主机
    pub protocol: NetworkApprovalProtocol, // 使用的协议
}
```

#### `NetworkPolicyAmendment`
网络策略修正，用于持久化允许/拒绝规则：
```rust
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction, // Allow / Deny
}
```

### 3. Guardian 风险评估

#### `GuardianAssessmentEvent`
AI 辅助安全审查的事件结构：
- `id` - 评估生命周期标识符
- `turn_id` - 所属对话轮次
- `status` - 评估状态（InProgress/Approved/Denied/Aborted）
- `risk_score` - 0-100 的风险分数
- `risk_level` - 风险等级（Low/Medium/High）
- `rationale` - 评估理由说明
- `action` - 被审查的操作详情

### 4. 执行审批请求

#### `ExecApprovalRequestEvent`
命令执行前向用户发起的审批请求：
```rust
pub struct ExecApprovalRequestEvent {
    pub call_id: String,                    // 关联的命令执行项 ID
    pub approval_id: Option<String>,        // 子命令审批标识（execve 拦截场景）
    pub turn_id: String,                    // 所属对话轮次
    pub command: Vec<String>,               // 待执行的命令
    pub cwd: PathBuf,                       // 工作目录
    pub reason: Option<String>,             // 审批原因（如重试无沙箱）
    pub network_approval_context: Option<NetworkApprovalContext>, // 网络上下文
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>, // 建议的策略修正
    pub proposed_network_policy_amendments: Option<Vec<NetworkPolicyAmendment>>, // 网络策略修正
    pub additional_permissions: Option<PermissionProfile>, // 额外权限请求
    pub skill_metadata: Option<ExecApprovalRequestSkillMetadata>, // Skill 触发元数据
    pub available_decisions: Option<Vec<ReviewDecision>>, // 可用决策选项
    pub parsed_cmd: Vec<ParsedCommand>,     // 解析后的命令结构
}
```

**关键方法：**
- `effective_approval_id()` - 获取有效的审批 ID（优先使用 approval_id，回退到 call_id）
- `effective_available_decisions()` - 获取可用的决策选项（支持向后兼容的默认值逻辑）

### 5. 引导式输入请求 (Elicitation)

#### `ElicitationRequest`
MCP 工具需要额外用户输入时的请求类型：
```rust
pub enum ElicitationRequest {
    Form {
        meta: Option<JsonValue>,        // 元数据
        message: String,                // 提示消息
        requested_schema: JsonValue,    // 请求的输入结构（JSON Schema）
    },
    Url {
        meta: Option<JsonValue>,
        message: String,
        url: String,                    // 外部 URL（如 OAuth 授权页）
        elicitation_id: String,         // 请求标识
    },
}
```

#### `ElicitationRequestEvent`
包装 elicitation 请求的事件结构，包含服务器名称和请求 ID。

#### `ElicitationAction`
用户对 elicitation 的响应动作：
- `Accept` - 接受
- `Decline` - 拒绝
- `Cancel` - 取消

### 6. 补丁应用审批

#### `ApplyPatchApprovalRequestEvent`
文件变更（代码补丁）的审批请求：
```rust
pub struct ApplyPatchApprovalRequestEvent {
    pub call_id: String,                                    // Responses API 调用 ID
    pub turn_id: String,                                    // 所属对话轮次
    pub changes: HashMap<PathBuf, FileChange>,             // 文件路径 -> 变更内容
    pub reason: Option<String>,                             // 额外说明（如请求写权限）
    pub grant_root: Option<PathBuf>,                        // 请求授权的根目录
}
```

## 具体技术实现

### 决策选项生成逻辑

`ExecApprovalRequestEvent::default_available_decisions()` 实现了复杂的决策选项生成逻辑：

```rust
pub fn default_available_decisions(...) -> Vec<ReviewDecision> {
    if network_approval_context.is_some() {
        // 网络审批场景：Approve, ApproveForSession, NetworkPolicyAmendment, Abort
    }
    if additional_permissions.is_some() {
        // 额外权限场景：Approve, Abort
    }
    // 默认场景：Approve, ApprovedExecpolicyAmendment (if applicable), Abort
}
```

### 向后兼容处理

多个字段使用 `#[serde(default)]` 确保新旧版本兼容：
- `turn_id` - 旧版本可能不包含此字段
- `available_decisions` - 旧发送方可能不填充，使用遗留逻辑回退

### 序列化约定

- 枚举使用 `snake_case` 命名
- 可选字段使用 `Option<T>` + `#[ts(optional)]`
- 敏感字段使用 `skip_serializing_if` 条件序列化

## 关键代码路径与文件引用

### 本文件位置
```
codex-rs/protocol/src/approvals.rs
```

### 导入依赖
```rust
use crate::mcp::RequestId;
use crate::models::MacOsSeatbeltProfileExtensions;
use crate::models::PermissionProfile;
use crate::parse_command::ParsedCommand;
use crate::permissions::FileSystemSandboxPolicy;
use crate::permissions::NetworkSandboxPolicy;
use crate::protocol::FileChange;
use crate::protocol::ReviewDecision;
use crate::protocol::SandboxPolicy;
```

### 导出位置
在 `protocol.rs` 中重新导出：
```rust
pub use crate::approvals::ApplyPatchApprovalRequestEvent;
pub use crate::approvals::ElicitationAction;
pub use crate::approvals::ExecApprovalRequestEvent;
// ... 其他类型
```

### 跨 crate 使用
- `codex-core`: 生成审批请求、处理用户响应
- `codex-tui`: 渲染审批 UI、收集用户决策
- `codex-tui-app-server`: 协议转发

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 值类型 |
| `ts-rs` | TypeScript 类型绑定 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `mcp::RequestId` | Elicitation 请求标识 |
| `models` | PermissionProfile, MacOsSeatbeltProfileExtensions |
| `parse_command::ParsedCommand` | 命令解析结果 |
| `permissions` | 沙箱策略类型 |
| `protocol` | FileChange, ReviewDecision, SandboxPolicy |

## 风险、边界与改进建议

### 当前风险

1. **复杂决策逻辑**: `default_available_decisions()` 逻辑复杂，测试覆盖需要确保所有分支
2. **向后兼容负担**: 多个 `#[serde(default)]` 字段增加了维护复杂度
3. **类型耦合**: `ExecApprovalRequestEvent` 包含大量可选字段，可能导致使用时的空值检查遗漏

### 边界情况

1. **approval_id 回退**: 当 `approval_id` 为 None 时，使用 `call_id` 作为回退
2. **available_decisions 为空**: 需要正确处理空决策列表的情况
3. **network_approval_context 与 additional_permissions 同时存在**: 当前实现优先处理网络审批

### 改进建议

1. **Builder 模式**: 为 `ExecApprovalRequestEvent` 添加 Builder 模式，减少构造时的参数混乱
   ```rust
   let request = ExecApprovalRequestEvent::builder()
       .call_id("call-123")
       .command(vec!["git", "status"])
       .build();
   ```

2. **决策逻辑重构**: 将决策选项生成逻辑抽取为独立的策略模式，便于测试和扩展

3. **类型安全增强**: 考虑使用类型状态模式确保必要字段在编译期被填充

4. **文档完善**: 为复杂字段添加更多使用示例和边界情况说明

5. **验证逻辑**: 添加审批请求的结构验证，确保必要字段组合有效

### 测试建议

当前文件无内嵌测试，建议添加：
- 决策选项生成的边界测试
- 序列化/反序列化兼容性测试
- `effective_approval_id()` 回退逻辑测试
- 复杂字段组合的验证测试
