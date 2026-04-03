# HookCompletedNotification 研究文档

## 1. 场景与职责

`HookCompletedNotification` 是 App-Server Protocol v2 中的通知类型，用于在 Hook（钩子）执行完成后向客户端发送通知。该类型属于实时事件通知系统的一部分，支持客户端同步 Hook 执行状态。

**主要使用场景：**
- 会话开始时执行初始化 Hook
- 用户提交提示后执行预处理 Hook
- 停止操作时执行清理 Hook
- 客户端实时显示 Hook 执行进度和结果

## 2. 功能点目的

该类型的核心目的是通知客户端某个 Hook 的执行已完成，并提供以下关键信息：

1. **上下文定位**：通过 `threadId` 和 `turnId` 确定 Hook 执行的上下文
2. **执行结果**：通过 `run` 字段提供 Hook 执行的完整摘要信息

这个设计使得客户端能够：
- 追踪特定线程/回合中的 Hook 执行状态
- 展示 Hook 执行结果给用户
- 根据 Hook 结果决定后续操作

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type HookCompletedNotification = { 
  threadId: string, 
  turnId: string | null, 
  run: HookRunSummary, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookCompletedNotification {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 线程ID，标识 Hook 所属的会话线程 |
| `turnId` | `string \| null` | 回合ID，标识 Hook 所属的具体回合；会话级 Hook 可能为 `null` |
| `run` | `HookRunSummary` | Hook 执行的摘要信息，包含状态、输出等 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 支持 JSON Schema 生成

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4702-4709 行

### 相关通知类型

- `TurnCompletedNotification`：回合完成通知（第 4695-4700 行）
- `TurnDiffUpdatedNotification`：回合差异更新通知（第 4711-4720 行）

### 依赖类型

- `HookRunSummary`：Hook 执行摘要，包含执行状态、输出条目等

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `HookRunSummary` | 同文件定义 | Hook 执行摘要信息 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- `turn_id` 为 `Option<String>`，在 TypeScript 中表示为 `string | null`

## 6. 风险、边界与改进建议

### 潜在风险

1. **时序问题**：通知到达顺序可能与 Hook 实际执行顺序不一致
2. **空 turnId 处理**：会话级 Hook（如 `sessionStart`）可能没有 `turnId`，客户端需要正确处理
3. **通知丢失**：网络问题可能导致通知丢失，客户端需要具备状态同步机制

### 边界情况

- 当 Hook 执行失败时，`run` 字段中应包含错误信息
- 异步 Hook 可能在回合完成后才触发通知
- 多个 Hook 可能并发执行，通知顺序不确定

### 改进建议

1. **添加时间戳**：考虑添加 `completedAt` 字段用于排序和调试
2. **序列号**：添加序列号或版本号帮助检测丢失的通知
3. **重试机制**：文档化推荐的重试和状态同步策略
4. **类型细化**：考虑为不同类型的 Hook 提供专门的完成通知类型

### 相关 Hook 事件

根据 `HookEventName` 定义，支持的事件包括：
- `sessionStart`：会话开始
- `userPromptSubmit`：用户提交提示
- `stop`：停止操作
