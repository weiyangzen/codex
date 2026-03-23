# dynamic_tools.rs 研究文档

## 场景与职责

`dynamic_tools.rs` 是 Codex 协议层中负责**动态工具（Dynamic Tools）**功能的核心类型定义模块。动态工具是一种允许在运行时动态注册和调用的工具机制，区别于静态编译时确定的工具。

在 Codex 的整体架构中，该模块：
- 定义动态工具的规格（specification）结构
- 定义工具调用请求和响应的数据格式
- 支持工具调用的延迟加载（defer loading）配置
- 处理向后兼容的字段映射（`expose_to_context` → `defer_loading`）

动态工具主要用于：
- 插件系统 - 允许第三方扩展 Codex 功能
- 运行时工具发现 - 根据上下文动态可用工具
- 性能优化 - 延迟加载不常用的工具定义

## 功能点目的

### DynamicToolSpec 结构体

定义动态工具的规格信息：
```rust
pub struct DynamicToolSpec {
    pub name: String,              // 工具名称
    pub description: String,       // 工具描述
    pub input_schema: JsonValue,   // 输入参数 JSON Schema
    #[serde(default)]
    pub defer_loading: bool,       // 是否延迟加载
}
```

**延迟加载（defer_loading）**: 当为 `true` 时，工具定义不会立即加载到上下文中，而是在实际需要时才加载，用于优化性能和上下文大小。

### DynamicToolCallRequest 结构体

动态工具调用的请求格式：
```rust
pub struct DynamicToolCallRequest {
    pub call_id: String,           // 调用唯一标识
    pub turn_id: String,           // 所属对话轮次
    pub tool: String,              // 工具名称
    pub arguments: JsonValue,      // 调用参数
}
```

### DynamicToolResponse 结构体

动态工具调用的响应格式：
```rust
pub struct DynamicToolResponse {
    pub content_items: Vec<DynamicToolCallOutputContentItem>, // 输出内容项
    pub success: bool,                                          // 调用是否成功
}
```

### DynamicToolCallOutputContentItem 枚举

工具输出的内容项类型：
```rust
pub enum DynamicToolCallOutputContentItem {
    InputText { text: String },       // 文本输出
    InputImage { image_url: String }, // 图片输出（URL）
}
```

## 具体技术实现

### 向后兼容的自定义反序列化

`DynamicToolSpec` 实现了自定义的 `Deserialize`，处理遗留字段 `expose_to_context` 到 `defer_loading` 的映射：

```rust
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DynamicToolSpecDe {
    name: String,
    description: String,
    input_schema: JsonValue,
    defer_loading: Option<bool>,
    expose_to_context: Option<bool>, // 遗留字段
}

impl<'de> Deserialize<'de> for DynamicToolSpec {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let DynamicToolSpecDe { ... } = DynamicToolSpecDe::deserialize(deserializer)?;

        Ok(Self {
            name,
            description,
            input_schema,
            defer_loading: defer_loading
                .unwrap_or_else(|| expose_to_context.map(|visible| !visible).unwrap_or(false)),
        })
    }
}
```

**映射逻辑：**
- 优先使用 `defer_loading`（如果存在）
- 否则使用 `expose_to_context` 的反转值（`!visible`）
- 默认为 `false`

### 序列化约定

- 使用 `camelCase` 命名（`rename_all = "camelCase"`）
- 枚举使用标签字段 `type` 进行区分（`#[serde(tag = "type")]`）
- TypeScript 类型生成保持一致的命名约定

## 关键代码路径与文件引用

### 本文件位置
```
codex-rs/protocol/src/dynamic_tools.rs
```

### 被引用位置
通过 `lib.rs` 导出：
```rust
// codex-rs/protocol/src/lib.rs
pub mod dynamic_tools;
```

在 `protocol.rs` 中导入并重新导出：
```rust
use crate::dynamic_tools::DynamicToolCallOutputContentItem;
use crate::dynamic_tools::DynamicToolCallRequest;
use crate::dynamic_tools::DynamicToolResponse;
use crate::dynamic_tools::DynamicToolSpec;
```

### 跨 crate 使用场景
- **工具注册**: `codex-core` 中的工具注册和管理
- **工具调用**: 处理动态工具的调用请求和响应
- **协议转换**: 在内部表示和 API 格式之间转换

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 值类型 |
| `ts-rs` | TypeScript 类型绑定 |

### 内部依赖
无直接内部依赖。

## 风险、边界与改进建议

### 当前风险

1. **向后兼容复杂性**: 自定义反序列化逻辑增加了维护负担
2. **字段命名不一致**: `expose_to_context` 和 `defer_loading` 语义相反但容易混淆
3. **JSON Schema 验证**: `input_schema` 为 `JsonValue`，运行时才能验证有效性

### 边界情况

1. **defer_loading 默认值**: 当两个字段都缺失时，默认为 `false`
2. **空参数**: `arguments` 为空对象 `{}` 的处理
3. **失败响应**: `success = false` 时的错误信息传递

### 测试覆盖

当前文件包含 2 个单元测试：

1. **`dynamic_tool_spec_deserializes_defer_loading`**
   - 验证 `deferLoading: true` 正确解析

2. **`dynamic_tool_spec_legacy_expose_to_context_inverts_to_defer_loading`**
   - 验证遗留字段 `exposeToContext: false` 映射为 `defer_loading: true`

### 改进建议

1. **移除遗留字段支持**: 在适当的时候移除 `expose_to_context` 支持，简化代码
   ```rust
   // TODO: 在 v2.0 中移除
   #[deprecated(since = "1.5", note = "Use defer_loading instead")]
   ```

2. **类型安全增强**: 考虑为 `input_schema` 使用强类型
   ```rust
   pub struct JsonSchema(serde_json::Value);
   impl JsonSchema {
       pub fn validate(&self, value: &JsonValue) -> Result<(), ValidationError> {
           // 验证逻辑
       }
   }
   ```

3. **错误信息**: 在 `DynamicToolResponse` 中添加错误详情字段
   ```rust
   pub struct DynamicToolResponse {
       pub content_items: Vec<DynamicToolCallOutputContentItem>,
       pub success: bool,
       pub error: Option<String>, // 新增
   }
   ```

4. **Builder 模式**: 为复杂结构添加 Builder
   ```rust
   let spec = DynamicToolSpec::builder()
       .name("search")
       .description("Search tool")
       .input_schema(schema)
       .defer_loading(true)
       .build();
   ```

5. **文档完善**: 添加更多使用示例和最佳实践

### 架构建议

1. **工具版本控制**: 考虑添加工具版本字段，支持工具演进
2. **工具依赖声明**: 支持声明工具之间的依赖关系
3. **工具权限**: 添加工具所需的权限声明
