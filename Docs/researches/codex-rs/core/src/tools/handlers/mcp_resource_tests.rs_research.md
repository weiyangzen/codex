# mcp_resource_tests.rs 研究文档

## 场景与职责

`mcp_resource_tests.rs` 是 `mcp_resource.rs` 的配套测试模块，负责验证 MCP 资源管理相关的数据结构和辅助函数。该测试模块专注于单元测试，测试范围包括：

- 数据结构序列化/反序列化
- 响应 payload 构建逻辑
- 参数解析辅助函数
- 结果转换函数

**注意：** 该测试模块不包含集成测试（如实际的 MCP 服务器调用），主要测试纯逻辑函数。

## 功能点目的

### 1. 数据结构序列化测试

**`ResourceWithServer` 序列化：**
- 验证 `server` 字段正确包含在序列化输出中
- 验证资源字段（`uri`, `name`）正确扁平化

**`ResourceTemplateWithServer` 序列化：**
- 验证模板与服务器信息的组合序列化

### 2. Payload 构建测试

**`ListResourcesPayload::from_single_server`：**
- 验证单服务器响应正确包装
- 验证 `next_cursor` 正确传递

**`ListResourcesPayload::from_all_servers`：**
- 验证多服务器结果按服务器名称排序
- 验证资源正确聚合

### 3. 辅助函数测试

**`call_tool_result_from_content`：**
- 验证成功状态正确转换为 `is_error: Some(false)`
- 验证内容格式

**`parse_arguments`：**
- 验证空字符串返回 `None`
- 验证空白字符（空格、换行、制表符）返回 `None`
- 验证 `"null"` JSON 返回 `None`
- 验证有效 JSON 正确解析

## 具体技术实现

### 测试辅助函数

```rust
// 创建测试用的 Resource
fn resource(uri: &str, name: &str) -> Resource {
    rmcp::model::RawResource {
        uri: uri.to_string(),
        name: name.to_string(),
        title: None,
        description: None,
        mime_type: None,
        size: None,
        icons: None,
        meta: None,
    }
    .no_annotation()  // 移除注解，简化测试
}

// 创建测试用的 ResourceTemplate
fn template(uri_template: &str, name: &str) -> ResourceTemplate {
    rmcp::model::RawResourceTemplate {
        uri_template: uri_template.to_string(),
        name: name.to_string(),
        title: None,
        description: None,
        mime_type: None,
        icons: None,
    }
    .no_annotation()
}
```

### 测试用例详解

**1. 资源序列化测试**
```rust
#[test]
fn resource_with_server_serializes_server_field() {
    let entry = ResourceWithServer::new("test".to_string(), resource("memo://id", "memo"));
    let value = serde_json::to_value(&entry).expect("serialize resource");

    assert_eq!(value["server"], json!("test"));
    assert_eq!(value["uri"], json!("memo://id"));
    assert_eq!(value["name"], json!("memo"));
}
```

**2. 单服务器 payload 测试**
```rust
#[test]
fn list_resources_payload_from_single_server_copies_next_cursor() {
    let result = ListResourcesResult {
        meta: None,
        next_cursor: Some("cursor-1".to_string()),
        resources: vec![resource("memo://id", "memo")],
    };
    let payload = ListResourcesPayload::from_single_server("srv".to_string(), result);
    let value = serde_json::to_value(&payload).expect("serialize payload");

    assert_eq!(value["server"], json!("srv"));
    assert_eq!(value["nextCursor"], json!("cursor-1"));
    let resources = value["resources"].as_array().expect("resources array");
    assert_eq!(resources.len(), 1);
    assert_eq!(resources[0]["server"], json!("srv"));
}
```

**3. 多服务器排序测试**
```rust
#[test]
fn list_resources_payload_from_all_servers_is_sorted() {
    let mut map = HashMap::new();
    map.insert("beta".to_string(), vec![resource("memo://b-1", "b-1")]);
    map.insert("alpha".to_string(), vec![
        resource("memo://a-1", "a-1"),
        resource("memo://a-2", "a-2"),
    ]);

    let payload = ListResourcesPayload::from_all_servers(map);
    let value = serde_json::to_value(&payload).expect("serialize payload");
    let uris: Vec<String> = value["resources"]
        .as_array().expect("resources array")
        .iter()
        .map(|entry| entry["uri"].as_str().unwrap().to_string())
        .collect();

    // 验证按服务器名称字母顺序排序
    assert_eq!(uris, vec!["memo://a-1", "memo://a-2", "memo://b-1"]);
}
```

**4. 结果转换测试**
```rust
#[test]
fn call_tool_result_from_content_marks_success() {
    let result = call_tool_result_from_content("{}", Some(true));
    assert_eq!(result.is_error, Some(false));  // success=true -> is_error=false
    assert_eq!(result.content.len(), 1);
}
```

**5. 参数解析测试**
```rust
#[test]
fn parse_arguments_handles_empty_and_json() {
    // 纯空白字符 -> None
    assert!(parse_arguments(" \n\t").unwrap().is_none());
    
    // null JSON -> None
    assert!(parse_arguments("null").unwrap().is_none());
    
    // 有效 JSON -> Some(Value)
    let value = parse_arguments(r#"{"server":"figma"}"#)
        .expect("parse json")
        .expect("value present");
    assert_eq!(value["server"], json!("figma"));
}
```

**6. 模板序列化测试**
```rust
#[test]
fn template_with_server_serializes_server_field() {
    let entry = ResourceTemplateWithServer::new(
        "srv".to_string(),
        template("memo://{id}", "memo")
    );
    let value = serde_json::to_value(&entry).expect("serialize template");

    assert_eq!(value, json!({
        "server": "srv",
        "uriTemplate": "memo://{id}",
        "name": "memo"
    }));
}
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 导入 `mcp_resource.rs` 的所有导出内容 |
| `pretty_assertions::assert_eq` | 提供更好的 diff 输出 |
| `rmcp::model::AnnotateAble` | 创建无注解的测试资源 |
| `serde_json::json` | JSON 字面量构造 |

### 被测函数

测试直接调用 `mcp_resource.rs` 的内部函数：
```rust
// 被测函数（private，但 tests 模块可访问）
fn call_tool_result_from_content(content: &str, success: Option<bool>) -> CallToolResult
fn parse_arguments(raw_args: &str) -> Result<Option<Value>, FunctionCallError>

// 被测结构体方法
impl ResourceWithServer { fn new(...) -> Self }
impl ResourceTemplateWithServer { fn new(...) -> Self }
impl ListResourcesPayload { 
    fn from_single_server(...) -> Self 
    fn from_all_servers(...) -> Self
}
impl ListResourceTemplatesPayload { 
    fn from_single_server(...) -> Self 
    fn from_all_servers(...) -> Self
}
```

## 风险、边界与改进建议

### 当前测试覆盖情况

| 功能 | 覆盖状态 | 说明 |
|------|----------|------|
| ResourceWithServer 序列化 | ✅ | `resource_with_server_serializes_server_field` |
| ResourceTemplateWithServer 序列化 | ✅ | `template_with_server_serializes_server_field` |
| ListResourcesPayload 单服务器 | ✅ | `list_resources_payload_from_single_server_copies_next_cursor` |
| ListResourcesPayload 多服务器 | ✅ | `list_resources_payload_from_all_servers_is_sorted` |
| call_tool_result_from_content | ✅ | `call_tool_result_from_content_marks_success` |
| parse_arguments | ✅ | `parse_arguments_handles_empty_and_json` |

### 测试盲点

1. **缺少的测试场景：**
   - `handle_list_resources` 实际调用逻辑
   - `handle_list_resource_templates` 实际调用逻辑
   - `handle_read_resource` 实际调用逻辑
   - 事件发送（`emit_tool_call_begin/end`）
   - 错误处理路径
   - 字符串规范化（`normalize_optional_string`, `normalize_required_string`）

2. **集成测试缺失：**
   - 未测试与 `McpConnectionManager` 的集成
   - 未测试与 `Session` 的集成
   - 未测试实际的 MCP 服务器调用

3. **边界条件测试缺失：**
   - 空资源列表
   - 非常大的资源列表
   - 特殊字符在服务器名称中

### 改进建议

1. **添加错误场景测试**
```rust
#[test]
fn parse_arguments_rejects_invalid_json() {
    let result = parse_arguments("{invalid json}");
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), 
        FunctionCallError::RespondToModel(msg) if msg.contains("failed to parse")));
}

#[test]
fn normalize_optional_string_trims_whitespace() {
    assert_eq!(normalize_optional_string(Some("  test  ".to_string())), 
               Some("test".to_string()));
    assert_eq!(normalize_optional_string(Some("   ".to_string())), 
               None);
}

#[test]
fn normalize_required_string_rejects_empty() {
    let result = normalize_required_string("field_name", "   ".to_string());
    assert!(result.is_err());
}
```

2. **添加边界条件测试**
```rust
#[test]
fn list_resources_payload_handles_empty_map() {
    let map: HashMap<String, Vec<Resource>> = HashMap::new();
    let payload = ListResourcesPayload::from_all_servers(map);
    assert!(payload.resources.is_empty());
    assert!(payload.server.is_none());
}

#[test]
fn list_resources_payload_preserves_server_order() {
    // 测试服务器排序稳定性
}
```

3. **添加 mock 集成测试**
```rust
#[tokio::test]
async fn handle_list_resources_with_mock_session() {
    // 使用 mock Session 测试完整的 handler 流程
}
```

### 测试运行

```bash
# 运行所有 mcp_resource 测试
cargo test -p codex-core mcp_resource

# 运行特定测试
cargo test -p codex-core resource_with_server_serializes_server_field

# 查看测试输出
cargo test -p codex-core mcp_resource -- --nocapture
```

### 与主模块的集成

测试模块通过以下方式与主模块关联：
```rust
// mcp_resource.rs 末尾
#[cfg(test)]
#[path = "mcp_resource_tests.rs"]
mod tests;
```

这种组织方式：
- 保持主文件整洁
- 测试代码与实现代码分离
- 条件编译，仅在测试时包含
- 测试模块可以访问 private 函数和结构体
