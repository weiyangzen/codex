# ModelRerouteReason.ts 调研文档

## 场景与职责

`ModelRerouteReason` 是 Codex App Server Protocol v2 API 中用于表示模型重新路由原因的枚举类型。它定义了系统可能将请求从一个模型重定向到另一个模型的各种原因。

主要使用场景包括：
- 安全降级：当检测到高风险网络活动时，将请求路由到更安全的模型
- 模型重路由通知：向客户端解释为什么发生了模型切换

## 功能点目的

该类型的核心目的是提供标准化的模型重路由原因分类：

1. **安全合规**：标识因安全原因导致的模型切换
2. **审计追踪**：记录模型变更的原因供后续分析
3. **用户透明**：向用户解释模型变更的原因

TypeScript 定义：
```typescript
export type ModelRerouteReason = "highRiskCyberActivity"
```

## 具体技术实现

### Rust 端实现

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中使用宏定义：

```rust
v2_enum_from_core!(
    pub enum ModelRerouteReason from CoreModelRerouteReason {
        HighRiskCyberActivity
    }
);
```

### 宏展开

`v2_enum_from_core!` 宏展开后生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ModelRerouteReason {
    HighRiskCyberActivity
}

impl ModelRerouteReason {
    pub fn to_core(self) -> CoreModelRerouteReason {
        match self {
            ModelRerouteReason::HighRiskCyberActivity => CoreModelRerouteReason::HighRiskCyberActivity
        }
    }
}

impl From<CoreModelRerouteReason> for ModelRerouteReason {
    fn from(value: CoreModelRerouteReason) -> Self {
        match value {
            CoreModelRerouteReason::HighRiskCyberActivity => ModelRerouteReason::HighRiskCyberActivity
        }
    }
}
```

### 核心协议层定义

在 `codex-rs/protocol/src/protocol.rs` 中定义：

```rust
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, TS, JsonSchema)]
pub enum ModelRerouteReason {
    HighRiskCyberActivity,
}
```

### 使用位置

在 `ModelReroutedNotification` 中使用：

```rust
pub struct ModelReroutedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub from_model: String,
    pub to_model: String,
    pub reason: ModelRerouteReason,
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，第 343-346 行 |
| `codex-rs/protocol/src/protocol.rs` | 核心协议定义，第 1752 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelRerouteReason.ts` | 生成的 TypeScript 类型定义 |

### 引用文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | ModelReroutedNotification 中使用（第 5807 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelReroutedNotification.ts` | 导入引用 |

### 使用场景

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/outgoing_message.rs` | 发送重路由通知（第 803 行） |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 处理重路由事件（第 325 行） |
| `codex-rs/core/src/codex.rs` | 触发安全降级（第 3315 行） |

## 依赖与外部交互

### 内部依赖

1. **核心协议层**：`codex_protocol::protocol::ModelRerouteReason`
2. **序列化框架**：`serde` 使用 `rename_all = "camelCase"`
3. **TypeScript 生成**：`ts-rs` crate
4. **JSON Schema 生成**：`schemars` crate

### 外部交互

- **App Server**：在检测到安全风险时触发模型重路由
- **客户端应用**：接收 `ModelReroutedNotification` 并展示原因

### 安全降级流程

```
检测到高风险网络活动
        |
        v
+-------+--------+
| 安全系统        |
+-------+--------+
        |
        v
选择更安全的模型
        |
        v
发送 ModelReroutedNotification
{reason: HighRiskCyberActivity}
        |
        v
客户端展示通知
```

## 风险、边界与改进建议

### 潜在风险

1. **枚举值单一**：目前只有一个值 `highRiskCyberActivity`，扩展性受限
   - 建议：规划更多重路由场景（如模型不可用、配额限制等）

2. **原因描述不足**：单一枚举值无法提供详细的上下文信息
   - 建议：在 `ModelReroutedNotification` 中添加 `reason_details` 字段

3. **误报风险**：安全检测可能产生误报，导致不必要的模型降级
   - 建议：添加置信度评分或人工审核机制

### 边界情况

1. **未知原因**：如果核心协议添加了新原因但 v2 API 未更新
   - 当前处理：反序列化会失败
   - 建议：添加 `Unknown` 变体作为后备

2. **向后兼容性**：枚举值变更对现有客户端的影响

### 改进建议

1. **扩展枚举值**：
   ```rust
   pub enum ModelRerouteReason {
       HighRiskCyberActivity,
       ModelUnavailable,        // 目标模型不可用
       QuotaExceeded,           // 配额超限
       SafetyViolation,         // 其他安全违规
       UserPreference,          // 用户主动切换
       SystemMaintenance,       // 系统维护
   }
   ```

2. **添加严重程度**：
   ```rust
   pub struct ModelRerouteDetails {
       pub reason: ModelRerouteReason,
       pub severity: RerouteSeverity,  // info, warning, critical
       pub description: Option<String>,
   }
   ```

3. **支持可恢复性**：
   ```rust
   pub is_reversible: bool,  // 是否可以在后续请求中恢复原始模型
   ```

4. **审计日志集成**：
   - 记录所有重路由事件
   - 支持导出和分析

5. **测试覆盖**：
   - 添加序列化/反序列化测试
   - 测试未知枚举值的处理
   - 验证与核心协议层的转换
