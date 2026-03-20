# Research: codex-rs/core/tests/suite/snapshots

## 场景与职责

`snapshots` 目录是 Codex Rust 核心测试套件的**快照测试数据存储目录**，使用 [`insta`](https://insta.rs/) 快照测试框架管理。该目录存储了 28 个 `.snap` 文件，这些文件记录了模型可见布局（model-visible layout）和上下文压缩（context compaction）相关测试的预期输出。

**核心职责：**
1. **回归测试保护**：捕获并持久化 Codex 核心向模型发送的请求结构，确保代码变更不会意外改变模型可见的上下文布局
2. **文档化行为**：作为可读的规格说明，展示不同场景下 Codex 如何组织发送给模型的消息序列
3. **跨平台一致性**：通过规范化处理（如路径、临时目录），确保测试在不同环境下结果一致

---

## 功能点目的

### 1. 上下文压缩（Context Compaction）快照

**测试场景覆盖：**
- **手动压缩** (`manual_compact_*`)：用户主动触发 `/compact` 命令时的请求结构
- **自动压缩** (`pre_turn_compaction_*`)：当 token 使用量超过阈值时自动触发的压缩
- **采样前压缩** (`pre_sampling_model_switch_*`)：切换到更小上下文窗口模型时的预处理压缩
- **回合中压缩** (`mid_turn_compaction_*`)：多轮对话过程中的中间压缩
- **恢复与分支** (`compact_resume_*`, `rollback_past_*`)：会话恢复和 fork 后的压缩状态保持

**关键验证点：**
- 压缩请求是否包含正确的 summarization prompt
- 压缩后的历史记录是否以 summary 消息形式重新注入
- 开发者指令（developer instructions）是否在压缩后保持
- 模型切换标记（model-switch）的处理是否正确

### 2. 远程压缩（Remote Compaction）快照

**测试场景覆盖：**
- 远程 `/v1/responses/compact` API 调用的请求结构
- 实时对话（realtime conversation）场景下的压缩行为
- 远程压缩失败时的错误处理

**关键验证点：**
- 远程压缩请求是否包含正确的认证头（session_id, authorization）
- 压缩输出是否正确地以 compaction item 形式返回
- 实时对话开始/结束标记的重新注入行为

### 3. 模型可见布局（Model Visible Layout）快照

**测试场景覆盖：**
- **回合覆盖** (`turn_overrides`)：单轮对话中 cwd、approval_policy、personality 的变更
- **会话恢复** (`resume_*`)：从 rollout 文件恢复会话后的首回合请求结构
- **环境上下文** (`environment_context_*`)：包含子代理（subagents）信息的环境上下文格式

**关键验证点：**
- 系统指令（system instructions）的正确排序和分组
- 用户消息与开发者消息的相对位置
- 环境上下文（environment_context）XML 结构的正确性
- AGENTS.md 指令的注入时机和格式

---

## 具体技术实现

### 快照生成流程

```rust
// 典型测试模式（来自 compact.rs）
insta::assert_snapshot!(
    "manual_compact_with_history_shapes",
    format_labeled_requests_snapshot(
        "Manual /compact with prior user history compacts existing history...",
        &[
            ("Local Compaction Request", &requests[1]),
            ("Local Post-Compaction History Layout", &requests[2]),
        ]
    )
);
```

**关键组件：**

1. **`format_labeled_requests_snapshot`** (`context_snapshot.rs:209-225`)
   - 将多个 HTTP 请求格式化为带标签的快照文本
   - 支持多种渲染模式（RedactedText, FullText, KindOnly, KindWithTextPrefix）

2. **`format_request_input_snapshot`** (`context_snapshot.rs:55-61`)
   - 提取请求中的 `input` 数组（OpenAI Responses API 格式）
   - 将 JSON 结构转换为人类可读的文本表示

3. **`format_response_items_snapshot`** (`context_snapshot.rs:63-207`)
   - 核心格式化逻辑，处理多种 item 类型：
     - `message`: 按 role（user/developer/assistant）分类，处理多 part 内容
     - `function_call` / `function_call_output`: 工具调用及其输出
     - `local_shell_call`: 本地 shell 命令执行
     - `reasoning`: 推理内容（含 encrypted_content 标记）
     - `compaction`: 压缩摘要项

### 文本规范化处理

**`canonicalize_snapshot_text`** (`context_snapshot.rs:271-326`) 实现敏感内容的脱敏和标准化：

| 原始内容模式 | 规范化后 |
|-------------|---------|
| `<permissions instructions>...` | `<PERMISSIONS_INSTRUCTIONS>` |
| `<apps_instructions>...` | `<APPS_INSTRUCTIONS>` |
| `<skills_instructions>...` | `<SKILLS_INSTRUCTIONS>` |
| `<plugins_instructions>...` | `<PLUGINS_INSTRUCTIONS>` |
| `# AGENTS.md instructions for ...` | `<AGENTS_MD>` |
| `<environment_context>...<cwd>X...</cwd>...</environment_context>` | `<ENVIRONMENT_CONTEXT:cwd=<CWD>>` |
| `You are performing a CONTEXT CHECKPOINT COMPACTION...` | `<SUMMARIZATION_PROMPT>` |
| `Another language model started to solve this problem\n{summary}` | `<COMPACTION_SUMMARY>\n{summary}` |
| `/.../skills/.system/{name}/SKILL.md` | `<SYSTEM_SKILLS_ROOT>/{name}/SKILL.md` |

### 渲染模式配置

**`ContextSnapshotOptions`** 结构体控制快照输出格式：

```rust
pub struct ContextSnapshotOptions {
    render_mode: ContextSnapshotRenderMode,  // 文本渲染模式
    strip_capability_instructions: bool,      // 是否移除 capability 指令
    strip_agents_md_user_context: bool,       // 是否移除 AGENTS.md 上下文
}
```

**渲染模式：**
- `RedactedText`（默认）：使用占位符替换敏感/长文本
- `FullText`：保留完整文本（用于调试）
- `KindOnly`：仅显示 item 类型和 role
- `KindWithTextPrefix { max_chars }`：显示类型和前 N 个字符（测试中最常用）

---

## 关键代码路径与文件引用

### 快照测试定义位置

| 快照文件前缀 | 测试源文件 | 测试函数 |
|-------------|-----------|---------|
| `all__suite__compact__*` | `codex-rs/core/tests/suite/compact.rs` | 多个测试函数（见下表） |
| `all__suite__compact_remote__*` | `codex-rs/core/tests/suite/compact_remote.rs` | 远程压缩相关测试 |
| `all__suite__compact_resume_fork__*` | `codex-rs/core/tests/suite/compact_resume_fork.rs` | 恢复/分支相关测试 |
| `all__suite__model_visible_layout__*` | `codex-rs/core/tests/suite/model_visible_layout.rs` | 布局快照测试 |

### 核心测试函数与快照对应关系

**compact.rs 中的快照测试：**

| 快照名称 | 测试函数 | 描述 |
|---------|---------|------|
| `manual_compact_with_history_shapes` | `summarize_context_three_requests_and_instructions` | 手动压缩保留历史记录 |
| `manual_compact_without_prev_user_shapes` | （内联在 `summarize_context_*`） | 无前序用户消息的手动压缩 |
| `pre_turn_compaction_context_window_exceeded_shapes` | `auto_compact_runs_after_token_limit_hit` | 上下文窗口超限的自动压缩 |
| `pre_turn_compaction_including_incoming_shapes` | `auto_compact_runs_after_resume_when_token_usage_is_over_limit` | 包含传入消息的预回合压缩 |
| `pre_turn_compaction_strips_incoming_model_switch_shapes` | `pre_sampling_compact_runs_on_switch_to_smaller_context_model` | 压缩时剥离模型切换标记 |
| `pre_sampling_model_switch_compaction_shapes` | `pre_sampling_compact_runs_on_switch_to_smaller_context_model` | 采样前模型切换压缩 |
| `mid_turn_compaction_shapes` | `multiple_auto_compact_per_task_runs_after_token_limit_hit` | 回合中多次自动压缩 |

**compact_remote.rs 中的快照测试：**

| 快照名称 | 测试函数 | 描述 |
|---------|---------|------|
| `remote_manual_compact_with_history_shapes` | `remote_compact_replaces_history_for_followups` | 远程手动压缩 |
| `remote_manual_compact_without_prev_user_shapes` | （相关测试） | 无前序用户消息的远程压缩 |
| `remote_pre_turn_compaction_*` | 多个测试 | 远程预回合压缩场景 |
| `remote_mid_turn_compaction_*` | 多个测试 | 远程回合中压缩场景 |
| `remote_compact_resume_*` | 恢复场景测试 | 恢复后的远程压缩 |

**compact_resume_fork.rs 中的快照测试：**

| 快照名称 | 测试函数 | 描述 |
|---------|---------|------|
| `rollback_past_compaction_shapes` | `snapshot_rollback_past_compaction_replays_append_only_history` | 回滚过压缩点的历史重放 |

**model_visible_layout.rs 中的快照测试：**

| 快照名称 | 测试函数 | 描述 |
|---------|---------|------|
| `model_visible_layout_turn_overrides` | `snapshot_model_visible_layout_turn_overrides` | 回合参数覆盖 |
| `model_visible_layout_cwd_change_does_not_refresh_agents` | `snapshot_model_visible_layout_cwd_change_does_not_refresh_agents` | cwd 变更不刷新 agents |
| `model_visible_layout_resume_with_personality_change` | `snapshot_model_visible_layout_resume_with_personality_change` | 恢复时 personality 变更 |
| `model_visible_layout_resume_override_matches_rollout_model` | `snapshot_model_visible_layout_resume_override_matches_rollout_model` | 覆盖匹配 rollout 模型 |
| `model_visible_layout_environment_context_includes_*` | 对应测试 | 环境上下文包含子代理 |

### 支持模块

| 文件 | 职责 |
|-----|------|
| `codex-rs/core/tests/common/context_snapshot.rs` | 快照格式化核心实现 |
| `codex-rs/core/tests/common/responses.rs` | Mock 服务器和响应构造工具 |
| `codex-rs/core/tests/common/test_codex.rs` | 测试用的 Codex 实例构建器 |
| `codex-rs/core/tests/suite/mod.rs` | 测试模块聚合和初始化 |

---

## 依赖与外部交互

### 内部依赖

```
snapshots/ (数据文件)
    ↑ 读取/生成
context_snapshot.rs (格式化逻辑)
    ↑ 使用
compact.rs, compact_remote.rs, compact_resume_fork.rs, model_visible_layout.rs (测试定义)
    ↑ 使用
responses.rs (Mock 服务器)
    ↑ 使用
codex_core (被测 crate)
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `insta` | 快照测试框架，提供 `assert_snapshot!` 宏 |
| `serde_json` | JSON 序列化/反序列化 |
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `regex_lite` | 正则表达式处理（路径规范化） |

### 环境配置

**`INSTA_WORKSPACE_ROOT`** (`lib.rs:34-51`)
- 在测试初始化时设置，指向 `codex-rs/` 目录
- 确保 insta 能正确找到快照文件的相对路径

**`CODEX_HOME`** (`mod.rs:15-55`)
- 测试前临时设置为临时目录，避免污染用户真实配置
- 测试后恢复原始值

---

## 风险、边界与改进建议

### 当前风险

1. **快照文件膨胀**
   - 28 个快照文件已覆盖多种场景，但新增功能可能需要更多快照
   - 建议：定期审查是否有重复或冗余的快照

2. **规范化遗漏**
   - 新添加的敏感信息类型（如新指令格式）需要同步更新 `canonicalize_snapshot_text`
   - 风险：未规范化的动态内容（如时间戳、UUID）会导致测试不稳定

3. **跨平台差异**
   - Windows 路径分隔符、换行符（CRLF vs LF）已通过 `normalize_line_endings` 处理
   - 但某些平台特定行为（如 shell 命令）仍可能导致差异

### 边界情况

1. **空历史压缩**
   - 测试 `manual_compact_without_prev_user_shapes` 覆盖无历史时的压缩行为
   - 边界：压缩请求应仅包含指令和 summarization prompt

2. **多次连续压缩**
   - `multiple_auto_compact_per_task_runs_after_token_limit_hit` 测试单轮内多次压缩
   - 边界：需确保 summary 消息的正确堆叠

3. **实时对话状态**
   - 远程压缩测试需处理 `<realtime_conversation>` 标记的重新注入
   - 边界：压缩后恢复对话时，标记顺序必须正确

### 改进建议

1. **快照文档化**
   - 当前快照文件名较长且含义不够直观
   - 建议：在快照文件头部添加更详细的场景描述注释

2. **自动化审查**
   - 建议：添加 CI 检查，当 `context_snapshot.rs` 变更时提醒更新相关快照

3. **性能优化**
   - 当前每个快照测试都启动完整 Codex 实例
   - 建议：考虑共享测试基础设施（如 Mock 服务器）以减少启动开销

4. **覆盖率扩展**
   - 当前缺少对以下场景的快照覆盖：
     - 多模态输入（图片 + 文本）的模型可见布局
     - 工具调用链（function calling chain）的压缩行为
     - 错误恢复场景（如部分压缩失败）的请求结构

---

## 附录：快照文件完整列表

```
codex-rs/core/tests/suite/snapshots/
├── all__suite__compact__manual_compact_with_history_shapes.snap
├── all__suite__compact__manual_compact_without_prev_user_shapes.snap
├── all__suite__compact__mid_turn_compaction_shapes.snap
├── all__suite__compact__pre_sampling_model_switch_compaction_shapes.snap
├── all__suite__compact__pre_turn_compaction_context_window_exceeded_shapes.snap
├── all__suite__compact__pre_turn_compaction_including_incoming_shapes.snap
├── all__suite__compact__pre_turn_compaction_strips_incoming_model_switch_shapes.snap
├── all__suite__compact_remote__remote_compact_resume_restates_realtime_end_shapes.snap
├── all__suite__compact_remote__remote_manual_compact_restates_realtime_start_shapes.snap
├── all__suite__compact_remote__remote_manual_compact_with_history_shapes.snap
├── all__suite__compact_remote__remote_manual_compact_without_prev_user_shapes.snap
├── all__suite__compact_remote__remote_mid_turn_compaction_does_not_restate_realtime_end_shapes.snap
├── all__suite__compact_remote__remote_mid_turn_compaction_multi_summary_reinjects_above_last_summary_shapes.snap
├── all__suite__compact_remote__remote_mid_turn_compaction_shapes.snap
├── all__suite__compact_remote__remote_mid_turn_compaction_summary_only_reinjects_context_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_context_window_exceeded_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_failure_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_including_incoming_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_restates_realtime_end_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_restates_realtime_start_shapes.snap
├── all__suite__compact_remote__remote_pre_turn_compaction_strips_incoming_model_switch_shapes.snap
├── all__suite__compact_resume_fork__rollback_past_compaction_shapes.snap
├── all__suite__model_visible_layout__model_visible_layout_cwd_change_does_not_refresh_agents.snap
├── all__suite__model_visible_layout__model_visible_layout_environment_context_includes_one_subagent.snap
├── all__suite__model_visible_layout__model_visible_layout_environment_context_includes_two_subagents.snap
├── all__suite__model_visible_layout__model_visible_layout_resume_override_matches_rollout_model.snap
├── all__suite__model_visible_layout__model_visible_layout_resume_with_personality_change.snap
└── all__suite__model_visible_layout__model_visible_layout_turn_overrides.snap
```

---

*Generated: 2026-03-21*
*Research Scope: DIR codex-rs/core/tests/suite/snapshots*
