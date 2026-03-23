# exec_policy.rs 深度研究文档

## 场景与职责

`exec_policy.rs` 是 Codex 核心测试套件中负责验证**执行策略（Exec Policy）**系统的集成测试文件。执行策略是 Codex 的安全机制，用于：

1. **命令过滤**：基于预定义规则允许或阻止特定命令执行
2. **审批策略集成**：与 `AskForApproval` 配置协同工作，决定何时需要用户确认
3. **协作模式兼容**：确保执行策略在协作模式（Collaboration Mode）下正常工作

该测试文件验证了 Codex 的**命令级安全控制**，防止 AI 执行潜在危险的操作。

## 功能点目的

### 1. 策略规则阻止命令
- **目的**：验证策略规则能够阻止匹配的命令
- **示例**：禁止以 `echo` 开头的命令

### 2. 空命令处理
- **目的**：确保空命令或仅包含空白字符的命令不会导致 panic
- **场景**：协作模式下模型可能生成空命令

### 3. 统一执行工具兼容性
- **目的**：验证执行策略在统一执行（Unified Exec）工具下同样有效
- **区别**：`shell_command` vs `exec_command`

## 具体技术实现

### 执行策略架构

```rust
// codex-rs/core/src/exec_policy.rs
pub(crate) struct ExecPolicyManager {
    policy: ArcSwap<Policy>,           // 原子交换的策略
    update_lock: tokio::sync::Mutex<()>, // 更新锁
}

pub(crate) struct ExecApprovalRequest<'a> {
    pub(crate) command: &'a [String],
    pub(crate) approval_policy: AskForApproval,
    pub(crate) sandbox_policy: &'a SandboxPolicy,
    pub(crate) file_system_sandbox_policy: &'a FileSystemSandboxPolicy,
}
```

### 策略规则定义

```rust
// codex-execpolicy crate
pub struct Policy {
    rules: Vec<Rule>,
}

pub enum Rule {
    PrefixRule { pattern: Vec<String>, decision: Decision },
    HeuristicsRule { ... },
    NetworkRule { ... },
}

pub enum Decision {
    Allow,
    Forbidden,
    Prompt,
}
```

### 策略评估流程

```rust
pub(crate) async fn evaluate(&self, request: ExecApprovalRequest<'_>) -> ExecEvaluation {
    // 1. 解析命令
    let parsed = parse_shell_lc_plain_commands(&command_string);
    
    // 2. 评估每条规则
    for rule in &self.policy.load().rules {
        match rule.evaluate(&parsed) {
            RuleMatch::PrefixRuleMatch { decision, .. } => {
                return ExecEvaluation::from_decision(decision, ...);
            }
            _ => continue,
        }
    }
    
    // 3. 无匹配规则，根据审批策略决定
    ExecEvaluation::from_decision(Decision::Prompt, ...)
}
```

### 审批策略冲突处理

```rust
pub(crate) fn prompt_is_rejected_by_policy(
    approval_policy: AskForApproval,
    prompt_is_rule: bool,
) -> Option<&'static str> {
    match approval_policy {
        AskForApproval::Never => Some("approval required by policy, but AskForApproval is set to Never"),
        AskForApproval::Granular(granular_config) => {
            if prompt_is_rule && !granular_config.allows_rules_approval() {
                Some("approval required by policy rule, but AskForApproval::Granular.rules is false")
            } else if !prompt_is_rule && !granular_config.allows_sandbox_approval() {
                Some("approval required by policy, but AskForApproval::Granular.sandbox_approval is false")
            } else {
                None
            }
        }
        _ => None,  // OnFailure, OnRequest, UnlessTrusted 允许提示
    }
}
```

### 策略文件格式

```
# policy.rules 文件示例
prefix_rule(pattern=["echo"], decision="forbidden")
prefix_rule(pattern=["rm", "-rf", "/"], decision="forbidden")
prefix_rule(pattern=["git", "status"], decision="allow")
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/exec_policy.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/exec_policy.rs` - 执行策略管理器
  - `ExecPolicyManager` - 策略管理器
  - `ExecApprovalRequest` - 审批请求
  - `prompt_is_rejected_by_policy` - 策略冲突检测

- `codex-rs/execpolicy/src/` - 策略引擎（独立 crate）
  - `Policy` - 策略定义
  - `Rule` - 规则类型
  - `Decision` - 决策枚举
  - `PolicyParser` - 策略文件解析

- `codex-rs/core/src/bash.rs` - Shell 命令解析
  - `parse_shell_lc_plain_commands` - 解析 shell 命令
  - `parse_shell_lc_single_command_prefix` - 提取命令前缀

### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `AskForApproval` - 审批策略枚举
  - `SandboxPolicy` - 沙箱策略

- `codex-rs/protocol/src/config_types.rs`
  - `CollaborationMode` - 协作模式
  - `ModeKind` - 模式类型

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_execpolicy` | 策略引擎 |
| `codex_core::bash` | Shell 命令解析 |
| `codex_core::features` | 特性标志（UnifiedExec, CollaborationModes）|
| `core_test_support` | 测试基础设施 |

### 测试基础设施
```rust
// 提交用户回合的辅助函数
async fn submit_user_turn(
    test: &TestCodex,
    prompt: &str,
    approval_policy: AskForApproval,
    sandbox_policy: SandboxPolicy,
    collaboration_mode: Option<CollaborationMode>,
) -> Result<()> {
    test.codex.submit(Op::UserTurn {
        items: vec![UserInput::Text { ... }],
        approval_policy,
        sandbox_policy,
        collaboration_mode,
        ...
    }).await
}
```

### 特性标志
```rust
// 启用协作模式
config.features.enable(Feature::CollaborationModes);

// 启用统一执行
config.features.enable(Feature::UnifiedExec);
```

## 风险、边界与改进建议

### 已知风险

1. **命令解析限制**
   - 当前不支持 PowerShell 命令解析
   - 代码注释：`TODO execpolicy doesn't parse powershell commands yet`

2. **空命令 panic 风险**
   - 历史问题：空命令在协作模式下导致 panic
   - 修复：添加空命令检查测试

3. **规则匹配粒度**
   - PrefixRule 只能匹配命令前缀
   - 复杂条件（如参数组合）难以表达

### 边界情况

1. **空命令/空白命令**
   ```rust
   // 测试用例
   let args = json!({"command": "", "timeout_ms": 1_000});
   let args = json!({"command": "  \n\t  ", "timeout_ms": 1_000});
   ```

2. **审批策略冲突**
   - `AskForApproval::Never` + 策略要求审批 = 错误
   - `AskForApproval::Granular` + 规则禁用 = 错误

3. **协作模式下的模型切换**
   ```rust
   fn collaboration_mode_for_model(model: String) -> CollaborationMode {
       CollaborationMode {
           mode: ModeKind::Default,
           settings: Settings {
               model,
               reasoning_effort: None,
               developer_instructions: Some("exercise approvals...".to_string()),
           },
       }
   }
   ```

### 改进建议

1. **命令解析增强**
   - 支持 PowerShell 命令解析
   - 支持管道和重定向分析

2. **规则类型扩展**
   - 添加正则表达式规则
   - 添加参数值匹配规则
   - 添加文件路径敏感规则

3. **策略动态更新**
   - 支持运行时策略热更新
   - 添加策略版本控制

4. **审计日志**
   - 记录所有策略决策
   - 提供策略命中分析

5. **用户体验**
   - 策略阻止时提供更清晰的解释
   - 建议替代命令

6. **测试覆盖**
   - 添加并发策略评估测试
   - 添加复杂命令链测试
   - 添加策略性能基准测试
