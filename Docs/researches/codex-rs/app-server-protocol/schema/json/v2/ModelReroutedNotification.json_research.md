# ModelReroutedNotification.json 研究文档

## 场景与职责

`ModelReroutedNotification.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述模型重新路由通知的结构。

该通知用于当服务器自动将请求从一个模型切换到另一个模型时通知客户端，通常发生在安全策略触发或模型不可用时。

## 功能点目的

1. **安全策略执行**: 当检测到高风险网络活动时，自动切换到更安全的模型
2. **模型降级**: 当请求的模型不可用时，自动切换到可用模型
3. **透明度**: 向客户端和用户透明地展示模型变更
4. **审计追踪**: 记录模型切换的原因和上下文

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ModelRerouteReason": {
      "enum": ["highRiskCyberActivity"],
      "type": "string"
    }
  },
  "properties": {
    "fromModel": { "type": "string" },
    "reason": { "$ref": "#/definitions/ModelRerouteReason" },
    "threadId": { "type": "string" },
    "toModel": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["fromModel", "reason", "threadId", "toModel", "turnId"],
  "title": "ModelReroutedNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `fromModel` | string | 是 | 原始请求的模型 ID |
| `toModel` | string | 是 | 实际使用的目标模型 ID |
| `reason` | string | 是 | 重新路由的原因，当前支持 `highRiskCyberActivity` |
| `threadId` | string | 是 | 发生模型切换的线程 ID |
| `turnId` | string | 是 | 发生模型切换的回合 ID |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:5802
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelReroutedNotification {
    pub from_model: String,
    pub to_model: String,
    pub reason: ModelRerouteReason,
    pub thread_id: String,
    pub turn_id: String,
}

// ModelRerouteReason 枚举定义 (行 342-346)
v2_enum_from_core! {
    pub enum ModelRerouteReason from CoreModelRerouteReason {
        HighRiskCyberActivity
    }
}
```

### 通知注册

```rust
// common.rs 行 916
ModelRerouted => "model/rerouted" (v2::ModelReroutedNotification)
```

### 核心枚举定义

```rust
// 来自 codex_protocol::protocol::ModelRerouteReason
pub enum ModelRerouteReason {
    HighRiskCyberActivity,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 5802-5811)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ModelReroutedNotification.json`
- **通知注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 916)
- **枚举定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 342-346)

### 发送方
- **模型路由器**: 在检测到需要模型切换时发送通知
- **安全策略引擎**: 当触发高风险活动检测时

### 接收方
- **客户端 UI**: 向用户展示模型切换提示
- **日志系统**: 记录模型切换事件用于审计

## 依赖与外部交互

### 上游依赖
1. **安全策略引擎**: 检测高风险网络活动
2. **模型可用性检查**: 验证请求模型的可用性
3. **模型路由逻辑**: 决定目标模型的选择策略

### 下游使用方
1. **客户端通知处理器**: 处理并展示模型切换通知
2. **分析系统**: 收集模型切换统计数据
3. **用户界面**: 显示模型切换警告或提示

### 触发场景
1. **高风险活动**: 用户请求涉及潜在危险的网络安全操作
2. **模型不可用**: 请求的模型当前无法访问
3. **配额限制**: 用户达到特定模型的使用限制

## 风险、边界与改进建议

### 潜在风险
1. **用户体验**: 未经用户同意的模型切换可能导致困惑
2. **功能差异**: 不同模型的能力差异可能导致预期外行为
3. **成本影响**: 模型切换可能影响 API 调用成本

### 边界情况
1. **多次切换**: 同一会话中可能发生多次模型切换
2. **回退失败**: 目标模型也可能不可用时的处理
3. **通知延迟**: 通知可能在模型切换完成后才到达

### 改进建议

#### 1. 扩展切换原因
```rust
pub enum ModelRerouteReason {
    HighRiskCyberActivity,
    ModelUnavailable,
    QuotaExceeded,
    CostOptimization,
    CapabilityMismatch,
    Maintenance,
}
```

#### 2. 添加用户确认
```json
{
  "fromModel": "gpt-4",
  "toModel": "gpt-3.5-turbo",
  "reason": "highRiskCyberActivity",
  "threadId": "...",
  "turnId": "...",
  "requiresUserAcknowledgment": true,
  "userMessage": "由于检测到高风险操作，已切换到更安全的模型。"
}
```

#### 3. 添加切换详情
```json
{
  "fromModel": "gpt-4",
  "toModel": "gpt-3.5-turbo",
  "reason": "highRiskCyberActivity",
  "threadId": "...",
  "turnId": "...",
  "details": {
    "riskScore": 0.85,
    "detectedPatterns": ["sql_injection", "privilege_escalation"],
    "timestamp": 1712345678
  }
}
```

#### 4. 添加恢复机制
```json
{
  "fromModel": "gpt-4",
  "toModel": "gpt-3.5-turbo",
  "reason": "highRiskCyberActivity",
  "threadId": "...",
  "turnId": "...",
  "canRevert": true,
  "revertInstructions": "请联系管理员以恢复使用原始模型。"
}
```

### 最佳实践
1. **用户通知**: 客户端应向用户清晰展示模型切换原因
2. **日志记录**: 详细记录模型切换事件用于安全审计
3. **恢复选项**: 在适当情况下提供恢复到原始模型的选项
4. **能力降级提示**: 当切换到能力较低的模型时，告知用户可能的功能限制

### 相关通知
- `ThreadStatusChangedNotification` - 线程状态变更
- `TurnCompletedNotification` - 回合完成（可能使用切换后的模型）
- `DeprecationNoticeNotification` - 弃用通知（与模型变更相关）
