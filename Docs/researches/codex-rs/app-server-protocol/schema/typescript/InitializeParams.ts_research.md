# InitializeParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`InitializeParams` 是 App-Server Protocol 中客户端初始化连接时发送的参数类型。它是客户端与服务器建立通信会话的第一步，用于交换基本信息和能力协商。

主要使用场景：
- **连接建立**：客户端启动时与服务器建立连接
- **身份声明**：客户端向服务器报告自身身份和版本
- **能力协商**：协商双方支持的协议特性和实验性功能
- **会话初始化**：为后续通信建立基础上下文

## 2. 功能点目的 (Purpose of This Type)

- **身份识别**：让服务器了解客户端类型和版本
- **功能协商**：协商实验性 API 和通知偏好
- **兼容性检查**：为版本兼容性提供基础
- **会话配置**：配置连接的基本参数

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
import type { ClientInfo } from "./ClientInfo";
import type { InitializeCapabilities } from "./InitializeCapabilities";

export type InitializeParams = {
  clientInfo: ClientInfo,
  capabilities: InitializeCapabilities | null,
};
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_info: ClientInfo,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<InitializeCapabilities>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ClientInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `client_info` | `ClientInfo` | 客户端基本信息（名称、标题、版本） |
| `capabilities` | `InitializeCapabilities \| null` | 客户端能力声明（可选） |

### ClientInfo 字段

| 字段 | 类型 | 说明 |
|-----|------|------|
| `name` | `string` | 客户端标识名（如 "codex_vscode"） |
| `title` | `string \| null` | 客户端显示标题（如 "Codex VSCode"） |
| `version` | `string` | 客户端版本号 |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 26-40) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/InitializeParams.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/schema/typescript/ClientInfo.ts` | ClientInfo TypeScript 定义 |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 206-209) | Initialize 请求注册 |

### 相关类型

- `InitializeResponse`：服务器返回的初始化响应
- `InitializeCapabilities`：客户端能力声明
- `ClientInfo`：客户端基本信息

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `ClientInfo`：客户端信息结构
- `InitializeCapabilities`：能力声明结构
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 使用流程

```rust
// 1. 客户端构造初始化请求
let params = InitializeParams {
    client_info: ClientInfo {
        name: "codex_vscode".to_string(),
        title: Some("Codex VSCode".to_string()),
        version: "1.0.0".to_string(),
    },
    capabilities: Some(InitializeCapabilities {
        experimental_api: true,
        opt_out_notification_methods: None,
    }),
};

// 2. 发送 Initialize 请求
let request = ClientRequest::Initialize {
    request_id: RequestId::Integer(1),
    params,
};

// 3. 接收 InitializeResponse
// { user_agent, platform_family, platform_os }
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **capabilities 为 null**：客户端可能不发送能力声明，服务器需要处理默认值
2. **版本兼容性**：客户端和服务器版本不匹配可能导致功能异常
3. **重初始化**：需要明确是否支持重新初始化

### 改进建议

1. **添加协议版本**：明确声明支持的协议版本
   ```rust
   pub protocol_version: String,  // 如 "2024-03-15"
   ```

2. **添加区域设置**：支持国际化
   ```rust
   pub locale: Option<String>,  // 如 "zh-CN", "en-US"
   ```

3. **添加客户端能力列表**：更细粒度的能力声明
   ```rust
   pub supported_methods: Option<Vec<String>>,
   ```

4. **添加追踪 ID**：支持分布式追踪
   ```rust
   pub trace_id: Option<String>,
   ```

### 测试建议

- 测试默认值的正确性
- 测试 capabilities 为 null 的情况
- 验证序列化/反序列化
- 测试不同客户端类型的初始化

### 安全考虑

- 验证 client_info 中的信息真实性
- 限制 experimental_api 的权限范围
- 记录初始化事件用于审计
