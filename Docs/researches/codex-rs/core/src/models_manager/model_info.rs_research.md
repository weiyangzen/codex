# model_info.rs 研究文档

## 场景与职责

`model_info.rs` 提供模型元数据的工具函数，负责：

1. **配置覆盖应用**：将用户配置（`Config`）中的覆盖项应用到 `ModelInfo`
2. **Fallback 元数据生成**：为未知模型 slug 生成默认元数据
3. **个性化消息组装**：为支持个性化的模型组装指令模板

该模块是模型管理的数据处理层，介于原始模型数据和最终使用场景之间。

## 功能点目的

### 1. 配置覆盖应用 (`with_config_overrides`)
- **目的**：将用户配置中的模型相关设置应用到 `ModelInfo`
- **支持的覆盖项**：
  | 配置项 | 目标字段 | 说明 |
  |--------|----------|------|
  | `model_supports_reasoning_summaries` | `supports_reasoning_summaries` | 仅支持设置为 true |
  | `model_context_window` | `context_window` | 完全覆盖 |
  | `model_auto_compact_token_limit` | `auto_compact_token_limit` | 完全覆盖 |
  | `tool_output_token_limit` | `truncation_policy.limit` | 根据 mode 转换为 bytes 或 tokens |
  | `base_instructions` | `base_instructions` | 完全覆盖，同时清空 `model_messages` |
  | `features.personality` | `model_messages` | 禁用 personality 时清空 |

- **特殊行为**：
  - `reasoning_summaries` 仅支持启用（`true`），不支持禁用
  - 设置 `base_instructions` 会清除 `model_messages`（避免冲突）
  - `tool_output_token_limit` 根据现有 `truncation_policy.mode` 进行单位转换

### 2. Fallback 元数据生成 (`model_info_from_slug`)
- **目的**：为未知模型生成可用的默认元数据
- **触发条件**：模型 slug 在远程/捆绑目录中无匹配
- **生成的默认值**：
  - `slug`: 输入值
  - `display_name`: 输入值
  - `base_instructions`: 加载自 `prompt.md`
  - `context_window`: 272,000
  - `truncation_policy`: bytes 模式，限制 10,000
  - `priority`: 99（低优先级）
  - `used_fallback_model_metadata`: `true`（标记为 fallback）

### 3. 个性化消息组装 (`local_personality_messages_for_slug`)
- **目的**：为特定模型生成支持 personality 特性的消息模板
- **支持的模型**：
  - `gpt-5.2-codex`
  - `exp-codex-personality`
- **模板结构**：
  ```
  {DEFAULT_PERSONALITY_HEADER}
  
  {PERSONALITY_PLACEHOLDER}
  
  {BASE_INSTRUCTIONS}
  ```
- **变量**：
  - `personality_default`: 空字符串
  - `personality_friendly`: 友好型个性描述
  - `personality_pragmatic`: 务实型个性描述

## 具体技术实现

### 关键数据结构

```rust
// 来自 codex_protocol::openai_models
pub struct ModelInfo {
    pub slug: String,
    pub display_name: String,
    pub description: Option<String>,
    pub default_reasoning_level: Option<ReasoningEffort>,
    pub supported_reasoning_levels: Vec<ReasoningEffortPreset>,
    pub shell_type: ConfigShellToolType,
    pub visibility: ModelVisibility,
    pub supported_in_api: bool,
    pub priority: i32,
    // ... 更多字段
    pub used_fallback_model_metadata: bool,  // 标记 fallback 来源
}
```

### 核心流程

#### 配置覆盖流程
```rust
pub(crate) fn with_config_overrides(mut model: ModelInfo, config: &Config) -> ModelInfo {
    // 1. Reasoning summaries（仅启用）
    if config.model_supports_reasoning_summaries == Some(true) {
        model.supports_reasoning_summaries = true;
    }
    
    // 2. Context window
    if let Some(context_window) = config.model_context_window {
        model.context_window = Some(context_window);
    }
    
    // 3. Auto compact token limit
    if let Some(limit) = config.model_auto_compact_token_limit {
        model.auto_compact_token_limit = Some(limit);
    }
    
    // 4. Tool output token limit（需单位转换）
    if let Some(token_limit) = config.tool_output_token_limit {
        model.truncation_policy = match model.truncation_policy.mode {
            TruncationMode::Bytes => {
                let byte_limit = approx_bytes_for_tokens(token_limit);
                TruncationPolicyConfig::bytes(byte_limit)
            }
            TruncationMode::Tokens => {
                TruncationPolicyConfig::tokens(token_limit as i64)
            }
        };
    }
    
    // 5. Base instructions（覆盖并清除 model_messages）
    if let Some(base_instructions) = &config.base_instructions {
        model.base_instructions = base_instructions.clone();
        model.model_messages = None;
    } else if !config.features.enabled(Feature::Personality) {
        model.model_messages = None;
    }
    
    model
}
```

#### Fallback 生成流程
```rust
pub(crate) fn model_info_from_slug(slug: &str) -> ModelInfo {
    warn!("Unknown model {slug} is used. This will use fallback model metadata.");
    
    ModelInfo {
        slug: slug.to_string(),
        display_name: slug.to_string(),
        description: None,
        default_reasoning_level: None,
        supported_reasoning_levels: Vec::new(),
        shell_type: ConfigShellToolType::Default,
        visibility: ModelVisibility::None,
        supported_in_api: true,
        priority: 99,  // 低优先级
        // ...
        base_instructions: BASE_INSTRUCTIONS.to_string(),  // 来自 prompt.md
        model_messages: local_personality_messages_for_slug(slug),
        used_fallback_model_metadata: true,  // 标记为 fallback
        // ...
    }
}
```

### 单位转换

```rust
// 来自 crate::truncate
fn approx_bytes_for_tokens(tokens: usize) -> usize {
    // 使用近似比例将 token 数转换为字节数
    // 典型值：1 token ≈ 4 bytes（英文文本）
    tokens * 4
}
```

## 关键代码路径与文件引用

### 内部依赖
| 路径 | 用途 |
|------|------|
| `crate::config::Config` | 配置结构定义 |
| `crate::features::Feature` | 特性标志检查 |
| `crate::truncate::approx_bytes_for_tokens` | Token 到字节转换 |

### 协议类型依赖
| 路径 | 用途 |
|------|------|
| `codex_protocol::config_types::ReasoningSummary` | 推理摘要类型 |
| `codex_protocol::openai_models::*` | 模型相关类型 |

### 模板文件
| 路径 | 用途 |
|------|------|
| `codex-rs/core/prompt.md` | Fallback 模型的基础指令 |

### 外部调用方
| 路径 | 调用方法 | 用途 |
|------|----------|------|
| `manager.rs:373` | `with_config_overrides` | 应用配置覆盖 |
| `manager.rs:371` | `model_info_from_slug` | 未知模型 fallback |

### 常量定义
```rust
const BASE_INSTRUCTIONS: &str = include_str!("../../prompt.md");
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
const LOCAL_FRIENDLY_TEMPLATE: &str = "You optimize for team morale...";
const LOCAL_PRAGMATIC_TEMPLATE: &str = "You are a deeply pragmatic...";
const PERSONALITY_PLACEHOLDER: &str = "{{ personality }}";
```

## 依赖与外部交互

### 外部 Crate 依赖
- `tracing::warn`：记录 fallback 使用警告

### 编译时资源嵌入
```rust
const BASE_INSTRUCTIONS: &str = include_str!("../../prompt.md");
```

### 配置系统交互
```rust
// 从 Config 读取覆盖值
if let Some(supports_reasoning_summaries) = config.model_supports_reasoning_summaries
    && supports_reasoning_summaries
{
    model.supports_reasoning_summaries = true;
}
```

## 风险、边界与改进建议

### 已知风险

1. **Reasoning Summaries 单向覆盖**
   - 风险：配置只能启用，不能禁用
   - 现状：`Some(false)` 被忽略
   - 建议：明确文档化此行为，或支持双向覆盖

2. **Base Instructions 与 Model Messages 冲突**
   - 风险：设置 `base_instructions` 会静默清除 `model_messages`
   - 影响：用户可能意外丢失 personality 支持
   - 建议：添加警告日志或文档说明

3. **Fallback 模型功能受限**
   - 风险：未知模型使用保守的默认配置
   - 影响：可能不支持某些高级功能（如并行工具调用）
   - 缓解：合理的默认值确保基本功能可用

4. **Token 转换近似性**
   - 风险：`approx_bytes_for_tokens` 使用固定比例（4:1）
   - 影响：非英文内容可能估算不准确
   - 建议：考虑语言感知的转换或配置

### 边界条件

| 场景 | 行为 |
|------|------|
| `tool_output_token_limit` 很大 | 使用 `i64::MAX` 作为上限 |
| `approx_bytes_for_tokens` 溢出 | 返回 `i64::MAX` |
| 未知模型 slug | 生成 fallback，记录警告 |
| 不支持 personality 的模型 | `model_messages = None` |
| `base_instructions` 为空字符串 | 仍覆盖并清除 `model_messages` |

### 改进建议

1. **配置验证**
   ```rust
   pub fn validate_config_overrides(config: &Config) -> Result<(), ConfigError> {
       if config.base_instructions.is_some() && config.features.enabled(Feature::Personality) {
           warn!("Setting base_instructions will disable personality features");
       }
       Ok(())
   }
   ```

2. **Fallback 模型增强**
   - 根据 slug 模式猜测模型特性（如 `gpt-5*` 系列）
   - 提供最小功能集检测机制

3. **单位转换改进**
   ```rust
   // 支持多种编码估算
   fn approx_bytes_for_tokens(tokens: usize, encoding: Encoding) -> usize {
       match encoding {
           Encoding::Cl100kBase => tokens * 4,
           Encoding::P50kBase => tokens * 5,
       }
   }
   ```

4. **文档增强**
   - 添加配置覆盖的优先级说明
   - 提供配置示例和最佳实践

### 测试覆盖

测试文件：`model_info_tests.rs`

| 测试用例 | 覆盖场景 |
|----------|----------|
| `reasoning_summaries_override_true_enables_support` | 启用 reasoning summaries |
| `reasoning_summaries_override_false_does_not_disable_support` | 禁用无效（单向性） |
| `reasoning_summaries_override_false_is_noop_when_model_is_false` | 无变化时的行为 |

### 缺失测试场景

1. **配置覆盖测试**
   - `model_context_window` 覆盖
   - `model_auto_compact_token_limit` 覆盖
   - `tool_output_token_limit` 单位转换
   - `base_instructions` 覆盖和 `model_messages` 清除

2. **Fallback 生成测试**
   - 未知模型的完整字段验证
   - `used_fallback_model_metadata` 标记

3. **个性化消息测试**
   - `local_personality_messages_for_slug` 的返回值
   - 支持/不支持 personality 的模型

4. **边界条件测试**
   - 极大 token limit 处理
   - 空字符串配置值处理
