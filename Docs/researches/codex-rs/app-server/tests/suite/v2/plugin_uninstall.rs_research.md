# plugin_uninstall.rs 研究文档

## 场景与职责

`plugin_uninstall.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**插件卸载（Plugin Uninstall）**功能的端到端测试。插件卸载不仅涉及本地文件系统的清理，还包括与远程 ChatGPT 后端的同步（如果启用），以及相关的配置清理和遥测事件上报。

该测试文件的核心职责包括：
1. 验证插件本地缓存和配置的正确清理
2. 验证远程同步卸载流程（与 ChatGPT 后端集成）
3. 验证卸载操作的幂等性（重复卸载不报错）
4. 验证卸载操作的遥测事件上报

## 功能点目的

### 1. 本地卸载 (`plugin_uninstall_removes_plugin_cache_and_config_entry`)
- **目的**：验证卸载操作删除本地插件缓存和配置条目
- **业务价值**：
  - 释放磁盘空间
  - 清理不再使用的配置
  - 保持系统整洁
- **关键验证点**：
  - 插件缓存目录被删除（`plugins/cache/{marketplace}/{plugin}`）
  - 配置文件中插件条目被移除（`[plugins."{plugin}@{marketplace}"]`）
  - 幂等性：重复卸载返回成功（不报错）

### 2. 远程同步卸载 (`plugin_uninstall_force_remote_sync_calls_remote_uninstall_first`)
- **目的**：验证 `force_remote_sync: true` 时先调用远程卸载 API
- **业务价值**：
  - 保持本地状态与 ChatGPT 账户同步
  - 确保远程服务正确清理用户数据
- **关键验证点**：
  - 调用 `POST /backend-api/plugins/{plugin_id}/uninstall`
  - 包含正确的认证头（`Authorization: Bearer {token}`）
  - 包含账户 ID 头（`chatgpt-account-id`）
  - 远程调用成功后清理本地缓存

### 3. 遥测事件上报 (`plugin_uninstall_tracks_analytics_event`)
- **目的**：验证卸载操作上报分析事件
- **业务价值**：
  - 收集插件使用统计
  - 帮助改进插件生态系统
  - 支持产品决策
- **关键验证点**：
  - 事件类型：`codex_plugin_uninstalled`
  - 事件参数：
    - `plugin_id`：插件完整 ID
    - `plugin_name`：插件名称
    - `marketplace_name`：市场名称
    - `has_skills`：是否包含技能
    - `mcp_server_count`：MCP 服务器数量
    - `connector_ids`：连接器 ID 列表
    - `product_client_id`：客户端标识

## 具体技术实现

### 核心数据结构

#### PluginUninstallParams（请求参数）
```rust
pub struct PluginUninstallParams {
    pub plugin_id: String,        // 格式: "{plugin_name}@{marketplace_name}"
    pub force_remote_sync: bool,  // 是否强制远程同步
}
```

#### PluginUninstallResponse（响应）
```rust
pub struct PluginUninstallResponse {
    // 空响应表示成功
}
```

### 卸载流程

#### 本地卸载流程
```
plugin/uninstall (force_remote_sync: false)
    |
    v
解析 plugin_id（提取 plugin_name 和 marketplace_name）
    |
    v
删除本地缓存目录
    {codex_home}/plugins/cache/{marketplace}/{plugin}
    |
    v
从配置中移除插件条目
    [plugins."{plugin}@{marketplace}"]
    |
    v
上报遥测事件
    |
    v
返回成功
```

#### 远程同步卸载流程
```
plugin/uninstall (force_remote_sync: true)
    |
    v
检查 ChatGPT 认证
    |
    +-- 未认证 --> 返回错误
    |
    +-- 已认证 --> 调用远程卸载 API
                       POST /backend-api/plugins/{plugin_id}/uninstall
                       |
                       v
                   检查响应状态
                       |
                       +-- 失败 --> 返回错误
                       |
                       +-- 成功 --> 继续本地清理
                                       |
                                       v
                                   删除本地缓存
                                       |
                                       v
                                   更新配置
                                       |
                                       v
                                   上报遥测
                                       |
                                       v
                                   返回成功
```

### 遥测事件结构

#### 事件负载
```json
{
  "events": [{
    "event_type": "codex_plugin_uninstalled",
    "event_params": {
      "plugin_id": "sample-plugin@debug",
      "plugin_name": "sample-plugin",
      "marketplace_name": "debug",
      "has_skills": false,
      "mcp_server_count": 0,
      "connector_ids": [],
      "product_client_id": "codex-app-server-tests"
    }
  }]
}
```

#### 事件参数说明
| 参数 | 类型 | 说明 |
|-----|------|------|
| `plugin_id` | String | 插件完整标识符 |
| `plugin_name` | String | 插件短名称 |
| `marketplace_name` | String | 所属市场名称 |
| `has_skills` | Boolean | 插件是否包含技能 |
| `mcp_server_count` | Integer | MCP 服务器数量 |
| `connector_ids` | Array | 应用连接器 ID 列表 |
| `product_client_id` | String | 客户端标识符 |

### 配置清理

#### 清理前配置示例
```toml
[features]
plugins = true

[plugins."sample-plugin@debug"]
enabled = true
```

#### 清理后配置
```toml
[features]
plugins = true
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `PluginUninstallParams`, `PluginUninstallResponse` 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ClientRequest::PluginUninstall` 枚举 |

### 核心实现
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/plugins/manager.rs` | `PluginsManager::uninstall_plugin()` 实现 |
| `codex-rs/core/src/plugins/store.rs` | 插件存储清理逻辑 |
| `codex-rs/core/src/plugins/remote.rs` | 远程卸载 API 调用 |
| `codex-rs/core/src/analytics_client.rs` | 遥测事件上报 |

### API 实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs` | `plugin/uninstall` 请求处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 插件卸载实现 |

### 测试支持
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/common/mcp_process.rs` | `send_plugin_uninstall_request` 辅助方法 |
| `codex-rs/app-server/tests/common/analytics.rs` | 遥测测试支持（推测） |

## 依赖与外部交互

### 内部依赖
```rust
use codex_app_server_protocol::{
    PluginUninstallParams, PluginUninstallResponse,
    JSONRPCResponse, RequestId,
};
use codex_core::auth::AuthCredentialsStoreMode;
```

### 外部依赖
- **wiremock**：模拟 ChatGPT 后端 API
- **tempfile**：临时目录管理
- **tokio**：异步运行时

### 测试辅助函数

#### `write_installed_plugin`
创建模拟的已安装插件：
```rust
fn write_installed_plugin(
    codex_home: &TempDir,
    marketplace_name: &str,
    plugin_name: &str,
) -> Result<()> {
    let plugin_root = codex_home
        .path()
        .join("plugins/cache")
        .join(marketplace_name)
        .join(plugin_name)
        .join("local/.codex-plugin");
    std::fs::create_dir_all(&plugin_root)?;
    std::fs::write(
        plugin_root.join("plugin.json"),
        format!(r#"{{"name":"{plugin_name}"}}"#),
    )?;
    Ok(())
}
```

#### `write_chatgpt_auth`
写入 ChatGPT 认证信息（来自 `app_test_support`）

#### `start_analytics_events_server`
启动遥测事件接收服务器（来自 `app_test_support`）

## 风险、边界与改进建议

### 风险点

1. **远程依赖**
   - 远程同步卸载依赖 ChatGPT 后端可用性
   - **风险**：网络故障可能导致卸载失败
   - **建议**：实现重试机制，或支持"仅本地卸载"降级

2. **数据丢失**
   - 卸载操作不可逆，删除插件缓存
   - **风险**：用户可能误卸载重要插件
   - **建议**：添加确认提示或软删除机制

3. **配置损坏**
   - 直接编辑 TOML 配置文件可能损坏格式
   - **风险**：其他配置条目可能受影响
   - **建议**：使用 TOML 编辑库（如 `toml_edit`）进行安全编辑

4. **遥测失败**
   - 遥测上报失败不应影响卸载流程
   - **风险**：当前测试验证遥测，但生产代码可能忽略失败
   - **建议**：确保遥测失败不阻塞卸载

### 边界情况

1. **正在使用的插件**
   - 测试未验证插件正在使用时的情况
   - **风险**：卸载正在使用的插件可能导致运行时错误
   - **建议**：添加使用检查，拒绝卸载活动插件

2. **依赖关系**
   - 插件可能有依赖关系（如技能依赖其他技能）
   - **风险**：卸载被依赖的插件可能导致功能损坏
   - **建议**：实现依赖检查和警告

3. **部分失败**
   - 缓存删除成功但配置清理失败
   - **风险**：系统处于不一致状态
   - **建议**：实现事务性卸载（回滚机制）

4. **并发卸载**
   - 测试为单线程
   - **风险**：并发卸载同一插件可能导致竞态条件
   - **建议**：添加并发控制（如文件锁）

### 改进建议

1. **软删除**
   - 实现"移动到回收站"而非立即删除
   - 支持撤销卸载操作

2. **卸载预览**
   - 提供卸载前预览（将删除的文件、依赖影响）
   - 帮助用户做出明智决策

3. **批量卸载**
   - 支持一次卸载多个插件
   - 提高效率

4. **卸载原因收集**
   - 可选收集用户卸载原因
   - 帮助改进插件质量

5. **清理优化**
   - 定期清理孤立的插件数据
   - 释放磁盘空间

6. **审计日志**
   - 记录所有卸载操作
   - 支持故障排查

7. **远程同步增强**
   - 支持离线队列，网络恢复后自动同步
   - 处理冲突（本地与远程状态不一致）
