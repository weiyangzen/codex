# HookEventName 研究文档

## 1. 场景与职责

`HookEventName` 是 App-Server Protocol v2 中的枚举类型，定义了系统中支持的所有 Hook 事件名称。该类型是 Hook 系统的核心组成部分，用于标识何时触发用户定义的 Hook。

**主要使用场景：**
- Hook 配置中指定触发时机
- 事件分发系统路由 Hook 调用
- 客户端了解哪些事件可以订阅 Hook
- 权限控制和审计日志记录

## 2. 功能点目的

该类型的核心目的是提供一套标准化的生命周期事件，允许用户在特定时机插入自定义逻辑：

1. **会话级事件**：`sessionStart` - 会话开始时触发
2. **交互级事件**：`userPromptSubmit` - 用户提交提示时触发
3. **控制级事件**：`stop` - 停止操作时触发

这个设计使得用户能够：
- 在会话开始时执行初始化（如加载上下文）
- 在用户提交前进行预处理或验证
- 在停止操作时执行清理或保存状态

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type HookEventName = "sessionStart" | "userPromptSubmit" | "stop";
```

### Rust 源定义

```rust
v2_enum_from_core!(
    pub enum HookEventName from CoreHookEventName {
        SessionStart, UserPromptSubmit, Stop
    }
);
```

### 枚举值说明

| 枚举值 | 字符串表示 | 说明 |
|--------|-----------|------|
| `SessionStart` | `"sessionStart"` | 会话开始时触发 |
| `UserPromptSubmit` | `"userPromptSubmit"` | 用户提交提示时触发 |
| `Stop` | `"stop"` | 停止操作时触发 |

### 实现机制

该枚举使用 `v2_enum_from_core!` 宏从核心协议类型 `CoreHookEventName` 派生：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum HookEventName {
    SessionStart,
    UserPromptSubmit,
    Stop,
}
```

### 特性注解

- `#[serde(rename_all = "camelCase")]`：序列化为 camelCase 字符串
- 实现了与核心类型的双向转换

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 348-351 行

### 核心类型来源

- `CoreHookEventName`：定义在 `codex_protocol::protocol` 模块

### 相关类型

- `HookHandlerType`：Hook 处理器类型（第 354-357 行）
- `HookExecutionMode`：Hook 执行模式（第 360-363 行）
- `HookScope`：Hook 作用域（第 366-369 行）
- `HookRunStatus`：Hook 运行状态（第 372-375 行）

## 5. 依赖与外部交互

### 依赖关系

| 依赖 | 来源 | 说明 |
|------|------|------|
| `CoreHookEventName` | `codex_protocol::protocol` | 核心协议定义的事件枚举 |

### 序列化行为

- 使用 `serde` 序列化为 camelCase 字符串
- TypeScript 中表示为字符串字面量联合类型
- 支持 JSON Schema 生成

## 6. 风险、边界与改进建议

### 潜在风险

1. **扩展性**：当前只有3个事件，未来扩展需要保持向后兼容
2. **命名冲突**：字符串值需要全局唯一，避免与其他系统冲突
3. **事件顺序**：某些事件可能有隐含的顺序依赖（如 `sessionStart` 必须在其他事件之前）

### 边界情况

- `userPromptSubmit` 可能在同一会话的多个回合中多次触发
- `stop` 事件可能在任何阶段触发，Hook 需要处理中断状态
- 事件可能并发触发，Hook 执行需要考虑并发安全

### 改进建议

1. **添加更多事件**：
   - `sessionEnd`：会话结束时
   - `turnStart`：回合开始时
   - `turnEnd`：回合结束时
   - `toolCall`：工具调用时
   - `error`：错误发生时

2. **事件过滤**：支持更细粒度的事件过滤条件
3. **事件优先级**：定义事件的优先级和处理顺序
4. **文档化**：为每个事件提供详细的触发时机和上下文信息

### 相关宏定义

`v2_enum_from_core!` 宏简化了从核心类型到 v2 协议的枚举映射，确保类型一致性。
