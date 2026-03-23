# 研究报告: `codex-rs/core/tests/suite/approvals.rs`

## 1. 场景与职责

### 1.1 文件定位

`approvals.rs` 是 Codex Rust 核心测试套件中的关键集成测试文件，位于 `codex-rs/core/tests/suite/` 目录下。该文件专门测试**命令执行审批流程**（Approval Flow），验证 Codex 在不同沙箱策略和审批策略组合下的行为是否符合预期。

### 1.2 核心职责

该测试文件承担以下核心职责：

1. **审批策略矩阵测试**: 验证 `AskForApproval` 枚举（`OnRequest`, `UnlessTrusted`, `OnFailure`, `Never`）与不同 `SandboxPolicy` 组合的行为
2. **沙箱策略验证**: 测试 `DangerFullAccess`, `ReadOnly`, `WorkspaceWrite` 等沙箱策略对命令执行的影响
3. **补丁应用审批**: 测试 `apply_patch` 工具在文件系统边界外的审批流程
4. **执行策略修正**: 验证 `ExecPolicyAmendment` 机制，包括前缀规则的持久化和传播
5. **网络策略修正**: 测试 `NetworkPolicyAmendment` 对网络访问控制的影响
6. **子代理权限传播**: 验证子代理（subagent）的 execpolicy 修正如何传播到父会话

### 1.3 测试架构角色

```
codex-rs/core/tests/
├── common/                    # 测试基础设施
│   ├── lib.rs                 # 测试工具库（wait_for_event, skip_if_no_network 等）
│   ├── test_codex.rs          # TestCodex 构建器和测试环境
│   ├── responses.rs           # Mock SSE 响应服务器
│   └── zsh_fork.rs            # Zsh Fork 测试运行时
├── suite/
│   ├── mod.rs                 # 测试模块聚合（包含 approvals 模块声明）
│   ├── approvals.rs           # <-- 本文件：审批流程集成测试
│   ├── exec_policy.rs         # 执行策略规则测试
│   ├── seatbelt.rs            # macOS Seatbelt 沙箱测试
│   └── ...
└── all.rs                     # 测试入口
```

---

## 2. 功能点目的

### 2.1 主要测试功能

| 功能类别 | 测试目的 | 关键测试场景 |
|---------|---------|-------------|
| **审批策略** | 验证不同审批策略下命令是否触发用户确认 | `OnRequest`, `UnlessTrusted`, `OnFailure`, `Never` |
| **沙箱边界** | 验证文件系统访问控制 | 工作区内/外写入、只读策略、网络访问 |
| **补丁审批** | 验证代码补丁应用的审批流程 | 工作区内/外补丁、shell vs function 调用 |
| **策略持久化** | 验证用户审批决策的持久化 | `ApprovedForSession`, `ApprovedExecpolicyAmendment` |
| **网络策略** | 验证网络访问审批和拒绝 | `NetworkPolicyAmendment` 的 allow/deny |
| **子代理** | 验证权限在代理层级间的传播 | 子代理 execpolicy 修正传播到父会话 |

### 2.2 场景规格定义（ScenarioSpec）

测试使用 `ScenarioSpec` 结构体定义测试用例：

```rust
struct ScenarioSpec {
    name: &'static str,                    // 测试用例名称
    approval_policy: AskForApproval,       // 审批策略
    sandbox_policy: SandboxPolicy,         // 沙箱策略
    action: ActionKind,                    // 执行动作
    sandbox_permissions: SandboxPermissions, // 沙箱权限
    features: Vec<Feature>,                // 需要启用的特性
    model_override: Option<&'static str>,  // 模型覆盖
    outcome: Outcome,                      // 预期结果
    expectation: Expectation,              // 验证期望
}
```

### 2.3 动作类型（ActionKind）

| 动作 | 描述 | 用途 |
|-----|------|-----|
| `WriteFile` | 通过 Python 脚本写入文件 | 测试文件系统写入权限 |
| `FetchUrl` | 通过 urllib 发起 HTTP 请求 | 测试网络访问控制 |
| `FetchUrlNoProxy` | 无代理的 HTTP 请求 | 测试直接网络访问 |
| `RunCommand` | 执行 shell 命令 | 测试命令执行审批 |
| `RunUnifiedExecCommand` | 执行统一执行命令 | 测试 UnifiedExec 特性 |
| `ApplyPatchFunction` | 通过函数调用应用补丁 | 测试补丁审批 |
| `ApplyPatchShell` | 通过 shell 命令应用补丁 | 测试 shell 方式补丁 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 审批决策（ReviewDecision）

```rust
// 定义于: codex-rs/protocol/src/protocol.rs:3086
pub enum ReviewDecision {
    Approved,                           // 批准执行
    ApprovedExecpolicyAmendment {       // 批准并添加前缀规则
        proposed_execpolicy_amendment: ExecPolicyAmendment,
    },
    ApprovedForSession,                 // 批准并缓存到会话
    NetworkPolicyAmendment {            // 网络策略修正
        network_policy_amendment: NetworkPolicyAmendment,
    },
    Denied,                             // 拒绝（默认）
    Abort,                              // 中止会话
}
```

#### 3.1.2 执行策略修正（ExecPolicyAmendment）

```rust
// 定义于: codex-rs/protocol/src/approvals.rs:39
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,  // 前缀规则命令序列
}
```

#### 3.1.3 网络策略修正（NetworkPolicyAmendment）

```rust
// 定义于: codex-rs/protocol/src/approvals.rs:105
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,  // Allow 或 Deny
}
```

#### 3.1.4 执行审批请求事件（ExecApprovalRequestEvent）

```rust
// 定义于: codex-rs/protocol/src/approvals.rs:147
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub approval_id: Option<String>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub network_approval_context: Option<NetworkApprovalContext>,
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    pub proposed_network_policy_amendments: Option<Vec<NetworkPolicyAmendment>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub skill_metadata: Option<ExecApprovalRequestSkillMetadata>,
    pub available_decisions: Option<Vec<ReviewDecision>>,
    pub parsed_cmd: Vec<ParsedCommand>,
}
```

### 3.2 关键流程

#### 3.2.1 场景测试主流程（`run_scenario`）

```rust
async fn run_scenario(scenario: &ScenarioSpec) -> Result<()> {
    // 1. 启动 Mock SSE 服务器
    let server = start_mock_server().await;
    
    // 2. 构建测试配置
    let mut builder = test_codex()
        .with_model(model)
        .with_config(|config| {
            config.permissions.approval_policy = Constrained::allow_any(approval_policy);
            config.permissions.sandbox_policy = Constrained::allow_any(sandbox_policy);
        });
    let test = builder.build(&server).await?;
    
    // 3. 准备动作事件
    let (event, expected_command) = scenario.action.prepare(&test, &server, call_id, ...).await?;
    
    // 4. 挂载 Mock SSE 响应
    let _ = mount_sse_once(&server, sse(vec![...])).await;
    
    // 5. 提交用户回合
    submit_turn(&test, scenario.name, scenario.approval_policy, scenario.sandbox_policy).await?;
    
    // 6. 根据预期结果处理审批
    match &scenario.outcome {
        Outcome::Auto => wait_for_completion_without_approval(&test).await,
        Outcome::ExecApproval { decision, .. } => {
            let approval = expect_exec_approval(&test, command).await;
            test.codex.submit(Op::ExecApproval { id, decision }).await?;
        }
        Outcome::PatchApproval { decision, .. } => {
            let approval = expect_patch_approval(&test, call_id).await;
            test.codex.submit(Op::PatchApproval { id, decision }).await?;
        }
    }
    
    // 7. 验证结果
    scenario.expectation.verify(&test, &result)?;
}
```

#### 3.2.2 审批请求等待流程

```rust
async fn expect_exec_approval(
    test: &TestCodex,
    expected_command: &str,
) -> ExecApprovalRequestEvent {
    let event = wait_for_event(&test.codex, |event| {
        matches!(event, 
            EventMsg::ExecApprovalRequest(_) | EventMsg::TurnComplete(_)
        )
    }).await;
    
    match event {
        EventMsg::ExecApprovalRequest(approval) => {
            assert_eq!(approval.command.last(), Some(expected_command));
            approval
        }
        EventMsg::TurnComplete(_) => panic!("expected approval request before completion"),
        other => panic!("unexpected event: {other:?}"),
    }
}
```

### 3.3 协议与命令

#### 3.3.1 用户回合提交（Op::UserTurn）

```rust
Op::UserTurn {
    items: Vec<UserInput>,           // 用户输入项
    final_output_json_schema: None,
    cwd: PathBuf,                    // 工作目录
    approval_policy: AskForApproval, // 审批策略
    sandbox_policy: SandboxPolicy,   // 沙箱策略
    model: String,                   // 模型标识
    effort: None,
    summary: None,
    service_tier: None,
    collaboration_mode: None,
    personality: None,
}
```

#### 3.3.2 执行审批提交（Op::ExecApproval）

```rust
Op::ExecApproval {
    id: String,                      // 审批ID
    turn_id: Option<String>,         // 回合ID
    decision: ReviewDecision,        // 用户决策
}
```

#### 3.3.3 SSE 事件构造

```rust
// 函数调用事件
fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "function_call",
            "call_id": call_id,
            "name": name,
            "arguments": arguments
        }
    })
}

// 补丁函数调用事件
fn ev_apply_patch_function_call(call_id: &str, patch: &str) -> Value {
    let arguments = serde_json::json!({ "input": patch });
    // ...
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心依赖文件

| 文件路径 | 职责 | 关键导出 |
|---------|------|---------|
| `codex-rs/protocol/src/protocol.rs` | 协议定义 | `AskForApproval`, `SandboxPolicy`, `ReviewDecision`, `Op`, `EventMsg` |
| `codex-rs/protocol/src/approvals.rs` | 审批结构定义 | `ExecApprovalRequestEvent`, `ApplyPatchApprovalRequestEvent`, `ExecPolicyAmendment`, `NetworkPolicyAmendment` |
| `codex-rs/core/tests/common/test_codex.rs` | 测试构建器 | `TestCodex`, `TestCodexBuilder`, `test_codex()` |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应 | `start_mock_server()`, `mount_sse_once()`, `ev_function_call()`, `sse()` |
| `codex-rs/core/tests/common/lib.rs` | 测试工具 | `wait_for_event()`, `wait_for_event_with_timeout()`, `skip_if_no_network!` |
| `codex-rs/core/tests/common/zsh_fork.rs` | Zsh Fork 支持 | `zsh_fork_runtime()`, `build_zsh_fork_test()` |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱实现 | `SandboxManager`, `ExecRequest`, `SandboxTransformRequest` |

### 4.2 关键代码路径

```
approvals.rs 测试执行流程:
├── test_codex().with_config(...)     // 配置测试环境 (test_codex.rs)
│   └── Config {
│       permissions.approval_policy   // 设置审批策略
│       permissions.sandbox_policy    // 设置沙箱策略
│   }
├── builder.build(&server).await      // 构建测试实例
│   └── ThreadManager::start_thread() // 启动 Codex 线程
├── action.prepare(...)               // 准备 Mock 事件
│   └── shell_event() / exec_command_event()
├── mount_sse_once(...)               // 挂载 Mock SSE 响应 (responses.rs)
├── submit_turn(...)                  // 提交用户回合
│   └── codex.submit(Op::UserTurn {..})
├── expect_exec_approval(...)         // 等待审批请求事件
│   └── wait_for_event(...)           // 等待 EventMsg::ExecApprovalRequest
├── test.codex.submit(Op::ExecApproval {..}) // 提交审批决策
└── scenario.expectation.verify(...)  // 验证执行结果
```

### 4.3 场景矩阵覆盖

测试文件定义了约 **60+** 个测试场景，覆盖：

1. **DangerFullAccess 策略** × 4 种审批策略 × 2 种模型（gpt-5, gpt-5.1）
2. **ReadOnly 策略** × 读写/网络操作 × 审批决策
3. **WorkspaceWrite 策略** × 工作区内/外操作
4. **ApplyPatch** × 函数调用/Shell 调用 × 工作区内/外
5. **UnifiedExec** × 安全/特权命令
6. **ExecPolicyAmendment** 持久化和传播
7. **NetworkPolicyAmendment** 允许/拒绝网络访问

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
// 核心协议依赖
use codex_protocol::approvals::NetworkApprovalProtocol;
use codex_protocol::approvals::NetworkPolicyAmendment;
use codex_protocol::approvals::NetworkPolicyRuleAction;
use codex_protocol::protocol::ApplyPatchApprovalRequestEvent;
use codex_protocol::protocol::AskForApproval;
use codex_protocol::protocol::EventMsg;
use codex_protocol::protocol::ExecApprovalRequestEvent;
use codex_protocol::protocol::ExecPolicyAmendment;
use codex_protocol::protocol::Op;
use codex_protocol::protocol::ReviewDecision;
use codex_protocol::protocol::SandboxPolicy;
use codex_protocol::user_input::UserInput;

// 核心配置依赖
use codex_core::config::Constrained;
use codex_core::config_loader::ConfigLayerStack;
use codex_core::config_loader::NetworkConstraints;
use codex_core::config_loader::NetworkRequirementsToml;
use codex_core::config_loader::RequirementSource;
use codex_core::config_loader::Sourced;
use codex_core::features::Feature;
use codex_core::sandboxing::SandboxPermissions;

// 测试支持依赖
use core_test_support::responses::*;
use core_test_support::test_codex::TestCodex;
use core_test_support::test_codex::test_codex;
use core_test_support::wait_for_event;
use core_test_support::wait_for_event_with_timeout;
use core_test_support::zsh_fork::*;
```

### 5.2 外部工具依赖

| 工具 | 用途 | 测试条件 |
|-----|------|---------|
| **wiremock** | Mock HTTP 服务器 | 模拟 OpenAI Responses API |
| **tokio** | 异步运行时 | `#[tokio::test(flavor = "multi_thread")]` |
| **tempfile** | 临时目录 | 隔离测试文件系统操作 |
| **serde_json** | JSON 序列化 | SSE 事件构造和解析 |
| **zsh** (可选) | Zsh Fork 测试 | 仅在 Unix 且支持 EXEC_WRAPPER 时 |
| **codex-linux-sandbox** | Linux 沙箱 | 仅在 Linux 平台 |
| **dotslash** | 获取测试依赖 | 获取 zsh 等工具 |

### 5.3 环境条件跳过

```rust
// 无网络时跳过
skip_if_no_network!(Ok(()));

// Linux 行为差异（TODO）
#[cfg(not(target_os = "linux"))]

// Unix 特定测试
#[cfg(unix)]

// Linux ARM 跳过（测试变通方案不工作）
#[cfg(not(all(target_os = "linux", target_arch = "aarch64")))]
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险与边界

#### 6.1.1 平台差异风险

| 风险点 | 描述 | 缓解措施 |
|-------|------|---------|
| **Linux 行为差异** | 注释 `TODO (pakrym): figure out why linux behaves differently` | 使用 `#[cfg(not(target_os = "linux"))]` 跳过 |
| **ARM 架构限制** | Linux ARM 上 zsh-fork 测试变通方案不工作 | 使用 `#[cfg(not(all(target_os = "linux", target_arch = "aarch64")))]` 跳过 |
| **Windows 不支持** | 整个 approvals 模块在 Windows 上被排除 | `#[cfg(not(target_os = "windows"))]` 在 `suite/mod.rs` 中 |

#### 6.1.2 测试稳定性风险

| 风险点 | 描述 | 影响 |
|-------|------|------|
| **网络依赖** | 部分测试需要网络访问 | 使用 `skip_if_no_network!` 宏跳过 |
| **外部工具依赖** | zsh-fork 测试依赖特定 zsh 版本和 EXEC_WRAPPER 支持 | 运行时检测并跳过 |
| **时间敏感操作** | `wait_for_event_with_timeout` 使用固定超时 | 可能因系统负载导致不稳定 |

#### 6.1.3 测试覆盖边界

1. **模型特定行为**: 测试硬编码 `gpt-5` 和 `gpt-5.1` 的行为差异（如 exit code 处理）
2. **并发场景**: 子代理测试使用多线程运行时，但复杂并发场景覆盖有限
3. **错误恢复**: 主要测试成功路径，错误恢复路径覆盖较少

### 6.2 改进建议

#### 6.2.1 代码结构改进

```rust
// 建议: 提取重复的场景定义模式
// 当前: 大量重复的 ScenarioSpec 定义
// 改进: 使用宏或构建器模式减少样板代码

macro_rules! scenario {
    ($name:expr, $policy:expr, $sandbox:expr, $action:expr, $outcome:expr, $expect:expr) => {
        ScenarioSpec {
            name: $name,
            approval_policy: $policy,
            sandbox_policy: $sandbox,
            action: $action,
            sandbox_permissions: SandboxPermissions::UseDefault,
            features: vec![],
            model_override: None,
            outcome: $outcome,
            expectation: $expect,
        }
    };
}
```

#### 6.2.2 测试可维护性改进

1. **场景命名规范化**: 当前场景名称使用 snake_case，但缺乏统一前缀分类
   - 建议: `danger_full_access/on_request/allows_outside_write`

2. **期望验证抽象**: `Expectation` 枚举的验证逻辑较长，可提取为独立模块

3. **Mock 响应复用**: 多个测试使用相似的 SSE 事件序列，可提取为固定装置（fixture）

#### 6.2.3 平台兼容性改进

1. **Linux 行为调查**: 解决 `read_only_on_failure_escalates_after_sandbox_error` 在 Linux 上的行为差异

2. **ARM 支持**: 为 Linux ARM 实现 zsh-fork 测试的替代方案

3. **Windows 支持**: 评估是否可以为 Windows 添加 approvals 测试子集

#### 6.2.4 测试性能改进

```rust
// 建议: 使用单线程运行时减少测试开销
// 当前: 部分测试使用 multi_thread
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]

// 改进: 评估是否可以使用 current_thread
#[tokio::test(flavor = "current_thread")]
```

### 6.3 安全相关注意事项

1. **DangerFullAccess 测试**: 测试确实会写入工作区外的临时文件，但使用 `TempDir` 确保隔离
2. **网络访问**: 网络测试使用本地 Mock 服务器，不访问真实外部服务
3. **沙箱降级**: `OnFailure` 策略测试验证沙箱失败后的权限升级，需确保不会意外授予过多权限

---

## 7. 总结

`approvals.rs` 是 Codex 核心测试套件中**最关键的安全相关测试文件**之一。它通过系统化的场景矩阵，验证了：

1. **审批策略的正确实现**: 确保不同策略下命令执行行为符合预期
2. **沙箱边界的有效性**: 验证文件系统和网络访问控制
3. **用户决策的持久化**: 确保 `ApprovedForSession` 和 `ApprovedExecpolicyAmendment` 正确工作
4. **权限传播的正确性**: 验证子代理权限不会意外泄露或传播错误

该测试文件的维护需要特别关注**平台差异**和**外部工具依赖**，建议定期审查跳过的测试用例，确保跨平台行为一致性。
