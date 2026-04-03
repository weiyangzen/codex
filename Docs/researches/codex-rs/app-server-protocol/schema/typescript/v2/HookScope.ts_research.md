# HookScope.ts Research Document

## 场景与职责

`HookScope` 是 Codex App-Server Protocol v2 中用于定义 Hook 作用域的枚举类型。它决定了 Hook 执行的生命周期范围——是在整个线程（Thread）级别持续有效，还是仅在单次对话轮次（Turn）内有效。

在 Codex 的 Hook 系统中，作用域是一个关键概念，它影响：
- Hook 的触发时机和频率
- Hook 状态的持久化范围
- 资源的生命周期管理
- 客户端 UI 的展示组织方式

## 功能点目的

该枚举的主要目的是：

1. **生命周期界定**：明确 Hook 执行的有效范围和时间跨度
2. **资源管理**：指导系统何时创建和清理 Hook 相关资源
3. **状态隔离**：区分线程级和轮次级状态，避免相互干扰
4. **UI 组织**：帮助客户端以合适的方式组织和展示 Hook 信息

## 具体技术实现

### 数据结构定义

```typescript
export type HookScope = "thread" | "turn";
```

### 关键字段说明

| 值 | 说明 | 使用场景 |
|---|---|---|
| `"thread"` | 线程级作用域 | Hook 在整个线程生命周期内持续有效，跨多个对话轮次保持状态 |
| `"turn"` | 轮次级作用域 | Hook 仅在单次对话轮次内有效，轮次结束后状态重置 |

### 作用域对比

| 特性 | `"thread"` | `"turn"` |
|---|---|---|
| 生命周期 | 整个线程（从创建到关闭） | 单次轮次（从用户输入到 AI 响应完成） |
| 状态持久化 | 跨轮次保持 | 轮次结束后清理 |
| 触发频率 | 按事件触发，不限制次数 | 通常每轮次触发一次 |
| 典型用途 | 会话管理、全局监控 | 输入验证、单次处理 |
| UI 展示位置 | 线程级面板 | 轮次级时间线 |

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/HookScope.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

在 Rust 中的对应定义（使用宏生成）：

```rust
v2_enum_from_core!(
    pub enum HookScope from CoreHookScope {
        Thread, Turn
    }
);
```

核心协议定义位于：`codex_protocol::protocol::HookScope`

### 在 HookRunSummary 中的使用

```rust
pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,  // <-- 这里使用
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,
    pub status_message: Option<String>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}
```

## 依赖与外部交互

### 相关类型

- `HookRunSummary`: 包含 `scope` 字段，标识该 Hook 运行的作用域
- `HookStartedNotification`: 通知中包含 `turnId` 字段，对于 `"turn"` 作用域的 Hook，该字段有值；对于 `"thread"` 作用域，可能为 null

### 与通知的关系

```typescript
// HookStartedNotification 中 turnId 的可空性反映作用域
export type HookStartedNotification = { 
  threadId: string, 
  turnId: string | null,  // turn 作用域时有值，thread 作用域时可能为 null
  run: HookRunSummary,    // 包含 scope 字段
};
```

### 典型使用场景

1. **Thread 作用域 Hook**：
   - 会话初始化 Hook（`sessionStart` 事件）
   - 全局安全检查
   - 跨轮次的上下文收集

2. **Turn 作用域 Hook**：
   - 用户输入预处理（`userPromptSubmit` 事件）
   - 单次请求的内容过滤
   - 轮次级别的日志记录

## 风险、边界与改进建议

### 潜在风险

1. **二值局限**：只有两种作用域，可能无法满足某些复杂场景（如"跨多个线程"或"会话级"）
2. **混合使用复杂性**：同一个事件可能同时触发 Thread 和 Turn 作用域的 Hook，需要明确的执行顺序
3. **状态泄漏**：Thread 作用域的 Hook 如果不正确清理，可能导致内存泄漏

### 边界情况

1. **线程内多轮次**：Thread 作用域 Hook 在跨轮次时如何保持和恢复状态
2. **轮次中断**：Turn 作用域 Hook 在轮次被中断时的清理逻辑
3. **嵌套调用**：Thread 作用域 Hook 触发 Turn 作用域 Hook 的嵌套场景

### 改进建议

1. **添加 `session` 作用域**：考虑添加会话级作用域，跨多个线程有效
2. **作用域继承**：支持 Hook 配置继承或覆盖默认作用域
3. **动态作用域**：允许某些 Hook 根据运行时条件动态决定作用域
4. **作用域验证**：在配置加载时验证作用域与事件类型的兼容性
5. **添加 `global` 作用域**：用于全局监控和审计，不绑定特定线程或轮次

### 设计考量

当前只有两种作用域的设计是刻意保持简单：
- `"thread"` 对应长期运行的、有状态的服务
- `"turn"` 对应短期的、无状态的处理

这种设计与 Codex 的核心架构（Thread → Turn → Item 的层级结构）保持一致。

### 注意事项

- 此文件是自动生成的，**不应手动修改**
- 生成工具：[ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- 在配置 Hook 时，选择合适的作用域对性能和正确性都很重要
