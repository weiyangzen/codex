# AppMetadata 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppMetadata` 是 Codex App-Server Protocol v2 中用于描述应用程序详细元数据的类型。它提供了比 `AppBranding` 更丰富的应用信息，主要用于：

- **应用详情页面**：展示应用的完整信息，包括截图、版本、分类等
- **应用商店展示**：支持应用发现、浏览和比较
- **版本管理**：跟踪应用版本、版本说明
- **审核状态展示**：显示应用的审核状态（如 marketplace 审核）
- **SEO 优化**：提供搜索引擎优化的描述信息
- **分类浏览**：支持按类别和子类别筛选应用

### 1.2 核心职责

- 提供应用的市场展示信息（截图、SEO 描述）
- 支持应用分类体系（categories、subCategories）
- 管理应用版本信息（version、versionId、versionNotes）
- 标识应用来源类型（firstPartyType、firstPartyRequiresInstall）
- 控制应用在 Composer 中的显示行为（showInComposerWhenUnlinked）
- 提供审核状态信息（review）

### 1.3 与 AppBranding 的区别

| 维度 | AppBranding | AppMetadata |
|------|-------------|-------------|
| 关注点 | 品牌信任与合规 | 市场展示与发现 |
| 关键字段 | 开发者、隐私政策 | 截图、分类、版本 |
| 使用场景 | 用户信任建立 | 应用浏览与选择 |

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `review` | `AppReview \| null` | 应用审核状态 |
| `categories` | `Array<string> \| null` | 主要分类标签 |
| `subCategories` | `Array<string> \| null` | 子分类标签 |
| `seoDescription` | `string \| null` | SEO 优化描述 |
| `screenshots` | `Array<AppScreenshot> \| null` | 应用截图列表 |
| `developer` | `string \| null` | 开发者名称（可与 branding.developer 不同） |
| `version` | `string \| null` | 应用版本号（如 "1.2.3"） |
| `versionId` | `string \| null` | 版本唯一标识符 |
| `versionNotes` | `string \| null` | 版本更新说明 |
| `firstPartyType` | `string \| null` | 第一方应用类型标识 |
| `firstPartyRequiresInstall` | `boolean \| null` | 第一方应用是否需要安装 |
| `showInComposerWhenUnlinked` | `boolean \| null` | 未关联时是否在 Composer 中显示 |

### 2.2 设计意图

1. **市场发现**：通过 `categories`、`subCategories`、`seoDescription` 支持应用分类和搜索
2. **视觉展示**：`screenshots` 提供应用预览，帮助用户了解功能
3. **版本管理**：完整的版本信息支持版本控制和更新提示
4. **第一方应用支持**：`firstParty*` 字段支持 OpenAI 官方应用的特殊处理
5. **UX 控制**：`showInComposerWhenUnlinked` 控制未配置应用的可见性

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppMetadata = {
  review: AppReview | null,
  categories: Array<string> | null,
  subCategories: Array<string> | null,
  seoDescription: string | null,
  screenshots: Array<AppScreenshot> | null,
  developer: string | null,
  version: string | null,
  versionId: string | null,
  versionNotes: string | null,
  firstPartyType: string | null,
  firstPartyRequiresInstall: boolean | null,
  showInComposerWhenUnlinked: boolean | null,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AppMetadata {
    pub review: Option<AppReview>,
    pub categories: Option<Vec<String>>,
    pub sub_categories: Option<Vec<String>>,
    pub seo_description: Option<String>,
    pub screenshots: Option<Vec<AppScreenshot>>,
    pub developer: Option<String>,
    pub version: Option<String>,
    pub version_id: Option<String>,
    pub version_notes: Option<String>,
    pub first_party_type: Option<String>,
    pub first_party_requires_install: Option<bool>,
    pub show_in_composer_when_unlinked: Option<bool>,
}
```

### 3.3 序列化规则

- 使用 `#[serde(rename_all = "camelCase")]` 转换字段名
- 所有字段均为 `Option<T>`，在 TypeScript 中映射为 `T | null`
- 布尔字段使用 `Option<bool>` 而非默认 false，以区分"未设置"和"设置为 false"

### 3.4 嵌套类型

```rust
// AppReview - 审核状态
pub struct AppReview {
    pub status: String,
}

// AppScreenshot - 截图信息
pub struct AppScreenshot {
    pub url: Option<String>,
    pub file_id: Option<String>,
    pub user_prompt: String,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 1979-1995 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppMetadata.ts` | 生成的 TypeScript 类型 |

### 4.2 依赖类型

```
AppMetadata
  ├── review: AppReview
  └── screenshots: AppScreenshot[]
```

### 4.3 引用关系

| 类型 | 关系 |
|------|------|
| `AppInfo` | 包含 `appMetadata: AppMetadata \| null` |

### 4.4 相关文件

| 文件路径 | 说明 |
|----------|------|
| `AppReview.ts` | 审核状态类型 |
| `AppScreenshot.ts` | 截图信息类型 |
| `AppInfo.ts` | 引用 AppMetadata |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

```typescript
import type { AppReview } from "./AppReview";
import type { AppScreenshot } from "./AppScreenshot";
```

### 5.2 外部协议依赖

- **serde**：序列化/反序列化
- **schemars**：JSON Schema 生成
- **ts-rs**：TypeScript 类型生成

### 5.3 客户端使用示例

```typescript
import type { AppMetadata } from "./AppMetadata";
import type { AppInfo } from "./AppInfo";

// 提取应用分类信息
function getAppCategories(app: AppInfo): string[] {
  return app.appMetadata?.categories ?? [];
}

// 获取应用截图 URL
function getScreenshotUrls(app: AppInfo): string[] {
  return app.appMetadata?.screenshots
    ?.map(s => s.url)
    .filter((url): url is string => url !== null) ?? [];
}

// 检查应用是否需要安装
function requiresInstall(app: AppInfo): boolean {
  return app.appMetadata?.firstPartyRequiresInstall ?? false;
}

// 获取版本信息
function getVersionInfo(app: AppInfo): { version: string; notes: string } | null {
  const metadata = app.appMetadata;
  if (!metadata?.version) return null;
  
  return {
    version: metadata.version,
    notes: metadata.versionNotes ?? 'No release notes',
  };
}

// 检查审核状态
function isApproved(app: AppInfo): boolean {
  return app.appMetadata?.review?.status === 'approved';
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **字段过多** | 11 个字段，部分可能为空 | 客户端使用可选链操作符处理 |
| **类型宽松** | `firstPartyType` 为 string 而非枚举 | 文档说明有效值，客户端做好未知值处理 |
| **URL 验证缺失** | screenshots[].url 无格式验证 | 客户端使用前验证 |
| **版本格式不统一** | version 字段无格式约束 | 建议使用 SemVer，但不强制 |

### 6.2 边界情况

1. **所有字段为 null**：应用可能没有任何元数据，客户端应优雅处理
2. **空数组 vs null**：`categories`、`screenshots` 可能为空数组或 null
3. **审核状态值**：`review.status` 的具体值未枚举，可能为任意字符串

### 6.3 改进建议

1. **枚举化审核状态**：
   ```typescript
   type ReviewStatus = 'pending' | 'approved' | 'rejected' | 'under_review';
   ```

2. **枚举化第一方类型**：
   ```typescript
   type FirstPartyType = 'builtin' | 'premium' | 'enterprise' | null;
   ```

3. **版本格式约束**：
   ```typescript
   type SemVer = `${number}.${number}.${number}`;
   ```

4. **截图添加尺寸信息**：
   ```typescript
   interface AppScreenshot {
     url: string;
     fileId: string | null;
     userPrompt: string;
     width?: number;
     height?: number;
   }
   ```

5. **分类标准化**：
   ```typescript
   type AppCategory = 
     | 'productivity'
     | 'developer_tools'
     | 'communication'
     | 'data_analysis'
     | string;  // 允许自定义
   ```

### 6.4 SEO 最佳实践

`seoDescription` 字段的使用建议：
- 长度控制在 150-160 字符以内
- 包含应用的核心功能和价值主张
- 避免关键词堆砌
- 支持多语言（未来可考虑添加 `seoDescriptionLocalized`）

### 6.5 版本管理建议

```typescript
// 版本比较工具
function compareVersions(v1: string, v2: string): number {
  const parts1 = v1.split('.').map(Number);
  const parts2 = v2.split('.').map(Number);
  
  for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
    const p1 = parts1[i] ?? 0;
    const p2 = parts2[i] ?? 0;
    if (p1 !== p2) return p1 - p2;
  }
  return 0;
}
```
