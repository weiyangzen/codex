# request_permissions_tool.rs 深入研究

## 场景与职责

`request_permissions_tool.rs` 是 Codex Core 的集成测试文件，专门测试 **request_permissions** 工具的功能。该工具允许 AI 模型在执行敏感操作前向用户请求临时或持久的权限授权。

### 核心测试场景

1. **文件夹写入权限请求与执行命令的协同**：验证当模型通过 `request_permissions` 工具请求特定文件夹的写入权限后，后续 `exec_command` 可以在不触发额外沙箱参数的情况下正常执行
2. **文件夹写入权限请求与补丁应用的协同**：验证权限授予后，`apply_patch` 工具可以在不触发额外提示的情况下正常工作

### 测试限制

- **仅限 macOS**：`#![cfg(target_os = "macos")]` 条件编译限制
- **需要网络**：使用 `skip_if_no_network!` 宏跳过沙箱网络受限环境
- **需要非沙箱环境**：使用 `skip_if_sandbox!` 宏避免在 Seatbelt 沙箱中运行

---

## 功能点目的

### 1. 权限请求工具 (request_permissions)

允许模型在需要访问受限资源时主动请求用户授权，支持：
- **文件系统权限**：指定读/写路径
- **网络权限**：控制网络访问
- **授权范围**：Turn（单轮）或 Session（整个会话）

### 2. 权限与沙箱策略的协同

测试验证的关键行为：
- 当用户通过 `request_permissions` 授予特定文件夹写入权限后
- 后续在该文件夹的操作不应再触发额外的审批请求
- 与 `WorkspaceWrite` 沙箱策略协同工作

---

## 具体技术实现

### 关键数据结构

```rust
// 权限配置结构
RequestPermissionProfile {
    file_system: Some(FileSystemPermissions {
        read: Some(vec![]),
        write: Some(vec![absolute_path(path)]),
    }),
    ..RequestPermissionProfile::default()
}

// 沙箱策略配置
SandboxPolicy::WorkspaceWrite {
    writable_roots: vec![],
    read_only_access: Default::default(),
    network_access: false,
    exclude_tmpdir_env_var: true,
    exclude_slash_tmp: true,
}
```

### 测试流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         测试流程                                 │
├─────────────────────────────────────────────────────────────────┤
│  1. 启动 Mock SSE Server                                        │
│  2. 配置 TestCodex（启用 ExecPermissionApprovals +             │
│                    RequestPermissionsTool 特性）                 │
│  3. 挂载 SSE 响应序列（3 轮响应）                                │
│  4. 提交 UserTurn 触发权限请求                                   │
│  5. 等待 RequestPermissions 事件                                 │
│  6. 提交 RequestPermissionsResponse 授予权限                     │
│  7. 等待 ExecApprovalRequest / ApplyPatchApprovalRequest         │
│  8. 验证操作成功执行                                             │
└─────────────────────────────────────────────────────────────────┘
```

### SSE 响应序列配置

测试使用 `mount_sse_sequence` 配置多轮 SSE 响应：

```rust
let responses = mount_sse_sequence(
    &server,
    vec![
        // 第一轮：权限请求
        sse(vec![
            ev_response_created("resp-request-permissions-1"),
            request_permissions_tool_event("permissions-call", "Allow writing outside the workspace", &requested_permissions)?,
            ev_completed("resp-request-permissions-1"),
        ]),
        // 第二轮：执行命令或应用补丁
        sse(vec![
            ev_response_created("resp-request-permissions-2"),
            exec_command_event("exec-call", &command)?,  // 或 ev_apply_patch_function_call
            ev_completed("resp-request-permissions-2"),
        ]),
        // 第三轮：完成确认
        sse(vec![
            ev_response_created("resp-request-permissions-3"),
            ev_assistant_message("msg-request-permissions-1", "done"),
            ev_completed("resp-request-permissions-3"),
        ]),
    ],
).await;
```

### 事件处理流程

```rust
// 等待权限请求事件
let granted_permissions = expect_request_permissions_event(&test, "permissions-call").await;

// 提交权限响应
 test.codex
    .submit(Op::RequestPermissionsResponse {
        id: "permissions-call".to_string(),
        response: RequestPermissionsResponse {
            permissions: normalized_requested_permissions,
            scope: PermissionGrantScope::Turn,  // 或 Session
        },
    })
    .await?;
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/request_permissions_tool.rs` | 本测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试支持库 |
| `codex-rs/core/tests/common/responses.rs` | SSE Mock 响应工具 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 构建器 |

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/request_permissions.rs` | 权限请求协议类型 |
| `codex-rs/protocol/src/protocol.rs` | Op 枚举（RequestPermissionsResponse） |

### 核心类型定义

```rust
// codex-rs/protocol/src/request_permissions.rs
pub struct RequestPermissionsEvent {
    pub call_id: String,
    pub turn_id: String,
    pub reason: Option<String>,
    pub permissions: RequestPermissionProfile,
}

pub struct RequestPermissionsResponse {
    pub permissions: RequestPermissionProfile,
    pub scope: PermissionGrantScope,  // Turn | Session
}

pub enum PermissionGrantScope {
    Turn,
    Session,
}
```

### 协议 Op 枚举

```rust
// codex-rs/protocol/src/protocol.rs
pub enum Op {
    // ... 其他变体
    RequestPermissionsResponse {
        id: String,
        response: RequestPermissionsResponse,
    },
    // ...
}
```

---

## 依赖与外部交互

### 测试依赖

```rust
// 核心依赖
codex_core::config::Constrained
codex_core::features::Feature
codex_protocol::models::FileSystemPermissions
codex_protocol::protocol::{AskForApproval, EventMsg, Op, ReviewDecision, SandboxPolicy}
codex_protocol::request_permissions::{PermissionGrantScope, RequestPermissionProfile, RequestPermissionsResponse}
codex_protocol::user_input::UserInput
codex_utils_absolute_path::AbsolutePathBuf

// 测试支持
core_test_support::responses::*
core_test_support::skip_if_no_network!
core_test_support::skip_if_sandbox!
core_test_support::test_codex::TestCodex
```

### Mock Server 交互

测试使用 `wiremock::MockServer` 模拟 OpenAI Responses API：

```rust
let server = start_mock_server().await;
```

SSE 事件通过 `responses::mount_sse_sequence` 挂载，支持：
- `ev_response_created(id)` - 响应创建事件
- `ev_function_call(call_id, name, args)` - 函数调用事件
- `ev_apply_patch_function_call(call_id, patch)` - 补丁应用调用
- `ev_completed(id)` - 响应完成事件
- `ev_assistant_message(id, text)` - 助手消息事件

---

## 风险、边界与改进建议

### 当前限制

1. **平台限制**：仅测试 macOS，Linux/Windows 行为未覆盖
2. **网络依赖**：需要真实网络连接（Mock Server 本地运行但仍需网络环境）
3. **沙箱环境**：无法在 Seatbelt 沙箱中运行

### 边界情况

1. **权限范围**：
   - `Turn` 范围：权限仅对当前轮次有效
   - `Session` 范围：权限在整个会话期间有效

2. **路径规范化**：
   ```rust
   fn normalized_directory_write_permissions(path: &Path) -> Result<RequestPermissionProfile>
   ```
   使用 `path.canonicalize()` 确保路径绝对且规范化

3. **沙箱策略协同**：
   - 测试使用 `workspace_write_excluding_tmp()` 策略
   - 排除 `/tmp` 和 `TMPDIR` 环境变量

### 改进建议

1. **扩展平台覆盖**：
   - 添加 Linux 平台测试（使用 `codex-linux-sandbox`）
   - 添加 Windows 平台测试

2. **增加边界测试**：
   - 权限拒绝场景
   - 权限范围过期验证
   - 多个文件夹权限请求
   - 嵌套路径权限冲突

3. **性能优化**：
   - 当前测试使用 `tokio::test(flavor = "current_thread")`
   - 考虑并行执行多个权限测试

4. **测试可读性**：
   - 提取公共的 SSE 序列构建器
   - 增加更多注释说明权限流程

### 相关测试

- `request_permissions.rs` - 基础权限请求测试
- `request_user_input.rs` - 用户输入请求测试（类似模式）
- `approvals.rs` - 审批流程测试
- `exec_policy.rs` - 执行策略测试
