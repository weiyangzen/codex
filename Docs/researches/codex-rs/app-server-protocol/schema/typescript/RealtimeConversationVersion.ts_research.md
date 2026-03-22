# RealtimeConversationVersion.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`RealtimeConversationVersion` 定义了实时对话（Realtime Conversation）的协议版本，用于区分不同版本的实时对话 API。

**使用场景：**
- 启动实时对话时指定协议版本
- 根据版本处理不同的实时事件格式
- 向后兼容支持旧版本客户端

**职责：**
- 提供标准化的版本标识
- 支持版本协商和兼容性处理
- 默认使用最新版本

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **版本管理**：支持实时对话协议的演进
2. **向后兼容**：允许旧版本客户端继续工作
3. **功能区分**：不同版本可能支持不同的功能集

**版本定义：**
- `v1`：实时对话协议版本 1
- `v2`：实时对话协议版本 2（默认）

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/protocol.rs` 第 1433-1439 行）：

```rust
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum RealtimeConversationVersion {
    #[default]
    V1,
    V2,
}
```

**TypeScript 生成定义：**

```typescript
export type RealtimeConversationVersion = "v1" | "v2";
```

**关键实现细节：**
- 使用 `snake_case` 序列化格式
- 默认值为 `V2`（最新版本）
- 在 `RealtimeConversationStartedEvent` 中使用（第 1441-1445 行）

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs`（第 1433-1439 行）：主要定义
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs`（第 1441-1445 行）：在事件中使用

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/RealtimeConversationVersion.ts`

**使用位置：**
- `RealtimeConversationStartedEvent.version` 字段
- 测试代码（common.rs 第 954 行）

**相关类型：**
- `RealtimeConversationStartedEvent`：包含版本信息的事件
- `RealtimeEvent`：实时对话事件枚举

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 中使用 snake_case：`"v1"`, `"v2"`

**与实时对话系统的交互：**
- 在实时对话启动时协商版本
- 影响实时事件的格式和处理方式

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **版本不一致**：客户端和服务器版本不匹配可能导致问题
2. **功能差异**：不同版本的功能差异可能导致用户体验不一致
3. **弃用计划**：旧版本最终需要弃用，需要明确的迁移路径

**边界情况：**
1. 版本协商失败时的回退策略
2. 未知版本的处理

**改进建议：**
1. **版本协商机制**：明确的版本协商流程
2. **功能矩阵**：清晰记录每个版本支持的功能
3. **弃用通知**：提前通知用户即将弃用的版本
4. **自动升级**：考虑支持自动升级到最新版本
5. **版本检测**：客户端自动检测服务器支持的版本
6. **兼容性层**：提供版本间的兼容性转换层
