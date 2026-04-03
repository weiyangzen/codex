# TerminalInteractionNotification 研究文档

## 1. 场景与职责

**TerminalInteractionNotification** 是 app-server-protocol v2 协议中用于通知客户端终端交互事件的服务器通知类型。该类型在以下场景中使用：

- **命令执行监控**：向客户端报告正在执行的命令的终端交互情况
- **实时输入显示**：显示发送到运行中命令的 stdin 输入
- **调试与审计**：记录命令执行过程中的交互历史
- **协作场景**：在多用户协作时同步终端交互状态

该类型作为服务器主动推送的通知，让客户端了解命令执行过程中的终端活动。

## 2. 功能点目的

该类型的核心目的是：

1. **透明化命令执行**：让客户端了解命令执行过程中的输入操作
2. **支持交互式命令**：处理需要用户输入的命令执行场景
3. **审计与记录**：为命令执行提供完整的交互审计日志
4. **实时同步**：在实时协作场景中同步终端状态

与 `ExecCommand` 相关的事件配合使用，提供完整的命令执行生命周期视图。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type TerminalInteractionNotification = {
  itemId: string,
  processId: string,
  stdin: string,
  threadId: string,
  turnId: string,
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread_id` | `String` | 所属会话（线程）的唯一标识符 |
| `turn_id` | `String` | 所属回合（turn）的唯一标识符 |
| `item_id` | `String` | 关联的线程项（通常是命令执行项）的标识符 |
| `process_id` | `String` | 关联的操作系统进程标识符 |
| `stdin` | `String` | 发送到命令的标准输入内容 |

### 序列化特性

- 使用 camelCase 命名规范进行序列化
- 所有字段均为必填字段，无可选字段
- 字符串字段用于标识符，便于跨系统传递

### 与核心协议类型的关系

该类型对应核心协议中的 `TerminalInteractionEvent`：

```rust
// codex-rs/protocol/src/protocol.rs
pub struct TerminalInteractionEvent {
    pub call_id: String,      // 映射到 item_id
    pub process_id: String,
    pub stdin: String,
}
```

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4887-4896 行

### 协议注册
- **服务器通知枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs`
  - 包含在 `ServerNotification` 枚举中

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/TerminalInteractionNotification.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/TerminalInteractionNotification.json`
- **服务器通知**: `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

### 核心协议对应
- **核心事件定义**: `codex-rs/protocol/src/protocol.rs` 第 2722-2729 行
  ```rust
  pub struct TerminalInteractionEvent {
      pub call_id: String,
      pub process_id: String,
      pub stdin: String,
  }
  ```

### 事件处理
- **事件处理**: `codex-rs/app-server/src/bespoke_event_handling.rs` 第 1624-1636 行
  ```rust
  EventMsg::TerminalInteraction(terminal_event) => {
      let item_id = terminal_event.call_id.clone();
      let notification = TerminalInteractionNotification {
          thread_id: conversation_id.to_string(),
          turn_id: event_turn_id.clone(),
          item_id,
          process_id: terminal_event.process_id,
          stdin: terminal_event.stdin,
      };
      outgoing.send_server_notification(...).await;
  }
  ```

## 5. 依赖与外部交互

### 导入依赖

该类型本身无外部类型依赖，作为服务器通知参与以下交互：

### 上游事件
- **TerminalInteractionEvent**: 核心协议中的终端交互事件
  - `call_id` 映射到 `item_id`
  - `process_id` 保持不变
  - `stdin` 保持不变

### 通知流程

```
命令执行
    │
    ├── ExecCommandBegin
    │
    ├── 终端交互发生
    │       │
    │       ▼
    │   TerminalInteractionEvent (核心)
    │       ├── call_id
    │       ├── process_id
    │       └── stdin
    │
    ▼
TerminalInteractionNotification (app-server)
    ├── thread_id (添加上下文)
    ├── turn_id (添加上下文)
    ├── item_id (来自 call_id)
    ├── process_id
    └── stdin
         │
         ▼
    推送到客户端
```

### 相关事件类型

| 事件类型 | 说明 | 关系 |
|----------|------|------|
| `ExecCommandBegin` | 命令开始执行 | 前置事件 |
| `ExecCommandOutputDelta` | 命令输出增量 | 并行事件 |
| `ExecCommandEnd` | 命令执行结束 | 后置事件 |
| `TerminalInteraction` | 终端交互 | 本类型 |

## 6. 风险、边界与改进建议

### 潜在风险

1. **敏感信息泄露**
   - 风险：`stdin` 可能包含敏感信息（密码、密钥等）
   - 建议：考虑添加敏感信息检测和脱敏机制

2. **大量通知性能**
   - 风险：频繁的终端交互可能产生大量通知，影响性能
   - 建议：考虑批量发送或采样机制

3. **编码问题**
   - 风险：`stdin` 可能包含二进制数据或非 UTF-8 内容
   - 现状：使用 `String` 类型，假设 UTF-8 编码
   - 建议：考虑使用 Base64 编码处理二进制数据

### 边界情况

1. **空 stdin**
   - 某些终端交互可能无实际输入内容

2. **多行输入**
   - `stdin` 可能包含多行文本，需要正确处理换行符

3. **特殊字符**
   - 控制字符、转义序列等需要正确处理

4. **长输入**
   - 大量输入内容可能导致通知过大

### 改进建议

1. **添加敏感信息标记**
   ```rust
   pub struct TerminalInteractionNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub item_id: String,
       pub process_id: String,
       pub stdin: String,
       pub sensitive: bool, // 标记是否包含敏感信息
   }
   ```

2. **支持二进制数据**
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub stdin_base64: Option<String>, // Base64 编码的二进制数据
       pub is_binary: bool,
   }
   ```

3. **添加时间戳**
   ```rust
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub timestamp: i64, // Unix 时间戳（毫秒）
   }
   ```

4. **添加输入类型**
   ```rust
   pub enum StdinType {
       Text,
       Password, // 密码输入（应脱敏）
       Control,  // 控制字符
   }
   
   pub struct TerminalInteractionNotification {
       // ... 现有字段
       pub stdin_type: StdinType,
   }
   ```

5. **支持输出内容**
   - 当前仅包含 stdin，可考虑同时包含 stdout 内容

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 验证命令执行过程中的通知发送
- **边界测试**: 空输入、长输入、特殊字符等场景
- **安全测试**: 敏感信息处理、编码安全
