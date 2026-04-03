# AppsListParams 类型研究文档

## 1. 场景与职责

### 使用场景
`AppsListParams` 是 Codex App-Server Protocol v2 中用于获取可用应用（Apps/Connectors）列表的请求参数类型。客户端通过 `app/list` RPC 方法调用，获取服务器上可用的应用信息，包括应用元数据、安装状态、可访问性等。

### 主要职责
- **分页查询**：支持游标分页，处理大量应用列表
- **上下文感知**：支持基于线程配置评估应用功能门控
- **缓存控制**：允许客户端强制刷新，绕过缓存获取最新数据
- **应用发现**：为客户端提供应用市场/应用商店功能的数据基础

### 使用场景示例
```typescript
// 首次获取应用列表
const params: AppsListParams = {
    limit: 20,  // 每页 20 个应用
};

// 获取下一页
const nextParams: AppsListParams = {
    cursor: response.nextCursor,
    limit: 20,
};

// 强制刷新（绕过缓存）
const refreshParams: AppsListParams = {
    forceRefetch: true,
};

// 基于特定线程配置评估
const threadParams: AppsListParams = {
    threadId: "thread-123",
    limit: 50,
};
```

---

## 2. 功能点目的

### 2.1 游标分页（`cursor` / `limit`）
- **目的**：处理大量应用列表，避免一次性返回所有数据
- **机制**：
  - `cursor`：不透明游标，由服务器生成，客户端原样传递
  - `limit`：每页返回的最大应用数量
- **优势**：
  - 避免偏移量分页的性能问题
  - 支持动态数据集（新增/删除应用时结果稳定）

### 2.2 线程上下文（`threadId`）
- **目的**：基于特定线程的配置评估应用功能门控
- **场景**：
  - 不同线程可能有不同的配置（如不同的模型、权限设置）
  - 某些应用可能仅在特定配置下可用
- **示例**：某应用仅在 `gpt-4` 模型下可用，通过 `threadId` 可以正确评估

### 2.3 强制刷新（`forceRefetch`）
- **目的**：绕过服务器缓存，获取最新数据
- **场景**：
  - 用户刚安装了新应用，需要立即看到
  - 应用状态可能在外部系统发生变化
- **实现**：服务器端会重新从数据源获取应用列表

### 2.4 可选参数设计
| 字段 | 可选性 | 默认值 | 说明 |
|------|--------|--------|------|
| `cursor` | 可选 | `null` | 不传表示获取第一页 |
| `limit` | 可选 | `null` | 服务器决定合理默认值 |
| `threadId` | 可选 | `null` | 不传表示使用默认配置评估 |
| `forceRefetch` | 可选 | `false` | 默认使用缓存 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
/**
 * EXPERIMENTAL - list available apps/connectors.
 */
export type AppsListParams = { 
    /**
     * Opaque pagination cursor returned by a previous call.
     */
    cursor?: string | null, 
    /**
     * Optional page size; defaults to a reasonable server-side value.
     */
    limit?: number | null, 
    /**
     * Optional thread id used to evaluate app feature gating from that thread's config.
     */
    threadId?: string | null, 
    /**
     * When true, bypass app caches and fetch the latest data from sources.
     */
    forceRefetch?: boolean, 
};
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - list available apps/connectors.
pub struct AppsListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a reasonable server-side value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
    /// Optional thread id used to evaluate app feature gating from that thread's config.
    #[ts(optional = nullable)]
    pub thread_id: Option<String>,
    /// When true, bypass app caches and fetch the latest data from sources.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_refetch: bool,
}
```

### 3.3 序列化特性
| 特性 | 字段 | 说明 |
|------|------|------|
| `#[ts(optional = nullable)]` | `cursor`, `limit`, `thread_id` | TypeScript 中可选且可为 null |
| `#[serde(default, skip_serializing_if = "std::ops::Not::not")]` | `force_refetch` | 为 false 时不序列化 |
| `rename_all = "camelCase"` | 全部 | 字段使用 camelCase |

### 3.4 特殊处理：`force_refetch`
```rust
#[serde(default, skip_serializing_if = "std::ops::Not::not")]
pub force_refetch: bool,
```
- `default`：省略时默认为 `false`
- `skip_serializing_if = "std::ops::Not::not"`：值为 `false` 时不包含在序列化结果中
- 这是 App-Server Protocol v2 中布尔字段的标准处理方式

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:1929-1946` | Rust 源类型定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| AppsListParams.ts | `codex-rs/app-server-protocol/schema/typescript/v2/AppsListParams.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/AppsListParams.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| common.rs | `codex-rs/app-server-protocol/src/protocol/common.rs:307-310` | 注册 `AppsList` RPC 方法 |

### 4.4 RPC 方法注册
```rust
// common.rs
AppsList => "app/list" {
    params: v2::AppsListParams,
    response: v2::AppsListResponse,
},
```

### 4.5 响应类型
| 类型 | 文件 | 说明 |
|------|------|------|
| `AppsListResponse` | `AppsListResponse.ts` | 应用列表响应 |
| `AppInfo` | `AppInfo.ts` | 单个应用信息 |

---

## 5. 依赖与外部交互

### 5.1 直接依赖
`AppsListParams` 是基础参数类型，不依赖其他自定义类型。

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| App List API | `app/list` | 主要使用场景 |
| Thread API | 内部调用 | 通过 `thread_id` 获取线程配置 |
| App Registry | 内部服务 | 获取应用元数据 |
| Cache Layer | 内部服务 | `force_refetch` 控制缓存行为 |

### 5.4 数据流
```
Client
    ↓ AppsListParams
App-Server
    ↓ 解析参数
    ├─ cursor → 确定分页位置
    ├─ limit → 限制返回数量
    ├─ thread_id → 获取线程配置 → 评估功能门控
    └─ force_refetch → 决定是否绕过缓存
    ↓
App Registry / Cache
    ↓
AppsListResponse (Vec<AppInfo> + next_cursor)
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：实验性 API 不稳定
- **问题**：类型标记为 `EXPERIMENTAL`，API 可能在未来版本中变更
- **影响**：客户端代码可能需要适配更新
- **缓解**：
  - 客户端应做好版本兼容性处理
  - 关注版本更新说明
  - 避免在生产环境关键路径依赖此 API

#### 风险 2：`limit` 值过大
- **问题**：客户端可能传入非常大的 `limit` 值
- **影响**：服务器资源消耗过大，响应延迟增加
- **缓解**：
  - 服务器端应实现最大限制（如 100）
  - 超过限制时自动截断或返回错误

#### 风险 3：无效 `cursor`
- **问题**：客户端可能传入过期或无效的游标
- **影响**：服务器无法定位分页位置
- **缓解**：
  - 服务器应返回明确的错误信息
  - 建议客户端在收到错误后重新从第一页开始

#### 风险 4：`thread_id` 不存在
- **问题**：传入的线程 ID 可能不存在或已删除
- **影响**：功能门控评估失败
- **缓解**：
  - 服务器应使用默认配置回退
  - 记录警告日志

### 6.2 边界情况

| 场景 | 预期行为 | 说明 |
|------|----------|------|
| `cursor` 为 `null` | 返回第一页 | 初始请求 |
| `cursor` 为空字符串 | 可能报错或视为 `null` | 取决于服务器实现 |
| `limit` 为 `0` | 可能返回空列表或报错 | 建议服务器处理为默认值 |
| `limit` 超过最大值 | 截断到最大值 | 服务器保护机制 |
| `thread_id` 不存在 | 使用默认配置 | 优雅降级 |
| `forceRefetch` 为 `true` | 绕过缓存 | 可能增加延迟 |
| 所有参数都省略 | 返回默认第一页 | 使用服务器默认值 |

### 6.3 改进建议

#### 建议 1：添加排序参数
```rust
pub struct AppsListParams {
    // ... 现有字段
    
    /// 排序字段
    #[ts(optional = nullable)]
    pub sort_by: Option<AppSortField>,  // name, created_at, popularity
    
    /// 排序方向
    #[serde(default)]
    pub sort_order: SortOrder,  // asc, desc
}
```

#### 建议 2：添加过滤参数
```rust
pub struct AppsListParams {
    // ... 现有字段
    
    /// 按类别过滤
    #[ts(optional = nullable)]
    pub category: Option<String>,
    
    /// 只返回已安装的应用
    #[serde(default)]
    pub installed_only: bool,
    
    /// 搜索关键词
    #[ts(optional = nullable)]
    pub search: Option<String>,
}
```

#### 建议 3：游标过期处理
```rust
// 服务器端伪代码
fn list_apps(params: AppsListParams) -> Result<AppsListResponse> {
    if let Some(cursor) = params.cursor {
        if is_expired(&cursor) {
            return Err(Error::CursorExpired {
                message: "游标已过期，请从第一页重新获取".to_string(),
            });
        }
    }
    // ...
}
```

#### 建议 4：添加元数据字段
```rust
pub struct AppsListResponse {
    pub data: Vec<AppInfo>,
    pub next_cursor: Option<String>,
    
    // 新增
    pub total_count: Option<u64>,  // 总应用数（可能为 null 如果计算成本高）
    pub has_more: bool,  // 是否有更多数据（比检查 next_cursor 更直观）
}
```

#### 建议 5：批量获取特定应用
```rust
pub struct AppsListParams {
    // ... 现有字段
    
    /// 指定要获取的应用 ID 列表（与分页互斥）
    #[ts(optional = nullable)]
    pub app_ids: Option<Vec<String>>,
}
```

### 6.4 实验性状态说明
- `AppsListParams` 目前标记为实验性 API
- 根据 `AGENTS.md`，所有新的 API 开发应在 v2 中进行
- 建议在使用此 API 时：
  1. 实现版本检查机制
  2. 准备降级方案（如 API 变更时的兼容处理）
  3. 关注协议更新动态
