# model_visible_layout.rs 研究文档

## 场景与职责

`model_visible_layout.rs` 是 Codex Core 集成测试套件中专注于**模型可见请求布局**的测试文件。该文件使用快照测试（snapshot testing）验证 Codex 构建的 HTTP 请求体（特别是 `input` 数组）的结构和内容，确保：

1. **回合覆盖的正确反映**：验证 `UserTurn` 中的 `cwd`、`approval_policy`、`personality` 等覆盖项是否正确体现在请求中
2. **会话恢复后的布局一致性**：验证会话恢复（resume）后，模型可见的请求布局与预期一致
3. **AGENTS.md 的缓存行为**：验证工作目录变更时 AGENTS.md 内容的刷新策略（当前行为：不刷新）
4. **环境上下文格式**：验证 `<environment_context>` 标签中子代理（subagents）信息的正确序列化

这些测试通过捕获和比较完整的请求结构，确保 Codex 的提示工程（prompt engineering）策略按预期工作。

## 功能点目的

### 测试用例矩阵

| 测试函数 | 目的 | 验证方式 |
|----------|------|----------|
| `snapshot_model_visible_layout_turn_overrides` | 验证回合级覆盖在请求中的体现 | 快照比较两回合的请求差异 |
| `snapshot_model_visible_layout_cwd_change_does_not_refresh_agents` | 验证 cwd 变更不触发 AGENTS.md 刷新 | 断言 `user_instructions_wrapper_count` 为 0 |
| `snapshot_model_visible_layout_resume_with_personality_change` | 验证恢复会话后个性变更的布局 | 快照比较恢复前后的请求 |
| `snapshot_model_visible_layout_resume_override_matches_rollout_model` | 验证覆盖模型与恢复模型匹配时的布局 | 快照验证无冗余模型切换消息 |
| `snapshot_model_visible_layout_environment_context_includes_one_subagent` | 验证单个子代理的环境上下文格式 | 快照验证 XML 结构 |
| `snapshot_model_visible_layout_environment_context_includes_two_subagents` | 验证多个子代理的环境上下文格式 | 快照验证 XML 结构 |

## 具体技术实现

### 快照测试框架

测试使用 `insta` crate 进行快照测试，通过 `insta::assert_snapshot!` 宏比较实际输出与预期快照：

```rust
insta::assert_snapshot!(
    "model_visible_layout_turn_overrides",
    format_labeled_requests_snapshot(
        "Second turn changes cwd, approval policy, and personality while keeping model constant.",
        &[
            ("First Request (Baseline)", &requests[0]),
            ("Second Request (Turn Overrides)", &requests[1]),
        ]
    )
);
```

### 上下文快照格式化

```rust
// model_visible_layout.rs 行 32-46
fn context_snapshot_options() -> ContextSnapshotOptions {
    ContextSnapshotOptions::default()
        .render_mode(ContextSnapshotRenderMode::KindWithTextPrefix { max_chars: 96 })
}

fn format_labeled_requests_snapshot(
    scenario: &str,
    sections: &[(&str, &ResponsesRequest)],
) -> String {
    context_snapshot::format_labeled_requests_snapshot(
        scenario,
        sections,
        &context_snapshot_options(),
    )
}
```

### 关键测试场景详解

#### 1. 回合覆盖测试 (行 80-175)

验证第二回合相对于第一回合的变更：
- `cwd` 变更为 `PRETURN_CONTEXT_DIFF_CWD`
- `approval_policy` 从 `Never` 变为 `OnRequest`
- `personality` 从 `Pragmatic` 变为 `Friendly`
- 模型保持不变

预期快照应显示：
- 环境上下文差异（`EnvironmentContext::diff_from_turn_context_item`）
- 权限指令更新
- 个性规范更新（`<personality_spec>`）

#### 2. AGENTS.md 缓存行为测试 (行 177-286)

```rust
// 创建两个不同的 AGENTS.md 文件
fs::write(
    cwd_one.join("AGENTS.md"),
    "# AGENTS one\n\n<INSTRUCTIONS>\nTurn one agents instructions.\n</INSTRUCTIONS>\n",
)?;
fs::write(
    cwd_two.join("AGENTS.md"),
    "# AGENTS two\n\n<INSTRUCTIONS>\nTurn two agents instructions.\n</INSTRUCTIONS>\n",
)?;
```

验证点：
- 第一回合在 `agents_one` 目录，AGENTS.md 内容被加载
- 第二回合切换到 `agents_two` 目录
- **当前行为**：不重新加载 AGENTS.md（`user_instructions_wrapper_count` 保持为 0）
- TODO 注释（行 178-179）表明未来可能实现动态刷新

#### 3. 会话恢复布局测试 (行 288-384)

测试场景：
1. 初始会话使用模型 `gpt-5.2`
2. 恢复会话配置模型为 `gpt-5.2-codex`，个性为 `Pragmatic`
3. 恢复后的第一回合覆盖个性为 `Friendly`

验证：恢复后的请求布局正确处理了模型差异和个性变更。

#### 4. 环境上下文子代理格式 (行 486-504)

```rust
fn format_environment_context_subagents_snapshot(subagents: &[&str]) -> String {
    let subagents_block = if subagents.is_empty() {
        String::new()
    } else {
        let lines = subagents
            .iter()
            .map(|line| format!("    {line}"))
            .collect::<Vec<_>>()
            .join("\n");
        format!("\n  <subagents>\n{lines}\n  </subagents>")
    };
    // ... 构建完整的 environment_context XML
}
```

生成格式示例：
```xml
<environment_context>
  <cwd>/tmp/example</cwd>
  <shell>bash</shell>
  <subagents>
    - agent-1: Atlas
    - agent-2: Juniper
  </subagents>
</environment_context>
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 功能描述 |
|------|----------|
| `codex-rs/core/src/context_manager/updates.rs` | 构建环境更新、权限更新、个性更新等上下文项 |
| `codex-rs/core/src/environment_context.rs` | `EnvironmentContext` 结构和差异计算 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions` 和 `ResponseItem` 定义 |

### 测试支持文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/tests/common/context_snapshot.rs` | 请求快照格式化和规范化 |
| `codex-rs/core/tests/common/responses.rs` | `ResponsesRequest` 和响应解析辅助 |
| `codex-rs/core/tests/suite/snapshots/` | 存储预期快照文件（`.snap`） |

### 快照文件命名规范

```
snapshots/
└── all__suite__model_visible_layout__{test_name}.snap
```

例如：
- `all__suite__model_visible_layout__model_visible_layout_turn_overrides.snap`
- `all__suite__model_visible_layout__model_visible_layout_resume_with_personality_change.snap`

## 依赖与外部交互

### 协议层依赖

- `codex_protocol::protocol::Op::UserTurn`: 定义回合级覆盖参数
- `codex_protocol::protocol::Op::UserInput`: 简化输入操作（用于恢复测试）
- `codex_protocol::protocol::Op::OverrideTurnContext`: 预回合上下文覆盖
- `codex_protocol::config_types::Personality`: 个性枚举（`Friendly`, `Pragmatic`）

### 快照测试依赖

- **insta**: 快照测试框架，提供 `assert_snapshot!` 宏
- **serde_json**: 请求体的 JSON 序列化/反序列化

### 环境设置常量

```rust
const PRETURN_CONTEXT_DIFF_CWD: &str = "PRETURN_CONTEXT_DIFF_CWD";
```

该常量用于标记测试中特意变更的工作目录，快照格式化器会特殊处理此路径（`context_snapshot.rs` 行 305-306）。

## 风险、边界与改进建议

### 当前风险

1. **快照维护成本**：布局变更需要更新所有相关快照，可能遗漏人工审查
2. **TODO 未实现**：AGENTS.md 动态刷新功能（行 178-179）尚未实现，但测试已固化当前行为
3. **路径硬编码**：`PRETURN_CONTEXT_DIFF_CWD` 是测试专用标记，可能被误用于生产代码

### 边界情况

1. **空子代理列表**：`format_environment_context_subagents_snapshot` 处理空列表时完全省略 `<subagents>` 标签
2. **个性功能开关**：个性相关测试需要显式启用 `Feature::Personality`
3. **恢复路径依赖**：恢复测试依赖具体的恢复路径格式，若序列化格式变更，测试可能失效

### 改进建议

1. **实现 AGENTS.md 刷新**：完成 TODO 功能，然后更新测试验证新行为
2. **添加负面快照测试**：验证不应出现的项（如冗余的模型切换消息）确实不存在
3. **参数化快照选项**：当前 `max_chars: 96` 是硬编码，可考虑按测试场景调整
4. **文档化快照更新流程**：在 `AGENTS.md` 中添加如何更新快照的说明
5. **分离纯格式化测试**：`environment_context_subagents` 测试不依赖网络，可移至单元测试

### 快照更新命令

```bash
# 运行测试生成新快照
cargo test -p codex-core --test suite model_visible_layout

# 查看待审查快照
cargo insta pending-snapshots -p codex-core

# 接受所有新快照（谨慎使用）
cargo insta accept -p codex-core
```

### 相关测试文件

- `model_switching.rs`: 测试模型切换的功能性行为（本文件关注布局结构）
- `resume.rs`: 更全面的会话恢复测试
- `compact.rs` / `compact_remote.rs`: 上下文压缩对布局的影响
