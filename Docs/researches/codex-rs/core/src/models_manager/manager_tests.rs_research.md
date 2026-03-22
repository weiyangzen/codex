# manager_tests.rs 研究文档

## 场景与职责

`manager_tests.rs` 是 `manager.rs` 的综合测试套件，包含 13 个测试用例，覆盖模型管理的所有核心功能：

1. **模型元数据解析**：验证模型查找、fallback 处理、自定义目录
2. **模型匹配逻辑**：验证前缀匹配、命名空间匹配、多级命名空间拒绝
3. **缓存行为**：验证缓存使用、过期刷新、版本不匹配处理
4. **刷新策略**：验证优先级排序、远程模型同步
5. **遥测数据**：验证认证环境信息收集
6. **数据完整性**：验证捆绑模型 JSON 的序列化正确性

## 功能点目的

### 1. 模型元数据测试组

#### `get_model_info_tracks_fallback_usage`
- **目的**：验证未知模型使用 fallback 元数据并正确标记
- **验证点**：
  - 已知模型：`used_fallback_model_metadata = false`
  - 未知模型：`used_fallback_model_metadata = true`

#### `get_model_info_uses_custom_catalog`
- **目的**：验证自定义模型目录覆盖捆绑数据
- **验证点**：
  - 自定义目录中的模型属性被正确继承
  - 前缀匹配正确应用自定义目录

#### `get_model_info_matches_namespaced_suffix`
- **目的**：验证单级命名空间后缀匹配
- **示例**：`custom/gpt-image` → 匹配 `gpt-image`

#### `get_model_info_rejects_multi_segment_namespace_suffix_matching`
- **目的**：验证多级命名空间被拒绝
- **示例**：`ns1/ns2/model` → 使用 fallback

### 2. 刷新策略测试组

#### `refresh_available_models_sorts_by_priority`
- **目的**：验证模型按 priority 字段升序排序
- **验证点**：priority 值小的模型排在前面

#### `refresh_available_models_uses_cache_when_fresh`
- **目的**：验证缓存命中时避免网络请求
- **验证点**：第二次调用不触发 `/models` 请求

#### `refresh_available_models_refetches_when_cache_stale`
- **目的**：验证缓存过期时自动刷新
- **技术**：使用 `manipulate_cache_for_test` 修改时间戳模拟过期

#### `refresh_available_models_refetches_when_version_mismatch`
- **目的**：验证版本不匹配时刷新
- **技术**：使用 `mutate_cache_for_test` 修改缓存版本

#### `refresh_available_models_drops_removed_remote_models`
- **目的**：验证远程模型列表更新时移除已删除模型

#### `refresh_available_models_skips_network_without_chatgpt_auth`
- **目的**：验证非 ChatGPT 认证模式下跳过网络请求

### 3. 遥测测试组

#### `models_request_telemetry_emits_auth_env_feedback_tags_on_failure`
- **目的**：验证失败请求时遥测数据包含完整认证环境信息
- **验证点**：
  - 端点、认证模式、请求 ID
  - 环境变量状态（OPENAI_API_KEY、CODEX_API_KEY 等）
  - 错误代码和错误信息

### 4. 工具与辅助函数

#### `build_available_models_picks_default_after_hiding_hidden_models`
- **目的**：验证默认模型选择逻辑（优先选择可见模型）

#### `bundled_models_json_roundtrips`
- **目的**：验证捆绑的 `models.json` 可正确序列化和反序列化

## 具体技术实现

### 测试基础设施

#### 模型构造辅助函数
```rust
fn remote_model(slug: &str, display: &str, priority: i32) -> ModelInfo {
    // 使用 serde_json 从 JSON 构造模型
}

fn remote_model_with_visibility(slug: &str, display: &str, priority: i32, visibility: &str) -> ModelInfo {
    // 构造指定可见性的模型
}
```

#### Mock 服务提供商构造
```rust
fn provider_for(base_url: String) -> ModelProviderInfo {
    ModelProviderInfo {
        name: "mock".into(),
        base_url: Some(base_url),
        // ... 其他字段使用默认值
    }
}
```

#### 遥测数据收集器
```rust
#[derive(Default)]
struct TagCollectorVisitor {
    tags: BTreeMap<String, String>,
}

impl Visit for TagCollectorVisitor {
    fn record_bool(&mut self, field: &Field, value: bool) { ... }
    fn record_str(&mut self, field: &Field, value: &str) { ... }
    fn record_debug(&mut self, field: &Field, value: &dyn Debug) { ... }
}

struct TagCollectorLayer {
    tags: Arc<Mutex<BTreeMap<String, String>>>,
}

impl<S> Layer<S> for TagCollectorLayer { ... }
```

### 测试模式

#### 标准测试结构
```rust
#[tokio::test]
async fn test_name() {
    // 1. 设置 Mock 服务器
    let server = MockServer::start().await;
    let models_mock = mount_models_once(&server, ModelsResponse { ... }).await;
    
    // 2. 创建临时目录和配置
    let codex_home = tempdir().expect("temp dir");
    let config = ConfigBuilder::default()...build().await;
    
    // 3. 创建认证管理器和模型管理器
    let auth_manager = AuthManager::from_auth_for_testing(...);
    let manager = ModelsManager::with_provider_for_tests(...);
    
    // 4. 执行操作
    let result = manager.some_method().await;
    
    // 5. 验证结果
    assert_eq!(result, expected);
    assert_eq!(models_mock.requests().len(), expected_count);
}
```

#### 缓存操作测试模式
```rust
// 模拟缓存过期
manager.cache_manager.manipulate_cache_for_test(|fetched_at| {
    *fetched_at = Utc::now() - chrono::Duration::hours(1);
}).await;

// 模拟版本不匹配
manager.cache_manager.mutate_cache_for_test(|cache| {
    cache.client_version = Some(format!("{client_version}-mismatch"));
}).await;
```

## 关键代码路径与文件引用

### 被测试的方法
| 方法 | 所在文件 | 测试覆盖 |
|------|----------|----------|
| `get_model_info` | `manager.rs:314` | 4 个测试 |
| `refresh_available_models` | `manager.rs:393` | 6 个测试 |
| `build_available_models` | `manager.rs:520` | 1 个测试 |
| `ModelsRequestTelemetry::on_request` | `manager.rs:54` | 1 个测试 |
| `load_remote_models_from_file` | `manager.rs:489` | 1 个测试 |

### 测试辅助类型
| 类型 | 用途 |
|------|------|
| `TagCollectorVisitor` | 收集 tracing 事件中的字段值 |
| `TagCollectorLayer` | 拦截 `feedback_tags` 目标的事件 |

### 外部测试依赖
| 路径 | 用途 |
|------|------|
| `core_test_support::responses::mount_models_once` | Mock `/models` 端点 |
| `wiremock::MockServer` | HTTP Mock 服务器 |
| `tempfile::tempdir` | 临时目录 |
| `tracing_subscriber` | 遥测数据捕获 |

## 依赖与外部交互

### 测试框架
- **异步运行时**：`tokio::test`
- **断言库**：`pretty_assertions::assert_eq`
- **Mock 服务器**：`wiremock::MockServer`

### 被测模块接口
```rust
// 父模块中条件引入测试模块
#[cfg(test)]
#[path = "manager_tests.rs"]
mod tests;
```

### 测试可见性
- 测试访问了多个 `pub(crate)` 方法：
  - `get_remote_models`
  - `cache_manager`
  - `build_available_models`
- 使用了专门的测试构造方法：`with_provider_for_tests`

## 风险、边界与改进建议

### 测试覆盖率分析

| 功能区域 | 覆盖状态 | 说明 |
|----------|----------|------|
| 模型元数据解析 | ✅ 良好 | Fallback、自定义目录、命名空间匹配 |
| 缓存行为 | ✅ 良好 | 命中、过期、版本不匹配 |
| 刷新策略 | ⚠️ 部分 | 缺少 `Offline` 策略测试 |
| 遥测数据 | ✅ 良好 | 失败场景覆盖完整 |
| 协作模式 | ❌ 缺失 | 未测试 `list_collaboration_modes` |
| 默认模型选择 | ⚠️ 部分 | 仅测试了隐藏模型场景 |
| ETag 处理 | ⚠️ 间接 | 通过缓存测试间接覆盖 |

### 缺失测试场景

1. **边界条件**
   - 空模型列表处理
   - 网络超时场景
   - 磁盘权限错误

2. **并发场景**
   - 并发刷新请求
   - 读写锁竞争

3. **错误处理**
   - 无效 JSON 响应
   - 部分模型数据损坏

4. **配置覆盖**
   - `model_supports_reasoning_summaries` 覆盖
   - `model_context_window` 覆盖
   - `tool_output_token_limit` 覆盖

### 改进建议

1. **参数化测试**
   ```rust
   #[test_case(RefreshStrategy::Online)]
   #[test_case(RefreshStrategy::Offline)]
   #[test_case(RefreshStrategy::OnlineIfUncached)]
   async fn refresh_with_strategy(strategy: RefreshStrategy) { ... }
   ```

2. **属性测试**
   - 使用 `proptest` 生成随机模型 slug 验证匹配逻辑
   - 验证前缀匹配的边界条件

3. **性能测试**
   - 大规模模型列表（1000+）的性能测试
   - 缓存加载/保存的 I/O 性能测试

4. **快照测试**
   - 使用 `insta` 对 `ModelInfo` 结构进行快照测试
   - 便于审查模型元数据变更

5. **模拟时间**
   - 使用 `tokio::time::pause` 替代实际睡眠
   - 加速时间相关测试

### 维护注意事项

1. **Mock 数据同步**
   - `remote_model` 函数中的 JSON 结构需与 `ModelInfo` 定义同步
   - 新增字段时需更新测试辅助函数

2. **测试隔离性**
   - 每个测试使用独立的 `tempdir`，确保隔离
   - Mock 服务器每个测试独立启动，避免状态污染

3. **异步测试可靠性**
   - 使用 `timeout` 包装可能挂起的操作
   - 避免在测试中依赖实际网络

4. **遥测测试稳定性**
   - `TagCollectorLayer` 依赖特定的 tracing 目标名称
   - 目标名称变更需同步更新测试
