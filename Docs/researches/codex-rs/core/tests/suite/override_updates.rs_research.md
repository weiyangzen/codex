# override_updates.rs 研究文档

## 场景与职责

`override_updates.rs` 是 Codex 核心库的上下文覆盖更新测试套件。它负责验证 `OverrideTurnContext` 操作在不同场景下的行为，特别是当没有用户回合 (user turn) 时，某些更新不应被记录到 rollout 中。

这些测试确保 Codex 的上下文管理系统能够正确地：
- 延迟记录权限更新直到下一个用户回合开始
- 延迟记录环境更新直到下一个用户回合开始
- 延迟记录协作模式更新直到下一个用户回合开始

这是 Codex 会话管理的关键部分，确保 rollout 文件（用于会话恢复和分叉）包含正确的上下文信息。

## 功能点目的

### 1. 权限策略更新延迟 (`override_turn_context_without_user_turn_does_not_record_permissions_update`)

验证在没有用户回合的情况下，通过 `OverrideTurnContext` 修改 `approval_policy` 不会立即在 rollout 中记录权限更新。这确保了：
- 用户可以在不触发新回合的情况下预览或准备配置变更
- 权限更新只在实际用户交互时生效并记录
- 避免在 rollout 中产生孤立的权限更新记录

### 2. 环境上下文更新延迟 (`override_turn_context_without_user_turn_does_not_record_environment_update`)

验证在没有用户回合的情况下，通过 `OverrideTurnContext` 修改工作目录 (`cwd`) 不会立即在 rollout 中记录环境更新。这确保了：
- 工作目录变更与实际的文件操作回合关联
- rollout 中的环境上下文始终与有意义的用户交互对齐

### 3. 协作模式更新延迟 (`override_turn_context_without_user_turn_does_not_record_collaboration_update`)

验证在没有用户回合的情况下，通过 `OverrideTurnContext` 修改协作模式 (`collaboration_mode`) 不会立即在 rollout 中记录协作指令更新。这确保了：
- 协作指令更新与实际的用户查询关联
- 避免在 rollout 中产生孤立的协作模式变更记录

## 具体技术实现

### 关键数据结构

```rust
// 协作模式辅助构造函数
fn collab_mode_with_instructions(instructions: Option<&str>) -> CollaborationMode {
    CollaborationMode {
        mode: ModeKind::Default,
        settings: Settings {
            model: "gpt-5.1".to_string(),
            reasoning_effort: None,
            developer_instructions: instructions.map(str::to_string),
        },
    }
}

// 协作指令 XML 包装
fn collab_xml(text: &str) -> String {
    format!("{COLLABORATION_MODE_OPEN_TAG}{text}{COLLABORATION_MODE_CLOSE_TAG}")
}
```

### Rollout 文件读取与解析

```rust
async fn read_rollout_text(path: &Path) -> anyhow::Result<String> {
    for _ in 0..50 {
        if path.exists()
            && let Ok(text) = std::fs::read_to_string(path)
            && !text.trim().is_empty()
        {
            return Ok(text);
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    Ok(std::fs::read_to_string(path)?)
}
```

使用轮询机制等待 rollout 文件写入完成，最多等待 1 秒（50 * 20ms）。

### Rollout 内容解析器

```rust
fn rollout_developer_texts(text: &str) -> Vec<String> {
    // 解析 rollout 中的 developer 角色消息
    // 用于验证权限指令是否被记录
}

fn rollout_environment_texts(text: &str) -> Vec<String> {
    // 解析 rollout 中的 environment_context 标签内容
    // 用于验证环境更新是否被记录
}
```

### 测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn override_turn_context_without_user_turn_does_not_record_permissions_update() -> Result<()> {
    skip_if_no_network!(Ok(()));

    // 1. 启动 mock 服务器
    let server = start_mock_server().await;
    
    // 2. 配置测试环境（approval_policy = OnRequest）
    let mut builder = test_codex().with_config(|config| {
        config.permissions.approval_policy = Constrained::allow_any(AskForApproval::OnRequest);
    });
    let test = builder.build(&server).await?;

    // 3. 提交 OverrideTurnContext 修改 approval_policy 为 Never
    // 注意：没有提交 UserInput！
    test.codex.submit(Op::OverrideTurnContext {
        cwd: None,
        approval_policy: Some(AskForApproval::Never),
        // ... 其他字段为 None
    }).await?;

    // 4. 关闭会话
    test.codex.submit(Op::Shutdown).await?;
    wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::ShutdownComplete)).await;

    // 5. 读取 rollout 文件并验证
    let rollout_path = test.codex.rollout_path().expect("rollout path");
    let rollout_text = read_rollout_text(&rollout_path).await?;
    let developer_texts = rollout_developer_texts(&rollout_text);
    
    // 6. 断言：不应包含权限更新
    let approval_texts: Vec<&String> = developer_texts
        .iter()
        .filter(|text| text.contains("`approval_policy`"))
        .collect();
    assert!(approval_texts.is_empty(), "did not expect permissions updates before a new user turn");

    Ok(())
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/override_updates.rs` - 本测试文件

### 被测试的源文件
- `codex-rs/core/src/codex.rs` - Codex 核心实现，处理 `OverrideTurnContext`
- `codex-rs/core/src/context_manager/mod.rs` - 上下文管理器
- `codex-rs/core/src/context_manager/updates.rs` - 上下文更新逻辑
- `codex-rs/core/src/rollout/recorder.rs` - Rollout 记录器

### 协议定义
- `codex-rs/protocol/src/protocol.rs` - `Op::OverrideTurnContext` 定义
- `codex-rs/protocol/src/config_types.rs` - `CollaborationMode`, `ModeKind`, `Settings`

### 测试支持文件
- `codex-rs/core/tests/common/test_codex.rs` - TestCodex 测试工具
- `codex-rs/core/tests/common/responses.rs` - Mock 服务器

### 关键常量
```rust
// 来自 codex_protocol::protocol
COLLABORATION_MODE_OPEN_TAG
COLLABORATION_MODE_CLOSE_TAG
ENVIRONMENT_CONTEXT_OPEN_TAG
```

## 依赖与外部交互

### 内部依赖

```rust
// 核心依赖
anyhow::Result
codex_core::config::Constrained
codex_protocol::protocol::*
codex_protocol::config_types::*
codex_protocol::models::ContentItem
codex_protocol::models::ResponseItem

// 测试支持
core_test_support::responses::start_mock_server
core_test_support::skip_if_no_network
core_test_support::test_codex::test_codex
core_test_support::wait_for_event

// 工具库
tempfile::TempDir
pretty_assertions::assert_eq
```

### 网络依赖

测试使用 `skip_if_no_network!` 宏检查网络可用性：
```rust
skip_if_no_network!(Ok(()));
```

这意味着测试需要网络连接（或至少网络未被禁用），因为实际的 rollout 写入可能涉及异步 I/O 操作。

### 多线程运行时

测试使用多线程运行时配置：
```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```

这是因为：
1. Codex 内部使用多线程处理
2. Rollout 写入是异步操作
3. 需要并发处理事件和 I/O

## 风险、边界与改进建议

### 当前风险

1. **轮询等待脆弱性**: `read_rollout_text` 使用固定间隔的轮询等待文件写入，如果系统负载高可能导致超时。

2. **网络依赖**: 测试标记为需要网络，但实际上主要测试本地文件系统行为，这种依赖可能不必要。

3. **平台差异**: 测试使用 `tempfile::TempDir`，在不同平台上的文件系统行为可能有细微差异。

### 边界情况

1. **并发覆盖**: 测试未覆盖多个 `OverrideTurnContext` 操作并发提交的场景。

2. **部分字段更新**: 测试验证了单个字段更新，但多个字段同时更新的组合场景覆盖不足。

3. **会话恢复**: 测试验证了 rollout 不包含更新，但未验证从该 rollout 恢复会话后的行为。

### 改进建议

1. **使用文件系统事件而非轮询**: 
   ```rust
   // 使用 notify crate 监听文件变化
   use notify::{Watcher, RecursiveMode};
   ```

2. **增加组合测试**: 测试同时更新多个字段（approval_policy + cwd + collaboration_mode）的行为。

3. **增加恢复验证**: 在测试末尾添加从 rollout 恢复会话并验证状态的步骤。

4. **移除不必要的网络依赖**: 如果可能，使用完全本地的 Mock 服务器，避免网络检查。

5. **增加错误场景测试**:
   - 无效的 approval_policy 值
   - 不存在的工作目录路径
   - 损坏的协作模式配置

6. **性能测试**: 测试大量 `OverrideTurnContext` 操作对内存和 rollout 文件大小的影响。

7. **文档化延迟更新语义**: 在代码注释或文档中明确说明哪些更新是延迟的，哪些是立即生效的。

8. **增加状态一致性测试**: 验证即使 rollout 未记录，内部状态是否正确更新（以便下一个用户回合使用正确的配置）。
