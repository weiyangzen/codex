# 研究文档: codex_tui_app_server__status__tests__status_snapshot_includes_reasoning_details.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_reasoning_details`。该测试验证当模型配置包含 reasoning effort 和 reasoning summary 设置时，状态显示能正确展示这些详细信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **Reasoning Effort 显示**: high/medium/low/none
2. **Reasoning Summary 显示**: detailed/auto/none
3. **双窗口速率限制**: 5 小时和每周限制
4. **Default 权限显示**

### Reasoning 功能背景
- Reasoning Effort 控制模型的推理努力程度
- Reasoning Summary 控制推理过程的摘要方式
- 仅在使用 Responses API 时有效

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
```

### 关键流程

1. **模型详情构建** (`card.rs:166-194`):
```rust
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
```

2. **测试数据** (`tests.rs:89-168`):
```rust
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_provider_id = "openai".to_string();
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
config.permissions.sandbox_policy.set(SandboxPolicy::WorkspaceWrite { ... });

let reasoning_effort_override = Some(Some(ReasoningEffort::High));
let composite = new_status_output(
    &config,
    account_display.as_ref(),
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
    reasoning_effort_override,
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:89-168` | 测试用例定义 |
| `tui_app_server/src/status/card.rs:166-194` | 模型详情构建 |
| `tui_app_server/src/status/helpers.rs` | `compose_model_display` |

## 依赖与外部交互

### 依赖模块
- `codex_core::WireApi` - API 类型判断
- `codex_protocol::ReasoningSummary` - 摘要配置
- `codex_protocol::ReasoningEffort` - 推理努力级别

## 风险、边界与改进建议

### 当前风险
1. **API 类型硬编码**: 仅在 Responses API 时显示
2. **设置覆盖**: override 可能覆盖配置值

### 改进建议
1. **统一显示**: 考虑不区分 API 类型
2. **配置验证**: 验证 reasoning 设置与 API 类型的兼容性

### 测试覆盖
- ✅ Reasoning Effort 显示
- ✅ Reasoning Summary 显示
- ✅ 双窗口速率限制
