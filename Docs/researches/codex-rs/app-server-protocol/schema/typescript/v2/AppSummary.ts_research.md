# AppSummary 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppSummary` 是 Codex App-Server Protocol v2 中用于描述应用程序精简信息的类型。它是 `AppInfo` 的轻量级版本，主要用于：

- **插件响应优化**：在插件相关 API 中返回精简的应用信息，减少数据传输
- **列表展示**：在需要展示大量应用的列表场景中使用
- **快速预览**：提供应用的基本信息，无需加载完整的 `AppInfo`
- **授权流程**：标识需要授权的应用列表

### 1.2 核心职责

- 提供应用的核心标识信息（ID、名称、描述）
- 支持应用安装链接
- 作为 `AppInfo` 的精简替代，优化性能
- 在插件安装流程中标识需要授权的应用

### 1.3 与 AppInfo 的关系

| 特性 | AppInfo | AppSummary |
|------|---------|------------|
| 数据量 | 完整（13+ 字段） | 精简（4 字段） |
| 使用场景 | 详情页面 | 列表、插件响应 |
| 嵌套类型 | 有（branding, metadata） | 无 |
| 性能 | 较高开销 | 低开销 |

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `id` | `string` | 应用唯一标识符 |
| `name` | `string` | 应用显示名称 |
| `description` | `string \| null` | 应用简短描述 |
| `installUrl` | `string \| null` | 应用安装/配置页面 URL |

### 2.2 设计意图

1. **最小可用信息**：仅包含标识和展示所需的最少字段
2. **性能优化**：减少序列化/反序列化和传输开销
3. **渐进加载**：先展示摘要，按需加载完整信息
4. **插件集成**：`installUrl` 支持插件安装后的跳转

### 2.3 使用场景对比

```typescript
// 场景 1：应用列表（使用 AppInfo）
const appsList: AppInfo[] = await api.app.list();

// 场景 2：插件安装响应（使用 AppSummary）
const installResponse: PluginInstallResponse = await api.plugin.install(pluginId);
const appsNeedingAuth: AppSummary[] = installResponse.apps_needing_auth;

// 场景 3：插件摘要（使用 AppSummary）
const pluginSummary: PluginSummary = await api.plugin.getSummary(pluginId);
const relatedApps: AppSummary[] = pluginSummary.apps;
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppSummary = {
  id: string,
  name: string,
  description: string | null,
  installUrl: string | null,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - app metadata summary for plugin responses.
pub struct AppSummary {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub install_url: Option<String>,
}
```

### 3.3 类型转换

```rust
// AppInfo 到 AppSummary 的转换
impl From<AppInfo> for AppSummary {
    fn from(value: AppInfo) -> Self {
        Self {
            id: value.id,
            name: value.name,
            description: value.description,
            install_url: value.install_url,
        }
    }
}
```

### 3.4 生成工具

- 生成命令：`just write-app-server-schema`
- 输出路径：`codex-rs/app-server-protocol/schema/typescript/v2/AppSummary.ts`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 2026-2046 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppSummary.ts` | 生成的 TypeScript 类型 |

### 4.2 引用关系

```
AppInfo -> AppSummary (通过 From trait 转换)

PluginSummary
  └── apps: AppSummary[]

PluginInstallResponse
  └── apps_needing_auth: AppSummary[]
```

### 4.3 相关类型

| 类型 | 关系 |
|------|------|
| `AppInfo` | 可转换为 `AppSummary` |
| `PluginSummary` | 包含 `apps: Vec<AppSummary>` |
| `PluginInstallResponse` | 包含 `apps_needing_auth: Vec<AppSummary>` |

### 4.4 使用位置

| API | 字段 | 说明 |
|-----|------|------|
| `PluginSummary` | `apps: AppSummary[]` | 插件关联的应用列表 |
| `PluginInstallResponse` | `apps_needing_auth: AppSummary[]` | 需要授权的应用 |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

`AppSummary.ts` 无直接导入，是独立的简单类型。

### 5.2 外部协议依赖

- **serde**：序列化/反序列化
- **schemars**：JSON Schema 生成
- **ts-rs**：TypeScript 类型生成

### 5.3 客户端使用示例

```typescript
import type { AppSummary } from "./AppSummary";
import type { PluginInstallResponse } from "./PluginInstallResponse";

// 处理插件安装响应
async function handlePluginInstall(response: PluginInstallResponse): Promise<void> {
  const { apps_needing_auth } = response;
  
  if (apps_needing_auth.length > 0) {
    // 显示需要授权的应用列表
    showAuthRequiredDialog(apps_needing_auth);
  }
}

// 显示授权对话框
function showAuthRequiredDialog(apps: AppSummary[]): void {
  const content = apps.map(app => ({
    id: app.id,
    title: app.name,
    description: app.description,
    action: app.installUrl ? {
      label: 'Configure',
      url: app.installUrl,
    } : undefined,
  }));
  
  openDialog({
    title: 'Authorization Required',
    message: 'The following apps need to be configured:',
    items: content,
  });
}

// 渲染应用卡片（精简版）
function renderAppCard(app: AppSummary): HTMLElement {
  const card = document.createElement('div');
  card.className = 'app-card';
  
  const title = document.createElement('h3');
  title.textContent = app.name;
  
  const desc = document.createElement('p');
  desc.textContent = app.description ?? 'No description available';
  
  card.appendChild(title);
  card.appendChild(desc);
  
  if (app.installUrl) {
    const link = document.createElement('a');
    link.href = app.installUrl;
    link.textContent = 'Install';
    card.appendChild(link);
  }
  
  return card;
}

// 批量加载完整应用信息
async function loadFullAppDetails(summaries: AppSummary[]): Promise<AppInfo[]> {
  const fullApps = await Promise.all(
    summaries.map(summary => 
      api.app.get(summary.id)  // 假设有获取单个应用的 API
    )
  );
  return fullApps;
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **信息不足** | 仅有 4 个字段，某些场景需要更多信息 | 按需加载完整 `AppInfo` |
| **实验性 API** | 可能变更 | 关注变更日志 |
| **无状态信息** | 不包含 `isEnabled`、`isAccessible` 等状态 | 在需要状态的场景使用 `AppInfo` |

### 6.2 边界情况

1. **空描述**：`description` 可能为 null，UI 需要占位文本
2. **无安装链接**：`installUrl` 可能为 null，表示无法直接安装
3. **重复 ID**：理论上不应发生，但客户端应做好去重

### 6.3 改进建议

1. **添加 Logo URL**：
   ```typescript
   interface AppSummary {
     id: string;
     name: string;
     description: string | null;
     installUrl: string | null;
     logoUrl?: string | null;  // 添加图标支持
   }
   ```

2. **添加状态指示器**：
   ```typescript
   interface AppSummary {
     id: string;
     name: string;
     description: string | null;
     installUrl: string | null;
     status?: 'installed' | 'available' | 'update-available';
   }
   ```

3. **添加分类信息**：
   ```typescript
   interface AppSummary {
     id: string;
     name: string;
     description: string | null;
     installUrl: string | null;
     category?: string;  // 用于列表分组
   }
   ```

4. **稳定化路径**：
   - 收集插件开发者的使用反馈
   - 评估是否需要添加更多字段
   - 考虑与 `AppInfo` 的字段对齐策略

### 6.4 性能最佳实践

1. **列表虚拟化**：
   ```typescript
   // 使用虚拟列表渲染大量 AppSummary
   <VirtualList
     items={appSummaries}
     renderItem={(app) => <AppCard summary={app} />}
     itemHeight={80}
   />
   ```

2. **缓存策略**：
   ```typescript
   // 缓存 AppSummary 到本地存储
   const cacheKey = `apps:${pluginId}`;
   const cached = localStorage.getItem(cacheKey);
   if (cached) {
     return JSON.parse(cached);
   }
   ```

3. **增量加载**：
   ```typescript
   // 先显示摘要，后台加载完整信息
   const [summaries, setSummaries] = useState<AppSummary[]>([]);
   const [fullApps, setFullApps] = useState<Record<string, AppInfo>>({});
   
   useEffect(() => {
     summaries.forEach(async (summary) => {
       const full = await api.app.get(summary.id);
       setFullApps(prev => ({ ...prev, [summary.id]: full }));
     });
   }, [summaries]);
   ```

### 6.5 与 AppInfo 的转换工具

```typescript
// 从 AppInfo 提取摘要
function toAppSummary(app: AppInfo): AppSummary {
  return {
    id: app.id,
    name: app.name,
    description: app.description,
    installUrl: app.installUrl,
  };
}

// 合并摘要和完整信息
function mergeAppInfo(
  summary: AppSummary, 
  full?: AppInfo
): AppInfo | AppSummary {
  return full ?? summary;
}
```
