# spawn_agent_description.rs 研究文档

## 场景与职责

`spawn_agent_description.rs` 是 Codex Core 的集成测试套件，专注于验证 **`spawn_agent` 工具描述** 的动态生成。该测试文件确保 `spawn_agent` 工具的描述能够根据可用模型和推理努力级别动态更新，为模型提供准确的子代理创建指导。

核心测试场景包括：
1. **模型列表展示** - 验证 `spawn_agent` 描述包含可见模型列表
2. **推理努力级别** - 验证描述包含支持的推理努力级别
3. **隐藏模型过滤** - 验证 `ModelVisibility::Hide` 的模型被排除
4. **使用指导** - 验证描述包含明确的子代理使用指导

## 功能点目的

### 1. spawn_agent 工具

`spawn_agent` 是 Codex 的多代理协作工具，允许模型创建子代理来并行处理任务。工具描述需要动态生成，因为：
- 可用模型列表可能变化
- 不同模型支持不同的推理努力级别
- 需要向模型提供清晰的使用指导

### 2. 模型可见性

```rust
pub enum ModelVisibility {
    List,  // 在模型列表中显示
    Hide,  // 隐藏（仅内部使用）
}
```

### 3. 推理努力级别

```rust
pub enum ReasoningEffort {
    Low,    // 快速扫描
    Medium, // 标准推理
    High,   // 深度分析
}

pub struct ReasoningEffortPreset {
    pub effort: ReasoningEffort,
    pub description: String,
}
```

## 具体技术实现

### 关键测试流程

#### 1. spawn_agent 描述提取

```rust
const SPAWN_AGENT_TOOL_NAME: &str = "spawn_agent";

fn spawn_agent_description(body: &Value) -> Option<String> {
    body.get("tools")
        .and_then(Value::as_array)
        .and_then(|tools| {
            tools.iter().find_map(|tool| {
                if tool.get("name").and_then(Value::as_str) == Some(SPAWN_AGENT_TOOL_NAME) {
                    tool.get("description")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                } else {
                    None
                }
            })
        })
}
```

#### 2. 测试模型信息构造

```rust
fn test_model_info(
    slug: &str,
    display_name: &str,
    description: &str,
    visibility: ModelVisibility,
    default_reasoning_level: ReasoningEffort,
    supported_reasoning_levels: Vec<ReasoningEffortPreset>,
) -> ModelInfo {
    ModelInfo {
        slug: slug.to_string(),
        display_name: display_name.to_string(),
        description: Some(description.to_string()),
        default_reasoning_level: Some(default_reasoning_level),
        supported_reasoning_levels,
        shell_type: ConfigShellToolType::ShellCommand,
        visibility,
        supported_in_api: true,
        input_modalities: default_input_modalities(),
        used_fallback_model_metadata: false,
        supports_search_tool: false,
        priority: 1,
        upgrade: None,
        base_instructions: "base instructions".to_string(),
        model_messages: None,
        supports_reasoning_summaries: false,
        default_reasoning_summary: ReasoningSummary::Auto,
        support_verbosity: false,
        default_verbosity: None,
        availability_nux: None,
        apply_patch_tool_type: None,
        web_search_tool_type: Default::default(),
        truncation_policy: TruncationPolicyConfig::bytes(10_000),
        supports_parallel_tool_calls: false,
        supports_image_detail_original: false,
        context_window: Some(272_000),
        auto_compact_token_limit: None,
        effective_context_window_percent: 95,
        experimental_supported_tools: Vec::new(),
    }
}
```

#### 3. 模型可用性等待

```rust
async fn wait_for_model_available(manager: &Arc<ModelsManager>, slug: &str) {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let available_models = manager.list_models(RefreshStrategy::Online).await;
        if available_models.iter().any(|model| model.model == slug) {
            return;
        }
        if Instant::now() >= deadline {
            panic!("timed out waiting for remote model {slug} to appear");
        }
        sleep(Duration::from_millis(25)).await;
    }
}
```

#### 4. 核心测试用例

```rust
#[tokio::test]
async fn spawn_agent_description_lists_visible_models_and_reasoning_efforts() -> Result<()> {
    let server = start_mock_server().await;
    
    // 挂载模型列表响应
    mount_models_once(
        &server,
        ModelsResponse {
            models: vec![
                test_model_info(
                    "visible-model",
                    "Visible Model",
                    "Fast and capable",
                    ModelVisibility::List,
                    ReasoningEffort::Medium,
                    vec![
                        ReasoningEffortPreset {
                            effort: ReasoningEffort::Low,
                            description: "Quick scan".to_string(),
                        },
                        ReasoningEffortPreset {
                            effort: ReasoningEffort::High,
                            description: "Deep dive".to_string(),
                        },
                    ],
                ),
                test_model_info(
                    "hidden-model",
                    "Hidden Model",
                    "Should not be shown",
                    ModelVisibility::Hide,
                    ReasoningEffort::Low,
                    vec![...],
                ),
            ],
        },
    ).await;
    
    // 构建测试实例
    let mut builder = test_codex()
        .with_auth(CodexAuth::create_dummy_chatgpt_auth_for_testing())
        .with_model("visible-model")
        .with_config(|config| {
            config.features.enable(Feature::Collab).expect(...);
        });
    let test = builder.build(&server).await?;
    
    // 等待模型可用
    wait_for_model_available(&test.thread_manager.get_models_manager(), "visible-model").await;
    
    // 提交回合
    test.submit_turn("hello").await?;
    
    // 提取并验证 spawn_agent 描述
    let body = resp_mock.single_request().body_json();
    let description = spawn_agent_description(&body).expect("spawn_agent description should be present");
    
    // 验证可见模型
    assert!(
        description.contains("- Visible Model (`visible-model`): Fast and capable"),
        "expected visible model summary in spawn_agent description"
    );
    
    // 验证默认推理努力
    assert!(
        description.contains("Default reasoning effort: medium."),
        "expected default reasoning effort in spawn_agent description"
    );
    
    // 验证推理努力级别
    assert!(
        description.contains("low (Quick scan), high (Deep dive)."),
        "expected reasoning efforts in spawn_agent description"
    );
    
    // 验证隐藏模型被排除
    assert!(
        !description.contains("Hidden Model"),
        "hidden picker model should be omitted from spawn_agent description"
    );
    
    // 验证使用指导
    assert!(
        description.contains("Only use `spawn_agent` if and only if the user explicitly asks for sub-agents, delegation, or parallel agent work."),
        "expected explicit authorization rule in spawn_agent description"
    );
}
```

### 关键数据结构

#### ModelInfo

```rust
pub struct ModelInfo {
    pub slug: String,                           // 模型标识符
    pub display_name: String,                   // 显示名称
    pub description: Option<String>,            // 描述
    pub default_reasoning_level: Option<ReasoningEffort>,
    pub supported_reasoning_levels: Vec<ReasoningEffortPreset>,
    pub visibility: ModelVisibility,            // 可见性
    pub supported_in_api: bool,                 // API 支持
    pub input_modalities: Vec<Modality>,        // 输入模态
    pub context_window: Option<u32>,            // 上下文窗口
    // ... 其他字段
}
```

#### ModelsResponse

```rust
pub struct ModelsResponse {
    pub models: Vec<ModelInfo>,
}
```

#### SpawnAgentArgs

```rust
#[derive(Debug, Deserialize)]
struct SpawnAgentArgs {
    message: Option<String>,           // 初始消息
    items: Option<Vec<UserInput>>,     // 输入项
    agent_type: Option<String>,        // 代理类型/角色
    model: Option<String>,             // 模型选择
    reasoning_effort: Option<ReasoningEffort>,
    #[serde(default)]
    fork_context: bool,                // 是否分叉上下文
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/spawn_agent_description.rs` - 本测试文件
- `codex-rs/core/tests/common/test_codex.rs` - 测试基础设施
- `codex-rs/core/tests/common/responses.rs` - 响应模拟辅助函数

### 被测试的源代码
- `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` - spawn_agent 处理器
- `codex-rs/core/src/models_manager/manager.rs` - 模型管理器
- `codex-rs/core/src/models_manager/model_info.rs` - 模型信息定义
- `codex-rs/core/src/agent/role.rs` - 代理角色定义

### 核心测试用例

| 测试用例 | 描述 |
|---------|------|
| `spawn_agent_description_lists_visible_models_and_reasoning_efforts` | 验证描述包含模型列表和推理努力级别 |

### spawn_agent 描述生成代码路径

1. **模型列表获取** - `models_manager::list_models`
2. **工具描述生成** - `tools::handlers::multi_agents::spawn::build_spawn_agent_description`
3. **描述格式化** - 根据模型信息格式化描述文本
4. **工具注册** - `tools::registry::ToolRegistry::register`

### 描述格式

生成的 `spawn_agent` 描述格式：
```markdown
## Available models

- Model Name (`model-slug`): Description
- ...

Default reasoning effort: {level}.
Available reasoning efforts: {effort} ({description}), ...

Only use `spawn_agent` if and only if the user explicitly asks for sub-agents, delegation, or parallel agent work.
Requests for depth, thoroughness, research, investigation, or detailed codebase analysis do not count as permission to spawn.
Agent-role guidance below only helps choose which agent to use after spawning is already authorized; it never authorizes spawning by itself.
```

## 依赖与外部交互

### 测试依赖

1. **core_test_support**
   - `test_codex::test_codex()` - 创建测试实例
   - `responses::start_mock_server()` - 启动模拟服务器
   - `responses::mount_models_once()` - 挂载模型列表响应
   - `responses::mount_sse_once()` - 挂载 SSE 响应

2. **codex_core**
   - `CodexAuth::create_dummy_chatgpt_auth_for_testing()` - 创建测试认证
   - `Feature::Collab` - 协作功能标志
   - `ModelsManager` - 模型管理器

3. **codex_protocol**
   - `ModelInfo` - 模型信息
   - `ModelVisibility` - 模型可见性枚举
   - `ReasoningEffort` - 推理努力枚举
   - `ReasoningEffortPreset` - 推理努力预设

### 协议交互

测试通过模拟以下端点与 Codex Core 交互：
- `GET /v1/models` - 获取模型列表
- `POST /v1/responses` - 提交对话请求

### 特性标志

测试涉及的特性：
- `Feature::Collab` - 多代理协作功能

### 认证

测试使用虚拟认证：
```rust
CodexAuth::create_dummy_chatgpt_auth_for_testing()
```

## 风险、边界与改进建议

### 当前风险

1. **单测试覆盖** - 目前只有一个测试用例，覆盖有限
2. **模型硬编码** - 测试使用硬编码的模型名称和描述
3. **时序敏感** - 需要等待模型可用，可能存在竞态条件
4. **描述格式依赖** - 测试依赖描述的特定格式，格式变更时可能失败

### 边界情况

1. **空模型列表** - 未测试无可用模型时的行为
2. **大量模型** - 未测试模型列表很长时的描述截断行为
3. **模型变更** - 未测试运行时模型列表变更的更新
4. **网络失败** - 未测试模型列表获取失败时的降级行为

### 改进建议

1. **增加空列表测试** - 验证无模型时的描述行为
2. **增加大量模型测试** - 验证模型列表很长时的处理
3. **增加模型变更测试** - 验证运行时模型列表更新
4. **增加网络失败测试** - 验证模型列表获取失败时的降级
5. **增加角色测试** - 验证不同 agent_type 角色的描述差异
6. **增加版本测试** - 验证模型版本信息的展示

### 相关配置项

```rust
config.features.enable(Feature::Collab)?;
config.model = Some("visible-model".to_string());
```

### 模型管理器配置

```rust
ModelsManager::new(
    &config,
    auth_manager,
    SessionSource::Exec,
    CollaborationModesConfig::default(),
)
```

### 描述更新机制

`spawn_agent` 描述在以下时机更新：
1. 会话初始化时
2. 模型列表刷新时
3. 配置变更时

### 安全考虑

1. **隐藏模型保护** - `ModelVisibility::Hide` 的模型不会暴露给前端
2. **内部模型隔离** - 内部测试模型不会在生产环境显示
3. **描述注入防护** - 模型描述经过转义，防止 XSS
