# DIR: codex-rs/core/tests/suite/snapshots 研究文档

## 场景与职责

`snapshots` 目录是 Codex Rust 核心模块的 **insta snapshot 测试快照存储目录**，用于存储集成测试生成的结构化快照数据。这些快照记录了 Codex 与模型交互时的请求/响应格式、上下文布局、历史记录压缩(compaction)等关键行为的预期输出。

### 核心职责

1. **回归测试防护**: 通过对比快照捕获 Codex 核心行为的变化，防止意外的行为回归
2. **文档化预期行为**: 快照文件本身就是对 Codex 内部数据流的活文档
3. **可视化模型可见上下文**: 展示 Codex 发送给模型的输入序列（input sequence）的结构
4. **验证 compaction 逻辑**: 捕获上下文压缩前后的历史记录变化

---

## 功能点目的

### 1. Snapshot 测试类型

该目录包含 28 个 `.snap` 文件，覆盖以下测试场景：

| 测试类别 | 文件数量 | 目的 |
|---------|---------|------|
| `compact` (本地压缩) | 7 | 验证手动/自动上下文压缩的行为 |
| `compact_remote` (远程压缩) | 14 | 验证通过 `/v1/responses/compact` API 的远程压缩 |
| `compact_resume_fork` | 1 | 验证压缩后的恢复(resume)和分支(fork)行为 |
| `model_visible_layout` | 6 | 验证模型可见的上下文布局变化 |

### 2. 关键测试场景详解

#### 2.1 本地 Compaction 测试 (`compact/*.snap`)

- **`manual_compact_with_history_shapes.snap`**: 手动压缩时，历史记录被压缩为摘要，后续请求包含摘要+新用户消息
- **`manual_compact_without_prev_user_shapes.snap`**: 无先前用户轮次时的压缩行为
- **`pre_turn_compaction_context_window_exceeded_shapes.snap`**: 上下文窗口超限时的预轮次压缩
- **`pre_sampling_model_switch_compaction_shapes.snap`**: 模型切换时的采样前压缩

#### 2.2 远程 Compaction 测试 (`compact_remote/*.snap`)

- **`remote_manual_compact_with_history_shapes.snap`**: 远程压缩后，历史被替换为 `compaction` 类型项
- **`remote_pre_turn_compaction_failure_shapes.snap`**: 远程压缩失败时的错误处理
- **`remote_pre_turn_compaction_restates_realtime_start/end_shapes.snap`**: Realtime 会话的压缩状态恢复

#### 2.3 模型可见布局测试 (`model_visible_layout/*.snap`)

- **`model_visible_layout_turn_overrides_shapes.snap`**: 轮次级覆盖（cwd、approval_policy、personality）对布局的影响
- **`model_visible_layout_environment_context_includes_*_subagents.snap`**: 子代理数量在环境上下文中的体现

---

## 具体技术实现

### 1. Snapshot 生成机制

#### 1.1 核心依赖: `insta` crate

```rust
// 来自 compact.rs 的示例
insta::assert_snapshot!(
    "pre_sampling_model_switch_compaction_shapes",
    format_labeled_requests_snapshot(
        "Pre-sampling compaction on model switch to a smaller context window...",
        &[
            ("Initial Request (Previous Model)", &requests[0]),
            ("Pre-sampling Compaction Request", &requests[1]),
            ("Post-Compaction Follow-up Request (Next Model)", &requests[2]),
        ]
    )
);
```

#### 1.2 Context Snapshot 工具模块

位于 `codex-rs/core/tests/common/context_snapshot.rs`:

```rust
pub enum ContextSnapshotRenderMode {
    #[default]
    RedactedText,      // 脱敏文本（默认）
    FullText,          // 完整文本
    KindOnly,          // 仅类型
    KindWithTextPrefix { max_chars: usize }, // 类型+文本前缀
}

pub struct ContextSnapshotOptions {
    render_mode: ContextSnapshotRenderMode,
    strip_capability_instructions: bool,  // 是否移除能力指令
    strip_agents_md_user_context: bool,   // 是否移除 AGENTS.md 上下文
}
```

#### 1.3 快照文本规范化

```rust
fn canonicalize_snapshot_text(text: &str) -> String {
    // 将动态内容替换为占位符，确保快照稳定性
    if text.starts_with("<permissions instructions>") {
        return "<PERMISSIONS_INSTRUCTIONS>".to_string();
    }
    if text.starts_with("<environment_context>") {
        // 提取 subagent 数量，标准化路径
        return "<ENVIRONMENT_CONTEXT:cwd=<CWD>:subagents=N>".to_string();
    }
    if text.starts_with("You are performing a CONTEXT CHECKPOINT COMPACTION.") {
        return "<SUMMARIZATION_PROMPT>".to_string();
    }
    // ... 其他规范化规则
}
```

### 2. 测试基础设施

#### 2.1 ResponseMock 请求捕获

```rust
// tests/common/responses.rs
#[derive(Debug, Clone)]
pub struct ResponseMock {
    requests: Arc<Mutex<Vec<ResponsesRequest>>>,
}

impl ResponseMock {
    pub fn single_request(&self) -> ResponsesRequest { ... }
    pub fn requests(&self) -> Vec<ResponsesRequest> { ... }
    pub fn body_contains_text(&self, text: &str) -> bool { ... }
}
```

#### 2.2 SSE 事件构造器

```rust
// 用于构造模拟的 SSE 响应流
pub fn sse(events: Vec<Value>) -> String { ... }
pub fn ev_assistant_message(id: &str, content: &str) -> Value { ... }
pub fn ev_completed(response_id: &str) -> Value { ... }
pub fn ev_completed_with_tokens(response_id: &str, tokens: i64) -> Value { ... }
```

### 3. Snapshot 文件格式

每个 `.snap` 文件是 YAML 格式的结构化数据：

```yaml
---
source: core/tests/suite/compact.rs                    # 源测试文件
expression: "format_labeled_requests_snapshot(...)"     # 生成表达式
---
Scenario: 测试场景描述

## 请求/响应段标题
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:hello world
03:message/assistant:FIRST_REPLY
04:message/user:<SUMMARIZATION_PROMPT>
```

### 4. 关键数据结构

#### 4.1 请求输入项类型映射

| 快照前缀 | OpenAI API 类型 | 说明 |
|---------|----------------|------|
| `message/developer` | `message` (role=developer) | 系统/开发者指令 |
| `message/user` | `message` (role=user) | 用户输入 |
| `message/assistant` | `message` (role=assistant) | 助手回复 |
| `function_call` | `function_call` | 工具调用 |
| `function_call_output` | `function_call_output` | 工具输出 |
| `local_shell_call` | `local_shell_call` | 本地 shell 调用 |
| `compaction` | `compaction` | 压缩摘要项 |
| `reasoning` | `reasoning` | 推理项 |

---

## 关键代码路径与文件引用

### 4.1 测试源文件 → Snapshot 映射

| 测试源文件 | 生成 Snapshot 数量 | 关键测试函数 |
|-----------|-------------------|-------------|
| `compact.rs` | 7 | `pre_sampling_model_switch_compaction`, `manual_compact_*` |
| `compact_remote.rs` | 14 | `remote_manual_compact_*`, `remote_pre_turn_compaction_*` |
| `compact_resume_fork.rs` | 1 | `snapshot_rollback_past_compaction_replays_append_only_history` |
| `model_visible_layout.rs` | 6 | `snapshot_model_visible_layout_*` |

### 4.2 核心代码路径

```
codex-rs/core/
├── tests/
│   ├── suite/
│   │   ├── snapshots/              # ← 本目录（快照存储）
│   │   ├── compact.rs              # 本地 compaction 测试
│   │   ├── compact_remote.rs       # 远程 compaction 测试
│   │   ├── compact_resume_fork.rs  # 恢复/分支测试
│   │   └── model_visible_layout.rs # 模型可见布局测试
│   └── common/
│       ├── context_snapshot.rs     # 快照格式化逻辑
│       ├── responses.rs            # Mock 响应服务器
│       └── test_codex.rs           # 测试构建器
└── src/
    └── compact.rs                  # Compaction 核心实现
```

### 4.3 关键函数调用链

```
测试函数
  └─> insta::assert_snapshot!(name, formatted_output)
        └─> format_labeled_requests_snapshot(scenario, sections, options)
              └─> context_snapshot::format_request_input_snapshot(request, options)
                    └─> format_response_items_snapshot(items, options)
                          └─> canonicalize_snapshot_text(text)  // 规范化
```

---

## 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|-----|------|
| `insta` | Snapshot 测试框架，提供 `assert_snapshot!` 宏 |
| `wiremock` | HTTP Mock 服务器，模拟 OpenAI API |
| `serde_json` | JSON 序列化/反序列化 |
| `tokio` | 异步运行时 |
| `regex-lite` | 快照文本正则处理 |

### 5.2 内部模块依赖

```rust
// 测试中使用的主要内部模块
use core_test_support::context_snapshot;           // 快照格式化
use core_test_support::responses::*;               // Mock 响应
use core_test_support::test_codex::test_codex;     // 测试构建器
use core_test_support::wait_for_event;             // 事件等待

use codex_core::compact::SUMMARIZATION_PROMPT;     // 压缩提示词
use codex_protocol::protocol::*;                   // 协议类型
```

### 5.3 环境配置

```rust
// tests/common/lib.rs
#[ctor]
fn configure_insta_workspace_root_for_snapshot_tests() {
    // 设置 INSTA_WORKSPACE_ROOT 环境变量
    // 确保快照文件存储在正确的相对路径
    unsafe {
        std::env::set_var("INSTA_WORKSPACE_ROOT", workspace_root);
    }
}
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 快照脆弱性 (Snapshot Fragility)

- **风险**: 任何改变请求/响应格式的代码变更都会导致大量快照测试失败
- **缓解**: `canonicalize_snapshot_text` 函数将动态内容（如路径、临时ID）替换为占位符
- **注意**: 新增字段或改变顺序仍需更新快照

#### 6.1.2 平台差异

- **风险**: Windows/Linux/macOS 的路径格式、换行符差异
- **缓解**: `normalize_line_endings` 和 `normalize_snapshot_line_endings` 统一处理

#### 6.1.3 测试间依赖

- **风险**: 快照测试依赖于特定的 Mock 服务器响应顺序
- **缓解**: 使用 `mount_sse_sequence` 和请求匹配器确保确定性

### 6.2 边界情况

| 边界场景 | 当前处理 |
|---------|---------|
| 空历史压缩 | `manual_compact_without_prev_user_shapes.snap` 覆盖 |
| 上下文窗口超限 | `pre_turn_compaction_context_window_exceeded_shapes.snap` 覆盖 |
| 远程压缩失败 | `remote_pre_turn_compaction_failure_shapes.snap` 覆盖 |
| 多子代理环境 | `model_visible_layout_environment_context_includes_*_subagents.snap` 覆盖 |
| Realtime 会话压缩 | `remote_*_restates_realtime_*.snap` 系列覆盖 |

### 6.3 改进建议

#### 6.3.1 快照组织优化

```
# 当前: 扁平命名
all__suite__compact__manual_compact_with_history_shapes.snap

# 建议: 分层目录结构
compact/
  manual/
    with_history.snap
    without_prev_user.snap
  auto/
    pre_turn_context_window_exceeded.snap
```

#### 6.3.2 增强快照可读性

- 当前快照使用缩写格式（如 `message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>`）
- 建议增加可选的详细模式，展示完整 JSON 结构（用于调试）

#### 6.3.3 自动化快照审查

- 建议添加 CI 检查，当快照变更时自动生成可视化 diff 报告
- 可参考 `cargo insta show` 集成到 PR review 流程

#### 6.3.4 覆盖缺口

- 缺少对 `truncation`（截断）行为的快照覆盖
- 缺少对多模态输入（图片+文本）的详细布局快照
- 建议增加对错误恢复路径的快照测试

### 6.4 维护最佳实践

1. **更新快照流程**:
   ```bash
   cargo test -p codex-core  # 生成 .snap.new 文件
   cargo insta review        # 交互式审查变更
   cargo insta accept        # 接受变更
   ```

2. **新增快照测试时**:
   - 使用描述性的场景名称
   - 确保 `canonicalize_snapshot_text` 处理所有动态内容
   - 在注释中说明测试的意图和覆盖的边界情况

3. **审查快照变更时**:
   - 检查是否有意外的字段顺序变化
   - 验证占位符替换是否完整（无绝对路径残留）
   - 确认新增/删除的项是否符合预期行为

---

## 附录: Snapshot 文件完整列表

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
└── all__suite__model_visible_layout__model_visible_layout_turn_overrides_shapes.snap
```

---

*文档生成时间: 2026-03-21*
*基于 codex-rs 仓库 commit: HEAD*
