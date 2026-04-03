# PluginInterface.ts 调研文档

## 场景与职责

`PluginInterface` 是 Codex 应用服务器协议中用于描述插件用户界面和元数据的类型。该类型主要用于以下场景：

1. **插件市场展示**：在插件市场中展示插件的详细信息
2. **插件详情页面**：提供丰富的插件介绍、截图、品牌信息
3. **Composer 集成**：在聊天界面中显示插件图标、品牌色等视觉元素
4. **用户引导**：通过默认提示词（defaultPrompt）帮助用户快速上手插件
5. **合规展示**：展示隐私政策、服务条款等法律信息

该类型在 `PluginSummary` 中作为可选字段存在，用于提供插件的完整界面定义。

## 功能点目的

`PluginInterface` 包含以下核心字段：

| 字段 | 类型 | 用途 |
|------|------|------|
| `displayName` | `string \| null` | 插件的显示名称（人类可读） |
| `shortDescription` | `string \| null` | 简短描述（用于列表展示） |
| `longDescription` | `string \| null` | 详细描述（用于详情页） |
| `developerName` | `string \| null` | 开发者名称 |
| `category` | `string \| null` | 插件分类 |
| `capabilities` | `string[]` | 插件能力标签 |
| `websiteUrl` | `string \| null` | 官方网站链接 |
| `privacyPolicyUrl` | `string \| null` | 隐私政策链接 |
| `termsOfServiceUrl` | `string \| null` | 服务条款链接 |
| `defaultPrompt` | `string[] \| null` | 默认提示词（最多3条，每条最多128字符） |
| `brandColor` | `string \| null` | 品牌色（十六进制） |
| `composerIcon` | `AbsolutePathBuf \| null` | Composer 界面图标路径 |
| `logo` | `AbsolutePathBuf \| null` | 插件 Logo 路径 |
| `screenshots` | `AbsolutePathBuf[]` | 截图路径列表 |

### 设计目的

1. **品牌一致性**：允许插件定义自己的品牌色和视觉元素
2. **用户引导**：通过默认提示词降低用户使用门槛
3. **合规要求**：提供必要的法律和隐私信息展示
4. **市场分类**：支持按分类、能力标签筛选插件
5. **视觉展示**：通过截图和图标提升插件吸引力

## 具体技术实现

### TypeScript 定义

```typescript
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

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub long_description: Option<String>,
    pub developer_name: Option<String>,
    pub category: Option<String>,
    pub capabilities: Vec<String>,
    pub website_url: Option<String>,
    pub privacy_policy_url: Option<String>,
    pub terms_of_service_url: Option<String>,
    /// Starter prompts for the plugin. Capped at 3 entries with a maximum of
    /// 128 characters per entry.
    pub default_prompt: Option<Vec<String>>,
    pub brand_color: Option<String>,
    pub composer_icon: Option<AbsolutePathBuf>,
    pub logo: Option<AbsolutePathBuf>,
    pub screenshots: Vec<AbsolutePathBuf>,
}
```

### 路径解析

- 所有路径（`composerIcon`, `logo`, `screenshots`）都是相对于插件根目录的绝对路径
- 在 `plugin.json` 中使用相对路径定义，服务器解析为绝对路径返回

### 插件清单示例

```json
{
  "name": "demo-plugin",
  "interface": {
    "displayName": "Plugin Display Name",
    "shortDescription": "Short description for subtitle",
    "longDescription": "Long description for details page",
    "developerName": "OpenAI",
    "category": "Productivity",
    "capabilities": ["Interactive", "Write"],
    "websiteURL": "https://openai.com/",
    "privacyPolicyURL": "https://openai.com/policies/privacy/",
    "termsOfServiceURL": "https://openai.com/policies/terms/",
    "defaultPrompt": [
      "Draft the reply",
      "Find my next action"
    ],
    "brandColor": "#3B82F6",
    "composerIcon": "./assets/icon.png",
    "logo": "./assets/logo.png",
    "screenshots": ["./assets/screenshot1.png", "./assets/screenshot2.png"]
  }
}
```

## 关键代码路径与文件引用

### 定义位置

- **Rust 源码**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3313-3330 行)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginInterface.ts`

### 引用位置

1. **PluginSummary** (`v2.rs` 第 3275-3284 行)
   ```rust
   pub struct PluginSummary {
       // ...
       pub interface: Option<PluginInterface>,
   }
   ```

2. **PluginDetail** (`v2.rs` 第 3289-3297 行)
   ```rust
   pub struct PluginDetail {
       // ...
       pub summary: PluginSummary, // 包含 interface
       // ...
   }
   ```

### 测试覆盖

- **文件**: `codex-rs/app-server/tests/suite/v2/plugin_list.rs`
- **关键测试用例**:
  - `plugin_list_returns_plugin_interface_with_absolute_asset_paths`：验证路径解析
  - `plugin_list_accepts_legacy_string_default_prompt`：验证向后兼容

- **文件**: `codex-rs/app-server/tests/suite/v2/plugin_read.rs`
- **关键测试用例**:
  - `plugin_read_returns_plugin_details_with_bundle_contents`：验证完整 interface 解析

### 路径解析逻辑

```rust
// 从 plugin.json 中的相对路径解析为绝对路径
let plugin_root = marketplace_path.parent().join(plugin_source_path);
let interface = PluginInterface {
    composer_icon: plugin_json.interface.composer_icon
        .map(|p| plugin_root.join(p)),
    logo: plugin_json.interface.logo
        .map(|p| plugin_root.join(p)),
    screenshots: plugin_json.interface.screenshots
        .into_iter()
        .map(|p| plugin_root.join(p))
        .collect(),
    // ...
};
```

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `AbsolutePathBuf` | 资源文件的绝对路径表示 |
| `serde` | JSON 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |

### 外部交互

1. **插件清单文件** (`.codex-plugin/plugin.json`)
   - 读取 `interface` 字段定义
   - 支持 `defaultPrompt` 为字符串（向后兼容）或字符串数组

2. **文件系统**
   - 验证资源文件（图标、Logo、截图）是否存在
   - 将相对路径解析为绝对路径

3. **市场配置** (`marketplace.json`)
   - 可以覆盖插件的 `category` 字段
   - 市场级别的分类优先级高于插件自身定义

## 风险、边界与改进建议

### 潜在风险

1. **资源文件缺失**：引用的图标、截图文件可能不存在或损坏
2. **路径遍历攻击**：需要验证相对路径不超出插件根目录
3. **内容安全**：外部 URL（websiteUrl 等）需要验证安全性
4. **尺寸限制**：截图文件可能过大，影响传输性能

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| `defaultPrompt` 为单个字符串 | 自动转换为单元素数组（向后兼容） |
| 资源文件不存在 | 路径仍返回，客户端需要处理 404 |
| 超过3个 defaultPrompt | 服务器可能截断或报错 |
| 超过128字符的提示词 | 服务器可能截断 |
| 无效的 brandColor | 原样返回，客户端验证 |

### 改进建议

1. **资源预检**
   ```rust
   pub struct PluginInterface {
       // ...
       pub resource_validation: ResourceValidationStatus, // 资源验证状态
   }
   
   pub enum ResourceValidationStatus {
       AllValid,
       SomeMissing(Vec<String>), // 缺失的资源路径
       ValidationFailed(String), // 验证错误信息
   }
   ```

2. **增加资源元数据**
   ```rust
   pub struct PluginAsset {
       pub path: AbsolutePathBuf,
       pub size_bytes: u64,
       pub mime_type: String,
       pub width: Option<u32>, // 图片宽度
       pub height: Option<u32>, // 图片高度
   }
   
   pub struct PluginInterface {
       // ...
       pub composer_icon: Option<PluginAsset>,
       pub logo: Option<PluginAsset>,
       pub screenshots: Vec<PluginAsset>,
   }
   ```

3. **多语言支持**
   ```rust
   pub struct LocalizedContent {
       pub locale: String,
       pub display_name: Option<String>,
       pub short_description: Option<String>,
       pub long_description: Option<String>,
   }
   
   pub struct PluginInterface {
       // ...
       pub default_locale: String,
       pub localized: Vec<LocalizedContent>,
   }
   ```

4. **内容安全策略**
   - 对 `websiteUrl`, `privacyPolicyUrl`, `termsOfServiceUrl` 进行域名白名单验证
   - 对 `brandColor` 进行格式验证（必须是有效的十六进制颜色）

5. **动态资源支持**
   ```rust
   pub struct PluginInterface {
       // ...
       pub dynamic_assets: Vec<DynamicAsset>, // 支持动态生成的资源
   }
   
   pub struct DynamicAsset {
       pub id: String,
       pub url: String, // 可以是相对路径或外部 URL
       pub asset_type: DynamicAssetType,
   }
   ```

6. **版本化 Interface**
   - 支持不同版本的界面定义
   - 允许插件根据客户端能力返回不同的 interface 格式
