# TerminalInteractionNotification.ts 研究文档

## 场景与职责

`TerminalInteractionNotification.ts` 定义了终端交互通知的数据结构，用于在服务器需要与终端进程交互时通知客户端。这是 Codex 终端管理功能的核心组件，支持向运行中的终端进程发送输入。

## 功能点目的

该类型用于：
1. **终端输入**：向运行中的终端进程发送输入
2. **进程通信**：支持与后台终端进程的交互
3. **自动化支持**：允许自动化脚本与终端交互
4. **远程控制**：支持远程控制终端会话

## 具体技术实现

### 数据结构定义

```typescript
export type TerminalInteractionNotification = { 
  threadId: string,     // 所属线程ID
  turnId: string,       // 所属回合ID
  itemId: string,       // 关联的响应项ID
  processId: string,    // 目标进程ID
  stdin: string         // 要发送到进程标准输入的数据
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| threadId | string | 标识此交互所属的线程 |
| turnId | string | 标识此交互所属的回合 |
| itemId | string | 关联的响应项标识符 |
| processId | string | 目标终端进程的唯一标识符 |
| stdin | string | 要发送到进程标准输入的数据 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TerminalInteractionNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub process_id: String,
    pub stdin: String,
}
```

### 使用场景

#### 向终端发送输入

```rust
// 服务器需要向终端发送输入
let notification = TerminalInteractionNotification {
    thread_id: "thread-123".to_string(),
    turn_id: "turn-456".to_string(),
    item_id: "item-789".to_string(),
    process_id: "proc-abc".to_string(),
    stdin: "yes\n".to_string(),  // 自动回答确认提示
};
send_server_notification(notification.into());
```

#### 自动化交互

```rust
// 自动化脚本响应交互式提示
let interactions = vec![
    ("Enter your name:", "John Doe\n"),
    ("Continue? [Y/n]", "Y\n"),
    ("Password:", "secret\n"),
];

for (prompt, response) in interactions {
    let notification = TerminalInteractionNotification {
        thread_id: thread_id.clone(),
        turn_id: turn_id.clone(),
        item_id: item_id.clone(),
        process_id: process_id.clone(),
        stdin: response.to_string(),
    };
    // 发送通知...
}
```

### 服务端发送逻辑

在 `codex-rs/app-server/src/bespoke_event_handling.rs` 中：

```rust
fn send_terminal_input(
    &mut self,
    thread_id: ThreadId,
    turn_id: TurnId,
    item_id: String,
    process_id: ProcessId,
    input: String,
) {
    let notification = TerminalInteractionNotification {
        thread_id: thread_id.to_string(),
        turn_id: turn_id.to_string(),
        item_id,
        process_id: process_id.to_string(),
        stdin: input,
    };
    self.outgoing_messages.send(notification.into());
}
```

### 客户端处理

客户端收到通知后，需要将 stdin 数据写入对应的终端进程：

```rust
match notification {
    TerminalInteractionNotification { process_id, stdin, .. } => {
        if let Some(terminal) = self.terminals.get_mut(&process_id) {
            terminal.write_input(&stdin)?;
        }
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/TerminalInteractionNotification.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 事件处理：`codex-rs/app-server/src/bespoke_event_handling.rs`

### 父类型引用
- ServerNotification：`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

## 依赖与外部交互

### 上游依赖
- 终端管理器：跟踪运行中的终端进程
- 命令执行：需要与终端交互的命令

### 下游消费
- 终端客户端：将输入写入对应的终端进程
- 进程管理：管理终端进程的生命周期

### 通知流程

```
命令执行需要输入
    ↓
服务器检测输入需求
    ↓
TerminalInteractionNotification
    ↓
客户端接收并写入终端
    ↓
终端进程接收输入
```

## 风险、边界与改进建议

### 边界情况
1. **进程终止**：目标进程可能在通知到达前已终止
2. **输入缓冲**：stdin 数据可能超过缓冲区大小
3. **编码问题**：stdin 字符串的编码处理

### 潜在风险
1. **注入风险**：stdin 数据可能包含恶意命令
2. **竞态条件**：多个通知可能同时到达
3. **死锁风险**：不当的交互顺序可能导致死锁

### 改进建议
1. **输入验证**：验证 stdin 数据的合法性
2. **超时机制**：添加交互超时处理
3. **确认机制**：添加输入接收确认
4. **批量输入**：支持一次发送多行输入
5. **交互历史**：记录交互历史用于调试
6. **安全模式**：提供只读模式禁止自动输入
