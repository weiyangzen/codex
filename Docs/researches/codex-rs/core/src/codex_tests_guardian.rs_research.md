# codex_tests_guardian.rs 深度研究文档

## 场景与职责

`codex_tests_guardian.rs` 是 Codex Core 模块中专门测试 **Guardian 审批系统** 的集成测试文件。Guardian 是 Codex 的安全子系统，用于自动评估和审批可能具有风险的命令执行请求，减少用户被打断的次数。

该测试文件位于 `codex-rs/core/src/` 目录下，属于核心测试套件的一部分，验证以下关键场景：

1. **Guardian 对额外权限请求的审批** - 验证 Guardian 能够正确评估和批准 shell 命令的额外权限请求
2. **统一执行处理程序的权限验证** - 测试 `UnifiedExecHandler` 对缺失权限参数的处理
3. **压缩历史记录的上下文保留** - 确保 Guardian 子代理的开发者消息在上下文压缩后得到正确处理
4. **粘性回合权限** - 验证回合级别的权限授予无需内联权限请求功能
5. **子代理执行策略隔离** - 确保 Guardian 子代理不继承父代理的执行策略规则

## 功能点目的

### 1. Guardian 自动审批验证

Guardian 系统的核心目标是**在安全的前提下减少用户审批打断**。当命令需要额外权限（如网络访问）时，Guardian 会：
- 分析命令的风险等级
- 评估风险分数（0-100）
- 低风险（<80分）自动批准，高风险转人工审批

### 2. 执行策略隔离

Guardian 作为子代理运行时，必须有独立的执行策略环境：
- 父代理可能有严格的执行策略（如禁止 `rm` 命令）
- Guardian 子代理需要独立的策略上下文来执行风险评估
- 防止父策略干扰 Guardian 的正常运作

### 3. 上下文压缩与保留

在长时间对话中，上下文压缩是必要的，但必须保留：
- Guardian 的开发者指令（安全策略提示）
- 用户消息的历史
- 回合级别的权限状态

## 具体技术实现

### 关键测试结构与依赖

```rust
// 核心依赖导入
use crate::compact::InitialContextInjection;
use crate::features::Feature;
use crate::guardian::GUARDIAN_REVIEWER_NAME;
use crate::protocol::AskForApproval;
use crate::sandboxing::SandboxPermissions;
use codex_execpolicy::{Decision, Evaluation, RuleMatch};
```

### 测试 1: Shell 额外权限请求的 Guardian 审批

**测试函数**: `guardian_allows_shell_additional_permissions_requests_past_policy_validation`

**流程**:
1. 启动 Mock SSE 服务器，模拟 Guardian 的评估响应
2. 配置测试会话，启用 Guardian 审批功能
3. 构造带有 `SandboxPermissions::WithAdditionalPermissions` 的 Shell 请求
4. 验证 Guardian 返回低风险评估后，命令成功执行

**关键代码**:
```rust
let params = ExecParams {
    command: vec!["/bin/sh", "-c", "echo hi"],
    sandbox_permissions: SandboxPermissions::WithAdditionalPermissions,
    additional_permissions: PermissionProfile {
        network: Some(NetworkPermissions { enabled: Some(true) }),
        ..Default::default()
    },
    justification: Some("test".to_string()),
    // ...
};
```

**Mock 响应结构**:
```json
{
    "risk_level": "low",
    "risk_score": 5,
    "rationale": "The request only widens permissions for a benign local echo command.",
    "evidence": [{
        "message": "The planned command is an `echo hi` smoke test.",
        "why": "This is low-risk and does not attempt destructive or exfiltrating behavior."
    }]
}
```

### 测试 2: UnifiedExec 权限验证

**测试函数**: `guardian_allows_unified_exec_additional_permissions_requests_past_policy_validation`

**目的**: 验证当使用 `with_additional_permissions` 但未提供具体权限时，系统返回明确的错误信息。

**验证点**:
```rust
let Err(FunctionCallError::RespondToModel(output)) = resp else {
    panic!("expected validation error result");
};
assert_eq!(output, "missing `additional_permissions`; provide at least one of `network`, `file_system`, or `macos`...");
```

### 测试 3: 压缩历史中的 Guardian 开发者消息保留

**测试函数**: `process_compacted_history_preserves_separate_guardian_developer_message`

**技术细节**:
- 使用 `InitialContextInjection::BeforeLastUserMessage` 策略
- 设置 `SessionSource::SubAgent(SubAgentSource::Other(GUARDIAN_REVIEWER_NAME))`
- 验证压缩后的历史中：
  - 旧的开发者消息被移除
  - Guardian 策略提示被保留
  - 用户消息顺序正确

**关键断言**:
```rust
assert!(!developer_messages.iter().any(|m| m.contains("stale developer message")));
assert!(developer_messages.len() >= 2);
assert_eq!(developer_messages.last(), Some(&guardian_policy));
```

### 测试 4: 粘性回合权限

**测试函数**: `shell_handler_allows_sticky_turn_permissions_without_inline_request_permissions_feature`

**机制**:
- 启用 `Feature::RequestPermissionsTool` 功能
- 在 `ActiveTurn` 中预授权权限配置
- 验证后续命令无需再次请求权限

**权限记录**:
```rust
turn_state.record_granted_permissions(PermissionProfile {
    network: Some(NetworkPermissions { enabled: Some(true) }),
    ..Default::default()
});
```

### 测试 5: 子代理执行策略隔离

**测试函数**: `guardian_subagent_does_not_inherit_parent_exec_policy_rules`

**复杂场景验证**:
1. 父代理配置：在项目目录下创建 `rules/deny.rules`，禁止 `rm` 命令
2. 加载父策略，验证 `rm` 被禁止
3. 创建 Guardian 子代理，传入 `inherited_exec_policy: Some(Arc::new(parent_exec_policy))`
4. 验证子代理中 `rm` 命令被允许（使用启发式规则而非父策略）

**策略检查对比**:
```rust
// 父策略：禁止 rm
assert_eq!(parent_exec_policy.check_multiple(...), Evaluation {
    decision: Decision::Forbidden,
    matched_rules: vec![RuleMatch::PrefixRuleMatch { ... }],
});

// 子策略：允许 rm（启发式匹配）
assert_eq!(codex.session.services.exec_policy.current().check_multiple(...), Evaluation {
    decision: Decision::Allow,
    matched_rules: vec![RuleMatch::HeuristicsRuleMatch { ... }],
});
```

## 关键代码路径与文件引用

### 被测试的核心组件

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| `ShellHandler` | `tools/handlers/shell.rs` | 处理 shell 工具调用 |
| `UnifiedExecHandler` | `tools/handlers/unified_exec.rs` | 统一执行命令处理 |
| `process_compacted_history` | `compact_remote.rs` | 处理压缩后的历史记录 |
| `GUARDIAN_REVIEWER_NAME` | `guardian/mod.rs` | Guardian 标识常量 |
| `ExecPolicyManager` | `exec_policy.rs` | 执行策略管理 |

### 测试辅助函数

```rust
// 来自 codex.rs 或 test_support
fn make_session_and_context() -> (Session, TurnContext)
fn build_test_config(codex_home: &Path) -> Config
fn models_manager_with_provider(...) -> ModelsManager
```

### 测试数据构造

**Mock SSE 服务器**:
```rust
let server = start_mock_server().await;
let _request_log = mount_sse_once(&server, sse(vec![
    ev_response_created("resp-guardian"),
    ev_assistant_message("msg-guardian", &risk_assessment_json),
    ev_completed("resp-guardian"),
])).await;
```

## 依赖与外部交互

### 内部模块依赖

```
codex_tests_guardian.rs
├── compact.rs (InitialContextInjection)
├── config_loader.rs (ConfigLayerEntry, ConfigRequirements)
├── exec.rs (ExecParams)
├── exec_policy.rs (ExecPolicyManager)
├── features.rs (Feature)
├── guardian/mod.rs (GUARDIAN_REVIEWER_NAME)
├── protocol.rs (AskForApproval)
├── sandboxing.rs (SandboxPermissions)
├── tools/context.rs (FunctionToolOutput)
└── turn_diff_tracker.rs (TurnDiffTracker)
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_execpolicy` | 执行策略规则引擎 (`Decision`, `Evaluation`, `RuleMatch`) |
| `codex_protocol` | 协议模型 (`PermissionProfile`, `NetworkPermissions`, `ContentItem`) |
| `codex_app_server_protocol` | 配置层源类型 (`ConfigLayerSource`) |
| `codex_utils_absolute_path` | 绝对路径处理 (`AbsolutePathBuf`) |
| `core_test_support` | 测试支持库 (Mock SSE 服务器、响应构造) |

### 测试环境要求

- **Linux Sandbox**: 部分测试需要 `codex_linux_sandbox_exe` 可用
- **Mock 服务器**: 使用 `wiremock` 模拟 OpenAI API 响应
- **临时目录**: 使用 `tempfile::tempdir()` 创建隔离的测试环境

## 风险、边界与改进建议

### 当前风险点

1. **平台差异**: 测试中有条件编译 `#[cfg(unix)]` 和 `cfg!(windows)`，确保跨平台行为一致性需要维护两套逻辑
   ```rust
   let command = if cfg!(windows) {
       vec!["cmd.exe", "/Q", "/D", "/C", "echo hi"]
   } else {
       vec!["/bin/sh", "-c", "echo hi"]
   };
   ```

2. **超时配置**: Windows 使用 2500ms，其他平台 1000ms，这种差异可能导致测试在慢速环境中不稳定
   ```rust
   let expiration_ms: u64 = if cfg!(windows) { 2_500 } else { 1_000 };
   ```

3. **硬编码模型**: 测试依赖特定的 Guardian 模型行为，如果模型更新可能导致测试失效

### 边界情况

1. **空权限配置**: 测试验证了 `additional_permissions` 缺失时的错误处理
2. **并发执行**: 测试使用 `Arc<Mutex<...>>` 确保线程安全
3. **资源清理**: 使用 `tempdir()` 和 `drop(codex)` 确保测试资源正确释放

### 改进建议

1. **参数化测试**: 将平台差异抽象为测试参数，减少重复代码
2. **模型 Mock**: 增加 Guardian 模型响应的 Mock 选项，减少对真实模型行为的依赖
3. **策略规则测试扩展**: 增加更多复杂的执行策略继承场景测试
4. **性能基准**: 添加 Guardian 审批延迟的性能测试，确保 90 秒超时设置合理
5. **错误覆盖**: 增加 Guardian 返回畸形 JSON 或超时的错误处理测试

### 相关文档

- `guardian/mod.rs` - Guardian 模块主文档
- `AGENTS.md` - 项目级代理行为指南
- `codex-rs/core/src/guardian/review_session.rs` - Guardian 审查会话实现
