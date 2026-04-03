# HookOutputEntryKind.ts Research Document

## 场景与职责

`HookOutputEntryKind` 是 Codex App-Server Protocol v2 中用于定义 Hook 输出条目类型的枚举类型。它用于分类 Hook 执行过程中产生的各种输出内容，包括警告、停止信号、反馈、上下文信息和错误等。

在 Codex 的 Hook 系统中，当用户提交提示或特定事件触发时，系统会执行配置的 Hook 处理器（如命令、提示词或 Agent）。这些处理器在执行过程中会产生各种类型的输出，`HookOutputEntryKind` 就是用来标记这些输出类型的分类器。

## 功能点目的

该枚举的主要目的是：

1. **标准化输出分类**：为 Hook 执行输出提供统一的类型标记
2. **支持 UI 渲染**：不同类型的输出可以在客户端以不同的样式展示
3. **流程控制**：某些类型（如 `stop`）可以影响后续处理流程
4. **错误处理**：区分正常输出和错误输出，便于错误追踪和处理

## 具体技术实现

### 数据结构定义

```typescript
export type HookOutputEntryKind = "warning" | "stop" | "feedback" | "context" | "error";
```

### 关键字段说明

| 值 | 说明 | 使用场景 |
|---|---|---|
| `"warning"` | 警告信息 | Hook 执行过程中产生的非致命警告，如配置问题、资源限制等 |
| `"stop"` | 停止信号 | 指示 Hook 系统停止后续处理，通常用于阻断不安全的操作 |
| `"feedback"` | 反馈信息 | 提供给用户的反馈内容，如确认提示、建议等 |
| `"context"` | 上下文信息 | 附加的上下文数据，可用于增强后续处理 |
| `"error"` | 错误信息 | Hook 执行过程中发生的错误 |

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/HookOutputEntryKind.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

在 Rust 中的对应定义（使用宏生成）：

```rust
v2_enum_from_core!(
    pub enum HookOutputEntryKind from CoreHookOutputEntryKind {
        Warning, Stop, Feedback, Context, Error
    }
);
```

核心协议定义位于：`codex_protocol::protocol::HookOutputEntryKind`

## 依赖与外部交互

### 相关类型

- `HookOutputEntry`: 包含 `kind` 字段（类型为 `HookOutputEntryKind`）和 `text` 字段的实际输出条目
- `HookRunSummary`: 包含 `entries` 数组，其中每个条目都是 `HookOutputEntry`

### 使用场景

1. **HookStartedNotification**: 当 Hook 开始执行时，可能携带初始输出条目
2. **HookCompletedNotification**: 当 Hook 执行完成时，携带所有输出条目

### 与其他枚举的关系

```
HookOutputEntryKind
    └── HookOutputEntry (使用 HookOutputEntryKind 作为 kind 字段)
            └── HookRunSummary (包含 entries: HookOutputEntry[])
                    └── HookStartedNotification / HookCompletedNotification
```

## 风险、边界与改进建议

### 潜在风险

1. **类型扩展性**：当前只有 5 种类型，未来如果需要更多类型（如 `info`、`debug`），需要更新协议
2. **语义模糊**：`context` 和 `feedback` 的界限可能不够清晰，导致开发者选择困难

### 边界情况

1. **空文本处理**：当 `HookOutputEntry` 的 `text` 为空字符串时，客户端应如何处理
2. **多类型组合**：同一个 Hook 可能产生多种类型的输出，需要确保顺序和关联性

### 改进建议

1. **添加 `info` 类型**：用于一般性信息输出，与 `context` 区分
2. **添加元数据支持**：考虑为某些类型添加结构化元数据，而不仅是文本
3. **国际化支持**：考虑为 `feedback` 和 `warning` 类型添加本地化标识
4. **版本控制**：由于这是生成代码，任何修改都需要重新生成 TypeScript 类型

### 注意事项

- 此文件是自动生成的，**不应手动修改**
- 生成工具：[ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- 修改需通过 Rust 源码并重新生成
