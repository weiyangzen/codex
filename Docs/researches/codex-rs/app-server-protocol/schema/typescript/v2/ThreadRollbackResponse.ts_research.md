# ThreadRollbackResponse 类型研究报告

## 场景与职责

`ThreadRollbackResponse` 是 Codex App-Server Protocol v2 中的响应类型，用于在 `thread/rollback` 操作成功后，向客户端返回回滚后的线程状态。

**主要使用场景：**
- 确认回滚操作成功执行
- 获取回滚后的线程最新状态
- 同步客户端显示的对话历史
- 验证回滚结果是否符合预期

**职责范围：**
- 返回更新后的线程对象
- 包含回滚后的完整 turns 列表
- 明确告知客户端历史记录可能存在的信息丢失

## 功能点目的

该类型的核心目的是：

1. **确认操作成功**: 向客户端表明回滚操作已完成
2. **提供最新状态**: 返回回滚后的线程完整状态，包括更新后的 turns
3. **管理预期**: 明确告知客户端返回的 ThreadItems 可能存在信息丢失
4. **同步客户端状态**: 使客户端能够更新 UI 以反映回滚后的对话历史

**重要说明**（来自代码注释）：
- 返回的 `Thread` 对象中 `turns` 字段会被填充
- `ThreadItems` 存储在每个 Turn 中是**有损的**（lossy）
- 系统明确不持久化所有代理交互（如命令执行）
- 这与 `thread/resume` 的行为一致

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadRollbackResponse = {
  /**
   * The updated thread after applying the rollback, with `turns` populated.
   *
   * The ThreadItems stored in each Turn are lossy since we explicitly do not
   * persist all agent interactions, such as command executions. This is the same
   * behavior as `thread/resume`.
   */
  thread: Thread,
};
```

### Rust 源类型定义

```rust
// Line 2917-2927
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRollbackResponse {
    /// The updated thread after applying the rollback, with `turns` populated.
    ///
    /// The ThreadItems stored in each Turn are lossy since we explicitly do not
    /// persist all agent interactions, such as command executions. This is the same
    /// behavior as `thread/resume`.
    pub thread: Thread,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | `Thread` | 回滚操作后的更新线程对象，包含填充的 turns |

### 关键特性

1. **Turns 填充**: 与普通的 Thread 查询不同，此响应中的 `turns` 字段会被实际填充
2. **有损历史**: ThreadItems 可能不包含所有原始交互细节
3. **一致性**: 与 `thread/resume` 的行为保持一致

### 相关类型

- **Thread**: 包含线程元数据和历史记录（turns）
- **Turn**: 对话回合，包含 ThreadItems
- **ThreadItem**: 对话中的具体项目（消息、工具调用等）

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRollbackResponse.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2917-2927

### 依赖类型文件
| 类型 | 路径 |
|------|------|
| Thread | `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts` |
| Turn | `codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts` |
| ThreadItem | `codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts` |

### 使用场景
- 与 `ThreadRollbackParams` 配对使用，构成完整的 rollback 请求-响应周期
- 服务端在执行回滚操作后，构造此响应返回给客户端

## 依赖与外部交互

### 内部依赖

1. **Thread 类型**: 核心依赖，包含线程的完整状态
2. **Turn 类型**: 对话回合，回滚后剩余的 turns
3. **ThreadItem 类型**: 每个 Turn 中的具体项目

### 外部交互

1. **与 ThreadRollbackParams 的交互**:
   - 接收回滚参数，执行删除操作
   - 返回更新后的线程状态

2. **与 ThreadResumeResponse 的关系**:
   - 两者都返回包含完整 turns 的 Thread 对象
   - 都遵循相同的"有损历史"行为
   - 表明这是系统性的历史记录设计决策

3. **与客户端 UI 的交互**:
   - 客户端使用返回的 Thread 更新对话历史显示
   - 需要根据有损特性处理可能的显示差异

### 有损历史的含义

```
原始交互:                    持久化存储:
- 用户消息                    ✓ 保存
- Agent 思考过程              ✗ 可能丢失
- 命令执行请求                ✓ 保存
- 命令执行输出（大量数据）     ✗ 可能截断/丢失
- 工具调用结果                ✓ 保存（摘要）
- 文件变更                    ✗ 不保存具体内容
```

## 风险、边界与改进建议

### 潜在风险

1. **数据丢失误解**:
   - 用户可能误以为回滚后能看到完整的历史记录
   - 实际上某些交互细节（如完整命令输出）可能已丢失

2. **客户端状态不一致**:
   - 如果客户端在回滚前缓存了完整的 turns
   - 回滚后收到有损版本，可能导致显示不一致

3. **调试困难**:
   - 丢失的命令执行细节可能影响问题排查
   - 无法准确重现历史对话状态

### 边界情况

1. **空线程**: 回滚所有 turns 后，线程可能变为空
2. **部分回滚**: 中间状态的 turns 保留，但信息可能不完整
3. **并发修改**: 回滚过程中如果有新 turns 添加
4. **持久化延迟**: 最近的 turns 可能尚未完全持久化

### 改进建议

1. **完整性指示器**:
   ```typescript
   export type ThreadRollbackResponse = {
     thread: Thread,
     historyCompleteness: {
       totalTurns: number,
       completeItems: number,
       partialItems: number,
       missingItems: number,
     },
   };
   ```

2. **详细度级别**:
   - 添加 `detailLevel` 参数到回滚请求
   - 允许客户端选择历史记录的详细程度
   - 例如：minimal, standard, complete

3. **变更摘要**:
   ```typescript
   export type ThreadRollbackResponse = {
     thread: Thread,
     rollbackSummary: {
       removedTurns: number,
       removedItems: number,
       affectedFiles: string[],  // 关联的文件变更
     },
   };
   ```

4. **元数据保留**:
   - 即使不保存完整内容，也保留元数据（如命令执行是否成功、执行时间等）
   - 帮助用户理解历史上下文

5. **客户端缓存策略**:
   - 建议客户端在回滚前保存本地完整的 turns 缓存
   - 允许用户在需要时查看完整历史（即使服务端已丢失）

6. **审计日志**:
   - 记录回滚操作的详细日志
   - 包括被删除的 turns 的摘要信息
   - 便于后续审计和故障排查

7. **渐进式加载**:
   - 对于大型线程，考虑支持按需加载 turns 详情
   - 初始返回摘要，需要时再获取完整内容
