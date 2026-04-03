# McpAuthStatus 研究文档

## 1. 场景与职责

`McpAuthStatus` 是 App-Server Protocol v2 中的枚举类型，定义了 MCP（Model Context Protocol）服务器的认证状态。该类型用于表示 MCP 服务器的认证情况，帮助客户端了解服务器的可用性和认证需求。

**主要使用场景：**
- 显示 MCP 服务器的认证状态
- 判断是否需要引导用户进行认证
- 管理 MCP 服务器的连接状态
- 安全策略制定

## 2. 功能点目的

该类型的核心目的是提供标准化的 MCP 服务器认证状态：

1. **不支持认证** (`unsupported`)：服务器不需要或不支持认证
2. **未登录** (`notLoggedIn`)：服务器需要认证但用户未登录
3. **Bearer Token** (`bearerToken`)：使用 Bearer Token 认证
4. **OAuth** (`oAuth`)：使用 OAuth 流程认证

这个设计使得客户端能够：
- 了解每个 MCP 服务器的认证需求
- 引导用户完成必要的认证流程
- 根据认证状态决定是否显示或使用该服务器

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type McpAuthStatus = "unsupported" | "notLoggedIn" | "bearerToken" | "oAuth";
```

### Rust 源定义

```rust
v2_enum_from_core!(
    pub enum McpAuthStatus from codex_protocol::protocol::McpAuthStatus {
        Unsupported,
        NotLoggedIn,
        BearerToken,
        OAuth
    }
);
```

### 枚举值说明

| 枚举值 | 字符串表示 | 说明 |
|--------|-----------|------|
| `Unsupported` | `"unsupported"` | 服务器不支持或不需要认证 |
| `NotLoggedIn` | `"notLoggedIn"` | 需要认证但用户未登录 |
| `BearerToken` | `"bearerToken"` | 使用 Bearer Token 认证 |
| `OAuth` | `"oAuth"` | 使用 OAuth 认证流程 |

### 实现机制

该枚举使用 `v2_enum_from_core!` 宏从核心协议类型 `McpAuthStatus` 派生：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum McpAuthStatus {
    Unsupported,
    NotLoggedIn,
    BearerToken,
    OAuth,
}
```

### 特性注解

- `#[serde(rename_all = "camelCase")]`：序列化为 camelCase 字符串
- 实现了与核心类型的双向转换

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 333-340 行

### 核心类型来源

- `McpAuthStatus`：定义在 `codex_protocol::protocol` 模块

### 相关类型

- `McpServerStatus`：MCP 服务器状态（包含 `auth_status` 字段）
- `ReviewDelivery`：审核交付方式（第 327-330 行）
- `ModelRerouteReason`：模型重路由原因（第 342-346 行）

## 5. 依赖与外部交互

### 依赖关系

| 依赖 | 来源 | 说明 |
|------|------|------|
| `McpAuthStatus` (core) | `codex_protocol::protocol` | 核心协议定义的认证状态枚举 |

### 序列化行为

- 使用 `serde` 序列化为 camelCase 字符串
- TypeScript 中表示为字符串字面量联合类型
- 支持 JSON Schema 生成

## 6. 风险、边界与改进建议

### 潜在风险

1. **状态同步**：认证状态可能在客户端缓存期间发生变化
2. **Token 过期**：`bearerToken` 状态不表示 token 是否有效
3. **OAuth 流程**：`oAuth` 状态需要客户端实现完整的 OAuth 流程
4. **并发认证**：多个 MCP 服务器同时认证可能导致冲突

### 边界情况

- 认证状态从 `notLoggedIn` 变为其他状态的过渡
- OAuth 流程中断或失败的处理
- Token 过期后的状态变更
- 服务器配置变更导致的认证方式变化

### 改进建议

1. **添加更多状态**：
   - `tokenExpired`：Token 已过期
   - `refreshing`：正在刷新认证
   - `error`：认证出错

2. **添加元数据**：
   - 添加 `expiresAt` 字段表示 Token 过期时间
   - 添加 `scopes` 字段表示授权范围
   - 添加 `authUrl` 字段用于 OAuth 流程

3. **认证流程增强**：
   - 支持自动 Token 刷新
   - 支持多因素认证
   - 支持 SSO 集成

4. **安全性增强**：
   - 支持 Token 加密存储
   - 实现安全的 Token 传输
   - 添加认证审计日志

### 使用建议

| 状态 | 客户端行为 |
|------|-----------|
| `unsupported` | 直接连接，无需认证 |
| `notLoggedIn` | 显示认证按钮，引导用户认证 |
| `bearerToken` | 使用存储的 Token 连接 |
| `oAuth` | 启动 OAuth 授权流程 |

### 相关配置

MCP 服务器配置通常需要配合其他字段使用：
- `auth_status`：当前认证状态
- `auth_config`：认证配置（如 OAuth 的 client_id、scope 等）
- `tools`：该服务器提供的工具列表
