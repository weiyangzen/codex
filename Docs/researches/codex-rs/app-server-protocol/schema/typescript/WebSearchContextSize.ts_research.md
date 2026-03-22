# WebSearchContextSize.ts 研究文档

## 1. 场景与职责

WebSearchContextSize 类型在 Codex 系统中用于控制网络搜索工具返回的上下文大小。它在以下场景中发挥作用：

- **搜索结果量控制**: 控制搜索返回的信息量
- **令牌管理**: 管理搜索上下文占用的令牌数量
- **成本优化**: 平衡搜索结果丰富度和成本
- **响应质量**: 根据查询复杂度调整上下文大小

## 2. 功能点目的

WebSearchContextSize 提供三个上下文大小级别：

1. **Low**: 最小上下文，适合简单查询，节省令牌
2. **Medium**: 中等上下文，适合一般查询（默认值）
3. **High**: 最大上下文，适合复杂查询，提供最全面的信息

这个类型用于配置网络搜索工具的行为，影响搜索结果的处理和呈现方式。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type WebSearchContextSize = "low" | "medium" | "high";
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` (lines 132-139):

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum WebSearchContextSize {
    Low,
    Medium,
    High,
}
```

### 关键特性

1. **小写序列化**: 使用 `"low"`、`"medium"`、`"high"` 小写字符串
2. **Copy trait**: 实现 Copy，可以低成本传递
3. **Display trait**: 支持格式化为字符串
4. **无默认值**: 与 Verbosity 不同，没有指定默认值

### 在配置中的使用

在 `WebSearchToolConfig` 中 (config_types.rs lines 161-167):

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Default, PartialEq, Eq, JsonSchema, TS)]
#[schemars(deny_unknown_fields)]
pub struct WebSearchToolConfig {
    pub context_size: Option<WebSearchContextSize>,
    pub allowed_domains: Option<Vec<String>>,
    pub location: Option<WebSearchLocation>,
}
```

在 `WebSearchConfig` 中 (config_types.rs lines 214-220):

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Default, PartialEq, Eq, JsonSchema, TS)]
#[schemars(deny_unknown_fields)]
pub struct WebSearchConfig {
    pub filters: Option<WebSearchFilters>,
    pub user_location: Option<WebSearchUserLocation>,
    pub search_context_size: Option<WebSearchContextSize>,
}
```

### 配置转换

`WebSearchToolConfig` 可以转换为 `WebSearchConfig` (lines 234-246):

```rust
impl From<WebSearchToolConfig> for WebSearchConfig {
    fn from(config: WebSearchToolConfig) -> Self {
        Self {
            filters: config.allowed_domains.map(...),
            user_location: config.location.map(Into::into),
            search_context_size: config.context_size,
        }
    }
}
```

### 配置合并

`WebSearchToolConfig` 支持配置合并 (lines 169-185):

```rust
impl WebSearchToolConfig {
    pub fn merge(&self, other: &Self) -> Self {
        Self {
            context_size: other.context_size.or(self.context_size),
            allowed_domains: other.allowed_domains.clone().or_else(|| self.allowed_domains.clone()),
            location: match (&self.location, &other.location) {
                (Some(location), Some(other_location)) => Some(location.merge(other_location)),
                (Some(location), None) => Some(location.clone()),
                (None, Some(other_location)) => Some(other_location.clone()),
                (None, None) => None,
            },
        }
    }
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | WebSearchContextSize 定义 (lines 132-139) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | WebSearchToolConfig 定义 (lines 161-185) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | WebSearchConfig 定义 (lines 214-246) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/WebSearchContextSize.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **strum**: Display trait 派生

### 外部交互

- **搜索服务**: context_size 传递给后端搜索服务
- **OpenAI API**: 可能映射到 OpenAI 搜索 API 的参数
- **用户配置**: 用户可以在配置中设置默认 context_size
- **工具配置**: 在 WebSearchToolConfig 中作为工具参数

## 6. 风险、边界与改进建议

### 风险

1. **令牌消耗**: High 上下文可能消耗大量令牌，增加成本
2. **信息过载**: 过多的上下文可能稀释重要信息
3. **响应延迟**: 更大的上下文可能导致更长的响应时间

### 边界情况

1. **未指定**: 当 context_size 为 None 时的默认行为
2. **与过滤器冲突**: context_size 与 allowed_domains 过滤器的交互
3. **动态调整**: 会话中动态调整 context_size 的效果

### 改进建议

1. **智能推荐**: 基于查询复杂度自动推荐 context_size
2. **令牌估算**: 显示不同 context_size 的预估令牌消耗
3. **渐进加载**: 支持先加载 Low，根据需要扩展到 High
4. **上下文压缩**: 对大上下文进行智能压缩
5. **相关性排序**: 在 High 模式下优先显示最相关的结果
6. **用户反馈**: 基于用户反馈优化 context_size 选择
7. **查询分类**: 基于查询类型自动选择最优 context_size
