# manager.rs 研究文档

## 场景与职责

`manager.rs` 是 Codex CLI 模型管理系统的核心 orchestrator，负责协调远程模型发现、本地缓存管理和模型元数据组装。它是整个 `models_manager` 模块的入口点，处理以下关键职责：

1. **模型列表管理**：从远程 API 或本地缓存获取可用模型列表
2. **模型元数据解析**：根据模型 slug 查找并组装完整的 `ModelInfo`
3. **刷新策略执行**：支持在线/离线/条件刷新三种模式
4. **协作模式集成**：提供协作模式预设列表
5. **遥测与监控**：记录模型请求的性能和认证指标

## 功能点目的

### 1. 刷新策略 (`RefreshStrategy`)
| 策略 | 行为 |
|------|------|
| `Online` | 始终从网络获取，忽略缓存 |
| `Offline` | 仅使用缓存，永不请求网络 |
| `OnlineIfUncached` | 缓存可用且新鲜时使用，否则请求网络 |

### 2. 目录模式 (`CatalogMode`)
| 模式 | 行为 |
|------|------|
| `Default` | 从捆绑的 `models.json` 启动，允许缓存/网络更新 |
| `Custom` | 使用调用方提供的目录，禁用后台刷新 |

### 3. 核心方法

#### `list_models` - 列出可用模型
- 根据刷新策略获取模型列表
- 返回按优先级排序的 `ModelPreset` 列表
- 根据认证模式过滤（ChatGPT 模式显示所有模型，否则仅显示 API 支持模型）

#### `get_default_model` - 获取默认模型
- 如果提供了模型参数，直接返回
- 否则按优先级选择默认模型
- 优先选择 `show_in_picker` 为 true 的模型

#### `get_model_info` - 获取模型元数据
- 支持前缀匹配（最长匹配优先）
- 支持命名空间后缀匹配（如 `custom/gpt-5` → `gpt-5`）
- 应用配置覆盖（context_window、reasoning_summaries 等）
- 未知模型返回 fallback 元数据

#### `refresh_if_new_etag` - 条件刷新
- 比较服务端 ETag 与本地缓存
- ETag 变化时触发完整刷新
- ETag 未变化时仅刷新缓存 TTL

## 具体技术实现

### 关键数据结构

```rust
/// 模型管理器
pub struct ModelsManager {
    remote_models: RwLock<Vec<ModelInfo>>,     // 远程模型缓存（内存）
    catalog_mode: CatalogMode,                  // 目录来源模式
    collaboration_modes_config: CollaborationModesConfig,
    auth_manager: Arc<AuthManager>,             // 认证管理器
    etag: RwLock<Option<String>>,              // 当前 ETag
    cache_manager: ModelsCacheManager,          // 磁盘缓存管理器
    provider: ModelProviderInfo,                // API 提供商配置
}

/// 模型请求遥测
struct ModelsRequestTelemetry {
    auth_mode: Option<String>,
    auth_header_attached: bool,
    auth_header_name: Option<&'static str>,
    auth_env: AuthEnvTelemetry,
}
```

### 核心流程

#### 模型列表获取流程
```
list_models(refresh_strategy)
├── refresh_available_models(strategy)
│   ├── Custom 模式 → 直接返回
│   ├── 非 ChatGPT 认证 → 仅尝试缓存
│   └── 根据策略选择分支
│       ├── Offline → try_load_cache()
│       ├── OnlineIfUncached → try_load_cache() 或 fetch_and_update_models()
│       └── Online → fetch_and_update_models()
├── get_remote_models() → 获取内存中的模型列表
└── build_available_models(remote_models)
    ├── 按 priority 排序
    ├── 转换为 ModelPreset
    ├── 根据 auth 模式过滤
    └── 标记默认模型
```

#### 远程获取流程 (`fetch_and_update_models`)
```
1. 获取认证信息（auth_manager.auth().await）
2. 构建 API 客户端（ModelsClient）
3. 设置 5 秒超时调用 list_models
4. 应用远程模型（合并到本地捆绑数据）
5. 更新 ETag
6. 持久化到磁盘缓存
```

#### 模型匹配算法

**最长前缀匹配** (`find_model_by_longest_prefix`):
```rust
// 示例：模型 "gpt-5.3-codex-special" 匹配 "gpt-5.3-codex" 而非 "gpt-5"
for candidate in candidates {
    if model.starts_with(&candidate.slug) {
        // 选择最长的匹配
        if candidate.slug.len() > best.slug.len() {
            best = candidate;
        }
    }
}
```

**命名空间后缀匹配** (`find_model_by_namespaced_suffix`):
```rust
// 示例："custom/gpt-5" → 尝试匹配 "gpt-5"
// 限制：仅支持单级命名空间，命名空间必须是 \w+ 格式
let (namespace, suffix) = model.split_once('/')?;
if suffix.contains('/') { return None; }  // 拒绝多级命名空间
if !namespace.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
    return None;  // 命名空间格式校验
}
find_model_by_longest_prefix(suffix, candidates)
```

### 遥测实现

`ModelsRequestTelemetry` 实现 `RequestTelemetry` trait，记录：
- 请求耗时（duration_ms）
- HTTP 状态码
- 认证信息（auth mode、header、环境变量状态）
- 错误详情（error message、request ID、CF Ray）

遥测数据同时发送到两个目标：
- `codex_otel.log_only`：完整遥测数据
- `codex_otel.trace_safe`：安全过滤后的遥测数据

## 关键代码路径与文件引用

### 内部模块依赖
| 路径 | 用途 |
|------|------|
| `cache.rs` | `ModelsCacheManager` - 磁盘缓存管理 |
| `collaboration_mode_presets.rs` | 协作模式预设生成 |
| `model_info.rs` | `model_info_from_slug`、`with_config_overrides` |

### 外部依赖
| 路径 | 用途 |
|------|------|
| `crate::auth::AuthManager` | 认证管理 |
| `crate::auth::AuthMode` | 认证模式判断 |
| `crate::config::Config` | 配置覆盖 |
| `crate::model_provider_info::ModelProviderInfo` | API 提供商配置 |
| `codex_api::ModelsClient` | 远程 API 客户端 |
| `codex_protocol::openai_models::*` | 协议类型 |

### 常量定义
| 常量 | 值 | 说明 |
|------|-----|------|
| `MODEL_CACHE_FILE` | `"models_cache.json"` | 缓存文件名 |
| `DEFAULT_MODEL_CACHE_TTL` | 300 秒 | 默认缓存 TTL |
| `MODELS_REFRESH_TIMEOUT` | 5 秒 | 刷新超时时间 |
| `MODELS_ENDPOINT` | `"/models"` | API 端点 |

### 捆绑数据
| 文件 | 用途 |
|------|------|
| `codex-rs/core/models.json` | 捆绑的模型元数据（编译时嵌入） |

## 依赖与外部交互

### 外部 Crate 依赖
- `tokio::sync::RwLock`：异步读写锁
- `tokio::time::timeout`：超时控制
- `tracing`：结构化日志
- `http::HeaderMap`：HTTP 头处理

### API 交互
- **端点**：`GET /models`
- **客户端**：`codex_api::ModelsClient`
- **超时**：5 秒
- **认证**：通过 `AuthManager` 获取

### 文件系统交互
- **读取**：`~/.codex/models_cache.json`
- **写入**：`~/.codex/models_cache.json`

### 认证集成
```rust
// 仅 ChatGPT 认证模式支持远程刷新
if self.auth_manager.auth_mode() != Some(AuthMode::Chatgpt) {
    // 仅使用缓存
}
```

## 风险、边界与改进建议

### 已知风险

1. **超时硬编码**
   - 风险：`MODELS_REFRESH_TIMEOUT = 5s` 在网络差时可能导致频繁失败
   - 建议：支持配置或自适应超时

2. **并发刷新竞争**
   - 风险：多个并发 `list_models` 调用可能触发多次网络请求
   - 现状：使用 `RwLock` 保护 `remote_models`，但无刷新去重机制
   - 建议：添加刷新状态标记，避免重复请求

3. **模型匹配歧义**
   - 风险：前缀匹配可能导致意外匹配（如 `gpt-5` 匹配 `gpt-5.1`）
   - 缓解：最长前缀匹配优先，命名空间匹配有严格限制
   - 建议：添加匹配日志，便于调试

4. **内存缓存与磁盘缓存不一致**
   - 风险：`apply_remote_models` 直接修改内存，失败时无回滚
   - 建议：考虑事务性更新或版本控制

### 边界条件

| 场景 | 行为 |
|------|------|
| 网络超时 | 返回错误，使用现有缓存（如果有） |
| 认证失败 | 记录遥测，返回错误 |
| 空模型列表 | 返回空列表 |
| 未知模型 slug | 返回 fallback 元数据（`used_fallback_model_metadata = true`） |
| 多级命名空间 | 拒绝匹配，使用 fallback |
| 缓存损坏 | 记录错误，视为无缓存 |

### 改进建议

1. **刷新去重**
   ```rust
   enum RefreshState {
       Idle,
       InProgress(oneshot::Receiver<Result<()>>),
       Completed(Instant),
   }
   ```

2. **智能重试**
   - 对网络错误实现指数退避重试
   - 区分可重试错误（超时）和不可重试错误（认证失败）

3. **模型匹配增强**
   - 添加模糊匹配支持（编辑距离）
   - 提供匹配建议（"您是否想输入 gpt-5.3-codex？"）

4. **缓存策略优化**
   - 支持分层缓存（内存 → 磁盘 → 网络）
   - 添加缓存预热机制

5. **可观测性增强**
   - 添加模型匹配指标（命中率、fallback 率）
   - 添加缓存性能指标（加载时间、命中率）

### 测试覆盖

测试文件：`manager_tests.rs`

| 测试用例 | 覆盖场景 |
|----------|----------|
| `get_model_info_tracks_fallback_usage` | Fallback 元数据标记 |
| `get_model_info_uses_custom_catalog` | 自定义目录 |
| `get_model_info_matches_namespaced_suffix` | 命名空间匹配 |
| `get_model_info_rejects_multi_segment_namespace` | 多级命名空间拒绝 |
| `refresh_available_models_sorts_by_priority` | 优先级排序 |
| `refresh_available_models_uses_cache_when_fresh` | 缓存使用 |
| `refresh_available_models_refetches_when_cache_stale` | 缓存过期刷新 |
| `refresh_available_models_refetches_when_version_mismatch` | 版本不匹配刷新 |
| `refresh_available_models_drops_removed_remote_models` | 远程模型移除 |
| `refresh_available_models_skips_network_without_chatgpt_auth` | 非 ChatGPT 认证 |
| `models_request_telemetry_emits_auth_env_feedback_tags_on_failure` | 遥测数据 |
| `build_available_models_picks_default_after_hiding_hidden_models` | 默认模型选择 |
| `bundled_models_json_roundtrips` | 捆绑数据序列化 |
