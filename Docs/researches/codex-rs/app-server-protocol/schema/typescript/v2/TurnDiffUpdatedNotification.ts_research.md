# TurnDiffUpdatedNotification.ts Research

## 场景与职责

`TurnDiffUpdatedNotification` 是 App-Server Protocol v2 中用于实时同步代码变更差异的通知类型。它在 AI 助手执行文件修改操作期间，持续向客户端推送累积的代码差异（unified diff），使客户端能够实时预览或展示变更内容。

主要使用场景包括：
- **实时 diff 预览**：IDE 或 TUI 客户端实时显示 AI 正在进行的代码修改
- **变更追踪**：在回合执行过程中持续更新文件变更视图
- **代码审查辅助**：让用户在 AI 完成前就能审查变更内容
- **撤销/重做支持**：提供完整的变更历史用于操作回退

## 功能点目的

该通知的核心目的是：

1. **增量同步**：在回合执行期间持续推送累积的代码差异，而非仅在结束时一次性发送
2. **统一视图**：提供跨所有文件变更的聚合 diff，便于整体审查
3. **实时反馈**：让用户能够实时观察 AI 的代码修改过程
4. **减少等待**：无需等待回合完成即可查看和评估变更

与其他通知的关系：
- 与 `FileChangeOutputDeltaNotification` 配合，后者通知单个文件的变更，而 `TurnDiffUpdatedNotification` 提供聚合视图
- 在 `TurnCompletedNotification` 之前持续发送，形成完整的变更事件流

## 具体技术实现

### TypeScript 类型定义

```typescript
/**
 * Notification that the turn-level unified diff has changed.
 * Contains the latest aggregated diff across all file changes in the turn.
 */
export type TurnDiffUpdatedNotification = { 
  threadId: string, 
  turnId: string, 
  diff: string, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// Notification that the turn-level unified diff has changed.
/// Contains the latest aggregated diff across all file changes in the turn.
pub struct TurnDiffUpdatedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub diff: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | string | 所属线程的唯一标识符 |
| `turnId` | string | 当前回合的唯一标识符 |
| `diff` | string | 统一格式的 diff 文本，包含该回合所有文件变更的聚合视图 |

### diff 格式

- 使用标准的 unified diff 格式
- 包含所有已修改文件的变更内容
- 随着回合执行持续更新，反映最新的累积变更

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4711-4720` | Rust 结构体定义及文档注释 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnDiffUpdatedNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnDiffUpdatedNotification.json` | JSON Schema 定义 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理，生成并发送 diff 更新通知 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:889` | ServerNotification 枚举定义（`turn/diff/updated`） |

### 客户端消费

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 组件处理 diff 更新 |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts:48` | TypeScript 联合类型包含此通知 |

### 相关类型

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | FileChangeOutputDeltaNotification 等相关类型 |

## 依赖与外部交互

### 内部依赖

```
TurnDiffUpdatedNotification
├── thread_id: String
├── turn_id: String
├── diff: String (unified diff format)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **通知类型**：`turn/diff/updated`（定义于 `common.rs:889`）
- **传输方式**：JSON-RPC 通知，通过 WebSocket 或 stdio 传输
- **发送时机**：在回合执行期间，每次文件变更累积后发送

### 相关组件

- **File Change Tracking**：底层文件变更追踪系统生成 diff
- **Diff Aggregation**：将多个文件的变更聚合为统一的 diff 视图
- **UI Rendering**：客户端负责解析和渲染 diff 内容

## 风险、边界与改进建议

### 潜在风险

1. **大 diff 性能**：对于大量文件修改，diff 字符串可能非常大，频繁发送可能影响性能
2. **网络带宽**：持续的 diff 更新可能占用较多网络带宽
3. **客户端处理压力**：频繁的 diff 解析和渲染可能给客户端带来性能压力
4. **一致性保证**：需要确保 diff 的累积顺序正确，避免丢失变更

### 边界情况

| 场景 | 行为 |
|------|------|
| 无文件变更 | 可能不发送此通知，或发送空 diff |
| 大量文件变更 | diff 字符串可能非常大，需要考虑分页或压缩 |
| 二进制文件 | diff 可能不包含二进制内容或显示特殊标记 |
| 回合中断 | 最后发送的 diff 反映中断前的累积变更 |

### 改进建议

1. **增量 diff**：考虑发送增量 diff 而非完整累积 diff，减少数据传输量
2. **压缩传输**：对大 diff 启用压缩，减少网络带宽占用
3. **节流机制**：添加发送频率限制，避免过于频繁的更新
4. **分页支持**：对超大 diff 支持分页或分块传输
5. **缓存优化**：客户端可缓存 diff 解析结果，优化渲染性能
6. **格式选项**：支持不同的 diff 格式选项（如 context 行数配置）
7. **选择性订阅**：允许客户端选择是否接收 diff 更新通知

### 监控指标建议

- diff 通知发送频率
- 平均 diff 大小
- 最大 diff 大小
- diff 生成耗时
- 客户端处理延迟
