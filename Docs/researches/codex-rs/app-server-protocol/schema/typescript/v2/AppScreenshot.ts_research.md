# AppScreenshot 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppScreenshot` 是 Codex App-Server Protocol v2 中用于描述应用程序截图信息的类型。它主要用于：

- **应用商店展示**：在应用详情页面展示应用界面预览
- **应用发现**：帮助用户直观了解应用功能和界面
- **营销材料**：提供高质量的视觉素材用于推广
- **AI 生成截图**：支持通过用户提示词（userPrompt）生成截图

### 1.2 核心职责

- 提供应用截图的访问路径（URL 或文件 ID）
- 支持截图的 AI 生成描述（userPrompt）
- 作为 `AppMetadata` 的子组件，构成完整的应用展示信息
- 支持多种存储方式（外部 URL 或内部文件系统）

### 1.3 截图来源

截图可能来自以下渠道：
- **手动上传**：开发者手动上传的截图
- **AI 生成**：基于 `userPrompt` 使用 AI 生成的截图
- **自动捕获**：应用运行时自动捕获的界面截图
- **外部托管**：存储在 CDN 或对象存储上的图片

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `url` | `string \| null` | 截图的外部访问 URL |
| `fileId` | `string \| null` | 内部文件系统标识符 |
| `userPrompt` | `string` | 用于生成截图的用户提示词 |

### 2.2 字段组合逻辑

| url | fileId | 含义 |
|-----|--------|------|
| 有值 | null | 外部托管的截图 |
| null | 有值 | 内部存储的截图 |
| 有值 | 有值 | 同时支持两种访问方式 |
| null | null | 仅包含生成提示词，截图待生成 |

### 2.3 设计意图

1. **双路径访问**：支持外部 URL 和内部 fileId，适应不同部署场景
2. **AI 生成支持**：`userPrompt` 字段支持 AI 生成截图的元数据记录
3. **灵活性**：所有字段均可为 null，适应不同的截图提供方式

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppScreenshot = {
  url: string | null,
  fileId: string | null,
  userPrompt: string,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AppScreenshot {
    pub url: Option<String>,
    #[serde(alias = "file_id")]
    pub file_id: Option<String>,
    #[serde(alias = "user_prompt")]
    pub user_prompt: String,
}
```

### 3.3 序列化规则

- 使用 `#[serde(rename_all = "camelCase")]` 转换字段名
- `url` 和 `file_id` 使用 `Option<String>`，可为 null
- `user_prompt` 为必填字段（`String` 类型）
- 使用 `#[serde(alias = ...)]` 支持 snake_case 的别名（向后兼容）

### 3.4 生成工具

- 生成命令：`just write-app-server-schema`
- 输出路径：`codex-rs/app-server-protocol/schema/typescript/v2/AppScreenshot.ts`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 1968-1977 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppScreenshot.ts` | 生成的 TypeScript 类型 |

### 4.2 引用关系

```
AppMetadata
  └── screenshots: AppScreenshot[] | null
```

- `AppScreenshot` 被 `AppMetadata` 类型引用，作为其 `screenshots` 数组的元素类型

### 4.3 相关类型

| 类型 | 关系 |
|------|------|
| `AppMetadata` | 包含 `screenshots: AppScreenshot[] \| null` |
| `AppInfo` | 通过 `appMetadata` 间接引用 |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

`AppScreenshot.ts` 无直接导入，是独立的类型。

### 5.2 外部协议依赖

- **serde**：序列化/反序列化
- **schemars**：JSON Schema 生成
- **ts-rs**：TypeScript 类型生成

### 5.3 客户端使用示例

```typescript
import type { AppScreenshot } from "./AppScreenshot";
import type { AppMetadata } from "./AppMetadata";
import type { AppInfo } from "./AppInfo";

// 获取截图 URL 列表
function getScreenshotUrls(app: AppInfo): string[] {
  return app.appMetadata?.screenshots
    ?.map(s => s.url)
    .filter((url): url is string => url !== null) ?? [];
}

// 获取最佳截图 URL（优先使用 url，其次通过 fileId 构建）
function getBestScreenshotUrl(screenshot: AppScreenshot, baseUrl: string): string | null {
  if (screenshot.url) {
    return screenshot.url;
  }
  if (screenshot.fileId) {
    return `${baseUrl}/files/${screenshot.fileId}`;
  }
  return null;
}

// 检查是否为 AI 生成的截图
function isAIGenerated(screenshot: AppScreenshot): boolean {
  return screenshot.userPrompt.length > 0 && !screenshot.url && !screenshot.fileId;
}

// 截图画廊组件
interface ScreenshotGalleryProps {
  screenshots: AppScreenshot[];
  baseFileUrl: string;
}

function ScreenshotGallery({ screenshots, baseFileUrl }: ScreenshotGalleryProps) {
  return (
    <div className="screenshot-gallery">
      {screenshots.map((screenshot, index) => {
        const url = getBestScreenshotUrl(screenshot, baseFileUrl);
        if (!url) {
          return (
            <div key={index} className="screenshot-placeholder">
              <p>AI Generating...</p>
              <small>{screenshot.userPrompt}</small>
            </div>
          );
        }
        
        return (
          <img
            key={index}
            src={url}
            alt={screenshot.userPrompt}
            title={screenshot.userPrompt}
          />
        );
      })}
    </div>
  );
}

// 验证截图数据完整性
function validateScreenshot(screenshot: AppScreenshot): string[] {
  const errors: string[] = [];
  
  if (!screenshot.url && !screenshot.fileId) {
    errors.push('Screenshot must have either url or fileId');
  }
  
  if (!screenshot.userPrompt.trim()) {
    errors.push('userPrompt is required');
  }
  
  return errors;
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **URL 失效** | 外部 URL 可能 404 或过期 | 实现 fallback 机制，优先使用 fileId |
| **userPrompt 必填** | 非 AI 生成的截图也需要提供 prompt | 可设为空字符串或通用描述 |
| **无尺寸信息** | 不知道截图的宽高比 | 客户端使用 object-fit 自适应 |
| **无格式信息** | 不知道图片格式（PNG/JPG/WebP） | 从 URL 扩展名推断或服务器返回 Content-Type |

### 6.2 边界情况

1. **空 userPrompt**：虽然类型要求非空，但可能收到空字符串
2. **无效 URL**：`url` 字段可能包含格式错误的 URL
3. **fileId 不存在**：引用的文件可能已被删除
4. **大量截图**：应用可能有数十张截图，需考虑性能

### 6.3 改进建议

1. **添加尺寸信息**：
   ```typescript
   interface AppScreenshot {
     url: string | null;
     fileId: string | null;
     userPrompt: string;
     width?: number;
     height?: number;
     format?: 'png' | 'jpg' | 'webp' | 'gif';
   }
   ```

2. **添加排序和标签**：
   ```typescript
   interface AppScreenshot {
     url: string | null;
     fileId: string | null;
     userPrompt: string;
     order?: number;           // 显示顺序
     tags?: string[];          // 标签，如 ['main', 'settings', 'dark-mode']
     caption?: string;         // 图片说明
   }
   ```

3. **支持多分辨率**：
   ```typescript
   interface AppScreenshot {
     userPrompt: string;
     variants: {
       thumbnail?: ImageVariant;
       medium?: ImageVariant;
       full?: ImageVariant;
     };
   }
   
   interface ImageVariant {
     url?: string;
     fileId?: string;
     width: number;
     height: number;
   }
   ```

4. **userPrompt 可选化**：
   ```typescript
   interface AppScreenshot {
     url: string | null;
     fileId: string | null;
     userPrompt?: string;  // 改为可选
     source: 'uploaded' | 'ai-generated' | 'auto-captured';
   }
   ```

### 6.4 性能优化

1. **懒加载**：
   ```typescript
   <img loading="lazy" src={url} alt={userPrompt} />
   ```

2. **渐进加载**：
   ```typescript
   // 先加载缩略图，再加载高清图
   <img 
     src={thumbnailUrl} 
     data-src={fullUrl}
     className="lazy-load"
   />
   ```

3. **预加载关键截图**：
   ```typescript
   // 预加载第一张截图
   <link rel="preload" as="image" href={screenshots[0]?.url} />
   ```

### 6.5 无障碍支持

```typescript
function ScreenshotWithAccessibility({ screenshot }: { screenshot: AppScreenshot }) {
  return (
    <figure>
      <img 
        src={screenshot.url || ''}
        alt={screenshot.userPrompt}  // 使用 userPrompt 作为 alt 文本
      />
      <figcaption>{screenshot.userPrompt}</figcaption>
    </figure>
  );
}
```
