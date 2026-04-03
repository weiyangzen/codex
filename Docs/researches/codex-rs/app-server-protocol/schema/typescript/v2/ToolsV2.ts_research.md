# ToolsV2 类型研究报告

## 场景与职责

`ToolsV2` 是一个配置类型，用于定义 Codex v2 协议中可用的工具集及其配置。它封装了网络搜索和图片查看等工具的配置选项，是 `Config` 和 `ProfileV2` 的重要组成部分。

**核心使用场景：**

1. **工具集配置**：在配置文件中定义哪些工具可用以及如何配置
2. **配置文件读写**：通过 `config/read` 和 `config/write` RPC 方法管理工具配置
3. **运行时工具启用/禁用**：根据配置动态启用或禁用特定工具
4. **网络搜索定制**：配置搜索的上下文大小、允许域、地理位置等
5. **图片查看控制**：启用或禁用图片查看功能

**典型使用场景：**
```toml
# config.toml 示例
[tools]
web_search = { context_size = "medium", allowed_domains = ["docs.rs", "crates.io"] }
view_image = true
```

## 功能点目的

该类型的设计目的包括：

1. **工具集抽象**：统一封装 v2 协议支持的所有工具
2. **可选配置**：所有工具都是可选的，支持渐进式启用
3. **类型安全**：强类型确保配置的正确性
4. **序列化友好**：支持 TOML/JSON 序列化，便于配置文件处理

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `web_search` | 网络搜索工具配置，`null` 表示禁用 |
| `view_image` | 图片查看功能开关，`null` 表示使用默认值 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
import type { WebSearchToolConfig } from "../WebSearchToolConfig";

export type ToolsV2 = { 
  web_search: WebSearchToolConfig | null, 
  view_image: boolean | null, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ToolsV2 {
    pub web_search: Option<WebSearchToolConfig>,
    pub view_image: Option<bool>,
}
```

### 命名风格说明

注意 Rust 定义使用 `snake_case` 序列化（`web_search`、`view_image`），这与配置文件的 TOML 键风格一致：
```rust
#[serde(rename_all = "snake_case")]
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `web_search` | `Option<WebSearchToolConfig>` / `WebSearchToolConfig \| null` | 网络搜索工具配置，`None`/`null` 表示禁用 |
| `view_image` | `Option<bool>` / `boolean \| null` | 图片查看功能开关，`None`/`null` 表示默认行为 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `WebSearchToolConfig` | 子配置 | 网络搜索工具的详细配置 |
| `WebSearchContextSize` | 子配置字段 | 搜索上下文大小（low/medium/high） |
| `WebSearchLocation` | 子配置字段 | 搜索地理位置配置 |
| `Config` | 父容器 | 包含 `tools: Option<ToolsV2>` |
| `ProfileV2` | 父容器 | 包含 `tools: Option<ToolsV2>` |

### 配置合并逻辑

```rust
// 来自 config_types.rs 的 WebSearchToolConfig::merge
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

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 536-542) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolsV2.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/v2/ConfigReadResponse.json` | 在配置响应 schema 中引用 |
| `codex-rs/protocol/src/config_types.rs` (lines 161-185) | `WebSearchToolConfig` 定义 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 作为 `Config` 和 `ProfileV2` 的字段 |
| `codex-rs/app-server/tests/suite/v2/config_rpc.rs` | 配置 RPC 测试 |
| `codex-rs/core/src/config/mod.rs` | 核心配置处理 |
| `codex-rs/protocol/src/config_types.rs` | 配置类型定义 |

### 配置层级

```
Config
  └── tools: Option<ToolsV2>
        ├── web_search: Option<WebSearchToolConfig>
        │     ├── context_size: Option<WebSearchContextSize>
        │     ├── allowed_domains: Option<Vec<String>>
        │     └── location: Option<WebSearchLocation>
        │           ├── country: Option<String>
        │           ├── region: Option<String>
        │           ├── city: Option<String>
        │           └── timezone: Option<String>
        └── view_image: Option<bool>
```

## 依赖与外部交互

### 内部依赖

```
ToolsV2
  ├── WebSearchToolConfig
  │     ├── WebSearchContextSize
  │     └── WebSearchLocation
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| TOML 配置文件 | 反序列化 | 从 config.toml 读取配置 |
| Config RPC | JSON 序列化 | 通过 `config/read` 和 `config/write` 管理 |
| 工具执行器 | 配置读取 | 根据配置启用/禁用工具 |

### 序列化示例

**TOML 配置：**
```toml
[tools]
web_search = { context_size = "medium" }
view_image = true
```

**JSON 表示：**
```json
{
  "web_search": {
    "context_size": "medium",
    "allowed_domains": null,
    "location": null
  },
  "view_image": true
}
```

**禁用网络搜索：**
```toml
[tools]
web_search = null
view_image = false
```

```json
{
  "web_search": null,
  "view_image": false
}
```

## 风险、边界与改进建议

### 潜在风险

1. **配置冲突**：不同层级（全局、项目、profile）的配置可能冲突
2. **工具版本兼容性**：配置格式变更可能导致旧配置不兼容
3. **空配置语义**：`web_search: null` 和 `web_search: {}` 的语义可能混淆
4. **地理位置隐私**：`WebSearchLocation` 可能暴露用户位置信息

### 边界情况

| 场景 | 当前行为 | 说明 |
|------|----------|------|
| 所有字段为 null | 允许 | 表示使用所有默认设置 |
| 空 allowed_domains | 允许 | 表示允许所有域 |
| 无效 context_size | 反序列化失败 | 应在配置验证时捕获 |
| 部分 location 字段 | 允许 | 使用提供的字段，其余默认 |

### 改进建议

1. **添加验证方法**：
   ```rust
   impl ToolsV2 {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if let Some(web_search) = &self.web_search {
               web_search.validate()?;
           }
           Ok(())
       }
   }
   
   impl WebSearchToolConfig {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证 allowed_domains 格式
           if let Some(domains) = &self.allowed_domains {
               for domain in domains {
                   if !is_valid_domain(domain) {
                       return Err(ValidationError::InvalidDomain(domain.clone()));
                   }
               }
           }
           Ok(())
       }
   }
   ```

2. **添加更多工具配置**：
   ```rust
   pub struct ToolsV2 {
       pub web_search: Option<WebSearchToolConfig>,
       pub view_image: Option<bool>,
       // 新增工具
       pub code_interpreter: Option<CodeInterpreterConfig>,
       pub file_system: Option<FileSystemConfig>,
       pub shell: Option<ShellConfig>,
   }
   ```

3. **添加工具版本控制**：
   ```rust
   pub struct ToolsV2 {
       pub version: String, // 配置格式版本
       pub web_search: Option<WebSearchToolConfig>,
       pub view_image: Option<bool>,
   }
   ```

4. **添加工具依赖关系**：
   ```rust
   pub struct ToolsV2 {
       pub web_search: Option<WebSearchToolConfig>,
       pub view_image: Option<bool>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub dependencies: Option<Vec<ToolDependency>>,
   }
   
   pub struct ToolDependency {
       pub tool: String,
       pub requires: Vec<String>,
   }
   ```

5. **添加工具启用条件**：
   ```rust
   pub struct WebSearchToolConfig {
       pub context_size: Option<WebSearchContextSize>,
       pub allowed_domains: Option<Vec<String>>,
       pub location: Option<WebSearchLocation>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub enabled_when: Option<Condition>, // 如 "model == 'gpt-4'"
   }
   ```

6. **改进默认值处理**：
   ```rust
   impl Default for ToolsV2 {
       fn default() -> Self {
           Self {
               web_search: Some(WebSearchToolConfig::default()),
               view_image: Some(true),
           }
       }
   }
   ```

7. **添加配置文档生成**：
   ```rust
   #[derive(Documentable)]
   pub struct ToolsV2 {
       /// Web search tool configuration. Set to null to disable.
       #[doc_example = r#"{ context_size = "medium" }"#]
       pub web_search: Option<WebSearchToolConfig>,
       /// Enable image viewing capability.
       #[doc_default = "true"]
       pub view_image: Option<bool>,
   }
   ```

### 配置继承与合并

建议明确配置继承规则：
1. 系统默认值
2. 全局配置 (~/.codex/config.toml)
3. 项目配置 (./.codex/config.toml)
4. Profile 配置
5. 运行时覆盖

每一层都可以覆盖上一层的配置。

### 向后兼容性

考虑到未来可能添加新工具，建议：
- 使用 `#[serde(default)]` 处理新字段
- 版本化配置格式
- 提供配置迁移工具
