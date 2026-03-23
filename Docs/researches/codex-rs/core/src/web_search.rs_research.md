# web_search.rs 研究文档

## 场景与职责

`web_search.rs` 是 Codex Core 中负责**网页搜索动作描述生成**的模块。其核心职责是：

1. **生成搜索动作描述**：将 `WebSearchAction` 转换为人类可读的描述文本
2. **支持多种搜索动作**：搜索、打开页面、页面内查找等
3. **提供回退描述**：当动作信息不足时使用查询字符串作为描述

该模块主要用于在 UI 或日志中显示用户或模型执行的网页搜索操作的可读描述。

## 功能点目的

### 1. 搜索动作描述 (`web_search_action_detail`)

为不同类型的搜索动作生成描述：

| 动作类型 | 描述格式 |
|----------|----------|
| `Search` | 使用 query 或第一个 query，多 query 时添加 "..." |
| `OpenPage` | 直接使用 URL |
| `FindInPage` | "'pattern' in url" 或简化形式 |
| `Other` | 空字符串 |

### 2. 搜索详情 (`web_search_detail`)

提供带回退的描述生成：
- 优先使用动作描述
- 如果动作为空，使用查询字符串

## 具体技术实现

### 核心数据结构

```rust
// 来自 codex_protocol::models
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
    Other,
}
```

### 关键流程

#### 1. 搜索动作描述生成

```rust
pub fn web_search_action_detail(action: &WebSearchAction) -> String
```

**Search 动作处理**：
```rust
fn search_action_detail(query: &Option<String>, queries: &Option<Vec<String>>) -> String {
    query.clone().filter(|q| !q.is_empty()).unwrap_or_else(|| {
        let items = queries.as_ref();
        let first = items
            .and_then(|queries| queries.first())
            .cloned()
            .unwrap_or_default();
        if items.is_some_and(|queries| queries.len() > 1) && !first.is_empty() {
            format!("{first} ...")
        } else {
            first
        }
    })
}
```

逻辑：
1. 优先使用 `query`（如果非空）
2. 否则使用 `queries` 的第一个元素
3. 如果有多个 query，添加 "..." 表示还有更多

**OpenPage 动作处理**：
```rust
WebSearchAction::OpenPage { url } => url.clone().unwrap_or_default()
```

**FindInPage 动作处理**：
```rust
WebSearchAction::FindInPage { url, pattern } => match (pattern, url) {
    (Some(pattern), Some(url)) => format!("'{pattern}' in {url}"),
    (Some(pattern), None) => format!("'{pattern}'"),
    (None, Some(url)) => url.clone(),
    (None, None) => String::new(),
}
```

#### 2. 带回退的描述

```rust
pub fn web_search_detail(action: Option<&WebSearchAction>, query: &str) -> String {
    let detail = action.map(web_search_action_detail).unwrap_or_default();
    if detail.is_empty() {
        query.to_string()
    } else {
        detail
    }
}
```

使用场景：
- 当 `WebSearchAction` 解析失败或为空时
- 使用原始查询字符串作为描述

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `web_search_action_detail` | 18-30 | 主入口：生成动作描述 |
| `search_action_detail` | 3-16 | Search 动作描述辅助函数 |
| `web_search_detail` | 32-39 | 带回退的描述生成 |

### 依赖文件

| 文件 | 依赖内容 |
|------|----------|
| `codex_protocol::models::WebSearchAction` | 搜索动作枚举 |

### 调用方

- UI 模块：显示搜索操作描述
- 日志模块：记录搜索操作
- 遥测模块：发送搜索指标

## 依赖与外部交互

### 协议依赖

```rust
use codex_protocol::models::WebSearchAction;
```

- 依赖 `codex_protocol` crate
- 使用其定义的 `WebSearchAction` 类型

### 无外部系统交互

该模块是纯函数式，无 I/O 操作：
- 无网络调用
- 无文件操作
- 无数据库访问

## 风险、边界与改进建议

### 风险点

1. **描述截断**
   - Search 动作多 query 时只显示第一个
   - 用户可能不知道还有其他 query

2. **URL 长度**
   - OpenPage 直接使用完整 URL
   - 长 URL 可能影响 UI 显示

3. **特殊字符**
   - FindInPage 的 pattern 直接嵌入描述
   - 可能包含引号等特殊字符

### 边界情况

1. **空 query**
   - `query` 为 `Some("")` 时视为空
   - 回退到 `queries`

2. **空 queries 列表**
   - `queries` 为 `Some([])` 时
   - `first()` 返回 `None`，结果为 `""`

3. **Both None**
   - `query` 和 `queries` 都为 `None`
   - 结果为 `""`

4. **FindInPage 部分信息**
   - 只有 pattern：显示 `'pattern'`
   - 只有 url：显示 url
   - 都没有：空字符串

### 改进建议

1. **添加长度限制**
```rust
const MAX_DETAIL_LENGTH: usize = 100;

fn truncate(s: String) -> String {
    if s.len() > MAX_DETAIL_LENGTH {
        format!("{}...", &s[..MAX_DETAIL_LENGTH-3])
    } else {
        s
    }
}
```

2. **特殊字符转义**
```rust
fn escape_pattern(s: &str) -> String {
    s.replace('\\', "\\\\").replace('\'', "\\'")
}
```

3. **显示 query 数量**
```rust
if items.is_some_and(|queries| queries.len() > 1) && !first.is_empty() {
    format!("{first} ... ({} more)", queries.len() - 1)
}
```

4. **添加测试**
   - 当前模块无测试文件
   - 建议添加边界情况测试

### 测试建议

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_uses_query_when_available() {
        let action = WebSearchAction::Search {
            query: Some("test".to_string()),
            queries: Some(vec!["other".to_string()]),
        };
        assert_eq!(web_search_action_detail(&action), "test");
    }

    #[test]
    fn search_uses_first_query_when_query_empty() {
        let action = WebSearchAction::Search {
            query: Some("".to_string()),
            queries: Some(vec!["first".to_string(), "second".to_string()]),
        };
        assert_eq!(web_search_action_detail(&action), "first ...");
    }

    #[test]
    fn find_in_page_formats_correctly() {
        let action = WebSearchAction::FindInPage {
            url: Some("https://example.com".to_string()),
            pattern: Some("search term".to_string()),
        };
        assert_eq!(web_search_action_detail(&action), "'search term' in https://example.com");
    }

    #[test]
    fn detail_falls_back_to_query() {
        assert_eq!(web_search_detail(None, "fallback"), "fallback");
        assert_eq!(web_search_detail(Some(&WebSearchAction::Other), "fallback"), "fallback");
    }
}
```

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 简洁性 | 高 | 代码简洁，易于理解 |
| 功能性 | 中 | 功能简单，但足够使用 |
| 可测试性 | 高 | 纯函数，易于测试 |
| 文档 | 低 | 无文档注释 |
| 测试覆盖 | 低 | 无测试 |
