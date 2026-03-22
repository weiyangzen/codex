# InitializeCapabilities Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`InitializeCapabilities` 是 App-Server Protocol 中用于客户端能力协商的核心类型。在初始化连接时，客户端通过该类型声明其支持的功能和偏好设置。

主要使用场景：
- **连接初始化**：客户端与服务器建立连接时的能力协商
- **实验性功能**：客户端选择是否接收实验性 API
- **通知控制**：客户端选择退订特定通知类型

## 2. 功能点目的 (Purpose of This Type)

- **能力声明**：客户端声明其实验性 API 支持
- **通知过滤**：允许客户端减少不需要的通知流量
- **版本协商**：为未来版本兼容性提供扩展点
- **功能发现**：服务器了解客户端能力以调整行为

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type InitializeCapabilities = {
  /**
   * Opt into receiving experimental API methods and fields.
   */
  experimentalApi: boolean,
  /**
   * Exact notification method names that should be suppressed for this
   * connection (for example `thread/started`).
   */
  optOutNotificationMethods?: Array<string> | null,
};
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct InitializeCapabilities {
    /// Opt into receiving experimental API methods and fields.
    #[serde(default)]
    pub experimental_api: bool,
    /// Exact notification method names that should be suppressed for this
    /// connection (for example `thread/started`).
    #[ts(optional = nullable)]
    pub opt_out_notification_methods: Option<Vec<String>>,
}
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `experimental_api` | `boolean` | `false` | 是否接收实验性 API 方法和字段 |
| `opt_out_notification_methods` | `string[] \| null` | `null` | 要抑制的通知方法名列表 |

### 关键特性

- **Default 派生**：提供合理的默认值（实验性功能关闭，无通知过滤）
- **可选字段**：`opt_out_notification_methods` 使用 `#[ts(optional = nullable)]`
- **serde 默认值**：`experimental_api` 使用 `#[serde(default)]`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 42-53) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/InitializeCapabilities.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 206-209) | Initialize 请求注册 |

### 使用位置

```rust
// 在 InitializeParams 中使用
pub struct InitializeParams {
    pub client_info: ClientInfo,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<InitializeCapabilities>,
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 相关类型

- `InitializeParams`：包含 capabilities 的初始化参数
- `InitializeResponse`：服务器返回的初始化响应
- `ClientInfo`：客户端信息

### 使用示例

```rust
// 构造 capabilities
let capabilities = InitializeCapabilities {
    experimental_api: true,  // 启用实验性功能
    opt_out_notification_methods: Some(vec![
        "thread/started".to_string(),
    ]),
};

let params = InitializeParams {
    client_info: ClientInfo {
        name: "codex_vscode".to_string(),
        title: Some("Codex VSCode".to_string()),
        version: "1.0.0".to_string(),
    },
    capabilities: Some(capabilities),
};
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **实验性功能稳定性**：启用 `experimental_api` 可能遇到不稳定的 API
2. **通知过滤影响**：退订通知可能导致客户端状态不一致
3. **版本兼容性**：未来添加新能力字段时需要向后兼容

### 改进建议

1. **添加版本字段**：明确声明客户端支持的协议版本
   ```rust
   pub protocol_version: Option<String>,
   ```

2. **细粒度实验性功能**：支持按功能启用实验性 API
   ```rust
   pub experimental_features: Option<Vec<String>>,
   ```

3. **通知订阅模式**：支持白名单模式（只接收指定通知）
   ```rust
   pub opt_in_notification_methods: Option<Vec<String>>,
   ```

4. **能力协商响应**：服务器返回实际启用的能力

### 测试建议

- 测试默认值的正确性
- 测试实验性 API 的启用/禁用
- 测试通知过滤功能
- 验证序列化/反序列化

### 安全考虑

- 实验性功能可能包含安全漏洞，需要明确警告用户
- 通知过滤不应影响关键安全通知
