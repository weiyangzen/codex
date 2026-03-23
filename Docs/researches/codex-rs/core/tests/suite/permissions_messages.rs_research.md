# permissions_messages.rs 研究文档

## 场景与职责

`permissions_messages.rs` 是 Codex 核心库的权限消息测试套件。它负责验证权限指令 (permissions instructions) 在会话生命周期中的正确传递和管理，包括：

- 权限消息在会话开始时的发送
- 权限策略变更时的消息更新
- 无变更时的消息去重
- 会话恢复时的权限消息重放
- 会话分叉时的权限消息追加
- 可写根目录信息在权限消息中的包含

这些测试确保 Codex 的权限系统能够正确地向模型传达当前的安全策略和约束。

## 功能点目的

### 1. 初始权限消息发送 (`permissions_message_sent_once_on_start`)

验证在会话开始时，权限指令消息只发送一次。这确保了：
- 模型在会话开始时即了解当前权限策略
- 避免重复发送相同的权限信息
- 减少不必要的令牌消耗

### 2. 权限变更时的消息更新 (`permissions_message_added_on_override_change`)

验证当权限策略通过 `OverrideTurnContext` 变更时，新的权限消息被添加到后续请求中。这确保了：
- 模型始终了解最新的权限策略
- 权限变更在用户回合开始时生效

### 3. 无变更时的消息去重 (`permissions_message_not_added_when_no_change`)

验证当权限策略未变更时，不会重复添加相同的权限消息。这确保了：
- 避免冗余的权限指令
- 优化令牌使用

### 4. 会话恢复时的权限消息重放 (`resume_replays_permissions_messages`)

验证从 rollout 恢复会话时，历史权限消息被正确重放。这确保了：
- 恢复的会话保持完整的权限历史
- 模型了解权限策略的演变过程

### 5. 恢复和分叉时的权限消息追加 (`resume_and_fork_append_permissions_messages`)

验证在会话恢复和分叉时，新的权限消息被正确追加到历史消息之后。这确保了：
- 恢复后的新权限策略与历史策略区分
- 分叉会话继承并扩展权限历史

### 6. 可写根目录信息包含 (`permissions_message_includes_writable_roots`)

验证权限消息包含正确的可写根目录信息。这确保了：
- 模型了解文件系统访问限制
- 沙箱策略正确传达给模型

## 具体技术实现

### 关键数据结构

```rust
// 从请求输入中提取权限消息文本
fn permissions_texts(input: &[serde_json::Value]) -> Vec<String> {
    input
        .iter()
        .filter_map(|item| {
            let role = item.get("role")?.as_str()?;
            if role != "developer" {
                return None;
            }
            let text = item
                .get("content")?
                .as_array()?
                .first()?
                .get("text")?
                .as_str()?;
            if text.contains("<permissions instructions>") {
                Some(text.to_string())
            } else {
                None
            }
        })
        .collect()
}
```

### 测试配置

```rust
// 使用 OnRequest 审批策略进行测试
let mut builder = test_codex().with_config(move |config| {
    config.permissions.approval_policy = Constrained::allow_any(AskForApproval::OnRequest);
});
```

### 典型测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn permissions_message_sent_once_on_start() -> Result<()> {
    skip_if_no_network!(Ok(()));

    // 1. 启动 mock 服务器并挂载 SSE 响应
    let server = start_mock_server().await;
    let req = mount_sse_once(&server, sse(vec![...])).await;

    // 2. 构建带有特定权限配置的 TestCodex
    let mut builder = test_codex().with_config(move |config| {
        config.permissions.approval_policy = Constrained::allow_any(AskForApproval::OnRequest);
    });
    let test = builder.build(&server).await?;

    // 3. 提交用户输入
    test.codex.submit(Op::UserInput { ... }).await?;
    wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

    // 4. 获取请求并验证权限消息
    let request = req.single_request();
    let body = request.body_json();
    let input = body["input"].as_array().expect("input array");
    let permissions = permissions_texts(input);
    assert_eq!(permissions.len(), 1);  // 只应有一条权限消息

    Ok(())
}
```

### 会话恢复测试

```rust
async fn resume_replays_permissions_messages() -> Result<()> {
    // ... 初始会话设置和交互
    
    // 获取 rollout 路径用于恢复
    let rollout_path = initial
        .session_configured
        .rollout_path
        .clone()
        .expect("rollout path");
    let home = initial.home.clone();

    // 执行一些操作并变更权限
    // ...

    // 恢复会话
    let resumed = builder.resume(&server, home, rollout_path).await?;
    
    // 提交新输入并验证权限消息历史
    // ...
    let permissions = permissions_texts(input);
    assert_eq!(permissions.len(), 3);  // 历史权限消息被重放
}
```

### 会话分叉测试

```rust
// 使用 ThreadManager 进行分叉
let mut fork_config = initial.config.clone();
fork_config.permissions.approval_policy = Constrained::allow_any(AskForApproval::UnlessTrusted);
let forked = initial
    .thread_manager
    .fork_thread(usize::MAX, fork_config, rollout_path, false, None)
    .await?;
```

### 可写根目录验证

```rust
// 配置 WorkspaceWrite 沙箱策略
let sandbox_policy = SandboxPolicy::WorkspaceWrite {
    writable_roots: vec![writable_root],
    read_only_access: Default::default(),
    network_access: false,
    exclude_tmpdir_env_var: false,
    exclude_slash_tmp: false,
};

// 验证生成的权限消息
let expected = DeveloperInstructions::from_policy(
    &sandbox_policy,
    AskForApproval::OnRequest,
    &Policy::empty(),
    test.config.cwd.as_path(),
    false,
    false,
).into_text();
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/permissions_messages.rs` - 本测试文件

### 被测试的源文件
- `codex-rs/core/src/instructions/mod.rs` - 指令生成
- `codex-rs/core/src/instructions/user_instructions.rs` - 用户指令处理
- `codex-rs/core/src/context_manager/mod.rs` - 上下文管理
- `codex-rs/core/src/context_manager/updates.rs` - 上下文更新
- `codex-rs/core/src/rollout/recorder.rs` - Rollout 记录
- `codex-rs/core/src/config/permissions.rs` - 权限配置

### 协议定义
- `codex-rs/protocol/src/protocol.rs` - `Op::OverrideTurnContext`, `SandboxPolicy`, `AskForApproval`
- `codex-rs/protocol/src/models.rs` - `DeveloperInstructions`

### 测试支持文件
- `codex-rs/core/tests/common/test_codex.rs` - TestCodex 测试工具
- `codex-rs/core/tests/common/responses.rs` - Mock 服务器和响应构造

### 关键类型

```rust
// 来自 codex_protocol::protocol
pub enum AskForApproval {
    Never,
    OnRequest,
    UnlessTrusted,
}

pub enum SandboxPolicy {
    DangerFullAccess,
    WorkspaceWrite { ... },
    // ...
}

// 来自 codex_protocol::models
pub struct DeveloperInstructions {
    // 生成权限指令文本
}
```

## 依赖与外部交互

### 内部依赖

```rust
// 核心依赖
anyhow::Result
codex_core::config::Constrained
codex_execpolicy::Policy
codex_protocol::models::DeveloperInstructions
codex_protocol::protocol::*
codex_utils_absolute_path::AbsolutePathBuf

// 测试支持
core_test_support::responses::*
core_test_support::skip_if_no_network
core_test_support::test_codex::test_codex
core_test_support::wait_for_event

// 工具库
pretty_assertions::assert_eq
std::collections::HashSet
tempfile::TempDir
```

### 网络依赖

所有测试都使用 `skip_if_no_network!` 宏：
```rust
skip_if_no_network!(Ok(()));
```

这是因为测试涉及实际的异步 I/O 和 rollout 文件写入。

### 多线程运行时

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```

使用多线程运行时因为：
1. Codex 内部使用多线程处理
2. Rollout 写入是异步操作
3. 需要并发处理事件和 I/O

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**: 所有测试都需要网络，增加了 CI 不稳定性和本地开发门槛。

2. **平台差异**: `permissions_message_includes_writable_roots` 测试处理路径分隔符差异：
   ```rust
   let normalize_line_endings = |s: &str| s.replace("\r\n", "\n");
   ```
   但未处理 Windows 路径格式差异。

3. **硬编码标签**: 测试依赖 `<permissions instructions>` XML 标签，如果格式改变会失败。

### 边界情况

1. **空权限消息**: 当 `approval_policy` 为 `Never` 且 `sandbox_policy` 为 `DangerFullAccess` 时，是否应发送权限消息？

2. **权限消息顺序**: 当多个权限变更快速发生时，消息顺序是否正确？

3. **并发恢复**: 多个会话同时从同一 rollout 恢复时的权限消息一致性。

4. **权限消息大小**: 大量可写根目录时的消息大小限制。

### 改进建议

1. **移除网络依赖**: 如果可能，使用完全本地的 Mock 服务器，避免网络检查。

2. **增加 Windows 路径测试**: 为 Windows 平台添加专门的路径格式测试。

3. **增加边界测试**:
   ```rust
   #[tokio::test]
   async fn permissions_message_empty_when_no_restrictions() { ... }
   
   #[tokio::test]
   async fn permissions_message_order_with_rapid_changes() { ... }
   
   #[tokio::test]
   async fn permissions_message_size_with_many_roots() { ... }
   ```

4. **使用结构化验证**: 替代字符串匹配 `<permissions instructions>`，使用 JSON/XML 解析验证结构。

5. **增加性能测试**:
   ```rust
   // 测试大量权限消息对请求体大小的影响
   // 测试权限消息生成性能
   ```

6. **增加安全测试**:
   ```rust
   // 验证权限消息不能被用户输入覆盖
   // 验证权限消息在模型响应中的位置
   ```

7. **文档化权限消息格式**: 在 `AGENTS.md` 中详细说明权限消息的 XML 结构和字段含义。

8. **增加国际化考虑**: 如果未来支持多语言，权限消息需要本地化。

9. **使用快照测试**: 对于复杂的权限消息内容，使用 `insta` 快照测试替代手动断言。

10. **增加回归测试**: 添加测试确保权限消息格式变更被显式审查。
    ```rust
    // 使用 insta 快照测试
    insta::assert_snapshot!(permissions_text);
    ```
