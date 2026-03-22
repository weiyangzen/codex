# WebSearchAction.ts 研究文档

## 1. 场景与职责

WebSearchAction 类型在 Codex 系统中用于表示网络搜索调用的具体动作。当 AI 模型触发网络搜索工具时，这个类型描述了要执行的具体搜索操作。主要应用场景包括：

- **网络搜索**: 执行关键词搜索获取最新信息
- **页面打开**: 打开特定 URL 获取页面内容
- **页面内查找**: 在特定页面内搜索特定内容
- **搜索结果处理**: 处理和组织搜索结果供模型使用

## 2. 功能点目的

WebSearchAction 是一个标签联合类型，支持多种搜索操作：

1. **Search**: 执行关键词搜索
   - `query`: 单个搜索查询
   - `queries`: 多个搜索查询（批量搜索）
2. **OpenPage**: 打开特定页面
   - `url`: 要打开的页面 URL
3. **FindInPage**: 在页面内查找
   - `url`: 目标页面 URL
   - `pattern`: 要查找的模式/文本
4. **Other**: 其他未知操作类型（用于向前兼容）

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type WebSearchAction = 
  | { "type": "search", query?: string, queries?: Array<string> } 
  | { "type": "open_page", url?: string } 
  | { "type": "find_in_page", url?: string, pattern?: string } 
  | { "type": "other" };
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs` (lines 1056-1084):

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
#[schemars(rename = "ResponsesApiWebSearchAction")]
pub enum WebSearchAction {
    Search {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        query: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        queries: Option<Vec<String>>,
    },
    OpenPage {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        url: Option<String>,
    },
    FindInPage {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        url: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(optional)]
        pattern: Option<String>,
    },
    #[serde(other)]
    Other,
}
```

### 关键特性

1. **标签联合**: 使用 `"type"` 字段区分不同操作类型
2. **可选字段**: 所有字段都是可选的，提供灵活性
3. **批量搜索**: Search 变体支持单个 query 或多个 queries
4. **向前兼容**: Other 变体处理未知的操作类型
5. **Schema 重命名**: 使用 `#[schemars(rename = "...")]` 指定 JSON Schema 名称

### 在 ResponseItem 中的使用

WebSearchAction 作为 `ResponseItem::WebSearchCall` 的一部分 (models.rs lines 410-420):

```rust
WebSearchCall {
    #[serde(default, skip_serializing)]
    #[ts(skip)]
    id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    action: Option<WebSearchAction>,
}
```

### 示例 payload

```json
{
  "id": "ws_...",
  "type": "web_search_call",
  "status": "completed",
  "action": {
    "type": "search",
    "query": "weather: San Francisco, CA"
  }
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs` | WebSearchAction 定义 (lines 1056-1084) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs` | ResponseItem::WebSearchCall 使用 (lines 410-420) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/WebSearchAction.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成

### 外部交互

- **OpenAI Responses API**: 类型设计与 OpenAI API 兼容
- **搜索服务**: 实际搜索操作由后端搜索服务执行
- **浏览器/爬虫**: OpenPage 和 FindInPage 可能需要网页抓取

## 6. 风险、边界与改进建议

### 风险

1. **URL 安全**: 打开的 URL 可能指向恶意网站
2. **隐私泄露**: 搜索查询可能包含敏感信息
3. **内容质量**: 搜索结果的质量和可靠性不一
4. **速率限制**: 搜索 API 可能有速率限制

### 边界情况

1. **空查询**: query 和 queries 都为空时的行为
2. **无效 URL**: 格式不正确或不可访问的 URL
3. **大结果集**: 搜索结果可能非常大
4. **超时**: 搜索操作可能超时

### 改进建议

1. **URL 安全扫描**: 在打开页面前进行安全检查
2. **查询过滤**: 过滤或警告可能包含敏感信息的查询
3. **结果缓存**: 缓存搜索结果减少重复查询
4. **结果摘要**: 自动生成搜索结果的摘要
5. **多源搜索**: 支持多个搜索引擎提高覆盖率
6. **结果评分**: 对搜索结果进行相关性评分
7. **用户确认**: 对于某些操作（如打开页面）请求用户确认
