# WebSearchToolConfig.ts 研究文档

## 1. 场景与职责

`WebSearchToolConfig` 是一个复合配置类型，用于精细控制网络搜索工具的行为。它在以下场景中发挥作用：

- **工具级配置**: 作为 `ToolsV2` 的一部分，提供对网络搜索工具的具体参数配置
- **搜索上下文控制**: 允许调整搜索返回的上下文大小，平衡信息量与成本
- **域名过滤**: 支持限制搜索仅限于特定域名，提高结果相关性和安全性
- **地理位置定制**: 允许为搜索指定特定的地理位置上下文

该类型是网络搜索功能的高级配置接口，通常在用户需要覆盖默认搜索行为时使用。

## 2. 功能点目的

`WebSearchToolConfig` 提供了三个维度的搜索定制能力：

### 上下文大小控制 (`context_size`)

- **目的**: 控制搜索结果返回的详细程度
- **可选值**: `"low"` | `"medium"` | `"high"` (通过 `WebSearchContextSize` 类型)
- **影响**: 决定模型接收的搜索上下文 token 数量，直接影响成本和响应质量

### 域名白名单 (`allowed_domains`)

- **目的**: 限制搜索仅在指定域名内进行
- **格式**: 字符串数组，如 `["openai.com", "github.com"]`
- **用途**: 
  - 提高搜索结果的相关性
  - 限制搜索范围到可信来源
  - 企业环境中限制到内部文档站点

### 地理位置 (`location`)

- **目的**: 指定搜索的地理位置上下文
- **类型**: `WebSearchLocation`（包含 country, region, city, timezone）
- **用途**: 获取本地化搜索结果，如本地新闻、天气、商家信息

## 3. 具体技术实现

### TypeScript 定义

```typescript
import type { WebSearchContextSize } from "./WebSearchContextSize";
import type { WebSearchLocation } from "./WebSearchLocation";

export type WebSearchToolConfig = { 
  context_size: WebSearchContextSize | null, 
  allowed_domains: Array<string> | null, 
  location: WebSearchLocation | null, 
};
```

### Rust 源定义

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` (第 161-167 行)：

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Default, PartialEq, Eq, JsonSchema, TS)]
#[schemars(deny_unknown_fields)]
pub struct WebSearchToolConfig {
    pub context_size: Option<WebSearchContextSize>,
    pub allowed_domains: Option<Vec<String>>,
    pub location: Option<WebSearchLocation>,
}
```

### 关键方法

`WebSearchToolConfig` 实现了 `merge` 方法（第 170-184 行）：

```rust
impl WebSearchToolConfig {
    pub fn merge(&self, other: &Self) -> Self {
        Self {
            context_size: other.context_size.or(self.context_size),
            allowed_domains: other
                .allowed_domains
                .clone()
                .or_else(|| self.allowed_domains.clone()),
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

合并逻辑特点：
- `context_size` 和 `allowed_domains`: 简单的 Option 替换
- `location`: 递归调用 `WebSearchLocation::merge`，实现字段级合并

### 类型转换

`WebSearchToolConfig` 可以转换为 `WebSearchConfig`（第 234-245 行）：

```rust
impl From<WebSearchToolConfig> for WebSearchConfig {
    fn from(config: WebSearchToolConfig) -> Self {
        Self {
            filters: config
                .allowed_domains
                .map(|allowed_domains| WebSearchFilters {
                    allowed_domains: Some(allowed_domains),
                }),
            user_location: config.location.map(Into::into),
            search_context_size: config.context_size,
        }
    }
}
```

转换映射关系：
- `allowed_domains` → `WebSearchFilters`
- `location` → `WebSearchUserLocation`
- `context_size` → `search_context_size`

### App Server Protocol v2 集成

在 `app-server-protocol/src/protocol/v2.rs` 中（第 536-542 行）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ToolsV2 {
    pub web_search: Option<WebSearchToolConfig>,
    pub view_image: Option<bool>,
}
```

在 `ProfileV2` 中使用（第 604-605 行）：

```rust
pub web_search: Option<WebSearchMode>,
pub tools: Option<ToolsV2>,
```

## 4. 关键代码路径与文件引用

### 生成来源

- **TypeScript 文件**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/WebSearchToolConfig.ts`
- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源 Rust 文件**: `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs`

### 依赖类型

| 类型 | 文件 | 用途 |
|------|------|------|
| `WebSearchContextSize` | `protocol/src/config_types.rs` | 上下文大小枚举 |
| `WebSearchLocation` | `protocol/src/config_types.rs` | 地理位置配置 |
| `WebSearchConfig` | `protocol/src/config_types.rs` | 目标转换类型 |
| `WebSearchFilters` | `protocol/src/config_types.rs` | 过滤器配置 |

### 使用路径

```
ProfileV2 (v2 API)
  └── tools: Option<ToolsV2>
        └── web_search: Option<WebSearchToolConfig>
              └── 转换为 WebSearchConfig
                    └── 用于实际网络搜索请求
```

## 5. 依赖与外部交互

### 依赖关系

- **ts-rs**: TypeScript 类型生成
- **serde**: 序列化/反序列化
- **schemars**: JSON Schema 生成（使用 `deny_unknown_fields` 拒绝未知字段）

### 外部交互

1. **配置系统**: 
   - 在 TOML 配置中对应 `[tools.web_search]` 段落
   - 支持通过 CLI 覆盖

2. **API 协议**:
   - 通过 v2 协议的 `ToolsV2` 结构体暴露
   - 支持在 `ProfileV2` 中按配置文件配置

3. **核心搜索功能**:
   - 转换为 `WebSearchConfig` 后传递给搜索实现
   - 影响实际的网络搜索请求参数

### 配置示例

```toml
[tools.web_search]
context_size = "high"
allowed_domains = ["docs.python.org", "github.com"]

[tools.web_search.location]
country = "US"
region = "CA"
city = "San Francisco"
timezone = "America/Los_Angeles"
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **空配置处理**: 所有字段都是 `Option`，需要确保下游正确处理 `None` 情况
2. **域名格式**: `allowed_domains` 没有严格的格式验证，可能接受无效域名
3. **合并复杂性**: `location` 的递归合并逻辑可能导致意外的配置结果
4. **性能影响**: `high` 上下文大小可能导致大量 token 消耗

### 边界情况

1. **空域名列表**: `allowed_domains: Some([])` 与 `None` 的行为差异
2. **部分 location**: 只设置 `country` 而不设置 `city` 的有效性
3. **配置层级合并**: 用户配置与项目配置合并时的优先级
4. **无效域名**: 域名格式不正确时的错误处理

### 改进建议

1. **验证增强**:
   - 添加域名格式验证
   - 验证 `country`/`region`/`city` 组合的合理性
   - 检查 `allowed_domains` 不为空数组（如果提供）

2. **文档改进**:
   - 添加各字段的详细说明和示例
   - 说明 `context_size` 各级别的具体 token 范围
   - 提供常见使用场景的示例配置

3. **功能扩展**:
   - 考虑添加 `excluded_domains` 黑名单支持
   - 支持通配符域名（如 `*.openai.com`）
   - 添加搜索超时配置

4. **错误处理**:
   - 在配置加载时提供更具体的验证错误
   - 添加警告当日志当配置可能不合理时

### 测试覆盖

现有测试位于 `protocol/src/config_types.rs` 第 528-561 行，验证了 `merge` 方法的正确性：

```rust
#[test]
fn web_search_tool_config_merge_prefers_overlay_values() {
    // 测试复杂合并场景，包括 location 的递归合并
}
```

建议添加更多测试：
- 边界值测试（空数组、空字符串）
- 无效配置的错误处理测试
- 端到端配置加载测试
