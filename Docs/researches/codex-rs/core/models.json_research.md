# models.json 研究文档

## 概述

`models.json` 是 Codex CLI 项目的核心模型配置文件，位于 `codex-rs/core/models.json`。该文件定义了 Codex 支持的所有 AI 模型的元数据，包括模型能力、指令模板、工具支持、可见性配置等。它是模型管理系统的基石，被编译时嵌入到二进制中，并可通过远程 API 动态更新。

---

## 1. 场景与职责

### 1.1 核心场景

| 场景 | 描述 |
|------|------|
| **模型发现与选择** | TUI/CLI 通过模型管理器列出可用模型，供用户选择 |
| **模型元数据解析** | 根据模型 slug 获取其能力配置（上下文窗口、工具支持等） |
| **指令模板渲染** | 根据模型配置生成系统提示词（system prompt） |
| **远程模型同步** | 从 `/models` API 端点获取最新模型列表并更新本地缓存 |
| **版本兼容性检查** | 验证客户端版本是否满足模型的最低版本要求 |
| **模型升级提示** | 根据配置向用户展示模型升级建议 |

### 1.2 职责边界

- **静态配置**：`models.json` 提供编译时嵌入的默认模型配置
- **动态更新**：`ModelsManager` 支持从远程 API 获取更新，并缓存到本地磁盘
- **配置覆盖**：用户可通过 `model_catalog_json` 配置项提供自定义模型目录
- **Fallback 机制**：未知模型 slug 时使用默认元数据，确保系统健壮性

---

## 2. 功能点目的

### 2.1 模型定义字段详解

```json
{
  "models": [
    {
      "slug": "gpt-5.3-codex",                    // 模型唯一标识
      "display_name": "gpt-5.3-codex",           // UI 显示名称
      "description": "Latest frontier agentic coding model.",
      "context_window": 272000,                   // 上下文窗口大小
      "default_reasoning_level": "medium",       // 默认推理级别
      "supported_reasoning_levels": [...],       // 支持的推理级别列表
      "shell_type": "shell_command",             // Shell 工具类型
      "visibility": "list",                      // 可见性（list/hide/none）
      "supported_in_api": true,                  // 是否支持 API 调用
      "minimal_client_version": "0.98.0",        // 最低客户端版本
      "priority": 0,                             // 优先级（越小越优先）
      "base_instructions": "...",                // 基础系统指令
      "model_messages": {...},                   // 个性化指令模板
      "truncation_policy": {                     // 输出截断策略
        "mode": "tokens",
        "limit": 10000
      },
      "supports_parallel_tool_calls": true,      // 是否支持并行工具调用
      "supports_reasoning_summaries": true,      // 是否支持推理摘要
      "input_modalities": ["text", "image"],     // 支持的输入模态
      "available_in_plans": [...],               // 可用的订阅计划
      "upgrade": {...}                           // 升级目标模型配置
    }
  ]
}
```

### 2.2 关键功能点

#### 2.2.1 模型可见性控制 (`visibility`)

- **`list`**：在模型选择器中显示
- **`hide`**：隐藏但可通过 slug 直接访问
- **`none`**：不显示且不可访问

#### 2.2.2 推理级别配置 (`reasoning_level`)

支持 `minimal`/`low`/`medium`/`high`/`xhigh` 五级推理强度，映射到 OpenAI API 的 `reasoning.effort` 参数。

#### 2.2.3 Shell 工具类型 (`shell_type`)

| 类型 | 说明 |
|------|------|
| `default` | 使用默认 Shell 配置 |
| `shell_command` | 使用经典 Shell 命令工具 |
| `unified_exec` | 使用统一执行引擎（支持长时间运行进程） |
| `disabled` | 禁用 Shell 工具 |

#### 2.2.4 个性化指令 (`model_messages`)

支持通过模板变量 `{{ personality }}` 注入不同的人格风格：
- `personality_default`：默认风格
- `personality_friendly`：友好协作风格
- `personality_pragmatic`：务实高效风格

#### 2.2.5 模型升级提示 (`upgrade`)

当有新版本模型可用时，向用户展示迁移说明：
```json
{
  "model": "gpt-5.4",
  "migration_markdown": "Introducing GPT-5.4..."
}
```

---

## 3. 具体技术实现

### 3.1 数据流架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        模型数据流                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │ models.json │───▶│ 编译时嵌入  │───▶│ ModelsManager       │ │
│  │ (静态配置)   │    │ include_str │    │ (运行时管理)         │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│                                                   │              │
│                           ┌───────────────────────┼──────────┐  │
│                           ▼                       ▼          │  │
│                    ┌─────────────┐         ┌─────────────┐   │  │
│                    │ 远程 API    │         │ 本地缓存    │   │  │
│                    │ /models     │◄───────▶│ models_cache│   │  │
│                    └─────────────┘         └─────────────┘   │  │
│                           │                       ▲          │  │
│                           └───────────────────────┘          │  │
│                                                                  │
│  使用场景：                                                       │
│  ├─ TUI 模型选择器 ──▶ list_models() ──▶ ModelPreset[]         │
│  ├─ 获取模型信息 ────▶ get_model_info() ──▶ ModelInfo          │
│  └─ 默认模型选择 ────▶ get_default_model() ──▶ String          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 ModelInfo (协议层)

文件：`codex-rs/protocol/src/openai_models.rs`

```rust
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
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
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub upgrade: Option<ModelInfoUpgrade>,
    pub base_instructions: String,
    pub model_messages: Option<ModelMessages>,
    pub supports_reasoning_summaries: bool,
    pub default_reasoning_summary: ReasoningSummary,
    pub support_verbosity: bool,
    pub default_verbosity: Option<Verbosity>,
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    pub web_search_tool_type: WebSearchToolType,
    pub truncation_policy: TruncationPolicyConfig,
    pub supports_parallel_tool_calls: bool,
    pub supports_image_detail_original: bool,
    pub context_window: Option<i64>,
    pub auto_compact_token_limit: Option<i64>,
    pub effective_context_window_percent: i64,
    pub experimental_supported_tools: Vec<String>,
    pub input_modalities: Vec<InputModality>,
    pub used_fallback_model_metadata: bool,  // 运行时标记
    pub supports_search_tool: bool,
}
```

#### 3.2.2 ModelPreset (UI 层)

```rust
#[derive(Debug, Clone, Deserialize, Serialize, TS, JsonSchema, PartialEq)]
pub struct ModelPreset {
    pub id: String,
    pub model: String,
    pub display_name: String,
    pub description: String,
    pub default_reasoning_effort: ReasoningEffort,
    pub supported_reasoning_efforts: Vec<ReasoningEffortPreset>,
    pub supports_personality: bool,
    pub is_default: bool,
    pub upgrade: Option<ModelUpgrade>,
    pub show_in_picker: bool,          // 由 visibility 派生
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub supported_in_api: bool,
    pub input_modalities: Vec<InputModality>,
}
```

#### 3.2.3 ModelsResponse (API 响应)

```rust
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema, Default)]
pub struct ModelsResponse {
    pub models: Vec<ModelInfo>,
}
```

### 3.3 模型管理器实现

文件：`codex-rs/core/src/models_manager/manager.rs`

#### 3.3.1 初始化流程

```rust
impl ModelsManager {
    pub fn new_with_provider(
        codex_home: PathBuf,
        auth_manager: Arc<AuthManager>,
        model_catalog: Option<ModelsResponse>,  // 用户自定义配置
        collaboration_modes_config: CollaborationModesConfig,
        provider: ModelProviderInfo,
    ) -> Self {
        let cache_path = codex_home.join(MODEL_CACHE_FILE);
        let cache_manager = ModelsCacheManager::new(cache_path, DEFAULT_MODEL_CACHE_TTL);
        
        // 确定目录模式
        let catalog_mode = if model_catalog.is_some() {
            CatalogMode::Custom  // 使用用户提供的配置，禁用远程刷新
        } else {
            CatalogMode::Default // 使用捆绑配置 + 远程刷新
        };
        
        // 加载初始模型列表
        let remote_models = model_catalog
            .map(|catalog| catalog.models)
            .unwrap_or_else(|| {
                Self::load_remote_models_from_file()  // 从 models.json 加载
                    .unwrap_or_else(|err| panic!("failed to load bundled models.json: {err}"))
            });
        
        Self { ... }
    }
}
```

#### 3.3.2 模型查找算法

支持最长前缀匹配和命名空间后缀匹配：

```rust
fn find_model_by_longest_prefix(model: &str, candidates: &[ModelInfo]) -> Option<ModelInfo> {
    let mut best: Option<ModelInfo> = None;
    for candidate in candidates {
        if !model.starts_with(&candidate.slug) {
            continue;
        }
        let is_better_match = if let Some(current) = best.as_ref() {
            candidate.slug.len() > current.slug.len()
        } else {
            true
        };
        if is_better_match {
            best = Some(candidate.clone());
        }
    }
    best
}

// 支持命名空间模型如 "custom/gpt-5.3-codex"
fn find_model_by_namespaced_suffix(model: &str, candidates: &[ModelInfo]) -> Option<ModelInfo> {
    let (namespace, suffix) = model.split_once('/')?;
    if suffix.contains('/') {
        return None;
    }
    // 验证命名空间格式 (\w+)
    if !namespace.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }
    Self::find_model_by_longest_prefix(suffix, candidates)
}
```

#### 3.3.3 远程刷新策略

```rust
pub enum RefreshStrategy {
    Online,           // 总是从网络获取
    Offline,          // 仅使用缓存
    OnlineIfUncached, // 缓存未命中时从网络获取
}

async fn refresh_available_models(&self, strategy: RefreshStrategy) -> CoreResult<()> {
    // 自定义目录模式跳过刷新
    if matches!(self.catalog_mode, CatalogMode::Custom) {
        return Ok(());
    }
    
    // 非 ChatGPT 模式仅使用缓存
    if self.auth_manager.auth_mode() != Some(AuthMode::Chatgpt) {
        self.try_load_cache().await;
        return Ok(());
    }
    
    match strategy {
        RefreshStrategy::Offline => {
            self.try_load_cache().await;
            Ok(())
        }
        RefreshStrategy::OnlineIfUncached => {
            if self.try_load_cache().await {
                return Ok(());
            }
            self.fetch_and_update_models().await
        }
        RefreshStrategy::Online => {
            self.fetch_and_update_models().await
        }
    }
}
```

### 3.4 缓存机制

文件：`codex-rs/core/src/models_manager/cache.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ModelsCache {
    pub(crate) fetched_at: DateTime<Utc>,      // 缓存时间戳
    pub(crate) etag: Option<String>,           // HTTP ETag
    pub(crate) client_version: Option<String>, // 客户端版本
    pub(crate) models: Vec<ModelInfo>,         // 模型列表
}

impl ModelsCache {
    fn is_fresh(&self, ttl: Duration) -> bool {
        if ttl.is_zero() { return false; }
        let Ok(ttl_duration) = chrono::Duration::from_std(ttl) else {
            return false;
        };
        let age = Utc::now().signed_duration_since(self.fetched_at);
        age <= ttl_duration
    }
}
```

缓存 TTL 默认为 300 秒（5 分钟）。

### 3.5 配置覆盖机制

文件：`codex-rs/core/src/models_manager/model_info.rs`

```rust
pub(crate) fn with_config_overrides(mut model: ModelInfo, config: &Config) -> ModelInfo {
    // 覆盖推理摘要支持
    if let Some(supports_reasoning_summaries) = config.model_supports_reasoning_summaries
        && supports_reasoning_summaries
    {
        model.supports_reasoning_summaries = true;
    }
    
    // 覆盖上下文窗口
    if let Some(context_window) = config.model_context_window {
        model.context_window = Some(context_window);
    }
    
    // 覆盖自动压缩阈值
    if let Some(auto_compact_token_limit) = config.model_auto_compact_token_limit {
        model.auto_compact_token_limit = Some(auto_compact_token_limit);
    }
    
    // 覆盖截断策略（基于 tool_output_token_limit）
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
    
    // 覆盖基础指令
    if let Some(base_instructions) = &config.base_instructions {
        model.base_instructions = base_instructions.clone();
        model.model_messages = None;
    }
    
    model
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/models.json` | 静态模型配置（编译时嵌入） |
| `codex-rs/protocol/src/openai_models.rs` | 模型相关的协议类型定义 |
| `codex-rs/core/src/models_manager/manager.rs` | 模型管理器主实现 |
| `codex-rs/core/src/models_manager/cache.rs` | 模型缓存管理 |
| `codex-rs/core/src/models_manager/model_info.rs` | 模型信息构造与配置覆盖 |
| `codex-rs/core/src/models_manager/model_presets.rs` | 遗留配置兼容 |
| `codex-rs/core/src/test_support.rs` | 测试支持（加载 models.json） |

### 4.2 调用链

#### 4.2.1 模型列表获取

```
TUI/CLI
  └─ ThreadManager::list_models()
       └─ ModelsManager::list_models(RefreshStrategy)
            ├─ refresh_available_models() [可选]
            │    ├─ try_load_cache() [离线]
            │    └─ fetch_and_update_models() [在线]
            │         └─ ModelsClient::list_models()
            └─ build_available_models()
                 ├─ ModelPreset::filter_by_auth()
                 └─ ModelPreset::mark_default_by_picker_visibility()
```

#### 4.2.2 模型信息获取

```
Codex::start_turn()
  └─ ModelsManager::get_model_info(model_slug, config)
       ├─ find_model_by_longest_prefix()
       ├─ find_model_by_namespaced_suffix() [fallback]
       └─ model_info_from_slug() [未知模型 fallback]
            └─ with_config_overrides()
```

#### 4.2.3 指令模板渲染

```
TurnContext::new()
  └─ model_info.get_model_instructions(personality)
       ├─ 使用 instructions_template + personality 变量替换
       └─ 或回退到 base_instructions
```

### 4.3 Bazel 构建配置

文件：`codex-rs/core/BUILD.bazel`

```bazel
filegroup(
    name = "model_availability_nux_fixtures",
    srcs = [
        "models.json",
        "tests/cli_responses_fixture.sse",
    ],
    visibility = ["//visibility:public"],
)

codex_rust_crate(
    name = "core",
    ...
    integration_compile_data_extra = [
        "//codex-rs/apply-patch:apply_patch_tool_instructions.md",
        "models.json",        # 编译时嵌入
        "prompt.md",
    ],
    ...
)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-core
  ├─ codex-protocol          # ModelInfo, ModelPreset, ModelsResponse 定义
  ├─ codex-api               # ModelsClient (远程 API 调用)
  ├─ codex-otel              # 遥测数据收集
  └─ codex-config            # Config 类型
```

### 5.2 外部 API 交互

#### 5.2.1 /models 端点

```rust
const MODELS_ENDPOINT: &str = "/models";
const MODELS_REFRESH_TIMEOUT: Duration = Duration::from_secs(5);

async fn fetch_and_update_models(&self) -> CoreResult<()> {
    let client = ModelsClient::new(transport, api_provider, api_auth)
        .with_telemetry(Some(request_telemetry));
    
    let (models, etag) = timeout(
        MODELS_REFRESH_TIMEOUT,
        client.list_models(&client_version, HeaderMap::new()),
    ).await?;
    
    self.apply_remote_models(models.clone()).await;
    self.cache_manager.persist_cache(&models, etag, client_version).await;
    Ok(())
}
```

#### 5.2.2 请求参数

- `client_version`: 客户端版本（用于服务端兼容性检查）
- `HeaderMap`: 包含认证头和其他元数据

### 5.3 配置集成

#### 5.3.1 用户自定义模型目录

```rust
// Config 中的配置项
pub struct Config {
    pub model_catalog: Option<ModelsResponse>,  // 运行时加载的自定义目录
    ...
}

// ConfigToml 中的配置
pub struct ConfigToml {
    pub model_catalog_json: Option<AbsolutePathBuf>,  // 配置文件路径
    ...
}
```

#### 5.3.2 加载流程

```rust
fn load_model_catalog(
    model_catalog_json: Option<AbsolutePathBuf>,
) -> std::io::Result<Option<ModelsResponse>> {
    model_catalog_json
        .map(|path| load_catalog_json(&path))
        .transpose()
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 模型 slug 冲突

**风险**：最长前缀匹配可能导致意外匹配。例如 `"gpt-5.3"` 会匹配 `"gpt-5.3-codex"` 的前缀。

**缓解**：`find_model_by_longest_prefix` 选择最长匹配项，但命名空间模型（如 `"custom/gpt-5.3"`）需要额外的后缀匹配逻辑。

#### 6.1.2 缓存失效

**风险**：远程模型更新后，本地缓存可能过期（TTL 5 分钟），导致用户暂时看不到新模型。

**缓解**：
- ETag 机制支持快速检测变更
- `refresh_if_new_etag()` 可在收到新 ETag 时立即刷新

#### 6.1.3 未知模型 Fallback

**风险**：使用未在 models.json 中定义的模型时，会回退到默认元数据，可能缺少关键功能支持。

**代码**：
```rust
pub(crate) fn model_info_from_slug(slug: &str) -> ModelInfo {
    warn!("Unknown model {slug} is used. This will use fallback model metadata.");
    ModelInfo {
        used_fallback_model_metadata: true,  // 标记为 fallback
        ...
    }
}
```

#### 6.1.4 编译时依赖

**风险**：`models.json` 通过 `include_str!` 编译时嵌入，修改后需要重新编译才能生效。

**缓解**：远程刷新机制允许运行时更新，但初始启动仍依赖编译版本。

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 空 models.json | 编译时 panic（`load_remote_models_from_file` 失败） |
| 自定义目录为空 | 配置加载时返回错误（`load_catalog_json` 验证） |
| 网络超时 | 回退到缓存或捆绑配置 |
| 缓存损坏 | 忽略缓存，从网络或捆绑配置重新加载 |
| 命名空间格式错误 | 拒绝匹配，使用 fallback 元数据 |

### 6.3 改进建议

#### 6.3.1 配置热重载

当前自定义模型目录仅在启动时加载。建议支持配置变更监听，实现热重载：

```rust
// 潜在实现
impl ModelsManager {
    pub async fn watch_catalog_changes(&self, path: PathBuf) {
        // 使用 FileWatcher 监听 model_catalog_json 变更
    }
}
```

#### 6.3.2 模型验证工具

添加 CI 检查验证 models.json 的完整性：

```rust
#[test]
fn validate_models_json() {
    // 检查必填字段
    // 验证 slug 唯一性
    // 验证 upgrade 目标存在性
    // 检查优先级冲突
}
```

#### 6.3.3 增量更新

当前远程刷新会替换整个模型列表。建议支持增量更新（PATCH），减少带宽：

```rust
// 潜在 API
pub struct ModelsDelta {
    pub added: Vec<ModelInfo>,
    pub updated: Vec<ModelInfo>,
    pub removed: Vec<String>, // slugs
}
```

#### 6.3.4 模型能力发现

当前模型能力通过静态配置声明。未来可考虑动态能力协商：

```rust
// 运行时从模型服务端获取实际能力
pub async fn negotiate_capabilities(&self, slug: &str) -> ModelCapabilities {
    // 调用 OPTIONS /models/{slug} 或类似端点
}
```

#### 6.3.5 更好的错误提示

当使用未知模型时，除了 warning 日志，可在 TUI 中显示友好提示：

```
⚠️  您正在使用未经验证的模型 "custom-model"。
   某些功能可能不可用。建议使用官方支持的模型列表中的模型。
```

### 6.4 测试覆盖

关键测试文件：

| 测试文件 | 覆盖场景 |
|---------|---------|
| `manager_tests.rs` | 缓存管理、模型查找、预设构建 |
| `model_info_tests.rs` | 配置覆盖、指令渲染 |
| `remote_models.rs` | 远程刷新、ETag 处理、网络超时 |
| `config_tests.rs` | 自定义目录加载、验证 |

建议添加的测试：
- 大规模模型列表性能测试（1000+ 模型）
- 并发刷新测试
- 缓存损坏恢复测试

---

## 7. 附录

### 7.1 models.json 中的模型列表（当前）

| slug | display_name | priority | visibility |
|------|-------------|----------|------------|
| gpt-5.3-codex | gpt-5.3-codex | 0 | list |
| gpt-5.4 | gpt-5.4 | 0 | list |
| gpt-5.2-codex | gpt-5.2-codex | 3 | list |
| gpt-5.1-codex-max | gpt-5.1-codex-max | 4 | list |
| gpt-5.1-codex | gpt-5.1-codex | 5 | hide |
| gpt-5.2 | gpt-5.2 | 6 | list |
| gpt-5.1 | gpt-5.1 | 7 | hide |
| gpt-5-codex | gpt-5-codex | 10 | hide |
| gpt-5 | gpt-5 | 11 | hide |
| gpt-oss-120b | gpt-oss-120b | 11 | hide |
| gpt-oss-20b | gpt-oss-20b | 11 | hide |
| gpt-5.1-codex-mini | gpt-5.1-codex-mini | 12 | list |
| gpt-5-codex-mini | gpt-5-codex-mini | 13 | hide |

### 7.2 相关环境变量

| 变量 | 说明 |
|------|------|
| `OPENAI_BASE_URL` | 覆盖默认 API 基础 URL |
| `CODEX_RS_SSE_FIXTURE` | 使用 SSE fixture 文件代替真实 API（测试用） |

### 7.3 相关配置项

```toml
# config.toml
model_catalog_json = "/path/to/custom_models.json"  # 自定义模型目录
model_context_window = 128000                        # 覆盖上下文窗口
model_auto_compact_token_limit = 100000             # 覆盖自动压缩阈值
tool_output_token_limit = 5000                      # 覆盖工具输出限制
```
