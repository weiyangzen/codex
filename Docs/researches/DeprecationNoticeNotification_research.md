# DeprecationNoticeNotification 研究报告

## 1. 场景与职责

### 1.1 使用场景

`DeprecationNoticeNotification` 是 Codex App-Server Protocol v2 中的弃用警告通知，用于向客户端通知某些功能、API 或配置项已被弃用。

**典型场景包括：**
- **API 演进**：当某个 API 即将被新版本替代时，提前通知客户端
- **配置迁移**：当配置项名称或格式变更时，引导用户更新
- **功能下线**：当某个功能即将停止服务时，发出警告
- **行为变更**：当系统行为有重大变更时，提前告知

### 1.2 核心职责

该通知的主要职责是：
1. **提前预警**：在功能实际移除前，给客户端足够的迁移时间
2. **迁移指导**：提供清晰的弃用说明和迁移建议
3. **兼容性维护**：支持平滑的版本升级路径
4. **透明沟通**：保持与开发者的开放沟通渠道

---

## 2. 功能点目的

### 2.1 设计意图

在快速发展的 AI 应用中，API 演进是常态。`DeprecationNoticeNotification` 的设计目的是：
- **减少破坏性变更**：避免突然移除功能导致客户端崩溃
- **促进生态健康**：鼓励客户端及时更新到最新 API
- **提升开发者体验**：提供清晰的迁移路径

### 2.2 通知目的

| 目的 | 说明 |
|------|------|
| 弃用声明 | 明确告知某功能已被弃用 |
| 影响说明 | 描述弃用对现有功能的影响 |
| 迁移指导 | 提供可选的迁移步骤或替代方案 |
| 时间线提示 | 暗示未来移除的时间（通过 details）|

### 2.3 使用策略

Codex 团队可以通过此通知实现：
1. **渐进式弃用**：先通知，后移除
2. **多版本支持**：同时支持新旧 API 一段时间
3. **定向沟通**：针对特定功能向受影响用户发送通知

---

## 3. 具体技术实现

### 3.1 数据结构定义

**JSON Schema 定义** (`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/DeprecationNoticeNotification.json`):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "details": {
      "description": "Optional extra guidance, such as migration steps or rationale.",
      "type": ["string", "null"]
    },
    "summary": {
      "description": "Concise summary of what is deprecated.",
      "type": "string"
    }
  },
  "required": ["summary"],
  "title": "DeprecationNoticeNotification",
  "type": "object"
}
```

**Rust 结构体定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs` Line 5810-5818):

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DeprecationNoticeNotification {
    /// Concise summary of what is deprecated.
    pub summary: String,
    /// Optional extra guidance, such as migration steps or rationale.
    pub details: Option<String>,
}
```

### 3.2 协议集成

**在 ServerNotification 枚举中注册** (`codex-rs/app-server-protocol/src/protocol/common.rs` Line 917):

```rust
server_notification_definitions! {
    // ... 其他通知
    DeprecationNotice => "deprecationNotice" (v2::DeprecationNoticeNotification),
    // ... 其他通知
}
```

**Wire 格式**：`"deprecationNotice"`

### 3.3 序列化规范

| 属性 | 类型 | 序列化名称 | 必填 | 说明 |
|------|------|-----------|------|------|
| summary | String | `summary` | 是 | 弃用内容的简洁描述 |
| details | Option<String> | `details` | 否 | 可选的额外指导信息 |

- 使用 camelCase 命名规范
- `details` 可为 null，用于提供迁移步骤或弃用原因

### 3.4 核心协议事件映射

**Core Protocol 事件** (`codex-rs/protocol/src/protocol.rs`):

```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
pub struct DeprecationNoticeEvent {
    pub summary: String,
    pub details: Option<String>,
}
```

**事件转换** (`codex-rs/app-server/src/bespoke_event_handling.rs` Line 1254-1261):

```rust
EventMsg::DeprecationNotice(event) => {
    let notification = DeprecationNoticeNotification {
        summary: event.summary,
        details: event.details,
    };
    outgoing
        .send_server_notification(ServerNotification::DeprecationNotice(notification))
        .await;
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/DeprecationNoticeNotification.json` | JSON Schema 定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` (Line 5810-5818) | Rust 结构体定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (Line 917) | ServerNotification 枚举注册 |

### 4.2 核心协议层

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | `DeprecationNoticeEvent` 定义 |

### 4.3 事件处理代码

**事件处理位置** (`codex-rs/app-server/src/bespoke_event_handling.rs` Line 1254-1261):

```rust
EventMsg::DeprecationNotice(event) => {
    let notification = DeprecationNoticeNotification {
        summary: event.summary,
        details: event.details,
    };
    outgoing
        .send_server_notification(ServerNotification::DeprecationNotice(notification))
        .await;
}
```

### 4.4 代码调用链

```
Core Protocol Layer
    ↓ EventMsg::DeprecationNotice
App-Server Event Handler (bespoke_event_handling.rs)
    ↓ 转换为 DeprecationNoticeNotification
ServerNotification 枚举包装
    ↓ JSON 序列化
Client (WebSocket/SSE)
    ↓ 显示警告或记录日志
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_protocol::protocol::EventMsg::DeprecationNotice` | 核心协议事件定义 |
| `codex_app_server_protocol::ServerNotification` | 通知枚举包装 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts_rs` | TypeScript 类型导出 |

### 5.2 外部交互

**与客户端的交互**：
- 通过 WebSocket 或 SSE 连接发送
- 客户端应监听 `"deprecationNotice"` 方法名
- 建议在 UI 中显示警告 banner 或记录到日志

**典型客户端处理**：
```typescript
// 伪代码示例
client.onNotification('deprecationNotice', (params) => {
    console.warn(`[DEPRECATED] ${params.summary}`);
    if (params.details) {
        console.info(`Migration guide: ${params.details}`);
    }
    // 可选：显示 UI 警告
    showDeprecationWarning(params.summary, params.details);
});
```

### 5.3 触发场景

| 场景 | 示例 |
|------|------|
| API 弃用 | `"ContextCompactedNotification is deprecated"` |
| 配置变更 | `"config key 'old_key' is renamed to 'new_key'"` |
| 功能移除 | `"Feature X will be removed in v3.0"` |
| 行为变更 | `"Default behavior of Y is changing"` |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 严重程度 |
|------|------|---------|
| 通知疲劳 | 过多的弃用通知可能导致开发者忽视 | 中 |
| 信息不足 | 仅有 summary 和 details，缺少结构化数据 | 低 |
| 版本信息缺失 | 未包含预计移除版本或替代 API 标识 | 中 |

### 6.2 边界情况

1. **重复通知**：同一弃用项可能在多个 Turn 中重复通知
2. **多客户端**：不同客户端版本可能收到不同的弃用通知
3. **国际化**：通知文本为英文，需要客户端自行翻译

### 6.3 改进建议

#### 短期（维护阶段）

1. **添加结构化字段**
   ```rust
   pub struct DeprecationNoticeNotification {
       pub summary: String,
       pub details: Option<String>,
       // 建议添加：
       pub deprecated_since: Option<String>,  // 版本号
       pub removal_version: Option<String>,   // 预计移除版本
       pub replacement_api: Option<String>,   // 替代 API 名称
       pub documentation_url: Option<String>, // 详细文档链接
   }
   ```

2. **去重机制**
   - 在客户端或服务器端实现通知去重
   - 基于 `summary` 哈希值进行去重

3. **分级警告**
   - 添加 `level` 字段区分 `warning` 和 `critical`
   - 允许客户端根据级别决定展示方式

#### 长期（演进方向）

1. **标准化弃用流程**
   ```rust
   pub enum DeprecationLevel {
       Info,      // 信息性通知
       Warning,   // 建议迁移
       Critical,  // 即将移除
   }
   ```

2. **机器可读标识**
   - 添加 `deprecation_code` 字段
   - 客户端可根据代码执行自动化迁移

3. **遥测集成**
   - 追踪哪些弃用通知被频繁触发
   - 帮助团队评估迁移进度

### 6.4 最佳实践建议

**对服务器开发者**：
1. 在弃用前至少一个主要版本发出通知
2. 提供清晰的迁移指南链接
3. 避免在一次会话中重复发送相同通知

**对客户端开发者**：
1. 始终监听并记录弃用通知
2. 在开发/测试环境中显示明显警告
3. 定期检查日志中的弃用警告
4. 制定定期更新计划

---

## 附录：相关代码片段

### A.1 核心协议事件定义

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
pub struct DeprecationNoticeEvent {
    pub summary: String,
    pub details: Option<String>,
}
```

### A.2 事件处理完整代码

```rust
// codex-rs/app-server/src/bespoke_event_handling.rs
EventMsg::DeprecationNotice(event) => {
    let notification = DeprecationNoticeNotification {
        summary: event.summary,
        details: event.details,
    };
    outgoing
        .send_server_notification(ServerNotification::DeprecationNotice(notification))
        .await;
}
```

### A.3 ServerNotification 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    DeprecationNotice => "deprecationNotice" (v2::DeprecationNoticeNotification),
    // ...
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/app-server-protocol v2 API*
