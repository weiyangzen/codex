# app_list.rs 研究文档

## 场景与职责

`app_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 **App/Connector 列表管理**功能。该文件测试了以下核心场景：

1. **App 列表查询与分页** - 验证 `app/list` RPC 方法的正确性
2. **连接器(Connector)可访问性管理** - 测试 accessible vs directory apps 的合并逻辑
3. **配置驱动的启用状态** - 验证 `config.toml` 中 `[apps.*]` 配置的 `is_enabled` 字段
4. **线程级别的特性开关** - 测试 `thread_id` 参数对 connectors 特性的影响
5. **缓存与强制刷新** - 验证 `force_refetch` 参数的行为及缓存容错机制

## 功能点目的

### 1. App 列表基础功能
- **空列表返回**：当 connectors 特性禁用时返回空列表
- **API Key 认证限制**：API Key 认证模式下不返回任何 apps
- **分页支持**：通过 `limit` 和 `cursor` 参数实现游标分页

### 2. 连接器可访问性合并
- **Accessible Apps**：用户已安装/授权的连接器（通过 MCP tools 发现）
- **Directory Apps**：来自目录的可用连接器列表
- **合并策略**：
  - 优先展示 accessible apps（用户已安装的）
  - 合并 directory apps 补充可用选项
  - 相同 ID 的 app 以 accessible 版本为准

### 3. 实时通知机制
- `app/list/updated` 通知在数据加载过程中分阶段推送
- 先推送 accessible apps，再推送合并后的完整列表
- 避免空列表的临时通知（防止 UI 闪烁）

### 4. 缓存策略
- 首次请求后缓存 app 列表
- `force_refetch=true` 强制刷新缓存
- 刷新失败时保留旧缓存（容错机制）
- 增量更新：基于缓存快照合并新数据

## 具体技术实现

### 关键数据结构

```rust
// App 列表请求参数
pub struct AppsListParams {
    pub cursor: Option<String>,           // 分页游标
    pub limit: Option<u32>,               // 每页数量
    pub thread_id: Option<String>,        // 用于特性开关评估
    pub force_refetch: bool,              // 强制刷新缓存
}

// App 列表响应
pub struct AppsListResponse {
    pub data: Vec<AppInfo>,               // App 列表
    pub next_cursor: Option<String>,      // 下一页游标
}

// App 元数据
pub struct AppInfo {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub logo_url: Option<String>,
    pub is_accessible: bool,              // 用户是否已安装/授权
    pub is_enabled: bool,                 // 配置中是否启用
    pub install_url: Option<String>,      // 安装链接
    pub branding: Option<AppBranding>,    // 品牌信息
    pub app_metadata: Option<AppMetadata>, // 应用元数据
}

// 更新通知
pub struct AppListUpdatedNotification {
    pub data: Vec<AppInfo>,
}
```

### 关键测试辅助函数

```rust
// 读取 app/list/updated 通知
async fn read_app_list_updated_notification(
    mcp: &mut McpProcess,
) -> Result<AppListUpdatedNotification>

// 启动模拟的 Apps 服务器（带延迟控制）
async fn start_apps_server_with_delays(
    connectors: Vec<AppInfo>,
    tools: Vec<Tool>,
    directory_delay: Duration,    // 目录响应延迟
    tools_delay: Duration,        // MCP tools 响应延迟
) -> Result<(String, JoinHandle<()>)>

// 创建连接器工具（用于模拟 accessible apps）
fn connector_tool(connector_id: &str, connector_name: &str) -> Result<Tool>

// 写入连接器配置
fn write_connectors_config(codex_home: &Path, base_url: &str) -> io::Result<()>
```

### 测试用例矩阵

| 测试用例 | 目的 | 关键验证点 |
|---------|------|-----------|
| `list_apps_returns_empty_when_connectors_disabled` | 特性禁用时空列表 | `features.connectors = false` |
| `list_apps_returns_empty_with_api_key_auth` | API Key 认证限制 | AuthMode::ApiKey |
| `list_apps_uses_thread_feature_flag_when_thread_id_is_provided` | 线程级特性开关 | 全局禁用但线程启用时返回 apps |
| `list_apps_reports_is_enabled_from_config` | 配置驱动启用状态 | `[apps.beta] enabled = false` |
| `list_apps_emits_updates_and_returns_after_both_lists_load` | 分阶段通知 | 先 accessible 后合并列表 |
| `list_apps_waits_for_accessible_data_before_emitting_directory_updates` | 加载顺序控制 | 目录先返回时等待 accessible |
| `list_apps_does_not_emit_empty_interim_updates` | 避免空通知 | 150ms 超时验证无通知 |
| `list_apps_paginates_results` | 分页功能 | limit/cursor 工作正常 |
| `list_apps_force_refetch_preserves_previous_cache_on_failure` | 缓存容错 | 刷新失败保留旧数据 |
| `list_apps_force_refetch_patches_updates_from_cached_snapshots` | 增量更新 | 基于缓存合并新数据 |

### Mock 服务器实现

测试使用自定义的 Axum 服务器模拟 ChatGPT 后端：

```rust
struct AppsServerState {
    expected_bearer: String,
    expected_account_id: String,
    response: Arc<StdMutex<serde_json::Value>>,
    directory_delay: Duration,
}

struct AppListMcpServer {
    tools: Arc<StdMutex<Vec<Tool>>>,
    tools_delay: Duration,
}

// 路由配置
let router = Router::new()
    .route("/connectors/directory/list", get(list_directory_connectors))
    .route("/connectors/directory/list_workspace", get(list_directory_connectors))
    .nest_service("/api/codex/apps", mcp_service);
```

## 关键代码路径与文件引用

### 测试文件
- `/codex-rs/app-server/tests/suite/v2/app_list.rs` - 本测试文件
- `/codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
- `/codex-rs/app-server/tests/common/lib.rs` - 测试工具库

### 协议定义
- `/codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `AppsListParams` (行 1929-1946)
  - `AppsListResponse` (行 2048-2057)
  - `AppListUpdatedNotification` (行 2059-2065)
  - `AppInfo` (行 1999-2024)
  - `AppBranding`, `AppMetadata`, `AppReview`, `AppScreenshot`

### 依赖配置
- `/codex-rs/app-server/tests/common/config.rs` - `write_mock_responses_config_toml`
- `/codex-rs/app-server/tests/common/auth_fixtures.rs` - `ChatGptAuthFixture`

### 核心协议
- `/codex-rs/app-server-protocol/src/protocol/common.rs` - 共享类型定义
- `/codex-rs/app-server-protocol/src/protocol/mappers.rs` - 类型映射

## 依赖与外部交互

### 外部服务依赖
1. **Mock ChatGPT 服务器** - 提供 connectors 目录和 MCP tools
2. **Codex App Server** - 被测服务，通过 MCP 协议交互
3. **临时文件系统** - 使用 `tempfile::TempDir` 作为 `CODEX_HOME`

### 协议依赖
- **JSON-RPC 2.0** - 请求/响应格式
- **MCP (Model Context Protocol)** - 服务器能力协商
- **SSE (Server-Sent Events)** - 实时通知推送

### 关键 Crate 依赖
```toml
# 测试框架
tokio = { features = ["process", "time"] }
tempfile = "*"
wiremock = "*"

# MCP 协议
rmcp = { version = "...", features = ["server", "streamable-http"] }

# 序列化
serde_json = "*"

# HTTP 服务器
axum = "*"
```

## 风险、边界与改进建议

### 已知风险

1. **时序敏感测试**
   - 多个测试依赖 `tokio::time::timeout` 和 `sleep` 延迟
   - 在慢速 CI 环境可能 flaky
   - 建议：使用 `tokio::time::pause()` 进行确定性测试

2. **端口绑定竞争**
   - Mock 服务器使用 `127.0.0.1:0` 动态分配端口
   - 理论上存在端口耗尽风险
   - 建议：添加端口分配重试逻辑

3. **缓存状态污染**
   - `force_refetch` 测试依赖全局缓存状态
   - 并行测试可能相互干扰
   - 缓解：每个测试使用独立的 `CODEX_HOME`

### 边界情况

1. **空列表处理**
   - 测试验证了不发送空列表通知
   - 但边界情况：accessible 为空但 directory 有数据

2. **分页边界**
   - 测试覆盖了 limit=1 的分页
   - 未测试 cursor 过期/无效的情况

3. **并发刷新**
   - 未测试多个客户端同时 `force_refetch` 的场景

### 改进建议

1. **测试稳定性**
   ```rust
   // 建议：使用确定性时间控制
   tokio::time::pause();
   // 执行操作
   tokio::time::advance(Duration::from_millis(300)).await;
   ```

2. **覆盖增强**
   - 添加测试：无效 cursor 的处理
   - 添加测试：并发 force_refetch
   - 添加测试：网络超时/重试

3. **文档完善**
   - 添加 App 列表状态机图示
   - 明确 accessible/directory 合并算法的复杂度

4. **性能测试**
   - 当前测试使用 300ms 延迟模拟慢速后端
   - 建议添加基准测试验证实际性能

### 相关 Issue 模式

- 缓存不一致：当 `force_refetch` 失败时，旧缓存可能包含已删除的 apps
- 通知顺序：客户端必须处理乱序到达的 `app/list/updated` 通知
- 线程安全：`AppsServerControl` 使用 `StdMutex`，在异步上下文中可能阻塞
