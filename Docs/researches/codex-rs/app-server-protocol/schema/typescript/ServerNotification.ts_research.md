# ServerNotification.ts 研究文档

## 1. 场景与职责

ServerNotification 是 Codex app-server 协议中服务器向客户端发送通知的核心类型。它在以下场景中发挥关键作用：

- **会话生命周期**: 通知客户端会话的启动、状态变更、归档、关闭等事件
- **回合（Turn）管理**: 通知回合的开始、完成、中断、差异更新等
- **项目（Item）进度**: 通知单个项目的开始、完成、 Guardian 审批审查等
- **实时通信**: 实时语音对话的音频流、转录增量等
- **配置变更**: 配置警告、模型重路由等系统事件
- **文件搜索**: 模糊文件搜索会话的更新和完成通知

## 2. 功能点目的

ServerNotification 是一个丰富的标签联合类型，涵盖以下通知类别：

### 会话/线程相关
- `error`: 错误通知
- `thread/started`, `thread/status/changed`, `thread/archived/unarchived/closed`: 线程生命周期
- `thread/name/updated`, `thread/tokenUsage/updated`: 线程元数据更新

### 回合相关
- `turn/started`, `turn/completed`: 回合生命周期
- `turn/diff/updated`, `turn/plan/updated`: 回合内容更新
- `hook/started`, `hook/completed`: Hook 执行事件

### 项目相关
- `item/started`, `item/completed`: 项目生命周期
- `item/autoApprovalReview/started/completed`: Guardian 审批审查
- `item/agentMessage/delta`, `item/plan/delta`: 增量更新
- `item/commandExecution/outputDelta`, `item/fileChange/outputDelta`: 执行输出
- `item/reasoning/*`: 推理相关增量

### 实时对话（实验性）
- `thread/realtime/started`, `thread/realtime/itemAdded`
- `thread/realtime/outputAudio/delta`, `thread/realtime/error`, `thread/realtime/closed`

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ServerNotification = 
  | { "method": "error", "params": ErrorNotification }
  | { "method": "thread/started", "params": ThreadStartedNotification }
  | { "method": "thread/status/changed", "params": ThreadStatusChangedNotification }
  // ... 更多变体
  | { "method": "thread/realtime/started", "params": ThreadRealtimeStartedNotification }
  // ... 实验性通知
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 640-695, 874-941):

```rust
// 宏定义生成 ServerNotification
macro_rules! server_notification_definitions {
    (
        $(
            $(#[$variant_meta:meta])*
            $variant:ident $(=> $wire:literal)? ( $payload:ty )
        ),* $(,)?
    ) => {
        #[derive(
            Serialize, Deserialize, Debug, Clone, JsonSchema, TS, Display, ExperimentalApi,
        )]
        #[serde(tag = "method", content = "params", rename_all = "camelCase")]
        #[strum(serialize_all = "camelCase")]
        pub enum ServerNotification {
            $(
                $(#[$variant_meta])*
                $(#[serde(rename = $wire)] #[ts(rename = $wire)] #[strum(serialize = $wire)])?
                $variant($payload),
            )*
        }
        // ... 实现
    };
}

// 实际通知定义
server_notification_definitions! {
    Error => "error" (v2::ErrorNotification),
    ThreadStarted => "thread/started" (v2::ThreadStartedNotification),
    ThreadStatusChanged => "thread/status/changed" (v2::ThreadStatusChangedNotification),
    // ... 更多定义
    #[experimental("thread/realtime/started")]
    ThreadRealtimeStarted => "thread/realtime/started" (v2::ThreadRealtimeStartedNotification),
    // ...
}
```

### 关键特性

1. **宏生成**: 使用宏批量生成枚举变体和辅助方法
2. **实验性标记**: 支持 `#[experimental("...")]` 标记实验性 API
3. **JSON-RPC 风格**: 使用 `method` 和 `params` 字段，符合 JSON-RPC 通知格式
4. **类型安全**: 每个通知变体都有明确的 payload 类型
5. **Display trait**: 支持转换为字符串表示

### ExperimentalApi 派生

ServerNotification 实现了 `ExperimentalApi` trait，用于检查通知是否为实验性：

```rust
impl crate::experimental_api::ExperimentalApi for ServerNotification {
    fn experimental_reason(&self) -> Option<&'static str> {
        // 根据变体返回实验性原因
    }
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 宏定义和实现 (lines 640-695) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` | 通知变体定义 (lines 874-941) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` | 各通知 payload 类型定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **strum**: Display trait 派生
- **codex_experimental_api_macros**: 实验性 API 宏

### 外部交互

- **WebSocket/SSE**: 通知通过 WebSocket 或 Server-Sent Events 发送
- **客户端 UI**: TypeScript 类型用于前端事件处理
- **实验性 API 系统**: 与实验性功能开关系统集成

## 6. 风险、边界与改进建议

### 风险

1. **通知风暴**: 高频通知可能导致客户端处理压力
2. **版本兼容性**: 新增通知类型需要客户端同步更新
3. **实验性 API 稳定性**: 实验性通知可能在版本间变化

### 边界情况

1. **通知丢失**: 网络问题可能导致通知丢失，需要重连机制
2. **乱序到达**: 通知可能乱序到达，客户端需要处理
3. **重复通知**: 重连后可能收到重复通知
4. **大 payload**: 某些通知（如文件内容）可能非常大

### 改进建议

1. **通知批处理**: 支持批量发送通知减少网络开销
2. **通知优先级**: 添加优先级字段，重要通知优先处理
3. **通知确认**: 关键通知支持客户端确认机制
4. **压缩**: 大 payload 通知支持压缩
5. **过滤**: 客户端可以订阅特定类型的通知
6. **速率限制**: 服务器端通知速率限制防止风暴
7. **文档生成**: 自动生成通知文档，包含触发条件和 payload 示例
