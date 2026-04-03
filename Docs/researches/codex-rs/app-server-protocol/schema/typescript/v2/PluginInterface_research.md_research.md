# PluginInterface 研究文档

## 场景与职责

`PluginInterface` 是 Codex 插件系统的用户界面描述类型，定义了插件在 UI 中展示所需的全部元数据。它包含插件的显示名称、描述、品牌信息、图标、截图等，用于在插件市场、设置页面和 Composer 中呈现插件。

该类型是插件发现、展示和用户体验的核心数据结构，将技术性的插件配置转化为用户友好的界面呈现。

## 功能点目的

### 核心功能
1. **品牌展示**：提供插件的显示名称、开发者信息、网站链接
2. **内容描述**：通过短描述、长描述和分类帮助用户理解插件功能
3. **视觉呈现**：支持品牌色、图标、Logo 和截图的展示
4. **快速入门**：提供默认提示词（starter prompts）帮助用户快速上手

### 使用场景
- 插件市场列表展示
- 插件详情页面
- Composer 中的插件选择器
- 设置页面的已安装插件列表

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3310-3330)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInterface {
    pub display_name: Option<String>,           // 显示名称
    pub short_description: Option<String>,      // 短描述（列表展示）
    pub long_description: Option<String>,       // 长描述（详情页）
    pub developer_name: Option<String>,         // 开发者名称
    pub category: Option<String>,               // 分类
    pub capabilities: Vec<String>,              // 功能标签
    pub website_url: Option<String>,            // 官网链接
    pub privacy_policy_url: Option<String>,     // 隐私政策
    pub terms_of_service_url: Option<String>,  // 服务条款
    /// Starter prompts for the plugin. Capped at 3 entries with a maximum of
    /// 128 characters per entry.
    pub default_prompt: Option<Vec<String>>,   // 默认提示词（最多3条，每条128字符）
    pub brand_color: Option<String>,            // 品牌色（HEX格式）
    pub composer_icon: Option<AbsolutePathBuf>, // Composer 图标路径
    pub logo: Option<AbsolutePathBuf>,          // Logo 路径
    pub screenshots: Vec<AbsolutePathBuf>,      // 截图路径列表
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/PluginInterface.ts
import type { AbsolutePathBuf } from "../AbsolutePathBuf";

export type PluginInterface = { 
    displayName: string | null, 
    shortDescription: string | null, 
    longDescription: string | null, 
    developerName: string | null, 
    category: string | null, 
    capabilities: Array<string>, 
    websiteUrl: string | null, 
    privacyPolicyUrl: string | null, 
    termsOfServiceUrl: string | null, 
    /**
     * Starter prompts for the plugin. Capped at 3 entries with a maximum of
     * 128 characters per entry.
     */
    defaultPrompt: Array<string> | null, 
    brandColor: string | null, 
    composerIcon: AbsolutePathBuf | null, 
    logo: AbsolutePathBuf | null, 
    screenshots: Array<AbsolutePathBuf>, 
};
```

### 在插件摘要中的使用

```rust
// PluginSummary (lines 3272-3284)
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,
    pub installed: bool,
    pub enabled: bool,
    pub install_policy: PluginInstallPolicy,
    pub auth_policy: PluginAuthPolicy,
    pub interface: Option<PluginInterface>,  // 可选的界面信息
}
```

### 在插件详情中的使用

```rust
// PluginDetail (lines 3286-3298)
pub struct PluginDetail {
    pub marketplace_name: String,
    pub marketplace_path: AbsolutePathBuf,
    pub summary: PluginSummary,              // 包含 interface
    pub description: Option<String>,
    pub skills: Vec<SkillSummary>,
    pub apps: Vec<AppSummary>,
    pub mcp_servers: Vec<String>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3310-3330：`PluginInterface` 结构体

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginSummary` | v2.rs | 3272-3284 | 插件摘要（包含 interface） |
| `PluginDetail` | v2.rs | 3286-3298 | 插件详情 |
| `PluginMarketplaceEntry` | v2.rs | 3233-3238 | 市场条目 |
| `MarketplaceInterface` | v2.rs | 3240-3245 | 市场界面（简化版） |
| `SkillInterface` | v2.rs | 3166-3182 | Skill 界面（类似结构） |

### 字段约束说明
| 字段 | 约束 | 说明 |
|------|------|------|
| `default_prompt` | 最多3条，每条128字符 | 防止提示词过长影响 UI |
| `screenshots` | 无明确上限 | 建议控制在 5-10 张 |
| `brand_color` | HEX 格式 | 如 `"#FF5733"` |
| `capabilities` | 字符串数组 | 如 `["git", "github", "file-system"]` |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginInterface.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/AbsolutePathBuf.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：驼峰命名序列化
4. **codex_utils_absolute_path**：`AbsolutePathBuf` 类型

### 数据来源
`PluginInterface` 的数据通常来自插件的 `codex.json` 或 `plugin.json` 配置文件：

```json
{
  "name": "github-plugin",
  "interface": {
    "display_name": "GitHub",
    "short_description": "GitHub integration for Codex",
    "long_description": "Full-featured GitHub integration...",
    "developer_name": "OpenAI",
    "category": "developer-tools",
    "capabilities": ["git", "github", "pull-requests"],
    "website_url": "https://github.com",
    "privacy_policy_url": "https://github.com/privacy",
    "terms_of_service_url": "https://github.com/terms",
    "default_prompt": ["Review my PR", "Check open issues"],
    "brand_color": "#24292e",
    "composer_icon": "./assets/icon.svg",
    "logo": "./assets/logo.svg",
    "screenshots": ["./assets/screenshot1.png"]
  }
}
```

### 与 SkillInterface 的关系
```rust
// SkillInterface 是简化版（lines 3166-3182）
pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,  // 注意：这里是 String 不是 Vec
}
```

## 风险、边界与改进建议

### 潜在风险
1. **路径有效性**：`composer_icon`、`logo`、`screenshots` 中的路径可能在运行时无效
2. **URL 格式**：`website_url` 等 URL 字段没有格式验证
3. **颜色格式**：`brand_color` 没有验证是否为有效 HEX 格式
4. **空列表**：`capabilities` 和 `screenshots` 为空时的 UI 处理

### 边界情况
1. **所有字段为 None**：最小化配置时的默认 UI 行为
2. **过长描述**：`long_description` 过长时的截断策略
3. **图片加载失败**：图标/截图文件不存在时的降级方案

### 改进建议
1. **添加验证**：
   ```rust
   impl PluginInterface {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if let Some(color) = &self.brand_color {
               if !is_valid_hex_color(color) {
                   return Err(ValidationError::InvalidBrandColor);
               }
           }
           if let Some(prompts) = &self.default_prompt {
               if prompts.len() > 3 {
                   return Err(ValidationError::TooManyDefaultPrompts);
               }
               for prompt in prompts {
                   if prompt.len() > 128 {
                       return Err(ValidationError::DefaultPromptTooLong);
                   }
               }
           }
           Ok(())
       }
   }
   ```

2. **添加本地化支持**：
   ```rust
   pub struct PluginInterface {
       // ... 现有字段
       pub display_name_i18n: HashMap<String, String>,  // 多语言显示名称
   }
   ```

3. **添加版本信息**：
   ```rust
   pub struct PluginInterface {
       // ... 现有字段
       pub version: Option<String>,
       pub min_codex_version: Option<String>,
   }
   ```

4. **支持远程资源**：
   ```rust
   pub enum IconSource {
       Local(AbsolutePathBuf),
       Remote(String),  // URL
   }
   ```

### 测试覆盖
建议测试场景：
1. 完整配置序列化/反序列化
2. 最小配置（所有可选字段为 None）
3. default_prompt 长度约束验证
4. 无效颜色格式处理
5. 特殊字符在描述中的转义

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为插件系统的核心类型，变更影响广泛
- 建议通过添加可选字段来扩展，避免破坏性变更
