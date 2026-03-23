# mcp.rs 研究文档

## 场景与职责

`mcp.rs` 是 Codex 协议层中负责 **Model Context Protocol (MCP)** 类型定义的核心模块。MCP 是 Codex 与外部工具和资源交互的标准协议，该模块提供了：

1. **MCP 核心类型** - 工具、资源、请求 ID 等的协议定义
2. **适配器辅助** - 将 MCP JSON 数据转换为 TS/JsonSchema 友好的类型
3. **序列化兼容** - 处理不同命名约定（camelCase/snake_case）的字段映射
4. **类型安全** - 确保 MCP 数据在 Codex 内部的类型安全使用

在 Codex 的整体架构中，该模块：
- 作为 MCP 协议的 Rust 类型表示
- 被 `codex-core` 的 MCP 连接管理器和工具调用逻辑使用
- 支持从 `rmcp` crate 的模型结构序列化后的数据转换
- 生成 TypeScript 类型供前端使用

## 功能点目的

### RequestId 枚举

MCP 请求标识符，支持字符串或整数：
```rust
pub enum RequestId {
    String(String),
    Integer(i64),
}
```

**设计说明**: MCP 规范允许请求 ID 为字符串或整数，此枚举确保类型安全处理。

### Tool 结构体

MCP 工具定义：
```rust
pub struct Tool {
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub input_schema: serde_json::Value,
    pub output_schema: Option<serde_json::Value>,
    pub annotations: Option<serde_json::Value>,
    pub icons: Option<Vec<serde_json::Value>>,
    pub meta: Option<serde_json::Value>,
}
```

### Resource 结构体

MCP 资源定义：
```rust
pub struct Resource {
    pub annotations: Option<serde_json::Value>,
    pub description: Option<String>,
    pub mime_type: Option<String>,
    pub name: String,
    pub size: Option<i64>,
    pub title: Option<String>,
    pub uri: String,
    pub icons: Option<Vec<serde_json::Value>>,
    pub meta: Option<serde_json::Value>,
}
```

### ResourceTemplate 结构体

MCP 资源模板：
```rust
pub struct ResourceTemplate {
    pub annotations: Option<serde_json::Value>,
    pub uri_template: String,
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub mime_type: Option<String>,
}
```

### CallToolResult 结构体

工具调用结果：
```rust
pub struct CallToolResult {
    pub content: Vec<serde_json::Value>,
    pub structured_content: Option<serde_json::Value>,
    pub is_error: Option<bool>,
    pub meta: Option<serde_json::Value>,
}
```

## 具体技术实现

### 适配器模式

模块实现了从 MCP "wire-shaped" JSON 到协议类型的转换，避免直接依赖 `mcp-types` crate：

```rust
// 内部反序列化结构（支持多种命名约定）
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ToolSerde {
    name: String,
    #[serde(default)]
    title: Option<String>,
    #[serde(default, rename = "inputSchema", alias = "input_schema")]
    input_schema: serde_json::Value,
    // ...
}

// 转换为公共类型
impl From<ToolSerde> for Tool {
    fn from(value: ToolSerde) -> Self { ... }
}
```

### 字段别名处理

支持多种命名约定的字段映射：
```rust
#[serde(default, rename = "inputSchema", alias = "input_schema")]
input_schema: serde_json::Value,
```

这允许接受：
- `{"inputSchema": {...}}`（标准 MCP）
- `{"input_schema": {...}}`（snake_case 风格）

### 大小字段的安全反序列化

`Resource` 的 `size` 字段使用自定义反序列化处理大数值：

```rust
fn deserialize_lossy_opt_i64<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    match Option::<serde_json::Number>::deserialize(deserializer)? {
        Some(number) => {
            if let Some(v) = number.as_i64() {
                Ok(Some(v))
            } else if let Some(v) = number.as_u64() {
                Ok(i64::try_from(v).ok()) // u64 -> i64 转换
            } else {
                Ok(None) // f64 无法表示，返回 None
            }
        }
        None => Ok(None),
    }
}
```

**设计原因**: JavaScript 数字为双精度浮点，大整数可能以 u64 形式传输，需要安全转换为 i64。

### 工厂方法

提供从 JSON Value 构造类型的便捷方法：
```rust
impl Tool {
    pub fn from_mcp_value(value: serde_json::Value) -> Result<Self, serde_json::Error> {
        Ok(serde_json::from_value::<ToolSerde>(value)?.into())
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
```
codex-rs/protocol/src/mcp.rs
```

### 被引用位置
通过 `lib.rs` 导出：
```rust
// codex-rs/protocol/src/lib.rs
pub mod mcp;
```

在 `protocol.rs` 中导入：
```rust
use crate::mcp::CallToolResult;
use crate::mcp::RequestId;
use crate::mcp::Resource as McpResource;
use crate::mcp::ResourceTemplate as McpResourceTemplate;
use crate::mcp::Tool as McpTool;
```

在 `models.rs` 中导入：
```rust
use crate::mcp::CallToolResult;
```

在 `approvals.rs` 中导入：
```rust
use crate::mcp::RequestId;
```

### 跨 crate 使用场景
- **MCP 连接管理**: `codex-core/src/mcp_connection_manager.rs`
- **工具调用**: `codex-core/src/mcp_tool_call.rs`
- **工具路由**: `codex-core/src/tools/handlers/mcp.rs`
- **Codex Apps**: `codex-core/src/apps/render.rs`

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型绑定 |

### 内部依赖
无直接内部依赖。

### 相关协议
- **MCP Specification**: Model Context Protocol 规范
- **JSON-RPC 2.0**: MCP 基于 JSON-RPC 2.0 传输

## 风险、边界与改进建议

### 当前风险

1. **大数值处理**: `size` 字段的 `i64` 类型可能溢出（虽然使用 `deserialize_lossy_opt_i64` 缓解）
2. **灵活 JSON 值**: 多个字段使用 `serde_json::Value`，运行时才能验证结构
3. **命名约定复杂性**: 支持多种命名约定增加了维护负担

### 边界情况

1. **size 溢出**: 大于 `i64::MAX` 的值会被转换为 `None`
2. **负数 size**: 允许负数，但语义上可能不合理
3. **空字符串**: `name` 和 `uri` 为空字符串的处理

### 测试覆盖

当前文件包含 1 个单元测试：

**`resource_size_deserializes_without_narrowing`**
- 验证 5_000_000_000u64 正确解析为 `Some(5_000_000_000)`
- 验证 -1 正确解析为 `Some(-1)`
- 验证超大值（u64::MAX）解析为 `None`

### 改进建议

1. **强类型 Schema**: 考虑为 `input_schema` 使用强类型
   ```rust
   pub struct JsonSchema {
       schema: serde_json::Value,
   }
   impl JsonSchema {
       pub fn validate(&self, value: &serde_json::Value) -> Result<(), ValidationError> { ... }
   }
   ```

2. **size 类型优化**: 考虑使用 `u64` 并添加自定义序列化
   ```rust
   #[serde(with = "serde_u64_as_string")]
   pub size: Option<u64>,
   ```

3. **验证逻辑**: 添加结构验证
   ```rust
   impl Tool {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.name.is_empty() {
               return Err(ValidationError::EmptyName);
           }
           // 验证 input_schema 是有效的 JSON Schema
           Ok(())
       }
   }
   ```

4. **Builder 模式**: 为复杂结构添加 Builder

5. **文档完善**: 添加 MCP 规范链接和字段说明

### 架构建议

1. **MCP 版本支持**: 考虑添加 MCP 协议版本字段
2. **扩展性**: 预留扩展字段以支持未来 MCP 规范更新
3. **类型生成**: 考虑从 MCP 规范自动生成类型定义
