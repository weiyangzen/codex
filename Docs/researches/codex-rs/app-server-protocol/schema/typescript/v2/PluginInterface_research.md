# PluginInterface 研究文档

## 场景与职责

`PluginInterface` 是插件的用户界面元数据类型，定义了插件在 Codex 客户端中展示所需的全部界面信息。它包含了插件的显示名称、描述、图标、品牌颜色、截图等视觉元素，以及能力声明和合规链接。

该类型是 Codex 插件市场展示和插件详情页面的核心数据结构，决定了用户如何感知和交互插件。

## 功能点目的

1. **品牌展示**: 提供插件的显示名称、Logo、品牌颜色等视觉标识
2. **信息描述**: 通过短描述、长描述向用户介绍插件功能
3. **能力声明**: 明确声明插件提供的能力列表
4. **合规信息**: 提供隐私政策、服务条款等合规链接
5. **入门引导**: 提供默认提示词 (defaultPrompt) 帮助用户快速上手
6. **视觉展示**: 通过截图展示插件的实际使用效果

## 具体技术实现

### 数据结构

```typescript
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
  defaultPrompt: Array<string> | null, 
  brandColor: string | null, 
  composerIcon: AbsolutePathBuf | null, 
  logo: AbsolutePathBuf | null, 
  screenshots: Array<AbsolutePathBuf>, 
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `displayName` | `string \| null` | 插件的显示名称，用于 UI 展示 |
| `shortDescription` | `string \| null` | 简短描述（通常一句话） |
| `longDescription` | `string \| null` | 详细描述，支持多段落 |
| `developerName` | `string \| null` | 开发者或组织名称 |
| `category` | `string \| null` | 插件分类，如 "Productivity", "Developer Tools" |
| `capabilities` | `Array<string>` | 插件提供的能力列表 |
| `websiteUrl` | `string \| null` | 官方网站链接 |
| `privacyPolicyUrl` | `string \| null` | 隐私政策链接 |
| `termsOfServiceUrl` | `string \| null` | 服务条款链接 |
| `defaultPrompt` | `Array<string> \| null` | 入门提示词，最多 3 条，每条最多 128 字符 |
| `brandColor` | `string \| null` | 品牌颜色（十六进制格式） |
| `composerIcon` | `AbsolutePathBuf \| null` | Composer 中使用的图标路径 |
| `logo` | `AbsolutePathBuf \| null` | 插件 Logo 路径 |
| `screenshots` | `Array<AbsolutePathBuf>` | 截图路径列表 |

### 约束规则

1. **defaultPrompt 限制**:
   - 最多 3 个条目
   - 每个条目最多 128 个字符

2. **路径类型**:
   - `AbsolutePathBuf` 表示绝对路径，确保资源可定位

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 从 Rust 源代码生成。

对应的 Rust 定义：
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
    pub default_prompt: Option<Vec<String>>,
    pub brand_color: Option<String>,
    pub composer_icon: Option<AbsolutePathBuf>,
    pub logo: Option<AbsolutePathBuf>,
    pub screenshots: Vec<AbsolutePathBuf>,
}
```

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginInterface.ts`
- **依赖类型**: `AbsolutePathBuf.ts` (来自 `../AbsolutePathBuf`)
- **索引**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行号约 3313-3330)
- **PluginSummary 使用**: 同一文件 (行号约 3275-3284)
- **PluginDetail 使用**: 同一文件 (行号约 3289-3297)

### 核心使用位置

1. **App Server 消息处理**
   - 文件: `codex-rs/app-server/src/codex_message_processor.rs`
   - 导入: `use codex_app_server_protocol::PluginInterface;`

2. **插件市场核心**
   - 文件: `codex-rs/core/src/plugins/marketplace.rs`
   - 功能: 插件界面元数据加载

3. **插件管理器**
   - 文件: `codex-rs/core/src/plugins/manager.rs`
   - 功能: 插件详情读取

### 相关类型

- `PluginSummary`: 包含 `interface: Option<PluginInterface>`
- `PluginDetail`: 包含 `summary: PluginSummary`，间接包含 interface

## 依赖与外部交互

### 数据来源

`PluginInterface` 的数据通常来自插件的 `marketplace.json` 文件：

```json
{
  "name": "my-plugin",
  "interface": {
    "display_name": "My Plugin",
    "short_description": "A helpful plugin for Codex",
    "capabilities": ["file_search", "code_analysis"],
    "default_prompt": ["Analyze this code", "Find bugs"],
    "brand_color": "#FF5733"
  },
  "plugins": [...]
}
```

### UI 展示流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      PluginInterface 使用流程                            │
└─────────────────────────────────────────────────────────────────────────┘

  marketplace.json
       │
       ▼
  ┌─────────────┐
  │  Plugin     │
  │  Interface  │
  │  数据解析    │
  └──────┬──────┘
         │
         ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │                        客户端展示                                │
  ├─────────────────────────────────────────────────────────────────┤
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
  │  │ 插件列表      │  │ 插件详情页    │  │ Composer 提示        │  │
  │  │              │  │              │  │                     │  │
  │  │ - logo       │  │ - displayName│  │ - defaultPrompt     │  │
  │  │ - displayName│  │ - screenshots│  │ - composerIcon      │  │
  │  │ - shortDesc  │  │ - longDesc   │  │                     │  │
  │  │ - category   │  │ - capabilities│ │                     │  │
  │  │              │  │ - URLs       │  │                     │  │
  │  └──────────────┘  └──────────────┘  └──────────────────────┘  │
  └─────────────────────────────────────────────────────────────────┘
```

### 与 PluginSummary 的关系

```rust
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,
    pub installed: bool,
    pub enabled: bool,
    pub install_policy: PluginInstallPolicy,
    pub auth_policy: PluginAuthPolicy,
    pub interface: Option<PluginInterface>,  // <-- 关联
}
```

## 风险、边界与改进建议

### 已知风险

1. **资源路径失效**: `logo`, `composer_icon`, `screenshots` 指向的路径可能不存在
   - 风险: UI 展示异常
   - 缓解: 客户端需要处理资源加载失败

2. **URL 安全风险**: `websiteUrl`, `privacyPolicyUrl` 等可能指向恶意网站
   - 风险: 钓鱼攻击
   - 缓解: 客户端应警告用户外部链接

3. **颜色格式错误**: `brandColor` 可能不是有效的十六进制颜色
   - 风险: UI 渲染异常
   - 缓解: 客户端应验证或使用默认值

4. **描述长度**: `longDescription` 可能非常长
   - 风险: UI 布局问题
   - 缓解: 客户端应实现折叠或滚动

### 边界情况

1. **所有字段为 null**: 插件未提供任何界面信息
   - 客户端应使用插件名称作为回退

2. **空 capabilities**: 插件声明了 interface 但没有能力
   - 可能表示插件仅提供配置

3. **过多 screenshots**: 截图数量过多可能影响性能
   - 建议客户端实现懒加载

4. **defaultPrompt 超限**: 超过 3 条或超过 128 字符
   - 服务器应验证并截断

### 改进建议

1. **添加版本信息**:
   ```typescript
   version?: string;
   minCodexVersion?: string;
   ```

2. **支持多语言**:
   ```typescript
   i18n?: {
     [locale: string]: {
       displayName?: string;
       shortDescription?: string;
       longDescription?: string;
     }
   };
   ```

3. **添加评分信息**:
   ```typescript
   rating?: {
     average: number;
     count: number;
   };
   ```

4. **支持视频演示**:
   ```typescript
   demoVideo?: {
     url: string;
     thumbnail: AbsolutePathBuf;
   };
   ```

5. **添加标签**:
   ```typescript
   tags?: string[];  // 用于搜索和分类
   ```

6. **支持深色模式**:
   ```typescript
   logoDark?: AbsolutePathBuf;  // 深色模式 Logo
   brandColorDark?: string;     // 深色模式品牌色
   ```

### 验证建议

1. **URL 验证**: 验证所有 URL 格式正确
2. **颜色验证**: 验证 brandColor 是有效的 CSS 颜色
3. **路径验证**: 验证所有路径存在且可读
4. **长度验证**: 验证 defaultPrompt 符合限制

### UI/UX 建议

1. **默认占位图**: 当 logo 缺失时显示默认图标
2. **截图画廊**: 支持缩放和轮播的截图展示
3. **能力标签**: 将 capabilities 渲染为可视化标签
4. **快速开始**: 突出展示 defaultPrompt，支持一键使用
5. **合规提示**: 在显眼位置展示隐私政策和服务条款链接
