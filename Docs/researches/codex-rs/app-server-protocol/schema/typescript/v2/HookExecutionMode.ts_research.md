# HookExecutionMode 研究文档

## 1. 场景与职责

`HookExecutionMode` 是 App-Server Protocol v2 中的枚举类型，定义了 Hook（钩子）的执行模式。该类型决定了 Hook 是同步执行还是异步执行，直接影响系统的响应性和可靠性。

**主要使用场景：**
- Hook 配置时指定执行模式
- 调度系统决定如何执行 Hook
- 客户端了解 Hook 执行的时间特性
- 错误处理和超时策略制定

## 2. 功能点目的

该类型的核心目的是区分两种 Hook 执行模式：

1. **同步模式 (`sync`)**：阻塞式执行，等待 Hook 完成后才继续
   - 适用于需要立即结果的预处理/验证
   - 可以修改或阻止后续操作
   - 有明确的超时限制

2. **异步模式 (`async`)**：非阻塞式执行，Hook 在后台运行
   - 适用于日志记录、通知发送等副作用
   - 不阻塞主流程
   - 失败不影响主操作

这个设计使得用户能够：
- 根据 Hook 的目的选择合适的执行模式
- 平衡系统响应性和功能完整性
- 实现复杂的预处理和后处理逻辑

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type HookExecutionMode = "sync" | "async";
```

### Rust 源定义

```rust
v2_enum_from_core!(
    pub enum HookExecutionMode from CoreHookExecutionMode {
        Sync, Async
    }
);
```

### 枚举值说明

| 枚举值 | 字符串表示 | 说明 |
|--------|-----------|------|
| `Sync` | `"sync"` | 同步执行，阻塞主流程 |
| `Async` | `"async"` | 异步执行，不阻塞主流程 |

### 实现机制

该枚举使用 `v2_enum_from_core!` 宏从核心协议类型 `CoreHookExecutionMode` 派生：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum HookExecutionMode {
    Sync,
    Async,
}
```

### 特性注解

- `#[serde(rename_all = "camelCase")]`：序列化为 camelCase 字符串
- 实现了与核心类型的双向转换

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 360-363 行

### 核心类型来源

- `CoreHookExecutionMode`：定义在 `codex_protocol::protocol` 模块

### 相关类型

- `HookEventName`：Hook 事件名称（第 348-351 行）
- `HookHandlerType`：Hook 处理器类型（第 354-357 行）
- `HookScope`：Hook 作用域（第 366-369 行）
- `HookRunStatus`：Hook 运行状态（第 372-375 行）

## 5. 依赖与外部交互

### 依赖关系

| 依赖 | 来源 | 说明 |
|------|------|------|
| `CoreHookExecutionMode` | `codex_protocol::protocol` | 核心协议定义的执行模式枚举 |

### 序列化行为

- 使用 `serde` 序列化为 camelCase 字符串
- TypeScript 中表示为字符串字面量联合类型
- 支持 JSON Schema 生成

## 6. 风险、边界与改进建议

### 潜在风险

1. **超时处理**：同步 Hook 如果没有超时机制可能导致系统挂起
2. **资源泄漏**：异步 Hook 如果管理不当可能导致资源泄漏
3. **顺序依赖**：异步 Hook 的执行顺序不确定，可能引发竞态条件
4. **错误传播**：异步 Hook 的错误可能难以追踪和处理

### 边界情况

- 同步 Hook 执行时间超过预期时的降级策略
- 异步 Hook 在主流程结束后仍在运行的处理
- 多个同步 Hook 的链式调用和错误处理
- 异步 Hook 的取消机制

### 改进建议

1. **添加超时配置**：
   - 为同步 Hook 添加可配置的超时时间
   - 为异步 Hook 添加最大执行时间限制

2. **添加更多模式**：
   - `parallel`：并行执行多个 Hook
   - `queued`：队列化执行，保证顺序
   - `debounced`：防抖执行，合并频繁触发

3. **执行策略增强**：
   - 支持重试机制配置
   - 支持失败后的降级处理
   - 支持执行优先级

4. **可观测性**：
   - 添加执行时间指标
   - 添加执行结果统计
   - 支持分布式追踪

### 使用建议

- **同步模式**：用于验证、转换、权限检查等必须完成的操作
- **异步模式**：用于日志、监控、通知等副作用操作
- 避免在同步 Hook 中执行耗时操作（如网络请求、大量计算）
