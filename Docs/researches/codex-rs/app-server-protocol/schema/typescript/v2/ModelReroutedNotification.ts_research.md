# ModelReroutedNotification.ts 调研文档

## 场景与职责

`ModelReroutedNotification` 是 Codex App Server Protocol v2 API 中的服务器通知类型。当系统因安全或其他原因将请求从一个模型重定向到另一个模型时，服务器会发送此通知给客户端。

主要使用场景包括：
- 安全降级：检测到高风险网络活动时自动切换模型
- 模型不可用：目标模型无法访问时切换到备用模型
- 用户通知：向用户透明地展示模型变更信息

## 功能点目的

该类型的核心目的是提供标准化的模型重路由事件通知：

1. **变更追踪**：记录模型切换的完整上下文（线程、回合、原模型、新模型）
2. **原因说明**：解释为什么发生模型切换
3. **审计支持**：为安全和合规审计提供数据

TypeScript 定义：
```typescript
export type ModelReroutedNotification = { 
    threadId: string, 
    turnId: string, 
    fromModel: string, 
    toModel: string, 
    reason: ModelRerouteReason 
}
```

## 具体技术实现

### Rust 端实现

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelReroutedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub from_model: String,
    pub to_model: String,
    pub reason: ModelRerouteReason,
}
```

### 服务器通知定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册：

```rust
ModelRerouted => "model/rerouted" (v2::ModelReroutedNotification)
```

### 发送实现

在 `codex-rs/app-server/src/outgoing_message.rs` 中：

```rust
let notification = ServerNotification::ModelRerouted(ModelReroutedNotification {
    thread_id: thread_id.to_string(),
    turn_id: turn_id.to_string(),
    from_model: from_model.clone(),
    to_model: to_model.clone(),
    reason: ModelRerouteReason::HighRiskCyberActivity,
});
```

### 事件处理

在 `codex-rs/app-server/src/bespoke_event_handling.rs` 中：

```rust
let notification = ModelReroutedNotification {
    thread_id: thread_id.to_string(),
    turn_id,
    from_model: original_model,
    to_model: target_model,
    reason: ModelRerouteReason::HighRiskCyberActivity,
};
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，第 5800-5808 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelReroutedNotification.ts` | 生成的 TypeScript 类型定义 |

### 服务器通知注册

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 第 916 行 |

### 使用/发送位置

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/outgoing_message.rs` | 第 798-808 行 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 第 63 行、第 325 行 |

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/safety_check_downgrade.rs` | 安全降级测试 |
| `codex-rs/core/tests/suite/safety_check_downgrade.rs` | 核心层测试 |

## 依赖与外部交互

### 内部依赖

1. **ModelRerouteReason**：说明重路由原因
2. **序列化框架**：`serde`
3. **TypeScript 生成**：`ts-rs` crate
4. **JSON Schema 生成**：`schemars` crate

### 外部交互

- **触发源**：安全检测系统（`codex-rs/core/src/codex.rs`）
- **发送方**：App Server（`outgoing_message.rs`）
- **接收方**：客户端应用（TUI、VS Code 扩展等）

### 通知流程

```
+-------------------+     +-------------------+     +-------------------+
| 安全检测系统       |     | App Server        |     | 客户端应用         |
| (codex.rs)        |     |                   |     |                   |
+---------+---------+     +---------+---------+     +---------+---------+
          |                         |                         |
          | 检测到高风险活动         |                         |
          |------------------------>|                         |
          |                         |                         |
          |                         | 构建通知                 |
          |                         | ModelReroutedNotification|
          |                         |                         |
          |                         | 发送通知                 |
          |                         |------------------------>|
          |                         |                         |
          |                         |                         | 展示通知
          |                         |                         |
```

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**：如果客户端在通知发送时未连接，可能错过模型变更信息
   - 建议：添加通知持久化或重试机制

2. **信息泄露**：`fromModel` 和 `toModel` 可能暴露内部模型信息
   - 建议：考虑添加权限检查

3. **时间戳缺失**：没有记录重路由发生的时间
   - 建议：添加 `timestamp` 字段

### 边界情况

1. **重复通知**：同一回合可能触发多次重路由
2. **快速切换**：模型在短时间内频繁切换
3. **客户端处理**：客户端如何展示和处理通知

### 改进建议

1. **添加时间戳**：
   ```rust
   pub struct ModelReroutedNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub from_model: String,
       pub to_model: String,
       pub reason: ModelRerouteReason,
       pub timestamp: i64,  // Unix 时间戳
   }
   ```

2. **添加序列号**：
   ```rust
   pub sequence: u32,  // 用于检测重复或丢失的通知
   ```

3. **扩展原因详情**：
   ```rust
   pub reason_details: Option<String>,  // 详细说明
   pub severity: RerouteSeverity,       // 严重程度
   ```

4. **支持用户确认**：
   ```rust
   pub requires_acknowledgment: bool,   // 是否需要用户确认
   ```

5. **添加元数据**：
   ```rust
   pub metadata: Option<HashMap<String, JsonValue>>,  // 扩展字段
   ```

6. **测试增强**：
   - 测试通知序列化/反序列化
   - 测试重复通知处理
   - 验证与客户端的集成
