# PluginInterface 研究文档

## 1. 场景与职责

`PluginInterface` 是插件的元数据描述结构，包含了插件的展示信息、品牌信息、功能描述和视觉资源。它用于插件市场中向用户展示插件的详细信息。

**使用场景：**
- 插件市场列表展示：显示插件卡片的基本信息
- 插件详情页面：展示完整的插件介绍
- 搜索和分类：根据类别、功能筛选插件
- 品牌展示：显示插件的logo、图标和品牌色

## 2. 功能点目的

该类型的核心目的是：

1. **提供插件展示信息**：名称、描述、开发者等基础信息
2. **支持品牌定制**：品牌色、图标、logo等视觉元素
3. **描述功能范围**：能力列表、分类、使用提示
4. **合规信息展示**：隐私政策、服务条款链接
5. **用户体验优化**：默认提示词、截图展示

## 3. 具体技术实现

### TypeScript 定义
```typescript
import type { AbsolutePathBuf } from "../common/AbsolutePathBuf.js";

export type PluginInterface = {
  displayName: string | null;
  shortDescription: string | null;
  longDescription: string | null;
  developerName: string | null;
  category: string | null;
  capabilities: Array<string>;
  websiteUrl: string | null;
  privacyPolicyUrl: string | null;
  termsOfServiceUrl: string | null;
  defaultPrompt: Array<string> | null;
  brandColor: string | null;
  composerIcon: AbsolutePathBuf | null;
  logo: AbsolutePathBuf | null;
  screenshots: Array<AbsolutePathBuf>;
};
```

### Rust 源实现
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `displayName` | `string \| null` | 插件的显示名称 |
| `shortDescription` | `string \| null` | 简短描述，用于列表展示 |
| `longDescription` | `string \| null` | 详细描述，用于详情页 |
| `developerName` | `string \| null` | 开发者名称 |
| `category` | `string \| null` | 插件分类 |
| `capabilities` | `string[]` | 插件能力列表 |
| `websiteUrl` | `string \| null` | 官方网站URL |
| `privacyPolicyUrl` | `string \| null` | 隐私政策链接 |
| `termsOfServiceUrl` | `string \| null` | 服务条款链接 |
| `defaultPrompt` | `string[] \| null` | 默认提示词，最多3条，每条最多128字符 |
| `brandColor` | `string \| null` | 品牌色（十六进制） |
| `composerIcon` | `AbsolutePathBuf \| null` | 编辑器图标路径 |
| `logo` | `AbsolutePathBuf \| null` | Logo图片路径 |
| `screenshots` | `AbsolutePathBuf[]` | 截图路径列表 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3313-3330

**使用位置：**
- `PluginSummary.interface`：插件摘要中的可选接口信息（行3283）
- 插件详情和列表的响应数据

## 5. 依赖与外部交互

**导入依赖：**
- `AbsolutePathBuf`：绝对路径类型，用于图标、logo、截图等资源路径

**使用场景：**
- 插件市场UI渲染
- 插件搜索和筛选

## 6. 风险、边界与改进建议

### 潜在风险
1. **资源路径失效**：图标、logo、截图的路径可能指向不存在的文件
2. **URL安全风险**：websiteUrl、privacyPolicyUrl等外部链接需要安全验证
3. **内容长度限制**：defaultPrompt有长度限制，但其他字段没有明确限制

### 边界情况
- 所有字段都可能为null（除了数组字段为空数组）
- 截图数组可能为空
- 路径可能是相对路径或绝对路径，需要正确处理

### 改进建议
1. **添加资源验证**：在服务器端验证所有路径指向的文件存在
2. **添加URL白名单**：限制可使用的域名，防止恶意链接
3. **添加内容长度限制**：为描述字段添加合理的长度限制
4. **支持多语言**：添加国际化字段支持多语言展示
5. **添加版本信息**：包含插件版本号，便于管理和更新
