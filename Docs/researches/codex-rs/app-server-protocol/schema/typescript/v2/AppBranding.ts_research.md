# AppBranding 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppBranding` 是 Codex App-Server Protocol v2 中用于描述应用程序品牌信息的元数据类型。它主要用于以下场景：

- **应用商店展示**：在应用列表（App Store/Apps List）中展示应用的品牌信息
- **应用发现（App Discovery）**：支持用户发现和浏览可用的应用/连接器
- **应用详情页面**：展示应用的开发者信息、隐私政策、服务条款等合规信息
- **应用分类浏览**：通过 `category` 字段支持按类别筛选和展示应用

### 1.2 核心职责

- 提供应用的品牌标识信息（开发者、网站、类别）
- 支持合规性信息展示（隐私政策、服务条款链接）
- 标记应用是否可在应用商店中被发现（`isDiscoverableApp`）
- 作为 `AppInfo` 类型的子组件，构成完整的应用元数据

### 1.3 实验性状态

该类型标记为 **EXPERIMENTAL**，表明：
- API 可能会在未来版本中发生变化
- 功能仍在迭代开发中
- 客户端应做好向后不兼容变更的准备

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `category` | `string \| null` | 应用分类，如 "productivity", "developer-tools" |
| `developer` | `string \| null` | 应用开发者/组织名称 |
| `website` | `string \| null` | 应用官方网站 URL |
| `privacyPolicy` | `string \| null` | 隐私政策文档链接 |
| `termsOfService` | `string \| null` | 服务条款文档链接 |
| `isDiscoverableApp` | `boolean` | 是否可在应用商店/发现页面中展示 |

### 2.2 设计意图

1. **合规性支持**：通过 `privacyPolicy` 和 `termsOfService` 字段，确保应用可以满足 GDPR、CCPA 等隐私法规要求
2. **品牌信任**：`developer` 和 `website` 字段帮助用户验证应用来源的可信度
3. **发现控制**：`isDiscoverableApp` 允许开发者控制应用是否在公共列表中可见（例如内部应用可设为 false）

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppBranding = {
  category: string | null,
  developer: string | null,
  website: string | null,
  privacyPolicy: string | null,
  termsOfService: string | null,
  isDiscoverableApp: boolean,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - app metadata returned by app-list APIs.
pub struct AppBranding {
    pub category: Option<String>,
    pub developer: Option<String>,
    pub website: Option<String>,
    pub privacy_policy: Option<String>,
    pub terms_of_service: Option<String>,
    pub is_discoverable_app: bool,
}
```

### 3.3 序列化规则

- 使用 `#[serde(rename_all = "camelCase")]` 将 Rust 的 snake_case 字段名转换为 camelCase
- 所有可选字段使用 `Option<String>` 类型，在 TypeScript 中映射为 `string | null`
- `is_discoverable_app` 为必填布尔字段

### 3.4 生成工具

该 TypeScript 类型由 **ts-rs** 库从 Rust 代码自动生成：
- 生成命令：`just write-app-server-schema` 或 `cargo run --bin export`
- 输出路径：`codex-rs/app-server-protocol/schema/typescript/v2/AppBranding.ts`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 1948-1959 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppBranding.ts` | 生成的 TypeScript 类型 |

### 4.2 引用关系

```
AppInfo
  └── branding: AppBranding | null
```

- `AppBranding` 被 `AppInfo` 类型引用，作为其 `branding` 字段的类型
- `AppInfo` 又被 `AppsListResponse` 和 `AppListUpdatedNotification` 引用

### 4.3 相关 API

| API | 说明 |
|-----|------|
| `app/list` | 返回应用列表，包含 `AppInfo` 数组 |
| `AppListUpdatedNotification` | 应用列表变更时推送的通知 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```typescript
// AppBranding.ts 无直接导入，但逻辑上依赖：
// - AppInfo.ts（被引用于）
```

### 5.2 外部协议依赖

- **codex_protocol**：底层的应用元数据模型
- **ts-rs**：Rust 到 TypeScript 的类型生成
- **serde**：序列化/反序列化
- **schemars**：JSON Schema 生成

### 5.3 客户端使用示例

```typescript
import type { AppBranding } from "./AppBranding";
import type { AppInfo } from "./AppInfo";

// 在组件中展示应用品牌信息
function renderAppBranding(app: AppInfo) {
  if (!app.branding) return null;
  
  const { developer, website, privacyPolicy, termsOfService } = app.branding;
  
  return {
    developer,
    website: website ? new URL(website) : null,
    privacyPolicy: privacyPolicy ? new URL(privacyPolicy) : null,
    termsOfService: termsOfService ? new URL(termsOfService) : null,
  };
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **实验性 API** | 类型定义可能在未来版本中变更 | 客户端应做好版本兼容性处理 |
| **URL 验证缺失** | 字段类型为 `string` 而非 `URL`，无格式验证 | 客户端使用前需自行验证 URL 格式 |
| **null 值处理** | 所有可选字段可能为 null | 客户端必须做空值检查 |

### 6.2 边界情况

1. **空字符串 vs null**：Rust 中 `Option<String>` 可能返回空字符串而非 null，客户端应同时处理两种情况
2. **isDiscoverableApp**：即使设为 true，应用仍可能因其他条件（如权限、配置）而不可见
3. **国际化缺失**：当前无多语言品牌信息支持

### 6.3 改进建议

1. **类型安全增强**：
   ```typescript
   // 建议使用 branded type 或模板字面量类型
   type URLString = `https://${string}`;
   ```

2. **添加验证注解**：
   ```rust
   // 在 Rust 侧添加 URL 格式验证
   #[serde(with = "url_serde")]
   pub website: Option<Url>,
   ```

3. **国际化支持**：
   ```typescript
   type AppBranding = {
     // ...现有字段
     localized: {
       [locale: string]: {
         developer?: string;
         description?: string;
       }
     } | null;
   };
   ```

4. **稳定化路径**：
   - 收集实验性使用反馈
   - 确定字段集是否满足所有用例
   - 考虑添加 `iconUrl`、`supportEmail` 等常用字段

### 6.4 相关 Issue/PR

- 实验性标记来源：`#[experimental("app/list")]` 或类似机制
- 建议关注 `app-server-protocol` 的变更日志以获取稳定化通知
