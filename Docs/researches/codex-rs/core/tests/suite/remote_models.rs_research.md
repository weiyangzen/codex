# remote_models.rs 研究文档

## 场景与职责

`remote_models.rs` 是 Codex 核心测试套件中的集成测试文件，专门测试**远程模型管理功能**。该文件验证 `ModelsManager` 组件与远程模型目录服务的交互逻辑，包括模型发现、元数据解析、前缀匹配策略、模型合并与缓存机制。

测试场景覆盖：
- 远程模型列表获取与本地模型合并
- 模型 slug 的最长前缀匹配算法
- 命名空间模型（如 `custom/gpt-5.2-codex`）的元数据解析
- 远程模型的 reasoning 配置传递
- UnifiedExec 工具类型与远程模型的集成
- 截断策略（Truncation Policy）的继承与覆盖
- 基础指令（base_instructions）的远程覆盖
- 模型优先级排序与默认模型选择
- 请求超时处理（5秒超时）
- 隐藏模型（picker-only）的处理

## 功能点目的

### 1. 远程模型发现与合并
测试 `ModelsManager` 如何从远程 `/models` 端点获取模型列表，并与本地捆绑的 `models.json` 合并。验证新增模型、模型属性覆盖、空响应处理等场景。

### 2. 最长前缀匹配（Longest Matching Prefix）
当请求的模型 slug（如 `gpt-5.3-codex-test`）不完全匹配远程模型列表中的任何条目时，系统使用最长前缀匹配算法找到最匹配的模型元数据（如 `gpt-5.3-codex`）。

### 3. 命名空间模型支持
验证形如 `namespace/model-name` 的模型 slug 能够正确解析，剥离命名空间后匹配基础模型元数据，且不触发 fallback 警告。

### 4. Reasoning 配置传递
测试远程模型定义的 `default_reasoning_level`、`supported_reasoning_levels`、`supports_reasoning_summaries`、`default_reasoning_summary` 等字段如何正确传递到 API 请求中。

### 5. UnifiedExec 集成
验证远程模型配置 `shell_type: ConfigShellToolType::UnifiedExec` 时，命令执行是否通过 UnifiedExec 启动（`ExecCommandSource::UnifiedExecStartup`）。

### 6. 截断策略管理
测试远程模型的 `truncation_policy` 如何被应用，以及用户配置 `tool_output_token_limit` 如何覆盖远程策略。

### 7. 基础指令覆盖
验证远程模型的 `base_instructions` 如何覆盖本地模型的基础指令。

### 8. 权限与可见性
测试 `ModelVisibility::Hide` 的模型在 picker 中隐藏但仍可通过 API 使用。

## 具体技术实现

### 关键数据结构

```rust
// 远程模型常量
const REMOTE_MODEL_SLUG: &str = "codex-test";

// 测试用的远程模型构造器
fn test_remote_model(
    slug: &str,
    visibility: ModelVisibility,
    priority: i32,
) -> ModelInfo

fn test_remote_model_with_policy(
    slug: &str,
    visibility: ModelVisibility,
    priority: i32,
    truncation_policy: TruncationPolicyConfig,
) -> ModelInfo
```

### 关键测试流程

#### 1. 最长前缀匹配测试
```rust
async fn remote_models_get_model_info_uses_longest_matching_prefix() {
    // 1. 创建 MockServer
    let server = MockServer::start().await;
    
    // 2. 定义两个模型：generic (gpt-5.3) 和 specific (gpt-5.3-codex)
    let generic = test_remote_model_with_policy("gpt-5.3", ...);
    let specific = test_remote_model_with_policy("gpt-5.3-codex", ...);
    
    // 3. 挂载 /models 响应
    mount_models_once(&server, ModelsResponse { models: vec![generic, specific] }).await;
    
    // 4. 创建 ModelsManager
    let manager = models_manager_with_provider(...);
    
    // 5. 请求 gpt-5.3-codex-test，应匹配 gpt-5.3-codex 的元数据
    let model_info = manager.get_model_info("gpt-5.3-codex-test", &config).await;
    assert_eq!(model_info.base_instructions, specific.base_instructions);
}
```

#### 2. Reasoning 配置传递测试
```rust
async fn remote_models_long_model_slug_is_sent_with_high_reasoning() {
    // 1. 配置远程模型支持 High reasoning
    remote_model.default_reasoning_level = Some(ReasoningEffort::High);
    remote_model.supported_reasoning_levels = vec![...];
    remote_model.supports_reasoning_summaries = true;
    remote_model.default_reasoning_summary = ReasoningSummary::Detailed;
    
    // 2. 挂载 SSE 响应
    mount_sse_once(&server, sse([ev_response_created, ev_completed])).await;
    
    // 3. 提交 UserTurn
    codex.submit(Op::UserTurn { model: "gpt-5.3-codex-test", ... }).await?;
    
    // 4. 验证请求体包含 reasoning.effort = "high" 和 reasoning.summary = "detailed"
    let body = response_mock.single_request().body_json();
    assert_eq!(body["reasoning"]["effort"], "high");
    assert_eq!(body["reasoning"]["summary"], "detailed");
}
```

#### 3. UnifiedExec 集成测试
```rust
async fn remote_models_remote_model_uses_unified_exec() {
    // 1. 配置远程模型使用 UnifiedExec
    remote_model.shell_type = ConfigShellToolType::UnifiedExec;
    
    // 2. 挂载 SSE 序列（exec_command 调用 + 完成）
    mount_sse_sequence(&server, [
        sse([ev_response_created, ev_function_call(call_id, "exec_command", args), ev_completed]),
        sse([ev_response_created, ev_assistant_message, ev_completed]),
    ]).await;
    
    // 3. 提交 UserTurn
    codex.submit(Op::UserTurn { model: REMOTE_MODEL_SLUG, ... }).await?;
    
    // 4. 验证 ExecCommandBegin 事件的 source 为 UnifiedExecStartup
    let begin_event = wait_for_event_match(&codex, |msg| match msg {
        EventMsg::ExecCommandBegin(event) if event.call_id == call_id => Some(event.clone()),
        _ => None,
    }).await;
    assert_eq!(begin_event.source, ExecCommandSource::UnifiedExecStartup);
}
```

#### 4. 截断策略测试
```rust
async fn remote_models_truncation_policy_without_override_preserves_remote() {
    // 验证远程模型的 truncation_policy 被保留
    let model_info = manager.get_model_info(slug, &test.config).await;
    assert_eq!(model_info.truncation_policy, TruncationPolicyConfig::bytes(12_000));
}

async fn remote_models_truncation_policy_with_tool_output_override() {
    // 验证 tool_output_token_limit 覆盖远程策略
    // config.tool_output_token_limit = Some(50) 导致 truncation_policy = bytes(200)
}
```

#### 5. 请求超时测试
```rust
async fn remote_models_request_times_out_after_5s() {
    // 1. 挂载延迟 6 秒的 /models 响应
    mount_models_once_with_delay(&server, models, Duration::from_secs(6)).await;
    
    // 2. 设置 7 秒超时等待 get_default_model
    let model = timeout(Duration::from_secs(7), 
        manager.get_default_model(&None, RefreshStrategy::OnlineIfUncached)).await;
    
    // 3. 验证在 4.5-5.8 秒内超时，并返回默认模型
    assert!(elapsed >= Duration::from_millis(4_500));
    assert!(elapsed < Duration::from_millis(5_800));
    assert_eq!(default_model, bundled_default_model_slug());
}
```

### 测试辅助函数

```rust
// 等待模型在 ModelsManager 中可用
async fn wait_for_model_available(manager: &Arc<ModelsManager>, slug: &str) -> ModelPreset {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(model) = manager.list_models(RefreshStrategy::OnlineIfUncached).await
            .iter().find(|m| m.model == slug).cloned() {
            return model;
        }
        if Instant::now() >= deadline { panic!("timed out"); }
        sleep(Duration::from_millis(25)).await;
    }
}

// 获取捆绑模型 slug
fn bundled_model_slug() -> String {
    let response: ModelsResponse = serde_json::from_str(include_str!("../../models.json")).unwrap();
    response.models.first().unwrap().slug.clone()
}

// 获取默认捆绑模型 slug
fn bundled_default_model_slug() -> String {
    codex_core::test_support::all_model_presets()
        .iter().find(|p| p.is_default).unwrap().model.clone()
}
```

## 关键代码路径与文件引用

### 被测试的核心代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/models_manager/manager.rs` | `ModelsManager` 实现，包含模型发现、缓存、合并逻辑 |
| `codex-rs/core/src/models_manager/cache.rs` | 模型缓存管理（`ModelsCacheManager`） |
| `codex-rs/core/src/models_manager/model_info.rs` | 模型元数据构造与配置覆盖 |
| `codex-rs/protocol/src/openai_models.rs` | `ModelInfo`, `ModelPreset`, `ModelsResponse` 定义 |

### 测试基础设施

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | `mount_models_once`, `mount_sse_once`, `mount_sse_sequence` 等 Mock 辅助函数 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex`, `TestCodexBuilder` 测试框架 |
| `codex-rs/core/src/test_support.rs` | `models_manager_with_provider`, `auth_manager_from_auth` 等测试辅助函数 |

### 关键代码路径

```
测试用例
    ↓
ModelsManager::list_models(RefreshStrategy::OnlineIfUncached)
    ↓
ModelsManager::refresh_available_models()
    ↓
ModelsManager::fetch_and_update_models() [如果缓存未命中]
    ↓
ModelsClient::list_models() → HTTP GET /models
    ↓
ModelsManager::apply_remote_models() [合并远程模型到本地]
    ↓
ModelsManager::build_available_models() [排序、过滤、标记默认]
```

模型元数据查询路径：
```
ModelsManager::get_model_info(model_slug, config)
    ↓
ModelsManager::find_model_by_longest_prefix() [最长前缀匹配]
    ↓
ModelsManager::find_model_by_namespaced_suffix() [命名空间处理]
    ↓
model_info::with_config_overrides() [应用配置覆盖]
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock::MockServer` | HTTP 模拟服务器，模拟 `/models` 和 `/responses` 端点 |
| `tokio::time::{Duration, Instant, timeout}` | 异步超时控制 |
| `tempfile::TempDir` | 临时目录用于 Codex Home |
| `serde_json` | JSON 序列化/反序列化 |

### 内部依赖模块

| 模块 | 用途 |
|-----|------|
| `core_test_support::*` | 测试框架和辅助函数 |
| `codex_core::models_manager::*` | 被测试的模型管理核心 |
| `codex_protocol::openai_models::*` | 模型相关协议类型 |
| `codex_protocol::protocol::*` | 事件和操作类型 |

### 测试跳过条件

所有测试都使用两个宏来跳过不兼容环境：
- `skip_if_no_network!(Ok(()))` - 无网络环境跳过
- `skip_if_sandbox!(Ok(()))` - 沙箱环境跳过（沙箱中无法运行 MockServer）

## 风险、边界与改进建议

### 已知风险

1. **Windows 平台限制**
   - 文件顶部有 `#![cfg(not(target_os = "windows"))]`
   - UnifiedExec 在 Windows 上不支持，整个测试文件被排除
   - 风险：Windows 平台的远程模型功能缺乏测试覆盖

2. **测试间状态污染**
   - `ModelsManager` 使用 `RwLock` 存储远程模型
   - 并发测试可能相互影响（虽然每个测试使用独立的 MockServer 和 TempDir）

3. **硬编码超时**
   - `MODELS_REFRESH_TIMEOUT = Duration::from_secs(5)` 是硬编码的
   - 在慢网络环境下可能导致测试不稳定

### 边界情况

1. **空模型列表响应**
   - `remote_models_merge_preserves_bundled_models_on_empty_response` 测试验证空响应不会清除本地模型

2. **延迟响应**
   - `remote_models_request_times_out_after_5s` 测试验证 5 秒超时行为

3. **优先级冲突**
   - `remote_models_merge_adds_new_high_priority_first` 测试验证负优先级（高优先级）模型排在前面

4. **模型重叠**
   - `remote_models_merge_replaces_overlapping_model` 测试验证远程模型覆盖本地模型

### 改进建议

1. **增加 Windows 测试覆盖**
   - 为非 UnifiedExec 相关的功能添加 Windows 兼容测试
   - 或使用条件编译分离平台特定测试

2. **参数化超时配置**
   - 将 `MODELS_REFRESH_TIMEOUT` 改为可配置，便于测试环境调整

3. **增加并发测试**
   - 测试多个线程同时调用 `list_models` 和 `get_model_info` 的线程安全性

4. **增加错误场景测试**
   - 测试网络错误、HTTP 错误码、无效 JSON 响应的处理
   - 测试缓存损坏后的恢复行为

5. **测试数据外置**
   - 将 `test_remote_model` 的硬编码配置改为从 JSON 文件加载，便于维护

6. **增加 ETag 测试**
   - 测试 `refresh_if_new_etag` 逻辑，验证缓存刷新优化
