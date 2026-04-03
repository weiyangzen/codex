# 研究文档: status_snapshot_includes_reasoning_details.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_reasoning_details`。该测试验证当模型配置包含 reasoning effort 和 reasoning summary 设置时，状态显示能正确展示这些详细信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **Reasoning Effort 显示**: 显示模型的推理努力级别（high/medium/low/none）
2. **Reasoning Summary 显示**: 显示推理摘要配置（detailed/auto/none）
3. **双窗口速率限制**: 显示 5 小时和每周限制
4. **Custom 权限显示**: 当权限非默认时显示详细信息

### 业务逻辑
- Reasoning Effort 控制模型在推理时投入的"思考"程度
- Reasoning Summary 控制是否以及如何总结推理过程
- 这些设置仅在使用 Responses API 时有效

## 具体技术实现

### 关键数据结构

```rust
pub enum ReasoningEffort {
    High,
    Medium,
    Low,
}

pub enum ReasoningSummary {
    Detailed,
    Auto,
    None,
}

pub enum WireApi {
    Responses,  // 支持 reasoning 设置
    ChatCompletions,
}
```

### 关键流程

1. **模型详情构建** (`card.rs:167-194`):
```rust
let mut config_entries = vec![
    ("workdir", config.cwd.display().to_string()),
    ("model", model_name.to_string()),
    ("provider", config.model_provider_id.clone()),
    ("approval", config.permissions.approval_policy.value().to_string()),
    ("sandbox", summarize_sandbox_policy(...)),
];

// 仅在 Responses API 时添加 reasoning 设置
if config.model_provider.wire_api == WireApi::Responses {
    let effort_value = reasoning_effort_override
        .unwrap_or(None)
        .map(|effort| effort.to_string())
        .unwrap_or_else(|| "none".to_string());
    config_entries.push(("reasoning effort", effort_value));
    config_entries.push(("reasoning summaries", 
        config.model_reasoning_summary
            .map(|summary| summary.to_string())
            .unwrap_or_else(|| "auto".to_string())
    ));
}
let (model_name, model_details) = compose_model_display(model_name, &config_entries);
```

2. **模型显示格式化** (`helpers.rs`):
```rust
pub(crate) fn compose_model_display(
    model_name: &str,
    config_entries: &[(&str, String)],
) -> (String, Vec<String>) {
    // 提取非核心配置作为 details
    let details: Vec<String> = config_entries
        .iter()
        .filter(|(k, _)| !matches!(*k, "model" | "workdir"))
        .map(|(k, v)| format!("{k}: {v}"))
        .collect();
    (model_name.to_string(), details)
}
```

3. **测试数据设置** (`tests.rs:93-172`):
```rust
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_provider_id = "openai".to_string();
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
config.permissions.sandbox_policy.set(SandboxPolicy::WorkspaceWrite {
    writable_roots: Vec::new(),
    read_only_access: Default::default(),
    network_access: false,
    ...
}).expect("set sandbox policy");

let reasoning_effort_override = Some(Some(ReasoningEffort::High));
let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    Some(&rate_display),
    None,
    captured_at,
    &model_slug,
    None,
    reasoning_effort_override,  // 传递 reasoning effort
);
```

4. **权限显示** (`card.rs:216-227`):
```rust
let permissions = if config.permissions.approval_policy.value() == AskForApproval::OnRequest
    && *config.permissions.sandbox_policy.get() == SandboxPolicy::new_workspace_write_policy()
{
    "Default".to_string()
} else {
    format!("Custom ({sandbox}, {approval})")  // 本测试中显示 Custom
};
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:93-172` | 测试用例定义 |
| `tui/src/status/card.rs:167-194` | 模型详情构建（含 reasoning 设置） |
| `tui/src/status/card.rs:216-227` | 权限显示逻辑 |
| `tui/src/status/helpers.rs` | `compose_model_display` - 模型显示格式化 |
| `codex_protocol/src/config_types.rs` | `ReasoningSummary` 定义 |
| `codex_protocol/src/openai_models.rs` | `ReasoningEffort` 定义 |

## 依赖与外部交互

### 依赖模块
- `codex_core::WireApi` - API 类型判断
- `codex_protocol::config_types::ReasoningSummary` - 摘要配置
- `codex_protocol::openai_models::ReasoningEffort` - 推理努力级别
- `codex_utils_sandbox_summary` - 沙盒策略摘要

### 显示格式
模型行显示格式：`Model: gpt-5.1-codex-max (reasoning high, summaries detailed)`
- 模型名称 + 括号内的详细信息
- 详细信息以逗号分隔的 key: value 对形式呈现

## 风险、边界与改进建议

### 当前风险
1. **API 类型硬编码**: 仅在 `WireApi::Responses` 时显示 reasoning 设置，如果 API 类型变更可能遗漏
2. **设置覆盖**: `reasoning_effort_override` 可能覆盖配置值，用户可能困惑

### 边界情况
1. **Chat Completions API**: 使用此 API 时不显示 reasoning 设置，即使配置了
2. **空 Details**: 如果所有配置都是默认值，details 为空，不显示括号
3. **长 Details**: 如果配置项很多，details 可能很长，在窄终端被截断

### 改进建议
1. **统一配置显示**: 考虑将所有配置项统一显示，不区分 API 类型
2. **图标标识**: 使用图标或颜色区分不同 API 类型的能力
3. **配置验证**: 在配置阶段验证 reasoning 设置与 API 类型的兼容性
4. **折叠显示**: 对于长 details，考虑可折叠的显示方式

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ Reasoning Effort 显示（high）
- ✅ Reasoning Summary 显示（detailed）
- ✅ Custom 权限显示
- ✅ 双窗口速率限制（5h + Weekly）
- ✅ Token 使用统计

### 相关测试
- `status_snapshot_truncates_in_narrow_terminal` - 测试窄终端截断
- `status_permissions_non_default_workspace_write_is_custom` - 测试权限显示
