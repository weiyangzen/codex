# WebSearchMode.ts 研究文档

## 1. 场景与职责

`WebSearchMode` 是一个枚举类型，用于控制网络搜索功能的工作模式。它在以下场景中发挥关键作用：

- **功能开关控制**：允许用户完全禁用网络搜索功能
- **搜索策略选择**：在缓存优先和实时搜索之间进行选择
- **性能与新鲜度权衡**：根据场景需求平衡搜索结果的获取速度和新鲜度
- **配置管理**：作为用户配置的一部分，可在 `config.toml` 中持久化

该类型是 Codex 网络搜索功能的核心控制开关，影响模型何时以及如何使用网络搜索工具。

## 2. 功能点目的

`WebSearchMode` 定义了三种网络搜索工作模式：

### 模式说明

| 模式值 | 名称 | 用途 |
|--------|------|------|
| `"disabled"` | 禁用模式 | 完全关闭网络搜索功能，模型不会触发任何网络搜索调用 |
| `"cached"` | 缓存模式 | 优先使用缓存的搜索结果，减少 API 调用，提高响应速度（默认模式） |
| `"live"` | 实时模式 | 始终执行实时网络搜索，获取最新信息，但可能增加延迟和成本 |

### 设计意图

- **灵活性**: 允许用户根据使用场景选择最合适的搜索策略
- **成本控制**: 通过缓存模式减少不必要的 API 调用
- **隐私保护**: 禁用模式确保不会向搜索引擎发送任何查询
- **时效性**: 实时模式确保获取最新的网络信息

## 3. 具体技术实现

### TypeScript 定义

```typescript
export type WebSearchMode = "disabled" | "cached" | "live";
```

### Rust 源定义

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` (第 125-130 行)：

```rust
#[derive(
    Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS, Default,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum WebSearchMode {
    Disabled,
    #[default]
    Cached,
    Live,
}
```

### 关键特性

1. **默认模式**: `Cached` 是默认模式，在不明确配置时启用缓存搜索
2. **序列化格式**: 使用小写字符串（`"disabled"`, `"cached"`, `"live"`）进行序列化
3. **派生 trait**: 实现了 `Display`、`JsonSchema`、`TS` 等 trait，支持多种使用场景

### 在配置中的使用

在 `Config` 结构体中（`core/src/config/mod.rs` 第 534 行）：

```rust
/// Explicit or feature-derived web search mode.
pub web_search_mode: Constrained<WebSearchMode>,
```

在 `WebSearchConfig` 中（`protocol/src/config_types.rs` 第 214-220 行）：

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Default, PartialEq, Eq, JsonSchema, TS)]
#[schemars(deny_unknown_fields)]
pub struct WebSearchConfig {
    pub filters: Option<WebSearchFilters>,
    pub user_location: Option<WebSearchUserLocation>,
    pub search_context_size: Option<WebSearchContextSize>,
}
```

### App Server Protocol v2 集成

在 `app-server-protocol/src/protocol/v2.rs` 中，通过 `ProfileV2` 暴露给客户端：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ProfileV2 {
    // ...
    pub web_search: Option<WebSearchMode>,
    // ...
}
```

以及在 `Config` 结构体中：

```rust
pub web_search: Option<WebSearchMode>,
```

## 4. 关键代码路径与文件引用

### 生成来源

- **TypeScript 文件**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/WebSearchMode.ts`
- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源 Rust 文件**: `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs`

### 相关文件引用

| 文件路径 | 用途 |
|----------|------|
| `protocol/src/config_types.rs` | 原始定义，包含枚举值和默认实现 |
| `core/src/config/mod.rs` | 在 `Config` 结构体中使用，作为 `web_search_mode` 字段类型 |
| `app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，在 `ProfileV2` 和 `Config` 中使用 |
| `app-server-protocol/src/protocol/v2.rs` | `ConfigRequirements` 中定义 `allowed_web_search_modes` 约束 |

### 配置层级

```
用户配置 (config.toml)
  └── web_search = "cached" | "live" | "disabled"
        └── 解析为 WebSearchMode
              └── 存储在 Config.web_search_mode
                    └── 影响模型是否/如何使用网络搜索
```

## 5. 依赖与外部交互

### 依赖关系

- **ts-rs**: TypeScript 类型生成
- **serde**: 序列化/反序列化（使用 `rename_all = "lowercase"`）
- **strum**: 提供 `Display` 和 `EnumIter` 等宏支持
- **schemars**: JSON Schema 生成

### 外部交互

1. **配置系统**: 从 TOML 配置文件解析，支持 `web_search` 配置键
2. **API 协议**: 通过 app-server v2 协议暴露给客户端
3. **约束系统**: 支持 `Constrained<WebSearchMode>`，允许需求层限制可用模式

### 约束配置示例

在 `ConfigRequirements` 中（`app-server-protocol/src/protocol/v2.rs` 第 820-832 行）：

```rust
pub struct ConfigRequirements {
    // ...
    pub allowed_web_search_modes: Option<Vec<WebSearchMode>>,
    // ...
}
```

这允许管理员/需求配置限制用户可选择的搜索模式。

## 6. 风险、边界与改进建议

### 潜在风险

1. **默认模式变更影响**: 如果默认模式从 `Cached` 改为其他值，可能影响现有用户的预期行为
2. **模式名称混淆**: `"cached"` 和 `"live"` 的具体行为差异可能不够直观
3. **配置漂移**: 不同层级配置（用户/项目/系统）可能设置冲突的模式

### 边界情况

1. **无效值处理**: 当配置文件包含无效的模式值时，serde 会返回反序列化错误
2. **大小写敏感**: 配置必须使用小写（`"cached"` 而非 `"Cached"`）
3. **空值处理**: 在 API 中作为 `Option<WebSearchMode>` 使用，需要处理 `None` 情况

### 改进建议

1. **文档增强**: 添加更详细的模式行为说明，特别是缓存策略的具体实现细节
2. **配置验证**: 在配置加载时提供更友好的错误消息，当模式值无效时
3. **模式别名**: 考虑添加更易理解的别名（如 `"off"` 作为 `"disabled"` 的别名）
4. **细粒度控制**: 考虑添加更多模式选项，如 `"auto"` 让系统根据查询类型自动选择
5. **遥测集成**: 记录模式使用情况，帮助理解用户偏好

### 向后兼容性考虑

- 当前使用 `lowercase` 序列化策略，与 OpenAI API 风格保持一致
- 默认值为 `Cached`，确保新用户获得平衡的性能和新鲜度
- 作为配置选项，变更需要谨慎考虑对现有用户的影响
