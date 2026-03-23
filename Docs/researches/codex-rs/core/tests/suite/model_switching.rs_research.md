# model_switching.rs 研究文档

## 场景与职责

`model_switching.rs` 是 Codex Core 集成测试套件中最全面的模型切换测试文件，负责验证模型切换功能的完整行为矩阵。该文件测试以下核心场景：

1. **模型切换时的指令注入**：验证切换模型时，系统会注入 `<model_switch>` 开发者消息，确保新模型获得正确的指令上下文
2. **多模态内容处理**：测试从图像支持模型切换到纯文本模型时，图像内容的处理策略（剥离、占位符替换）
3. **图像生成历史回放**：验证生成图像的历史记录在不同模型间的正确传递
4. **上下文窗口动态调整**：验证模型切换时上下文窗口大小的正确更新
5. **Service Tier 切换**：验证 `fast`/`flex`/`standard` 服务层级的正确应用

这些测试确保了 Codex 在多模型协作场景下的用户体验一致性。

## 功能点目的

### 测试用例矩阵

| 测试函数 | 目的 | 关键验证点 |
|----------|------|------------|
| `model_change_appends_model_instructions_developer_message` | 验证模型切换时注入切换指令 | `<model_switch>` 标签存在于开发者消息中 |
| `model_and_personality_change_only_appends_model_instructions` | 验证同时切换模型和个性时的消息优先级 | 仅注入模型切换消息，不注入个性更新 |
| `service_tier_change_is_applied_on_next_http_turn` | 验证 Service Tier 在 HTTP 回合中的正确应用 | `service_tier` 字段在请求体中的存在性 |
| `flex_service_tier_is_applied_to_http_turn` | 验证 Flex 服务层级的正确传递 | `service_tier: "flex"` 的精确匹配 |
| `model_change_from_image_to_text_strips_prior_image_content` | 图像→文本模型切换的内容处理 | 图像 URL 被剥离，占位符文本注入 |
| `generated_image_is_replayed_for_image_capable_models` | 验证图像生成历史的正确回放 | `image_generation_call` 类型输入项的存在 |
| `model_change_from_generated_image_to_text_preserves_prior_generated_image_call` | 图像生成→文本切换的特殊处理 | 保留调用记录但清空图像字节 |
| `thread_rollback_after_generated_image_drops_entire_image_turn_history` | 验证回滚对图像历史的清理 | 图像生成调用和占位符都被清除 |
| `model_switch_to_smaller_model_updates_token_context_window` | 验证上下文窗口的动态调整 | `TokenCount` 事件中窗口大小的变化 |

## 具体技术实现

### 关键数据结构

```rust
// ModelInfo 结构体 (protocol/src/openai_models.rs 行 243-294)
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelInfo {
    pub slug: String,
    pub display_name: String,
    pub description: Option<String>,
    pub context_window: Option<i64>,           // 上下文窗口大小
    pub effective_context_window_percent: i64, // 有效窗口百分比（默认95%）
    pub input_modalities: Vec<InputModality>,  // 支持的输入模态
    pub base_instructions: String,             // 基础指令模板
    pub model_messages: Option<ModelMessages>, // 模型特定消息模板
    // ... 其他字段
}

// InputModality 枚举 (protocol/src/openai_models.rs 行 62-83)
pub enum InputModality {
    Text,
    Image,
}
```

### 模型切换指令注入机制

```rust
// context_manager/updates.rs 行 141-158
pub(crate) fn build_model_instructions_update_item(
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions> {
    let previous_turn_settings = previous_turn_settings?;
    if previous_turn_settings.model == next.model_info.slug {
        return None;  // 模型未变化，不注入
    }

    let model_instructions = next.model_info.get_model_instructions(next.personality);
    if model_instructions.is_empty() {
        return None;
    }

    Some(DeveloperInstructions::model_switch_message(model_instructions))
}
```

### 图像内容处理策略

当从图像支持模型切换到纯文本模型时，系统执行以下处理：

1. **图像剥离**：从用户消息中移除 `input_image` 类型的内容项
2. **占位符注入**：添加文本 `"image content omitted because you do not support image input"`
3. **标签保留**：保留 `<image>` 和 `</image>` 标签文本，维持对话结构

```rust
// 测试验证代码 (model_switching.rs 行 415-438)
let second_request = requests.last().expect("expected second request");
assert!(
    second_request.message_input_image_urls("user").is_empty(),
    "second request should strip unsupported image content"
);
let second_user_texts = second_request.message_input_texts("user");
assert!(
    second_user_texts.iter().any(|text| text == "image content omitted because you do not support image input"),
    "second request should include the image-omitted placeholder text"
);
```

### 图像生成历史回放

对于支持图像的模型，图像生成调用的历史以 `image_generation_call` 类型保留：

```rust
// 测试验证 (model_switching.rs 行 533-556)
let image_generation_calls = second_request.inputs_of_type("image_generation_call");
assert_eq!(image_generation_calls.len(), 1);
assert_eq!(image_generation_calls[0]["id"].as_str(), Some("ig_123"));
assert_eq!(image_generation_calls[0]["result"].as_str(), Some("Zm9v"));
```

对于纯文本模型，保留调用记录但清空图像字节（`result` 为空字符串）：

```rust
assert_eq!(image_generation_calls[0]["result"].as_str(), Some(""),
    "second request should strip generated image bytes for text-only models"
);
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 功能描述 |
|------|----------|
| `codex-rs/core/src/context_manager/updates.rs` | 构建模型切换更新项 (`build_model_instructions_update_item`) |
| `codex-rs/core/src/codex.rs` | 处理回合开始时的上下文更新注入 (行 3410-3420) |
| `codex-rs/protocol/src/openai_models.rs` | `ModelInfo` 和 `InputModality` 定义 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::model_switch_message` 实现 |

### 测试支持文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 测试环境构建 |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应辅助函数（`mount_sse_sequence`, `ev_image_generation_call` 等） |
| `codex-rs/core/tests/common/context_snapshot.rs` | 请求快照格式化工具 |

### 关键辅助函数

```rust
// 测试文件中的辅助函数 (model_switching.rs 行 37-77)
fn test_model_info(
    slug: &str,
    display_name: &str,
    description: &str,
    input_modalities: Vec<InputModality>,
) -> ModelInfo {
    ModelInfo {
        slug: slug.to_string(),
        display_name: display_name.to_string(),
        description: Some(description.to_string()),
        input_modalities,  // 关键：控制模型支持的模态
        // ... 其他字段使用默认值
    }
}
```

## 依赖与外部交互

### 协议层依赖

- `codex_protocol::openai_models::ModelInfo`: 模型元数据结构
- `codex_protocol::openai_models::InputModality`: 输入模态枚举（`Text`, `Image`）
- `codex_protocol::protocol::Op::UserTurn`: 用户回合操作
- `codex_protocol::protocol::Op::OverrideTurnContext`: 上下文覆盖操作

### 测试基础设施

- **wiremock**: HTTP Mock 服务器，用于模拟 `/v1/models` 和 `/v1/responses` 端点
- **tokio**: 异步测试运行时，配置 `flavor = "multi_thread", worker_threads = 2`
- **insta**: 快照测试（虽然本文件未直接使用，但相关文件使用）

### Mock 响应辅助

```rust
// responses.rs 提供的辅助函数
pub fn ev_image_generation_call(id: &str, status: &str, revised_prompt: &str, result: &str) -> Value;
pub fn ev_completed_with_tokens(id: &str, total_tokens: i64) -> Value;
pub fn mount_models_once(server: &MockServer, response: ModelsResponse) -> ModelsMock;
pub fn mount_sse_sequence(server: &MockServer, bodies: Vec<String>) -> ResponseMock;
```

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**：所有测试都使用 `skip_if_no_network!` 宏，在无网络环境下跳过，可能掩盖回归问题
2. **硬编码模型名称**：测试使用 `"gpt-5.2-codex"` 等硬编码模型名，若后端模型列表变更，测试可能失效
3. **Mock 复杂性**：多回合测试需要精确的 SSE 序列 Mock，维护成本较高

### 边界情况

1. **快速连续切换**：未测试在一个回合内多次切换模型的行为
2. **相同模型切换**：未测试切换到相同模型（无实际变化）时的优化路径
3. **模态部分支持**：仅测试了完全支持图像和完全不支持的情况，未测试部分支持（如仅支持特定格式）

### 改进建议

1. **减少网络依赖**：将更多测试转换为纯离线 Mock 测试，仅保留少数端到端测试验证集成
2. **参数化模型名称**：使用常量或配置驱动模型名称，减少硬编码
3. **添加性能测试**：模型切换涉及缓存刷新，应验证大模型列表下的性能
4. **扩展模态测试**：添加音频、视频等其他模态的切换测试（当协议支持时）
5. **文档化策略**：在代码注释中明确说明图像剥离、历史回放等策略的决策依据

### 相关测试文件

- `model_overrides.rs`: 测试模型覆盖的持久化边界
- `model_visible_layout.rs`: 测试模型变更对请求布局的影响
- `models_cache_ttl.rs`: 测试模型缓存的 TTL 管理
- `prompt_caching.rs`: 测试提示缓存与模型切换的交互
