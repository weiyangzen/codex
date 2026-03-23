# config_types.rs 研究文档

## 场景与职责

`config_types.rs` 是 Codex 协议层中**配置类型定义的核心模块**，定义了所有与用户配置、协作模式、模型设置相关的类型。这些类型贯穿 Codex 的整个架构，用于：

1. **用户配置持久化** - 序列化到配置文件（如 config.toml）
2. **API 通信** - 客户端与服务端之间的配置同步
3. **TUI 设置界面** - 渲染配置选项和当前状态
4. **模型调用参数** - 控制模型行为（reasoning effort, verbosity 等）

该模块是 Codex 最基础的类型层之一，被 `models.rs`, `protocol.rs`, `openai_models.rs` 等多个核心模块依赖。

## 功能点目的

### 1. 模型输出控制

#### `ReasoningSummary`
控制模型推理过程的摘要输出级别：
```rust
pub enum ReasoningSummary {
    Auto,      // 自动（默认）
    Concise,   // 简洁
    Detailed,  // 详细
    None,      // 禁用
}
```

参考 OpenAI 文档：https://platform.openai.com/docs/guides/reasoning

#### `Verbosity`
控制 GPT-5 模型的输出长度/详细程度：
```rust
pub enum Verbosity {
    Low,
    Medium,    // 默认
    High,
}
```

### 2. 沙箱与审批配置

#### `SandboxMode`
沙箱执行模式：
| 变体 | 说明 |
|------|------|
| `ReadOnly` | 只读访问（默认） |
| `WorkspaceWrite` | 允许工作区写入 |
| `DangerFullAccess` | 完全访问（危险） |

#### `ApprovalsReviewer`
审批请求的路由目标：
- `User` - 路由给用户（默认）
- `GuardianSubagent` - 使用 AI 辅助的风险评估子代理

#### `WindowsSandboxLevel`
Windows 平台沙箱级别：
- `Disabled` / `RestrictedToken` / `Elevated`

### 3. 个性化与交互

#### `Personality`
模型个性风格：
```rust
pub enum Personality {
    None,
    Friendly,    // 友好
    Pragmatic,   // 务实
}
```

#### `WebSearchMode` / `WebSearchContextSize`
网络搜索配置：
- 模式：`Disabled` / `Cached`（默认）/ `Live`
- 上下文大小：`Low` / `Medium` / `High`

#### `WebSearchLocation` / `WebSearchToolConfig` / `WebSearchConfig`
地理位置和搜索过滤器配置，支持合并操作：
```rust
impl WebSearchToolConfig {
    pub fn merge(&self, other: &Self) -> Self {
        // overlay 值优先的合并逻辑
    }
}
```

### 4. 服务与认证

#### `ServiceTier`
API 服务层级：`Fast` / `Flex`

#### `ForcedLoginMethod`
强制登录方式：`Chatgpt` / `Api`

#### `TrustLevel`
项目目录信任级别：`Trusted` / `Untrusted`

### 5. TUI 显示控制

#### `AltScreenMode`
控制 TUI 是否使用终端的备用屏幕缓冲区：
```rust
pub enum AltScreenMode {
    Auto,    // 自动检测（Zellij 中禁用，其他启用）
    Always,  // 总是使用
    Never,   // 从不使用（内联模式）
}
```

**背景**: Zellij 等终端多路复用器遵循 xterm 规范，在备用屏幕模式下禁用滚动回退。此设置提供了与 Zellij 兼容的解决方案。

### 6. 协作模式（核心功能）

#### `ModeKind`
协作模式类型：
```rust
pub enum ModeKind {
    Plan,       // 规划模式
    Default,    // 默认模式（默认）
    // 隐藏变体（向后兼容）
    PairProgramming,
    Execute,
}
```

**别名支持**: `code`, `pair_programming`, `execute`, `custom` 都映射到 `Default`

**TUI 可见模式**: `TUI_VISIBLE_COLLABORATION_MODES = [ModeKind::Default, ModeKind::Plan]`

#### `CollaborationMode`
完整的协作模式定义：
```rust
pub struct CollaborationMode {
    pub mode: ModeKind,
    pub settings: Settings,
}
```

**核心方法：**
- `model()` - 获取模型名称
- `reasoning_effort()` - 获取推理努力级别
- `with_updates()` - 更新模型/努力/指令设置
- `apply_mask()` - 应用部分更新掩码

#### `Settings`
协作模式的具体设置：
```rust
pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,
}
```

#### `CollaborationModeMask`
部分更新掩码，用于选择性更新协作模式字段：
```rust
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
    pub developer_instructions: Option<Option<String>>,
}
```

## 具体技术实现

### 合并逻辑实现

`WebSearchLocation::merge()` 实现了 overlay 优先的合并策略：
```rust
pub fn merge(&self, other: &Self) -> Self {
    Self {
        country: other.country.clone().or_else(|| self.country.clone()),
        region: other.region.clone().or_else(|| self.region.clone()),
        // ...
    }
}
```

### 协作模式更新逻辑

`CollaborationMode::with_updates()` 使用嵌套 `Option` 模式实现字段级更新控制：
```rust
pub fn with_updates(
    &self,
    model: Option<String>,                                    // Some = 更新
    effort: Option<Option<ReasoningEffort>>,                 // Some(Some) = 设置, Some(None) = 清除
    developer_instructions: Option<Option<String>>,          // 同上
) -> Self
```

### 掩码应用逻辑

`CollaborationMode::apply_mask()` 实现部分更新：
```rust
pub fn apply_mask(&self, mask: &CollaborationModeMask) -> Self {
    CollaborationMode {
        mode: mask.mode.unwrap_or(self.mode),
        settings: Settings {
            model: mask.model.clone().unwrap_or_else(|| settings.model.clone()),
            // ...
        },
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
```
codex-rs/protocol/src/config_types.rs
```

### 导入依赖
```rust
use crate::openai_models::ReasoningEffort;
```

### 被引用位置
- `models.rs`: `CollaborationMode`, `SandboxMode`
- `protocol.rs`: `ApprovalsReviewer`, `CollaborationMode`, `ModeKind`, `Personality`, `ReasoningSummary`, `ServiceTier`, `WindowsSandboxLevel`
- `openai_models.rs`: `Personality`, `ReasoningSummary`, `Verbosity`

### 跨 crate 使用
- `codex-core`: 配置管理、模型调用
- `codex-tui`: 设置界面、模式切换
- `codex-tui-app-server`: 配置同步

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `strum_macros` | 枚举字符串转换（Display, EnumIter） |
| `ts-rs` | TypeScript 类型绑定 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `openai_models::ReasoningEffort` | 推理努力级别定义 |

## 风险、边界与改进建议

### 当前风险

1. **复杂嵌套 Option**: `Option<Option<T>>` 模式虽然灵活，但增加了理解和使用难度
2. **向后兼容负担**: `ModeKind` 的别名和隐藏变体增加了维护复杂度
3. **合并逻辑一致性**: 多个 `merge()` 方法实现模式相似但略有不同，容易引入不一致

### 边界情况

1. **ModeKind 别名解析**: `code`, `pair_programming`, `execute`, `custom` 都映射到 `Default`
2. **空字符串处理**: `developer_instructions` 为空字符串时的处理逻辑
3. **掩码 name 字段**: `CollaborationModeMask.name` 仅用于元数据，不参与实际更新

### 测试覆盖

当前文件包含 5 个单元测试：
1. `apply_mask_can_clear_optional_fields` - 验证掩码可以清除可选字段
2. `mode_kind_deserializes_alias_values_to_default` - 验证别名解析
3. `tui_visible_collaboration_modes_match_mode_kind_visibility` - 验证 TUI 可见性
4. `web_search_location_merge_prefers_overlay_values` - 验证合并逻辑
5. `web_search_tool_config_merge_prefers_overlay_values` - 验证配置合并

### 改进建议

1. **类型安全增强**: 考虑使用专门的更新类型替代 `Option<Option<T>>`
   ```rust
   pub enum FieldUpdate<T> {
       Keep,      // None 行为
       Set(T),    // Some(T) 行为
       Clear,     // Some(None) 行为
   }
   ```

2. **Builder 模式**: 为复杂结构添加 Builder
   ```rust
   CollaborationMode::builder()
       .mode(ModeKind::Plan)
       .model("gpt-5")
       .build()
   ```

3. **文档增强**: 为复杂方法（如 `with_updates`）添加更多使用示例

4. **合并逻辑统一**: 考虑使用宏或 trait 统一合并逻辑

5. **验证逻辑**: 添加配置验证，如检查模型名称有效性

### 架构建议

1. **配置版本化**: 考虑为配置类型添加版本字段，支持配置迁移
2. **特性标志**: 将实验性功能与稳定配置分离
3. **配置热重载**: 支持运行时配置更新通知机制
