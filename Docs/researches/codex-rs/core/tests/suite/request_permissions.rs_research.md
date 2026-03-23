# request_permissions.rs 研究文档

## 场景与职责

`request_permissions.rs` 是 Codex 核心测试套件中最复杂的集成测试文件之一（约 1865 行），专门测试**动态权限请求功能**。该文件验证 `request_permissions` 工具与执行权限审批流程的集成，包括工具调用时的额外权限请求、用户审批、权限授予的生命周期管理等。

测试场景覆盖：
- `WithAdditionalPermissions` 沙箱权限模式下的审批流程
- 独立 `request_permissions` 工具的使用
- 相对路径权限请求解析
- 只读沙箱下的权限扩展限制
- 工作区写入沙箱下的外部目录写入
- 权限被拒绝时的执行阻塞
- 权限授予的持续性（Turn 级别 vs Session 级别）
- 部分权限授予的处理
- 跨 Turn 的权限生命周期

## 功能点目的

### 1. 动态权限请求（Exec Permission Approvals）
允许 shell/exec 工具在执行时请求超出当前沙箱策略的额外权限，例如：
- 写入工作区外的特定目录
- 访问特定的网络资源
- 临时提升文件系统访问范围

### 2. 独立权限请求工具（RequestPermissionsTool）
提供一个独立的 `request_permissions` 工具，允许模型在执行命令前预先请求权限：
- 用户可以提前批准权限
- 后续命令自动应用已授予的权限
- 支持 Turn 级别和 Session 级别的权限范围

### 3. 权限审批策略集成
与 `AskForApproval` 策略集成：
- `OnRequest` 策略：每次权限请求都需要用户批准
- `Granular` 策略：可单独启用/禁用 `request_permissions` 审批

### 4. 权限生命周期管理
验证权限授予的不同范围：
- **Turn**：权限仅对当前 Turn 有效
- **Session**：权限在整个会话期间有效

### 5. 权限合并与验证
测试多个权限来源的合并逻辑：
- 基础沙箱策略
- 工具调用时的 `additional_permissions`
- 预先授予的权限

## 具体技术实现

### 关键数据结构

```rust
// 权限配置结构
use codex_protocol::request_permissions::{
    PermissionGrantScope,      // Turn | Session
    RequestPermissionProfile,  // 请求的权限配置
    RequestPermissionsResponse, // 用户响应
};
use codex_protocol::models::{
    FileSystemPermissions,     // 文件系统权限
    PermissionProfile,         // 完整权限配置
};
use codex_core::sandboxing::SandboxPermissions;

// 沙箱策略枚举
enum SandboxPermissions {
    Inherit,                        // 继承当前策略
    WithAdditionalPermissions,      // 使用额外权限
}
```

### 测试辅助函数

```rust
// 构造带权限请求的 shell_command 事件
fn shell_event_with_request_permissions<S: serde::Serialize>(
    call_id: &str,
    command: &str,
    additional_permissions: &S,
) -> Result<Value> {
    let args = json!({
        "command": command,
        "timeout_ms": 1_000_u64,
        "sandbox_permissions": SandboxPermissions::WithAdditionalPermissions,
        "additional_permissions": additional_permissions,
    });
    Ok(ev_function_call(call_id, "shell_command", &args_str))
}

// 构造 request_permissions 工具事件
fn request_permissions_tool_event(
    call_id: &str,
    reason: &str,
    permissions: &RequestPermissionProfile,
) -> Result<Value> {
    let args = json!({ "reason": reason, "permissions": permissions });
    Ok(ev_function_call(call_id, "request_permissions", &args_str))
}

// 构造 exec_command 事件
fn exec_command_event(call_id: &str, command: &str) -> Result<Value> {
    let args = json!({ "cmd": command, "yield_time_ms": 1_000_u64 });
    Ok(ev_function_call(call_id, "exec_command", &args_str))
}

// 解析命令执行结果
fn parse_result(item: &Value) -> CommandResult {
    // 解析 shell/exec 工具的输出，提取 exit_code 和 stdout
}
```

### 关键测试流程

#### 1. WithAdditionalPermissions 审批流程

```rust
async fn with_additional_permissions_requires_approval_under_on_request() -> Result<()> {
    // 1. 配置 OnRequest 审批策略和只读沙箱
    let approval_policy = AskForApproval::OnRequest;
    let sandbox_policy = SandboxPolicy::new_read_only_policy();
    
    // 2. 启用 ExecPermissionApprovals 和 RequestPermissionsTool 特性
    config.features.enable(Feature::ExecPermissionApprovals)?;
    config.features.enable(Feature::RequestPermissionsTool)?;

    // 3. 创建测试目录和请求权限
    let requested_dir = test.workspace_path("requested-dir");
    fs::create_dir_all(&requested_dir)?;
    let requested_permissions = PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec![]),
            write: Some(vec![absolute_path(&requested_dir_canonical)]),
        }),
        ..Default::default()
    };

    // 4. 挂载 SSE 序列：第一次响应触发权限请求
    let _ = mount_sse_once(&server, sse([
        ev_response_created("resp-1"),
        shell_event_with_request_permissions(call_id, command, &requested_permissions)?,
        ev_completed("resp-1"),
    ])).await;
    
    // 第二次响应返回执行结果
    let results = mount_sse_once(&server, sse([
        ev_assistant_message("msg-1", "done"),
        ev_completed("resp-2"),
    ])).await;

    // 5. 提交 UserTurn
    submit_turn(&test, call_id, approval_policy, sandbox_policy.clone()).await?;

    // 6. 等待并验证 ExecApprovalRequest 事件
    let approval = expect_exec_approval(&test, command).await;
    assert_eq!(approval.additional_permissions, Some(requested_permissions.clone()));

    // 7. 提交审批决定
    test.codex.submit(Op::ExecApproval {
        id: approval.effective_approval_id(),
        turn_id: None,
        decision: ReviewDecision::Approved,
    }).await?;
    wait_for_completion(&test).await;

    // 8. 验证执行结果
    let result = parse_result(&results.single_request().function_call_output(call_id));
    assert!(result.exit_code.is_none() || result.exit_code == Some(0));
    assert!(requested_write.exists());
}
```

#### 2. 相对路径权限解析

```rust
async fn relative_additional_permissions_resolve_against_tool_workdir() -> Result<()> {
    // 测试相对路径权限（如 "."）应相对于工具的工作目录解析
    let event = shell_event_with_raw_request_permissions(
        call_id,
        command,
        Some("nested"),  // workdir
        json!({ "file_system": { "write": ["."] } }),  // 相对路径
    )?;
    
    // 验证解析后的权限指向正确的绝对路径
    let approval = expect_exec_approval(&test, command).await;
    assert_eq!(approval.additional_permissions, Some(expected_permissions));
}
```

#### 3. 只读沙箱下的权限限制

```rust
#[cfg(target_os = "macos")]
async fn read_only_with_additional_permissions_does_not_widen_to_unrequested_cwd_write() -> Result<()> {
    // 验证：即使批准了权限，也不能写入未请求的 CWD 路径
    let requested_write = test.workspace_path("requested-only-cwd.txt");
    let unrequested_write = test.workspace_path("unrequested-cwd-write.txt");
    
    // 只请求写入 requested_write，但命令尝试写入 unrequested_write
    let command = format!("printf {:?} > {:?}", "cwd-widened", unrequested_write);
    
    // 验证执行失败
    let result = parse_result(&results.single_request().function_call_output(call_id));
    assert!(result.exit_code != Some(0));
    assert!(!unrequested_write.exists());
}
```

#### 4. Session 级别权限持续性

```rust
#[cfg(target_os = "macos")]
async fn request_permissions_session_grants_carry_across_turns() -> Result<()> {
    // 第一 Turn：请求 Session 级别的权限
    submit_turn(&test, "request session permissions", approval_policy, sandbox_policy.clone()).await?;
    
    let granted_permissions = expect_request_permissions_event(&test, "permissions-call").await;
    test.codex.submit(Op::RequestPermissionsResponse {
        id: "permissions-call".to_string(),
        response: RequestPermissionsResponse {
            permissions: normalized_requested_permissions,
            scope: PermissionGrantScope::Session,  // Session 级别
        },
    }).await?;
    wait_for_completion(&test).await;

    // 第二 Turn：使用已授予的权限执行命令（不重新请求）
    submit_turn(&test, "reuse session permissions", approval_policy, sandbox_policy).await?;
    
    // 验证命令成功执行，无需再次审批
    let exec_output = second_turn.function_call_output_text("exec-call").unwrap();
    let result = parse_result(&exec_output);
    assert_eq!(result.exit_code, Some(0));
}
```

#### 5. Turn 级别权限不跨 Turn

```rust
async fn request_permissions_grants_do_not_carry_across_turns() -> Result<()> {
    // 第一 Turn：请求 Turn 级别的权限
    test.codex.submit(Op::RequestPermissionsResponse {
        id: "permissions-call".to_string(),
        response: RequestPermissionsResponse {
            permissions: normalized_requested_permissions,
            scope: PermissionGrantScope::Turn,  // Turn 级别
        },
    }).await?;
    wait_for_completion(&test).await;

    // 第二 Turn：尝试使用权限（未重新请求）
    submit_turn(&test, "try to reuse permissions in a later turn", approval_policy, sandbox_policy).await?;
    wait_for_completion(&test).await;

    // 验证执行失败，提示缺少 additional_permissions
    let output = second_turn.function_call_output_text("exec-call").unwrap();
    assert!(output.contains("missing `additional_permissions`"));
}
```

#### 6. 部分权限授予

```rust
async fn partial_request_permissions_grants_do_not_preapprove_new_permissions() -> Result<()> {
    // 请求两个目录的写入权限
    let requested_permissions = RequestPermissionProfile {
        file_system: Some(FileSystemPermissions {
            write: Some(vec![absolute_path(first_dir.path()), absolute_path(second_dir.path())]),
        }),
        ..Default::default()
    };
    
    // 但只授予第一个目录的权限
    let granted_permissions = normalized_directory_write_permissions(first_dir.path())?;
    
    // 验证：执行需要第二个目录权限的命令时，仍需审批
    let approval = expect_exec_approval(&test, &command).await;
    // approval 包含合并后的权限（已授予 + 新请求）
}
```

#### 7. Granular 策略禁用 request_permissions

```rust
async fn request_permissions_tool_is_auto_denied_when_granular_request_permissions_is_disabled() -> Result<()> {
    // 配置 Granular 策略，禁用 request_permissions
    let approval_policy = AskForApproval::Granular(GranularApprovalConfig {
        sandbox_approval: true,
        rules: true,
        skill_approval: true,
        request_permissions: false,  // 禁用
        mcp_elicitations: true,
    });

    // 验证：不触发权限请求提示，直接返回 TurnComplete
    let event = wait_for_event(&test.codex, |event| {
        matches!(event, EventMsg::RequestPermissions(_) | EventMsg::TurnComplete(_))
    }).await;
    assert!(matches!(event, EventMsg::TurnComplete(_)));

    // 验证：返回空的权限响应
    let result: RequestPermissionsResponse = serde_json::from_str(...)?;
    assert_eq!(result, RequestPermissionsResponse {
        permissions: RequestPermissionProfile::default(),
        scope: PermissionGrantScope::Turn,
    });
}
```

## 关键代码路径与文件引用

### 被测试的核心代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/handlers/request_permissions.rs` | `RequestPermissionsHandler` 工具处理器 |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱权限转换和合并逻辑 |
| `codex-rs/core/src/exec_policy.rs` | 执行策略和权限检查 |
| `codex-rs/core/src/codex.rs` | `request_permissions` 方法实现 |
| `codex-rs/core/src/codex_delegate.rs` | 权限请求委托处理 |

### 协议类型定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/request_permissions.rs` | `RequestPermissionProfile`, `PermissionGrantScope`, `RequestPermissionsResponse` |
| `codex-rs/protocol/src/models.rs` | `PermissionProfile`, `FileSystemPermissions`, `SandboxPermissions` |
| `codex-rs/protocol/src/protocol.rs` | `ExecApprovalRequestEvent`, `RequestPermissionsEvent` |

### 测试基础设施

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex`, `TestCodexBuilder` |
| `codex-rs/core/tests/common/responses.rs` | `mount_sse_sequence`, `ev_function_call` 等 Mock 辅助函数 |

### 关键代码路径

权限请求处理流程：
```
ToolInvocation (shell_command/exec_command with additional_permissions)
    ↓
ShellCommandHandler::handle / UnifiedExecHandler::handle
    ↓
sandboxing::normalize_additional_permissions() [路径规范化]
    ↓
ExecPolicy::check_approval_required() [检查是否需要审批]
    ↓
Codex::submit(Op::ExecApprovalRequest) [发送审批请求事件]
    ↓
UI 显示审批对话框
    ↓
Codex::submit(Op::ExecApproval { decision: Approved/Denied })
    ↓
执行命令（应用批准的权限）
```

独立权限工具流程：
```
ToolInvocation (request_permissions)
    ↓
RequestPermissionsHandler::handle()
    ↓
sandboxing::normalize_additional_permissions()
    ↓
Session::request_permissions() [创建权限请求]
    ↓
Codex::submit(Op::RequestPermissions) [发送权限请求事件]
    ↓
UI 显示权限请求对话框
    ↓
Codex::submit(Op::RequestPermissionsResponse { permissions, scope })
    ↓
Session::apply_permission_grant() [应用权限到当前 Turn 或 Session]
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock::MockServer` | HTTP 模拟服务器 |
| `tokio` | 异步运行时 |
| `tempfile::TempDir` | 临时目录用于测试文件操作 |
| `serde_json` | JSON 序列化/反序列化 |
| `regex_lite` | 解析命令输出 |

### 特性开关

测试需要启用以下特性：
```rust
Feature::ExecPermissionApprovals  // 执行时权限请求
Feature::RequestPermissionsTool   // 独立权限请求工具
```

### 平台限制

部分测试仅在 macOS 上运行：
```rust
#[cfg(target_os = "macos")]
async fn read_only_with_additional_permissions_does_not_widen_to_unrequested_cwd_write() { ... }
```

原因：这些测试依赖于 macOS Seatbelt 沙箱的具体行为。

## 风险、边界与改进建议

### 已知风险

1. **平台差异**
   - macOS 和 Linux 的沙箱实现不同（Seatbelt vs Landlock）
   - 部分测试仅在 macOS 上运行，Linux 行为缺乏验证
   - Windows 完全不支持（整个文件被排除）

2. **测试复杂度**
   - 测试文件超过 1800 行，维护困难
   - 大量重复的设置代码（每个测试都配置相似的策略和特性）
   - 测试间可能存在隐式依赖

3. **路径规范化问题**
   - 相对路径解析依赖于工具的工作目录
   - 符号链接处理可能在不同平台表现不一致

### 边界情况

1. **权限冲突**
   - 当基础策略允许，但 additional_permissions 限制更多时如何处理？
   - 当前测试未覆盖此场景

2. **网络权限**
   - 大部分测试关注文件系统权限
   - 网络权限请求测试覆盖不足

3. **权限撤销**
   - 测试未覆盖 Session 级别权限的提前撤销
   - 用户可能希望在会话结束前撤销某些权限

4. **并发权限请求**
   - 多个工具同时请求权限时的处理
   - 权限队列和去重逻辑

### 改进建议

1. **重构测试代码**
   ```rust
   // 建议：提取通用设置到宏或辅助函数
   macro_rules! setup_permission_test {
       ($approval_policy:expr, $sandbox_policy:expr) => { ... }
   }
   ```

2. **增加 Linux 测试覆盖**
   - 为 Landlock 沙箱添加对应的测试
   - 或抽象沙箱接口，使测试平台无关

3. **增加边界测试**
   ```rust
   // 建议添加：
   - test_permission_revocation
   - test_concurrent_permission_requests
   - test_permission_inheritance_with_subagents
   - test_network_permission_requests
   ```

4. **权限可视化测试**
   - 测试权限请求在 UI 中的展示格式
   - 验证权限合并后的用户友好描述

5. **性能测试**
   - 大量权限授予后的查询性能
   - 权限检查对命令执行延迟的影响

6. **安全审计测试**
   - 验证权限不能逃逸到未请求的路径
   - 测试路径遍历攻击的防护（`../../../etc/passwd`）

7. **错误处理改进**
   - 测试无效权限配置的优雅处理
   - 测试权限请求超时场景
