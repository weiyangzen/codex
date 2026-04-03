# WebSearchAction.ts Research Document

## 场景与职责

`WebSearchAction` 是 App-Server Protocol v2 中定义网页搜索操作的可辨识联合类型。它在以下场景中发挥关键作用：

1. **网页搜索工具**: 作为 `web_search` 工具的调用参数，描述需要执行的搜索操作
2. **浏览器自动化**: 支持打开特定页面、在页面内查找等浏览器操作
3. **搜索结果处理**: 区分不同类型的搜索行为（关键词搜索、页面打开、页面内查找）
4. **AI 决策表达**: 允许 AI 模型以结构化方式表达其搜索意图
5. **审计和日志**: 记录 AI 执行的网页操作，用于安全审计和调试

## 功能点目的

该联合类型的核心目的是：

- **操作抽象**: 将各种网页操作抽象为统一的类型
- **AI 意图结构化**: 将 AI 的自然语言搜索意图转换为可执行的结构化操作
- **安全控制**: 通过明确的操作类型，实现细粒度的安全策略控制
- **用户体验**: 向用户清晰展示 AI 正在执行的网页操作
- **扩展性**: 支持未来添加新的网页操作类型

## 具体技术实现

### TypeScript 类型定义

```typescript
export type WebSearchAction = 
  | { "type": "search", query: string | null, queries: Array<string> | null }
  | { "type": "openPage", url: string | null }
  | { "type": "findInPage", url: string | null, pattern: string | null }
  | { "type": "other" };
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type", rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WebSearchAction {
    Search {
        query: Option<String>,
        queries: Option<Vec<String>>,
    },
    OpenPage {
        url: Option<String>,
    },
    FindInPage {
        url: Option<String>,
        pattern: Option<String>,
    },
    #[serde(other)]
    Other,
}
```

### 变体详解

| 变体 | `type` 值 | 字段 | 用途 |
|-----|----------|------|------|
| **Search** | `"search"` | `query?: string`, `queries?: string[]` | 执行关键词搜索，支持单查询或多查询 |
| **OpenPage** | `"openPage"` | `url?: string` | 打开特定 URL 页面 |
| **FindInPage** | `"findInPage"` | `url?: string`, `pattern?: string` | 在指定页面内查找特定内容 |
| **Other** | `"other"` | 无 | 其他未分类的网页操作（fallback） |

### 变体详细说明

#### Search

```typescript
{ type: "search", query?: string, queries?: string[] }
```

- `query`: 单一搜索查询（向后兼容或简单场景）
- `queries`: 多个搜索查询（并行搜索场景）
- 至少一个字段应有值，但类型上允许两者都为 null（需在应用层验证）

#### OpenPage

```typescript
{ type: "openPage", url?: string }
```

- `url`: 要打开的页面 URL
- 如果为 null，可能表示 AI 想要打开某个页面但未指定具体 URL

#### FindInPage

```typescript
{ type: "findInPage", url?: string, pattern?: string }
```

- `url`: 要在其中查找的页面 URL
- `pattern`: 要查找的文本模式或关键词
- 用于在已知页面中定位特定信息

#### Other

```typescript
{ type: "other" }
```

- 使用 `#[serde(other)]` 作为 fallback 变体
- 处理未知的或未来的操作类型
- 提供向前兼容性

### 核心层转换

```rust
impl From<codex_protocol::models::WebSearchAction> for WebSearchAction {
    fn from(value: codex_protocol::models::WebSearchAction) -> Self {
        match value {
            codex_protocol::models::WebSearchAction::Search { query, queries } => {
                WebSearchAction::Search { query, queries }
            }
            codex_protocol::models::WebSearchAction::OpenPage { url } => {
                WebSearchAction::OpenPage { url }
            }
            codex_protocol::models::WebSearchAction::FindInPage { url, pattern } => {
                WebSearchAction::FindInPage { url, pattern }
            }
            codex_protocol::models::WebSearchAction::Other => WebSearchAction::Other,
        }
    }
}
```

### 显示辅助函数

在 `core/src/web_search.rs` 中提供了用户友好的操作描述生成：

```rust
pub fn web_search_action_detail(action: &WebSearchAction) -> String {
    match action {
        WebSearchAction::Search { query, queries } => 
            format!("搜索: {}", query_or_first(queries)),
        WebSearchAction::OpenPage { url } => 
            url.clone().unwrap_or_default(),
        WebSearchAction::FindInPage { url, pattern } => 
            format!("'{}' in {}", pattern.unwrap_or(""), url.unwrap_or("")),
        WebSearchAction::Other => String::new(),
    }
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4329-4363) | Rust 枚举定义及转换实现 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WebSearchAction.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WebSearchAction.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/protocol/src/models.rs` | 核心层 `WebSearchAction` 定义 |
| `codex-rs/core/src/web_search.rs` | 搜索操作处理和显示 |
| `codex-rs/exec/src/exec_events.rs` | 执行事件中的搜索动作 |
| `codex-rs/tui/src/history_cell.rs` | TUI 历史记录中显示搜索操作 |
| `codex-rs/tui_app_server/src/history_cell.rs` | TUI 应用服务器历史记录渲染 |
| `codex-rs/app-server-protocol/src/protocol/thread_history.rs` | 线程历史中的搜索动作序列化 |

### 工具调用流程

```
AI 模型决定搜索
    │
    ▼
生成 WebSearchAction JSON
    │
    ▼
工具调用解析 → WebSearchAction
    │
    ▼
根据 type 分发处理:
    ├── Search → 调用搜索引擎 API
    ├── OpenPage → 浏览器打开页面
    ├── FindInPage → 页面内容提取
    └── Other → 通用处理/记录
```

## 依赖与外部交互

### 内部依赖

- **`codex_protocol::models::WebSearchAction`**: 核心层对应的搜索动作类型
- **`ThreadItem`**: 在对话历史中作为搜索工具调用的参数存储

### 协议依赖

- 作为工具调用的参数类型使用
- 在 `ResponseItem` 中序列化存储
- 用于 `web_search` 工具的参数验证

### 外部服务交互

| 变体 | 外部服务 | 说明 |
|-----|---------|------|
| `Search` | 搜索引擎 API | Google、Bing 等搜索接口 |
| `OpenPage` | HTTP 客户端 | 获取页面内容 |
| `FindInPage` | HTTP 客户端 + 文本处理 | 获取并解析页面内容 |

## 风险、边界与改进建议

### 潜在风险

1. **URL 安全**: `OpenPage` 和 `FindInPage` 中的 URL 可能指向恶意网站
2. **搜索注入**: `Search` 变体的查询内容可能包含搜索注入攻击
3. **隐私泄露**: 搜索查询可能包含敏感信息
4. **资源消耗**: 大量或复杂的网页操作可能消耗大量网络资源和计算资源

### 边界情况

1. **空查询**: `Search` 中 `query` 和 `queries` 都为 null 或空
2. **无效 URL**: URL 格式无效或无法访问
3. **页面过大**: `FindInPage` 目标页面内容过大
4. **编码问题**: 页面内容编码不一致导致查找失败
5. **Other 变体处理**: 收到未知操作类型时的降级策略

### 改进建议

1. **URL 安全校验**: 添加 URL 安全验证：
   ```rust
   impl WebSearchAction {
       pub fn validate_urls(&self) -> Result<(), ValidationError> {
           match self {
               WebSearchAction::OpenPage { url: Some(url) } |
               WebSearchAction::FindInPage { url: Some(url), .. } => {
                   validate_url_scheme(url)?;  // 只允许 https
                   validate_url_domain(url)?;  // 域名白名单/黑名单
               }
               _ => {}
           }
           Ok(())
       }
   }
   ```

2. **查询清理**: 对搜索查询进行清理和验证：
   ```rust
   pub fn sanitize_query(query: &str) -> String {
       // 移除或转义特殊字符
       // 限制查询长度
       // 检测敏感信息模式
   }
   ```

3. **操作超时**: 为每种操作类型设置合理的超时：
   ```rust
   pub struct WebSearchConfig {
       search_timeout: Duration,
       open_page_timeout: Duration,
       find_in_page_timeout: Duration,
       max_page_size: usize,
   }
   ```

4. **结果缓存**: 对搜索结果实现缓存机制：
   ```rust
   pub struct SearchCache {
       // 缓存近期搜索查询的结果
       // 减少重复搜索的 API 调用
   }
   ```

5. **新增变体**: 考虑添加更多操作类型：
   - `ScrollPage`: 滚动页面加载更多内容
   - `ClickElement`: 点击页面元素
   - `SubmitForm`: 提交表单
   - `NavigateBack`: 浏览器后退操作

6. **用户确认**: 对于某些高风险操作（如访问特定域名），添加用户确认步骤

### 测试覆盖

- 单元测试: `codex-rs/core/src/web_search.rs`（显示逻辑）
- 集成测试: `codex-rs/exec/tests/event_processor_with_json_output.rs`
- 建议添加：
  - URL 安全验证测试
  - 各种操作类型的端到端测试
  - 超时和错误处理测试
  - 缓存机制测试
