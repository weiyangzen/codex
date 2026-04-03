# ThreadStatus Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadStatus` 是一个可辨识联合类型（Discriminated Union），用于表示线程在运行时的各种状态。它是线程状态机的核心数据结构，支持客户端实时了解线程的当前活动状态。

**核心使用场景：**
1. **UI 状态展示**：在客户端界面显示线程当前状态（空闲、运行中、错误等）
2. **操作可用性判断**：根据状态决定哪些用户操作可用（如是否可以发送新消息）
3. **状态转换跟踪**：监控线程从创建到关闭的完整生命周期
4. **并发控制**：防止在特定状态下执行冲突操作

**职责范围：**
- 表示线程的四种基本状态：未加载、空闲、系统错误、活跃
- 在活跃状态下，提供详细的活动标志（activeFlags）
- 支持状态变更通知（`ThreadStatusChangedNotification`）
- 作为 `Thread` 对象的核心字段之一

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **状态机建模**
   - 明确定义线程可能处于的离散状态
   - 支持复合状态（活跃状态 + 活动标志）

2. **用户反馈**
   - 向用户传达线程当前正在做什么
   - 提供等待原因（如等待审批、等待用户输入）

3. **流程控制**
   - 防止在活跃状态下启动新的轮次
   - 在系统错误状态下提供恢复指引

4. **可扩展性**
   - 活跃状态的活动标志设计支持未来扩展
   - 新增活动类型无需修改状态结构

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 3022-3035）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Active {
        active_flags: Vec<ThreadActiveFlag>,
    },
}
```

**TypeScript 生成类型**（`ThreadStatus.ts`）：

```typescript
export type ThreadStatus = 
    { "type": "notLoaded" } | 
    { "type": "idle" } | 
    { "type": "systemError" } | 
    { "type": "active", activeFlags: Array<ThreadActiveFlag> };
```

### 状态详解

| 状态 | 类型 | 说明 |
|------|------|------|
| `NotLoaded` | 简单状态 | 线程已创建但尚未加载到内存中 |
| `Idle` | 简单状态 | 线程空闲，等待用户输入 |
| `SystemError` | 简单状态 | 线程遇到系统错误，可能需要用户干预 |
| `Active` | 复合状态 | 线程正在处理中，附带活动标志列表 |

### ThreadActiveFlag 活动标志

**Rust 定义**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 3037-3043）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ThreadActiveFlag {
    WaitingOnApproval,
    WaitingOnUserInput,
}
```

**TypeScript 类型**（`ThreadActiveFlag.ts`）：

```typescript
export type ThreadActiveFlag = "waitingOnApproval" | "waitingOnUserInput";
```

### 活动标志说明

| 标志 | 说明 |
|------|------|
| `waitingOnApproval` | 线程正在等待用户审批某个操作（如命令执行、文件修改） |
| `waitingOnUserInput` | 线程正在等待用户提供额外输入 |

### 序列化示例

```json
// NotLoaded
{ "type": "notLoaded" }

// Idle
{ "type": "idle" }

// SystemError
{ "type": "systemError" }

// Active - 等待审批
{ 
    "type": "active", 
    "activeFlags": ["waitingOnApproval"] 
}

// Active - 多个活动
{ 
    "type": "active", 
    "activeFlags": ["waitingOnApproval", "waitingOnUserInput"] 
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3022-3043)
  - `ThreadStatus` 枚举定义
  - `ThreadActiveFlag` 枚举定义

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadStatus.ts`**
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadActiveFlag.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadStatus.json`**

### 使用场景
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** - `Thread` 结构体中的 `status` 字段
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** - `ThreadStatusChangedNotification` 中的 `status` 字段

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_status.rs`**
  - 测试状态变更通知的接收
  - 验证状态转换序列（idle → active → idle）

- **`codex-rs/app-server/tests/suite/v2/thread_start.rs`** (line 82)
  - 验证新线程初始状态为 `Idle`

- **`codex-rs/app-server/tests/suite/v2/thread_unarchive.rs`** (line 143)
  - 验证解档后线程状态为 `NotLoaded`

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用根据状态显示不同的 UI

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `ThreadActiveFlag` | 活跃状态的子状态标志 |
| `Thread` | 包含 `ThreadStatus` 作为字段 |
| `ThreadStatusChangedNotification` | 使用 `ThreadStatus` 通知状态变更 |

### 状态转换图

```
                    ┌─────────────┐
                    │  NotLoaded  │
                    └──────┬──────┘
                           │ thread/load
                           ▼
┌─────────┐    error    ┌─────────┐
│ SystemError │ ◄──────── │  Idle   │
└────┬────┘             └───┬─────┘
     │                      │ turn/start
     │ recover              ▼
     └────────────────► ┌─────────┐
                        │  Active │
                        └────┬────┘
                             │ turn/completed
                             ▼
                       ┌─────────┐
                       │  Idle   │
                       └─────────┘
```

### 序列化配置

```rust
#[serde(tag = "type", rename_all = "camelCase")]  // 使用 type 字段作为辨识标签
#[ts(tag = "type")]                                  // TypeScript 使用相同的标签
```

这种配置确保 JSON 序列化后的格式为：
```json
{ "type": "idle" }
{ "type": "active", "activeFlags": [...] }
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **状态竞争**
   - 状态变更通知可能在网络中乱序到达
   - 客户端需要处理过期的状态通知

2. **复合状态复杂性**
   - `Active` 状态包含多个标志，可能存在冲突组合
   - 例如同时 `waitingOnApproval` 和 `waitingOnUserInput`

3. **状态持久化**
   - 服务器重启后，加载的线程状态可能不准确
   - 测试显示解档后状态为 `NotLoaded` 而非之前的实际状态

### 边界情况

1. **空活动标志列表**
   - `Active { active_flags: [] }` 是否合法？
   - 当前实现允许，但语义上可能不合理

2. **重复标志**
   - `active_flags` 是 `Vec`，可能包含重复标志
   - 建议使用 `HashSet` 或去重处理

3. **状态与实际操作不一致**
   - 状态显示为 `Idle` 但实际仍有后台任务
   - 需要确保状态更新的原子性

### 改进建议

1. **状态机验证**
   - 添加状态转换验证，防止非法转换
   - 例如：`NotLoaded` 不能直接到 `Active`

2. **活动标志优化**
   - 考虑将 `Vec<ThreadActiveFlag>` 改为 `HashSet` 防止重复
   - 添加验证确保 `Active` 状态至少有一个标志

3. **状态历史**
   - 考虑添加状态历史记录，便于调试
   - 可以记录状态变更的时间戳和原因

4. **扩展性**
   - 考虑添加更多活动标志：
     - `processing` - 正在处理中
     - `streaming` - 正在流式输出
     - `compacting` - 正在压缩上下文

5. **错误状态细化**
   - `SystemError` 可以细化为：
     - `ModelError` - 模型调用错误
     - `SandboxError` - 沙箱执行错误
     - `NetworkError` - 网络错误

6. **状态超时**
   - 为某些状态添加超时机制
   - 例如 `Active` 状态长时间无响应自动转为 `SystemError`
