# session.rs 研究文档

## 场景与职责

`session.rs` 定义了 `SessionState` 结构体，负责管理 Codex 会话级别的持久化状态。与 `SessionServices`（管理服务依赖）不同，`SessionState` 专注于存储会话运行时的可变状态数据。

核心职责：
1. **会话配置管理**：存储 `SessionConfiguration`，包含模型、策略等配置
2. **对话历史管理**：通过 `ContextManager` 管理对话历史记录
3. **速率限制跟踪**：跟踪 API 调用的速率限制状态
4. **权限管理**：记录已授予的权限配置文件
5. **连接器选择**：管理 MCP 连接器的激活状态
6. **环境变量**：存储依赖环境变量
7. **启动预热**：管理会话启动时的预热句柄

## 功能点目的

### 1. 会话配置 (session_configuration)
存储会话级别的配置，包括：
- 模型提供商和协作模式
- 沙箱策略和网络策略
- 用户和开发者指令
- 动态工具配置

### 2. 对话历史 (history)
通过 `ContextManager` 管理：
- 对话历史记录（`ResponseItem` 列表）
- Token 使用信息
- 参考上下文项（用于差异计算）

### 3. 速率限制 (latest_rate_limits)
跟踪 API 调用的速率限制：
- 主/次限制窗口
- 信用额度信息
- 计划类型

### 4. 权限管理 (granted_permissions)
记录用户已授予的权限配置文件，用于：
- 文件系统访问权限
- 网络访问权限
- macOS Seatbelt 扩展

### 5. 连接器选择 (active_connector_selection)
管理 MCP 服务器的激活状态：
- 添加/合并连接器 ID
- 清除选择
- 获取当前选择

### 6. 环境变量 (dependency_env)
存储从技能依赖中收集的环境变量。

### 7. 启动预热 (startup_prewarm)
管理会话启动时的模型预热：
- 存储预热句柄
- 在首次对话时消费

### 8. 上一轮设置 (previous_turn_settings)
记录上一轮常规用户对话的设置，用于：
- 轮次间的模型/实时处理
- 恢复或压缩后的完整上下文重新注入

## 具体技术实现

### 数据结构

```rust
pub(crate) struct SessionState {
    pub(crate) session_configuration: SessionConfiguration,
    pub(crate) history: ContextManager,
    pub(crate) latest_rate_limits: Option<RateLimitSnapshot>,
    pub(crate) server_reasoning_included: bool,
    pub(crate) dependency_env: HashMap<String, String>,
    pub(crate) mcp_dependency_prompted: HashSet<String>,
    previous_turn_settings: Option<PreviousTurnSettings>,
    pub(crate) startup_prewarm: Option<SessionStartupPrewarmHandle>,
    pub(crate) active_connector_selection: HashSet<String>,
    pub(crate) pending_session_start_source: Option<codex_hooks::SessionStartSource>,
    granted_permissions: Option<PermissionProfile>,
}
```

### 初始化

```rust
impl SessionState {
    pub(crate) fn new(session_configuration: SessionConfiguration) -> Self {
        let history = ContextManager::new();
        Self {
            session_configuration,
            history,
            latest_rate_limits: None,
            server_reasoning_included: false,
            dependency_env: HashMap::new(),
            mcp_dependency_prompted: HashSet::new(),
            previous_turn_settings: None,
            startup_prewarm: None,
            active_connector_selection: HashSet::new(),
            pending_session_start_source: None,
            granted_permissions: None,
        }
    }
}
```

### 关键方法

#### 历史管理

```rust
// 记录历史项
pub(crate) fn record_items<I>(&mut self, items: I, policy: TruncationPolicy)
where
    I: IntoIterator,
    I::Item: std::ops::Deref<Target = ResponseItem>,
{
    self.history.record_items(items, policy);
}

// 替换历史
pub(crate) fn replace_history(
    &mut self,
    items: Vec<ResponseItem>,
    reference_context_item: Option<TurnContextItem>,
) {
    self.history.replace(items);
    self.history.set_reference_context_item(reference_context_item);
}
```

#### Token 和速率限制

```rust
// 从使用量更新 Token 信息
pub(crate) fn update_token_info_from_usage(
    &mut self,
    usage: &TokenUsage,
    model_context_window: Option<i64>,
) {
    self.history.update_token_info(usage, model_context_window);
}

// 设置速率限制
pub(crate) fn set_rate_limits(&mut self, snapshot: RateLimitSnapshot) {
    self.latest_rate_limits = Some(merge_rate_limit_fields(
        self.latest_rate_limits.as_ref(),
        snapshot,
    ));
}
```

#### 连接器选择

```rust
// 合并连接器选择（自动去重）
pub(crate) fn merge_connector_selection<I>(&mut self, connector_ids: I) -> HashSet<String>
where
    I: IntoIterator<Item = String>,
{
    self.active_connector_selection.extend(connector_ids);
    self.active_connector_selection.clone()
}

// 清除连接器选择
pub(crate) fn clear_connector_selection(&mut self) {
    self.active_connector_selection.clear();
}
```

#### 权限管理

```rust
// 记录授予的权限
pub(crate) fn record_granted_permissions(&mut self, permissions: PermissionProfile) {
    self.granted_permissions =
        merge_permission_profiles(self.granted_permissions.as_ref(), Some(&permissions));
}
```

### 速率限制合并逻辑

```rust
fn merge_rate_limit_fields(
    previous: Option<&RateLimitSnapshot>,
    mut snapshot: RateLimitSnapshot,
) -> RateLimitSnapshot {
    // 默认 limit_id 为 "codex"
    if snapshot.limit_id.is_none() {
        snapshot.limit_id = Some("codex".to_string());
    }
    // 保留之前的信用额度信息
    if snapshot.credits.is_none() {
        snapshot.credits = previous.and_then(|prior| prior.credits.clone());
    }
    // 保留之前的计划类型
    if snapshot.plan_type.is_none() {
        snapshot.plan_type = previous.and_then(|prior| prior.plan_type);
    }
    snapshot
}
```

## 关键代码路径与文件引用

### 创建位置

`SessionState` 在 `codex.rs` 的 `Session::new()` 方法中创建：

```rust
// codex.rs
let state = SessionState::new(session_configuration);
```

### 主要使用位置

1. **Token 更新** (`codex.rs`):
   - 在 API 响应后调用 `update_token_info_from_usage`
   - 更新 `latest_rate_limits`

2. **历史记录** (`codex.rs`, `tasks/*.rs`):
   - 调用 `record_items` 记录对话历史
   - 调用 `replace_history` 在压缩后替换历史

3. **权限管理** (`codex.rs`):
   - 调用 `record_granted_permissions` 记录用户授权的权限

4. **连接器管理** (`codex.rs`, `connectors.rs`):
   - 调用 `merge_connector_selection` 添加连接器
   - 调用 `clear_connector_selection` 清除选择

5. **预热管理** (`session_startup_prewarm.rs`):
   - 调用 `set_session_startup_prewarm` 设置预热句柄
   - 调用 `take_session_startup_prewarm` 消费预热句柄

## 依赖与外部交互

### 导入依赖

```rust
use codex_protocol::models::PermissionProfile;
use codex_protocol::models::ResponseItem;
use std::collections::HashMap;
use std::collections::HashSet;

use crate::codex::PreviousTurnSettings;
use crate::codex::SessionConfiguration;
use crate::context_manager::ContextManager;
use crate::protocol::RateLimitSnapshot;
use crate::protocol::TokenUsage;
use crate::protocol::TokenUsageInfo;
use crate::sandboxing::merge_permission_profiles;
use crate::session_startup_prewarm::SessionStartupPrewarmHandle;
use crate::truncate::TruncationPolicy;
use codex_protocol::protocol::TurnContextItem;
```

### 外部 crate 依赖

- `codex_protocol`: 协议类型（`PermissionProfile`, `ResponseItem`, `RateLimitSnapshot` 等）

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `codex` | `PreviousTurnSettings`, `SessionConfiguration` |
| `context_manager` | `ContextManager` - 历史管理 |
| `protocol` | `RateLimitSnapshot`, `TokenUsage`, `TokenUsageInfo` |
| `sandboxing` | `merge_permission_profiles` - 权限合并 |
| `session_startup_prewarm` | `SessionStartupPrewarmHandle` |
| `truncate` | `TruncationPolicy` - 截断策略 |

## 风险、边界与改进建议

### 风险点

1. **状态膨胀**：`history` 可能随对话增长而占用大量内存
2. **并发访问**：`SessionState` 被 `Mutex` 保护，长时间持有锁可能导致阻塞
3. **权限累积**：`granted_permissions` 会持续合并，可能超出预期范围

### 边界条件

1. **速率限制合并**：当新快照缺少 `credits` 或 `plan_type` 时，会保留旧值
2. **连接器去重**：使用 `HashSet` 自动去重，但顺序不保证
3. **预热超时**：`startup_prewarm` 有过期时间，可能在使用前已失效

### 改进建议

1. **历史压缩策略**：
   - 实现更积极的历史压缩策略
   - 添加历史大小限制和自动清理

2. **权限审计**：
   - 添加权限审计日志
   - 实现权限撤销机制

3. **状态持久化**：
   - 考虑将关键状态持久化到 `state_db`
   - 支持会话恢复

4. **内存优化**：
   - 对 `history` 实现分页或懒加载
   - 使用更紧凑的数据结构存储历史

5. **测试覆盖**：
   - 添加边界条件测试（`session_tests.rs` 已有部分测试）
   - 测试权限合并逻辑
   - 测试速率限制合并逻辑

### 测试分析

`session_tests.rs` 中已包含以下测试：
- `merge_connector_selection_deduplicates_entries`: 连接器去重
- `clear_connector_selection_removes_entries`: 清除连接器
- `set_rate_limits_defaults_limit_id_to_codex_when_missing`: 默认 limit_id
- `set_rate_limits_defaults_to_codex_when_limit_id_missing_after_other_bucket`: 切换 bucket
- `set_rate_limits_carries_credits_and_plan_type_from_codex_to_codex_other`: 信用额度继承

建议补充：
- 权限合并测试
- 历史替换测试
- Token 信息更新测试
