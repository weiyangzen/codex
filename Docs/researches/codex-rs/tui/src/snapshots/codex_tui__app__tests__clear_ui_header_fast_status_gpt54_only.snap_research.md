# Clear UI Header with Fast Status 研究文档

## 场景与职责

该组件负责在 Codex TUI 的 `/clear` 命令执行后，显示包含 Fast 状态标识的会话头部信息。与普通头部不同，此版本专门用于展示支持 "Fast" 服务层级的模型（如 GPT-5.4）的状态信息，让用户清楚了解当前会话使用的是快速推理模式。

## 功能点目的

`clear_ui_header_lines_with_version` 函数在 Fast 状态显示方面的核心目的：

1. **服务层级可视化**：明确标识当前模型是否启用了 Fast 推理模式
2. **模型能力展示**：同时显示模型名称、推理努力级别和 Fast 状态
3. **性能预期管理**：帮助用户理解当前会话的响应速度预期
4. **配置状态确认**：让用户确认 `/model` 命令后的实际生效配置

## 具体技术实现

### Fast 状态判断逻辑

```rust
fn should_show_fast_status(&self, model: &str, service_tier: Option<ServiceTier>) -> bool {
    // 基于模型和服务层级判断是否显示 Fast 标识
    matches!(service_tier, Some(ServiceTier::Fast))
        || self.models_manager.is_fast_eligible(model)
}
```

### 头部渲染格式

```
╭────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                       │
│                                                    │
│ model:     gpt-5.4 xhigh   fast   /model to change │
│ directory: /tmp/project                            │
╰────────────────────────────────────────────────────╯
```

### 关键特性

1. **模型名称**：`gpt-5.4` - 当前使用的模型
2. **推理努力级别**：`xhigh` - 扩展高推理努力
3. **Fast 标识**：`fast` - 表示使用快速服务层级
4. **修改提示**：`/model to change` - 提示用户可以修改模型

### 数据流

```
ChatWidget.should_show_fast_status()
    ├── current_model() -> "gpt-5.4"
    ├── current_service_tier() -> Some(Fast)
    └── models_manager.is_fast_eligible("gpt-5.4") -> true

SessionHeaderHistoryCell::new(
    model: "gpt-5.4",
    effort: XHigh,
    show_fast: true,
    cwd: "/tmp/project",
    version: "x.x.x",
)
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `clear_ui_header_lines_with_version` 方法（第 1183-1199 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `clear_ui_header_lines` 方法（第 1201-1203 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/chatwidget.rs` | `should_show_fast_status` 方法实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/history_cell.rs` | `SessionHeaderHistoryCell` 结构体和渲染逻辑 |

### 相关配置项
```rust
// codex_protocol::protocol::ServiceTier
pub enum ServiceTier {
    Auto,
    Default,
    Fast,
}

// codex_protocol::openai_models::ReasoningEffort
pub enum ReasoningEffort {
    Low,
    Medium,
    High,
    XHigh,  // 扩展高
}
```

## 依赖与外部交互

### 依赖模块
- `codex_core::models_manager::ModelsManager` - 模型管理能力检测
- `codex_protocol::protocol::ServiceTier` - 服务层级枚举
- `codex_protocol::openai_models::ReasoningEffort` - 推理努力级别

### 配置信息来源
| 信息项 | 来源方法 |
|-------|---------|
| 模型名称 | `chat_widget.current_model()` |
| 推理努力级别 | `chat_widget.current_reasoning_effort()` |
| Fast 资格 | `models_manager.is_fast_eligible(model)` |
| 服务层级 | `chat_widget.current_service_tier()` |

### 模型管理器交互
```rust
impl ModelsManager {
    /// 检查模型是否支持 Fast 服务层级
    pub fn is_fast_eligible(&self, model: &str) -> bool {
        // 基于模型配置和能力判断
        self.get_model_preset(model)
            .map(|preset| preset.supports_fast_tier)
            .unwrap_or(false)
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **Fast 状态变化**：模型切换时 Fast 状态可能变化，需要及时更新头部
2. **服务层级降级**：Fast 层级不可用时需要回退显示
3. **模型不支持 Fast**：旧模型可能不支持 Fast 服务层级

### 潜在风险

1. **状态竞争**：`should_show_fast_status` 和实际请求可能不一致
2. **缓存过期**：模型能力缓存可能导致 Fast 状态显示错误
3. **网络依赖**：某些 Fast 状态检查可能需要网络请求

### 改进建议

1. **动态 Fast 指示器**：
   ```rust
   // 建议添加动态指示器显示当前请求是否实际使用 Fast
   enum FastStatusIndicator {
       Enabled,      // 已启用且可用
       EnabledButBusy, // 已启用但当前繁忙
       Disabled,     // 未启用
       Unavailable,  // 当前不可用
   }
   ```

2. **Fast 状态历史**：
   ```rust
   // 建议记录 Fast 状态变化历史
   struct FastStatusHistory {
       entries: Vec<(Timestamp, FastStatus)>,
       current: FastStatus,
   }
   ```

3. **性能指标显示**：
   ```rust
   // 建议显示实际的响应时间指标
   struct PerformanceMetrics {
       avg_response_time: Duration,
       fast_tier_usage_rate: f64,
       last_10_requests: Vec<Duration>,
   }
   ```

4. **Fast 状态提示**：
   - 当 Fast 不可用时显示原因（如 "Fast 队列繁忙"）
   - 提供切换到标准模式的建议

5. **配置持久化**：
   ```rust
   // 建议将 Fast 偏好持久化到配置
   struct UserPreferences {
       prefer_fast_when_available: bool,
       auto_fallback_to_default: bool,
   }
   ```

### 相关测试
- `clear_ui_header_fast_status_gpt54_only` - 验证 GPT-5.4 Fast 状态显示
- 测试覆盖不同模型、不同服务层级的组合场景
- 测试 Fast 状态动态变化的更新机制
