# 研究文档：status_snapshot_includes_reasoning_details.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块对推理（reasoning）配置详细信息的正确渲染。当用户使用支持推理的模型（如 gpt-5.1-codex-max）并配置了特定的推理努力和推理摘要设置时，状态卡片需要正确显示这些高级配置。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_includes_reasoning_details` 测试函数，验证推理相关配置在模型详情中的展示。

## 功能点目的

### 核心功能
1. **推理努力显示**：显示当前模型的推理努力级别（reasoning effort），如 "high"
2. **推理摘要显示**：显示推理摘要的配置，如 "detailed"
3. **模型详情格式化**：将推理信息作为模型名称的附加详情展示

### 业务逻辑
- 推理努力通过 `ReasoningEffort` 枚举定义（None, Low, Medium, High）
- 推理摘要通过 `ReasoningSummary` 枚举定义（Off, Auto, Concise, Detailed）
- 仅当使用 Responses API 时显示推理配置

## 具体技术实现

### 关键数据结构

```rust
// codex-rs/protocol/src/openai_models.rs
pub enum ReasoningEffort {
    None,
    Low,
    Medium,
    High,
}

// codex-rs/protocol/src/config_types.rs
pub enum ReasoningSummary {
    Off,
    Auto,
    Concise,
    Detailed,
}
```

### 配置项构建

```rust
// card.rs:167-193
let mut config_entries = vec![
    ("workdir", config.cwd.display().to_string()),
    ("model", model_name.to_string()),
    ("provider", config.model_provider_id.clone()),
    ("approval", config.permissions.approval_policy.value().to_string()),
    ("sandbox", summarize_sandbox_policy(config.permissions.sandbox_policy.get())),
];

// 仅对 Responses API 添加推理配置
if config.model_provider.wire_api == WireApi::Responses {
    let effort_value = reasoning_effort_override
        .unwrap_or(None)
        .map(|effort| effort.to_string())
        .unwrap_or_else(|| "none".to_string());
    config_entries.push(("reasoning effort", effort_value));
    config_entries.push((
        "reasoning summaries",
        config
            .model_reasoning_summary
            .map(|summary| summary.to_string())
            .unwrap_or_else(|| "auto".to_string()),
    ));
}
```

### 模型详情组合

```rust
// helpers.rs:19-37
pub(crate) fn compose_model_display(
    model_name: &str,
    entries: &[(&str, String)],
) -> (String, Vec<String>) {
    let mut details: Vec<String> = Vec::new();
    
    // 推理努力
    if let Some((_, effort)) = entries.iter().find(|(k, _)| *k == "reasoning effort") {
        details.push(format!("reasoning {}", effort.to_ascii_lowercase()));
    }
    
    // 推理摘要
    if let Some((_, summary)) = entries.iter().find(|(k, _)| *k == "reasoning summaries") {
        let summary = summary.trim();
        if summary.eq_ignore_ascii_case("none") || summary.eq_ignore_ascii_case("off") {
            details.push("summaries off".to_string());
        } else if !summary.is_empty() {
            details.push(format!("summaries {}", summary.to_ascii_lowercase()));
        }
    }

    (model_name.to_string(), details)
}
```

### 模型详情渲染

```rust
// card.rs:492-498
let mut model_spans = vec![Span::from(self.model_name.clone())];
if !self.model_details.is_empty() {
    model_spans.push(Span::from(" (").dim());
    model_spans.push(Span::from(self.model_details.join(", ")).dim());
    model_spans.push(Span::from(")").dim());
}
lines.push(formatter.line("Model", model_spans));
```

### 测试用例构造

```rust
// tests.rs:93-172
let mut config = test_config(&temp_home).await;
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_provider_id = "openai".to_string();
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);  // 推理摘要
config.permissions.sandbox_policy.set(SandboxPolicy::WorkspaceWrite { ... })
    .expect("set sandbox policy");

let reasoning_effort_override = Some(Some(ReasoningEffort::High));  // 推理努力

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
    reasoning_effort_override,  // 传入推理努力覆盖
);
```

### 渲染输出分析

```
╭───────────────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                                 │
│                                                                           │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date             │
│ information on rate limits and credits                                    │
│                                                                           │
│  Model:            gpt-5.1-codex-max (reasoning high, summaries detailed) │
│  Directory: [[workspace]]                                                 │
│  Permissions:      Default                                                │
│  Agents.md:        <none>                                                 │
│                                                                           │
│  Token usage:      1.9K total  (1K input + 900 output)                    │
│  Context window:   100% left (2.25K used / 272K)                          │
│  5h limit:         [██████░░░░░░░░░░░░░░] 28% left (resets 03:14)         │
│  Weekly limit:     [███████████░░░░░░░░░] 55% left (resets 03:24)         │
╰───────────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **模型详情格式**：`gpt-5.1-codex-max (reasoning high, summaries detailed)`
2. **推理努力**：显示为 "reasoning high"（小写）
3. **推理摘要**：显示为 "summaries detailed"（小写）
4. **权限显示**：使用 "Default" 而非 "Custom"，因为配置匹配默认策略

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 93-172 行 |
| `codex-rs/tui/src/status/card.rs` | 配置项构建，第 167-193 行；模型详情渲染，第 492-498 行 |
| `codex-rs/tui/src/status/helpers.rs` | 模型详情组合，第 19-37 行 |
| `codex-rs/protocol/src/openai_models.rs` | `ReasoningEffort` 定义 |
| `codex-rs/protocol/src/config_types.rs` | `ReasoningSummary` 定义 |

### 渲染调用链

```
new_status_output (card.rs:81)
  └── StatusHistoryCell::new (card.rs:152)
      ├── 构建 config_entries (第 167-193 行)
      │   ├── 基础配置（workdir, model, provider, approval, sandbox）
      │   └── 推理配置（仅 Responses API）
      │       ├── reasoning effort: "high"
      │       └── reasoning summaries: "detailed"
      ├── compose_model_display (helpers.rs:19)
      │   └── 提取并格式化推理详情
      │       └── ["reasoning high", "summaries detailed"]
      └── 存储到 model_details
  └── StatusHistoryCell::display_lines (card.rs:413)
      └── 渲染 Model 行 (第 492-498 行)
          └── "gpt-5.1-codex-max (reasoning high, summaries detailed)"
```

### WireApi 检查

```rust
// codex-rs/core/src/config/model_provider.rs
pub enum WireApi {
    Responses,  // OpenAI Responses API
    ChatCompletions,  // 标准 Chat Completions API
}

impl ModelProvider {
    pub fn is_openai(&self) -> bool {
        self.wire_api == WireApi::Responses
    }
}
```

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `ratatui` | 终端渲染，Span/Line 构造 |
| `insta` | 快照测试 |

### 内部模块

```rust
use codex_protocol::openai_models::ReasoningEffort;
use codex_protocol::config_types::ReasoningSummary;
use codex_core::WireApi;
```

## 风险、边界与改进建议

### 当前风险

1. **API 类型硬编码检查**：`wire_api == WireApi::Responses` 是硬编码检查，如果添加新 API 类型可能需要修改
2. **字符串匹配**：`compose_model_display` 使用字符串匹配查找配置项，容易因拼写错误导致 bug
3. **大小写转换**：`to_ascii_lowercase()` 假设所有值都是 ASCII，非 ASCII 字符可能处理不正确

### 边界情况

1. **空推理努力**：`reasoning_effort_override` 为 `None` 时显示 "reasoning none"
2. **关闭推理摘要**：`ReasoningSummary::Off` 显示为 "summaries off" 而非 "summaries none"
3. **非 Responses API**：使用 Chat Completions API 时不显示推理配置，即使模型支持

### 改进建议

1. **类型安全重构**：
   ```rust
   // 使用结构体替代元组
   struct ModelConfig {
       reasoning_effort: Option<ReasoningEffort>,
       reasoning_summary: Option<ReasoningSummary>,
       // ...
   }
   ```

2. **枚举直接渲染**：
   ```rust
   impl Display for ReasoningEffort {
       fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
           match self {
               Self::None => write!(f, "none"),
               Self::Low => write!(f, "low"),
               // ...
           }
       }
   }
   ```

3. **API 兼容性层**：
   - 添加配置选项强制显示推理配置，即使当前 API 不原生支持
   - 在状态行添加警告，提示推理配置可能被忽略

4. **测试扩展**：
   - 测试 `ReasoningSummary::Off` 显示为 "summaries off"
   - 测试非 Responses API 时不显示推理配置
   - 测试推理努力和摘要的各种组合

5. **UI 改进**：
   - 使用不同颜色区分推理配置（如蓝色表示高级功能）
   - 添加工具提示解释推理配置的含义
   - 提供快速修改推理配置的快捷键
