# Research: experimental_api.rs

## 文件信息

- **文件路径**: `codex-rs/app-server-protocol/src/experimental_api.rs`
- **所属 Crate**: `codex-app-server-protocol`
- **代码行数**: 172 行（含测试）
- **核心定位**: 实验性 API 能力声明与运行时门控机制

---

## 1. 场景与职责

### 1.1 业务场景

`experimental_api.rs` 是 Codex App Server Protocol 中负责**实验性功能门控**的核心模块。在现代 API 设计中，新功能往往需要经过 Beta 测试阶段才能稳定发布，该模块提供了以下能力：

1. **客户端能力协商**: 在 `initialize` 阶段，客户端声明是否支持实验性 API (`experimental_api: true/false`)
2. **方法级门控**: 整个 API 方法被标记为实验性（如 `thread/realtime/start`）
3. **字段级门控**: 某个请求/响应中的特定字段是实验性的（如 `ThreadStartParams.dynamic_tools`）
4. **枚举变体门控**: 枚举的特定变体是实验性的（如 `AskForApproval::Granular`）

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **标记定义** | 提供 `#[experimental("reason")]` 属性标记 |
| **能力检测** | 通过 `ExperimentalApi` trait 检测是否使用了实验性功能 |
| **错误生成** | 提供统一的错误消息格式：`{reason} requires experimentalApi capability` |
| **注册表维护** | 使用 `inventory` crate 收集所有实验性字段元数据 |
| **集合类型支持** | 为 `Option<T>`, `Vec<T>`, `HashMap<K,V>`, `BTreeMap<K,V>` 提供代理实现 |

---

## 2. 功能点目的

### 2.1 功能点清单

| 功能点 | 目的 | 使用场景 |
|--------|------|----------|
| `ExperimentalApi` trait | 统一的能力检测接口 | 所有需要门控的类型实现此 trait |
| `ExperimentalField` struct | 描述实验性字段的元数据 | 用于 schema 生成时过滤实验性字段 |
| `#[experimental(...)]` 属性 | 声明式标记实验性 API | 通过过程宏自动实现 trait |
| `experimental_fields()` | 获取所有注册的实验性字段 | TypeScript/JSON Schema 生成时使用 |
| `experimental_required_message()` | 统一错误消息格式 | 拒绝非实验性客户端调用时 |

### 2.2 设计哲学

```rust
// 核心理念：编译时标记 + 运行时检测
// 1. 编译时：通过过程宏收集所有实验性标记
// 2. 运行时：检查 session.experimental_api_enabled 决定是否放行
```

这种设计允许：
- **渐进式发布**: 新功能先标记为实验性，稳定后移除标记
- **客户端控制**: 客户端明确选择加入实验性功能
- **文档生成**: 自动生成包含/排除实验性功能的 schema

---

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
/// Marker trait for protocol types that can signal experimental usage.
pub trait ExperimentalApi {
    /// Returns a short reason identifier when an experimental method or field is
    /// used, or `None` when the value is entirely stable.
    fn experimental_reason(&self) -> Option<&'static str>;
}

/// Describes an experimental field on a specific type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExperimentalField {
    pub type_name: &'static str,
    pub field_name: &'static str,
    /// Stable identifier returned when this field is used.
    /// Convention: `<method>` for method-level gates or `<method>.<field>` for
    /// field-level gates.
    pub reason: &'static str,
}
```

### 3.2 关键流程

#### 3.2.1 请求处理流程（运行时门控）

```
Client Request
    ↓
JSON-RPC 解析 → ClientRequest
    ↓
检查 session.initialized
    ↓
【关键门控点】
if let Some(reason) = codex_request.experimental_reason()
    && !session.experimental_api_enabled
{
    返回错误: "{reason} requires experimentalApi capability"
}
    ↓
路由到具体处理器
```

代码位置：`codex-rs/app-server/src/message_processor.rs:616-626`

```rust
if let Some(reason) = codex_request.experimental_reason()
    && !session.experimental_api_enabled
{
    let error = JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: experimental_required_message(reason),
        data: None,
    };
    self.outgoing.send_error(connection_request_id, error).await;
    return;
}
```

#### 3.2.2 过程宏展开流程（编译时标记）

通过 `codex-experimental-api-macros` crate 中的 `#[derive(ExperimentalApi)]` 实现：

```rust
// 输入代码
#[derive(ExperimentalApi)]
struct ThreadStartParams {
    pub model: Option<String>,
    #[experimental("thread/start.dynamicTools")]
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
}

// 展开后（简化）
impl ExperimentalApi for ThreadStartParams {
    fn experimental_reason(&self) -> Option<&'static str> {
        if self.dynamic_tools.as_ref().is_some_and(|v| !v.is_empty()) {
            return Some("thread/start.dynamicTools");
        }
        None
    }
}

// 同时注册字段元数据
::inventory::submit! {
    ExperimentalField {
        type_name: "ThreadStartParams",
        field_name: "dynamicTools",
        reason: "thread/start.dynamicTools",
    }
}
```

### 3.3 协议/命令

#### 3.3.1 能力声明协议

客户端在 `initialize` 时声明能力：

```json
{
  "method": "initialize",
  "params": {
    "clientInfo": { "name": "vscode", "version": "1.0" },
    "capabilities": {
      "experimentalApi": true,
      "optOutNotificationMethods": ["thread/started"]
    }
  }
}
```

#### 3.3.2 错误响应格式

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "error": {
    "code": -32600,
    "message": "thread/realtime/start requires experimentalApi capability"
  }
}
```

### 3.4 集合类型代理实现

```rust
impl<T: ExperimentalApi> ExperimentalApi for Option<T> {
    fn experimental_reason(&self) -> Option<&'static str> {
        self.as_ref().and_then(ExperimentalApi::experimental_reason)
    }
}

impl<T: ExperimentalApi> ExperimentalApi for Vec<T> {
    fn experimental_reason(&self) -> Option<&'static str> {
        self.iter().find_map(ExperimentalApi::experimental_reason)
    }
}

impl<K, V: ExperimentalApi, S> ExperimentalApi for HashMap<K, V, S> {
    fn experimental_reason(&self) -> Option<&'static str> {
        self.values().find_map(ExperimentalApi::experimental_reason)
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 当前文件结构

```
codex-rs/app-server-protocol/src/experimental_api.rs
├── trait ExperimentalApi (行 5-9)
├── struct ExperimentalField (行 12-20)
├── inventory::collect! 宏调用 (行 22)
├── experimental_fields() 函数 (行 25-27)
├── experimental_required_message() 函数 (行 30-32)
├── 集合类型代理实现 (行 34-56)
└── 单元测试 (行 58-172)
```

### 4.2 调用方（被谁使用）

| 文件 | 使用方式 | 目的 |
|------|----------|------|
| `app-server/src/message_processor.rs:616` | `codex_request.experimental_reason()` | 运行时门控检查 |
| `app-server-protocol/src/protocol/common.rs:133-148` | `impl ExperimentalApi for ClientRequest` | 请求类型统一实现 |
| `app-server-protocol/src/protocol/v2.rs` | `#[derive(ExperimentalApi)]` | 参数/响应类型标记 |
| `app-server-protocol/src/export.rs:247` | `experimental_fields()` | TypeScript 生成过滤 |
| `app-server-protocol/src/export.rs:401` | `experimental_fields()` | JSON Schema 过滤 |

### 4.3 被调用方（依赖谁）

| 依赖 | 用途 |
|------|------|
| `inventory` crate | 全局注册表收集实验性字段 |
| `codex-experimental-api-macros` | `#[derive(ExperimentalApi)]` 过程宏 |

### 4.4 关键类型实现示例

**AskForApproval 枚举**（`protocol/v2.rs:201-223`）：

```rust
#[derive(..., ExperimentalApi)]
#[serde(rename_all = "kebab-case")]
pub enum AskForApproval {
    UnlessTrusted,
    OnFailure,
    OnRequest,
    #[experimental("askForApproval.granular")]
    Granular { sandbox_approval: bool, ... },
    Never,
}
```

**ThreadStartParams 结构体**（`protocol/v2.rs:2449-2508`）：

```rust
#[derive(..., ExperimentalApi)]
pub struct ThreadStartParams {
    pub model: Option<String>,
    // ... 稳定字段 ...
    #[experimental("thread/start.dynamicTools")]
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
    #[experimental("thread/start.mockExperimentalField")]
    pub mock_experimental_field: Option<String>,
}
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

```toml
# codex-rs/app-server-protocol/Cargo.toml (推断)
[dependencies]
inventory = "0.3"
codex-experimental-api-macros = { path = "../codex-experimental-api-macros" }
```

### 5.2 与过程宏的交互

`codex-experimental-api-macros/src/lib.rs` 提供：

1. **结构体字段检测**: 扫描 `#[experimental("reason")]` 属性
2. **枚举变体检测**: 支持 Unit、Tuple、Named 三种变体形状
3. **嵌套标记支持**: `#[experimental(nested)]` 用于递归检查
4. **字段名转换**: 自动将 `snake_case` 转换为 `camelCase`

### 5.3 与 Schema 生成的交互

```
生成 TypeScript/JSON Schema
    ↓
读取 experimental_fields() 获取所有实验性字段
    ↓
过滤 ClientRequest.ts 中的实验性方法
    ↓
过滤各类型中的实验性字段
    ↓
生成稳定的公共 Schema
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **跨客户端行为不一致** | 连接 A 启用实验性 API，连接 B 未启用，共享线程时行为不一致 | 文档明确说明；考虑实例级全局配置 |
| **inventory 编译开销** | 使用 `inventory` crate 可能增加编译时间 | 仅在 protocol crate 中使用，影响有限 |
| **字段名转换错误** | `snake_to_camel` 手动实现，可能遗漏边界情况 | 测试覆盖常见命名模式 |

### 6.2 边界情况

1. **空集合**: `Vec::new()` 和空 `HashMap` 不会触发实验性检测（符合预期）
2. **嵌套 Option**: `Option<Option<T>>` 正确处理，只检查最内层值
3. **布尔字段**: 仅当值为 `true` 时触发实验性检测

### 6.3 改进建议

#### 6.3.1 架构层面

```rust
// 建议：实例级全局配置替代连接级配置
pub struct ExperimentalApiConfig {
    // 当前：每个连接独立
    per_connection: bool,
    // 建议：实例级首写获胜
    instance_global: bool,
}
```

#### 6.3.2 代码层面

1. **增强测试覆盖**: 添加更多边界情况测试（如复杂嵌套结构）
2. **文档生成**: 自动生成实验性 API 文档页面
3. **遥测**: 记录实验性 API 使用频率，指导功能稳定化决策

#### 6.3.3 监控建议

```rust
// 在门控点添加指标
if let Some(reason) = codex_request.experimental_reason() {
    metrics::counter!("experimental_api.usage", "reason" => reason).increment(1);
    if !session.experimental_api_enabled {
        metrics::counter!("experimental_api.rejected", "reason" => reason).increment(1);
        // ... 返回错误 ...
    }
}
```

### 6.4 相关测试

| 测试文件 | 测试内容 |
|----------|----------|
| `app-server/tests/suite/v2/experimental_api.rs` | 集成测试：验证实验性 API 门控行为 |
| `app-server-protocol/src/experimental_api.rs:101-171` | 单元测试：derive 宏各种情况 |
| `app-server-protocol/src/protocol/common.rs:1609-1718` | 单元测试：具体类型的实验性标记验证 |

---

## 7. 总结

`experimental_api.rs` 是 Codex App Server Protocol 中**实验性功能管理**的基石模块。它通过编译时标记（过程宏）和运行时检测（trait 方法）的结合，实现了：

1. **清晰的能力边界**: 客户端必须显式选择加入实验性功能
2. **灵活的粒度控制**: 支持方法级、字段级、枚举变体级门控
3. **自动化文档生成**: 实验性标记自动反映在 TypeScript/JSON Schema 中
4. **一致的开发体验**: 统一的错误消息和检测模式

该模块的设计体现了现代 API 演进的最佳实践：**渐进式发布**与**显式能力协商**。
