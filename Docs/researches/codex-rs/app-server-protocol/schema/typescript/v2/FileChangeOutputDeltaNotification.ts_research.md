# FileChangeOutputDeltaNotification.ts 研究文档

## 场景与职责

`FileChangeOutputDeltaNotification.ts` 定义了文件变更输出增量通知类型，用于向客户端流式传输文件变更的进度信息。这是实时更新 UI 的重要机制，让用户能够看到文件操作的实时反馈。

该类型在文件编辑、补丁应用、批量修改等场景中发挥作用。

## 功能点目的

1. **进度反馈**: 实时显示文件变更进度
2. **流式更新**: 支持大文件的增量更新展示
3. **状态同步**: 保持客户端与服务器状态同步

## 具体技术实现

### 数据结构定义

```typescript
export type FileChangeOutputDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  delta: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 所属线程 ID |
| `turnId` | `string` | 所属回合 ID |
| `itemId` | `string` | 文件变更项 ID |
| `delta` | `string` | 增量内容（如进度信息、部分输出） |

### 使用示例

```typescript
// 监听文件变更增量通知
client.onNotification('fileChange/outputDelta', (notification: FileChangeOutputDeltaNotification) => {
  const { threadId, turnId, itemId, delta } = notification;
  
  // 更新 UI 显示
  updateFileChangeProgress(itemId, delta);
});
```

## 关键代码路径与文件引用

### Rust 源码定义

该类型在 Rust 源码中可能作为通用增量通知结构使用，具体定义需要查看通知发送逻辑。

### 相关类型

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4176-4180)

```rust
FileChange {
    id: String,
    changes: Vec<FileUpdateChange>,
    status: PatchApplyStatus,
}
```

### 增量通知模式

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

类似的增量通知类型：
- `ReasoningTextDeltaNotification`: 推理文本增量
- `ReasoningSummaryTextDeltaNotification`: 推理摘要增量
- `CommandExecOutputDeltaNotification`: 命令执行输出增量

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |

### 下游消费者

- **TUI 客户端**: 实时显示文件变更进度
- **VS Code 扩展**: 在编辑器中显示进度
- **Web 客户端**: 流式更新文件状态

## 风险、边界与改进建议

### 已知风险

1. **增量顺序**: 增量通知可能乱序到达
2. **丢失增量**: 网络问题可能导致增量丢失
3. **大增量**: 大文件的增量可能很大，影响性能

### 边界情况

1. **空增量**: `delta` 可能为空字符串
2. **编码问题**: 增量内容的编码需要一致
3. **并发变更**: 多个文件同时变更时的增量处理

### 改进建议

1. **序列号**: 增加序列号确保增量顺序
2. **压缩**: 大增量支持压缩传输
3. **确认机制**: 重要增量增加确认机制
4. **聚合**: 高频增量在客户端聚合显示
5. **取消支持**: 支持取消正在进行的文件变更

### 扩展示例

```typescript
export type FileChangeOutputDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string,
  sequence: number,  // 序列号
  delta: string,
  isFinal: boolean,  // 是否为最后增量
  progress?: {       // 进度信息
    current: number;
    total: number;
  },
};
```
