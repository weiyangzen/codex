# AppsListResponse 类型研究文档

## 1. 场景与职责

### 使用场景
`AppsListResponse` 是 Codex App-Server Protocol v2 中 `app/list` RPC 方法的响应类型。它封装了应用列表查询的结果，包括应用数据数组和分页游标，为客户端提供完整的应用发现功能。

### 主要职责
- **数据封装**：包含应用列表数据（`AppInfo` 数组）
- **分页支持**：提供下一页游标，支持大数据集的分页遍历
- **状态指示**：通过 `nextCursor` 指示是否还有更多数据
- **响应完整性**：与 `AppsListParams` 配合，完成应用列表查询的响应闭环

### 使用场景示例
```typescript
// 客户端调用示例
const response = await client.request('app/list', {
    limit: 20
});

// 处理响应
console.log(`获取到 ${response.data.length} 个应用`);

// 检查是否有更多数据
if (response.nextCursor) {
    // 获取下一页
    const nextPage = await client.request('app/list', {
        cursor: response.nextCursor,
        limit: 20
    });
}

// 遍历应用
for (const app of response.data) {
    console.log(`${app.name}: ${app.description}`);
    console.log(`可访问: ${app.isAccessible}, 已启用: ${app.isEnabled}`);
}
```

---

## 2. 功能点目的

### 2.1 应用数据数组（`data`）
- **目的**：返回查询结果中的应用列表
- **类型**：`Array<AppInfo>`
- **内容**：每个元素包含应用的完整元数据（ID、名称、描述、图标、状态等）
- **排序**：通常按服务器定义的顺序（如名称字母顺序、 popularity 等）

### 2.2 分页游标（`nextCursor`）
- **目的**：支持客户端获取下一页数据
- **类型**：`string | null`
- **机制**：
  - 有下一页时：返回非空字符串游标
  - 无更多数据时：返回 `null`
- **不透明性**：客户端不应解析游标内容，只需原样传递

### 2.3 分页完整性指示
| `nextCursor` 值 | 含义 | 客户端行为 |
|-----------------|------|------------|
| `null` | 无更多数据，已到最后一页 | 停止分页请求 |
| 非空字符串 | 有更多数据 | 使用此游标请求下一页 |

### 2.4 与请求参数的对应关系
```
AppsListParams          AppsListResponse
    │                           │
    ├─ cursor ─────────────────┤ (输入游标，确定起始位置)
    ├─ limit ──────────────────┤ (限制返回数量)
    ├─ threadId ───────────────┤ (影响 isAccessible 评估)
    └─ forceRefetch ───────────┤ (影响数据新鲜度)
                                │
                                ├─ data (应用列表)
                                └─ nextCursor (下一页游标)
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
import type { AppInfo } from "./AppInfo";

/**
 * EXPERIMENTAL - app list response.
 */
export type AppsListResponse = { 
    data: Array<AppInfo>, 
    /**
     * Opaque cursor to pass to the next call to continue after the last item.
     * If None, there are no more items to return.
     */
    nextCursor: string | null, 
};
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - app list response.
pub struct AppsListResponse {
    pub data: Vec<AppInfo>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 3.3 序列化特性
| 特性 | 说明 |
|------|------|
| `rename_all = "camelCase"` | 字段使用 camelCase（`next_cursor` → `nextCursor`） |
| `Option<String>` | `next_cursor` 可为 `null`（TypeScript 中对应 `string \| null`） |
| `Vec<AppInfo>` | `data` 字段在 TypeScript 中映射为 `Array<AppInfo>` |

### 3.4 关联类型
| 类型 | 文件 | 说明 |
|------|------|------|
| `AppInfo` | `AppInfo.ts` | 单个应用的详细信息 |
| `AppsListParams` | `AppsListParams.ts` | 对应的请求参数类型 |

### 3.5 AppInfo 结构概览
```typescript
type AppInfo = {
    id: string;                          // 应用唯一标识
    name: string;                        // 应用名称
    description: string | null;          // 应用描述
    logoUrl: string | null;              // Logo URL（亮色模式）
    logoUrlDark: string | null;          // Logo URL（暗色模式）
    distributionChannel: string | null;  // 分发渠道
    branding: AppBranding | null;        // 品牌信息
    appMetadata: AppMetadata | null;     // 应用元数据
    labels: Record<string, string> | null; // 标签
    installUrl: string | null;           // 安装链接
    isAccessible: boolean;               // 当前用户是否可访问
    isEnabled: boolean;                  // 是否在配置中启用
    pluginDisplayNames: string[];        // 插件显示名称
};
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:2048-2057` | Rust 源类型定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| AppsListResponse.ts | `codex-rs/app-server-protocol/schema/typescript/v2/AppsListResponse.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/AppsListResponse.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| common.rs | `codex-rs/app-server-protocol/src/protocol/common.rs:307-310` | 注册 `AppsList` RPC 方法响应类型 |

### 4.4 RPC 方法注册
```rust
// common.rs
AppsList => "app/list" {
    params: v2::AppsListParams,
    response: v2::AppsListResponse,  // 本类型
},
```

### 4.5 相关通知类型
| 类型 | 文件 | 路径 | 说明 |
|------|------|------|------|
| `AppListUpdatedNotification` | `AppListUpdatedNotification.ts` | `v2.rs:2059-2065` | 应用列表变更通知 |

### 4.6 代码引用链
```
ClientRequest::AppsList
    ├── params: AppsListParams
    └── response: AppsListResponse
            ├── data: Vec<AppInfo>
            │       ├── id: String
            │       ├── name: String
            │       ├── description: Option<String>
            │       ├── logo_url: Option<String>
            │       ├── logo_url_dark: Option<String>
            │       ├── distribution_channel: Option<String>
            │       ├── branding: Option<AppBranding>
            │       ├── app_metadata: Option<AppMetadata>
            │       ├── labels: Option<HashMap<String, String>>
            │       ├── install_url: Option<String>
            │       ├── is_accessible: bool
            │       ├── is_enabled: bool
            │       └── plugin_display_names: Vec<String>
            └── next_cursor: Option<String>
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
```typescript
import type { AppInfo } from "./AppInfo";
```

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| App List API | `app/list` 响应 | 主要使用场景 |
| App Registry | 数据源 | 获取应用元数据 |
| Config System | 评估 `is_enabled` | 检查应用配置状态 |
| Feature Gating | 评估 `is_accessible` | 基于线程配置评估可用性 |

### 5.4 数据流
```
App Registry / MCP Servers
    ↓
App-Server (过滤、排序、分页)
    ├─ 根据 thread_id 评估 is_accessible
    ├─ 根据 config 评估 is_enabled
    ├─ 应用 cursor 和 limit 分页
    └─ 生成 next_cursor
    ↓
AppsListResponse
    ↓
Client
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：实验性 API 不稳定
- **问题**：类型标记为 `EXPERIMENTAL`，API 可能在未来版本中变更
- **影响**：响应结构可能改变，客户端需要适配
- **缓解**：
  - 客户端实现版本协商机制
  - 关注协议更新说明
  - 准备降级方案

#### 风险 2：`data` 数组为空
- **问题**：某些情况下可能返回空数组
- **场景**：
  - 用户无可访问的应用
  - 所有应用都被禁用
  - 游标指向的范围无数据
- **缓解**：客户端应正确处理空列表情况

#### 风险 3：游标失效
- **问题**：`nextCursor` 可能在客户端使用前过期
- **影响**：下一页请求失败
- **缓解**：
  - 服务器应提供清晰的错误信息
  - 客户端应准备从第一页重新获取

#### 风险 4：数据一致性
- **问题**：分页过程中数据可能变化（新应用添加/删除）
- **影响**：可能出现重复或遗漏
- **缓解**：游标分页相比偏移量分页对此有更好的容忍度

### 6.2 边界情况

| 场景 | 预期行为 | 说明 |
|------|----------|------|
| 无应用可访问 | `data: [], nextCursor: null` | 空列表 |
| 最后一页 | `nextCursor: null` | 表示结束 |
| 单页包含所有数据 | `data: [...], nextCursor: null` | 无需分页 |
| 应用状态变更中 | 基于查询时刻的快照 | 非实时更新 |
| 大量应用 | 分页返回 | 每页数量由 `limit` 控制 |

### 6.3 改进建议

#### 建议 1：添加响应元数据
```rust
pub struct AppsListResponse {
    pub data: Vec<AppInfo>,
    pub next_cursor: Option<String>,
    
    // 新增
    /// 总应用数（可能为 null 如果计算成本高）
    pub total_count: Option<u64>,
    
    /// 是否有更多数据（比检查 next_cursor 更直观）
    pub has_more: bool,
    
    /// 当前页码（如果适用）
    pub page: Option<u32>,
}
```

#### 建议 2：添加响应时间戳
```rust
pub struct AppsListResponse {
    // ... 现有字段
    
    /// 数据生成时间戳（Unix 秒）
    pub generated_at: i64,
}
```

#### 建议 3：支持聚合信息
```rust
pub struct AppsListResponse {
    pub data: Vec<AppInfo>,
    pub next_cursor: Option<String>,
    
    /// 聚合统计
    pub summary: AppsListSummary,
}

pub struct AppsListSummary {
    /// 已安装应用数
    pub installed_count: u32,
    /// 可访问但未安装的应用数
    pub available_count: u32,
    /// 已启用应用数
    pub enabled_count: u32,
}
```

#### 建议 4：添加缓存信息
```rust
pub struct AppsListResponse {
    // ... 现有字段
    
    /// 数据是否来自缓存
    pub from_cache: bool,
    
    /// 缓存过期时间（Unix 秒）
    pub cache_expires_at: Option<i64>,
}
```

#### 建议 5：错误响应标准化
```rust
// 建议添加专门的错误响应类型
pub struct AppsListError {
    pub code: AppsListErrorCode,
    pub message: String,
    pub retry_after: Option<i64>,
}

pub enum AppsListErrorCode {
    InvalidCursor,
    CursorExpired,
    RateLimited,
    InternalError,
}
```

### 6.4 与通知机制的协同

当前协议还提供了 `AppListUpdatedNotification` 通知：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - notification emitted when the app list changes.
pub struct AppListUpdatedNotification {
    pub data: Vec<AppInfo>,
}
```

**建议改进**：
1. 通知应包含变更类型（添加、更新、删除）
2. 通知应包含变更原因（用户操作、配置变更等）
3. 客户端可以结合通知和轮询保持数据同步

```rust
pub struct AppListUpdatedNotification {
    pub change_type: AppListChangeType,
    pub affected_apps: Vec<AppInfo>,
    pub reason: Option<String>,
}

pub enum AppListChangeType {
    Added,
    Updated,
    Removed,
    Refreshed,  // 全量刷新
}
```

### 6.5 实验性状态说明
- `AppsListResponse` 目前标记为实验性 API
- 建议在使用时注意：
  1. 实现版本检查
  2. 准备降级方案
  3. 关注协议更新
