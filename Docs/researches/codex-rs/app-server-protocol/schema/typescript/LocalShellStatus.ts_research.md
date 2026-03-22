# LocalShellStatus Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`LocalShellStatus` 是 Codex Protocol 中表示本地 Shell 命令执行状态的枚举类型。它用于 `ResponseItem::LocalShellCall` 中，向客户端报告 Shell 命令的当前执行状态。

主要使用场景：
- **状态跟踪**：跟踪 Shell 命令的执行生命周期
- **进度通知**：向客户端报告命令执行进度
- **结果判断**：客户端根据状态判断命令是否成功完成
- **流式响应**：支持长时间运行命令的状态更新

## 2. 功能点目的 (Purpose of This Type)

- **生命周期管理**：定义命令执行的各个阶段
- **状态通信**：在服务器和客户端之间传递执行状态
- **结果分类**：区分成功完成、进行中和未完成状态
- **UI 反馈**：为用户界面提供状态显示依据

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type LocalShellStatus = "completed" | "in_progress" | "incomplete";
```

```rust
// Rust 定义
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum LocalShellStatus {
    Completed,
    InProgress,
    Incomplete,
}
```

### 变体说明

| 变体 | 值 | 说明 |
|-----|---|------|
| `Completed` | `"completed"` | 命令已成功完成执行 |
| `InProgress` | `"in_progress"` | 命令正在执行中 |
| `Incomplete` | `"incomplete"` | 命令未完成（可能失败或被中断） |

### 状态流转

```
         +-------------+
         |   Initial   |
         +------+------+
                |
                v
         +-------------+
    +--->| InProgress  |<---+
    |    +------+------+    |
    |           |           |
    |           v           |
    |    +-------------+    |
    +----+  Completed  |    |
         +-------------+    |
                           |
         +-------------+    |
         |  Incomplete |<---+
         +-------------+
```

### 使用位置

```rust
// 在 ResponseItem::LocalShellCall 中使用
pub enum ResponseItem {
    // ...
    LocalShellCall {
        #[serde(default, skip_serializing)]
        #[ts(skip)]
        id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(skip)]
        call_id: Option<String>,
        status: LocalShellStatus,
        action: LocalShellAction,
    },
    // ...
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/models.rs` (lines 1033-1039) | Rust 枚举定义 |
| `/codex-rs/app-server-protocol/schema/typescript/LocalShellStatus.ts` | TypeScript 类型定义（生成） |

### 相关类型

- `LocalShellAction`：Shell 操作类型
- `LocalShellExecAction`：Shell 执行参数
- `ResponseItem::LocalShellCall`：使用此状态的响应项

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化，使用 `snake_case` 命名策略
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 序列化示例

```json
// Completed
{
  "type": "local_shell_call",
  "status": "completed",
  "action": {
    "type": "exec",
    "command": ["echo", "hello"],
    // ...
  }
}

// InProgress
{
  "type": "local_shell_call",
  "status": "in_progress",
  "action": { /* ... */ }
}

// Incomplete
{
  "type": "local_shell_call",
  "status": "incomplete",
  "action": { /* ... */ }
}
```

### 使用场景

```rust
// 构造不同状态的 LocalShellCall

// 命令开始执行
let in_progress = ResponseItem::LocalShellCall {
    id: None,
    call_id: Some("call-123".to_string()),
    status: LocalShellStatus::InProgress,
    action: LocalShellAction::Exec(exec_action),
};

// 命令成功完成
let completed = ResponseItem::LocalShellCall {
    id: None,
    call_id: Some("call-123".to_string()),
    status: LocalShellStatus::Completed,
    action: LocalShellAction::Exec(exec_action),
};

// 命令失败或超时
let incomplete = ResponseItem::LocalShellCall {
    id: None,
    call_id: Some("call-123".to_string()),
    status: LocalShellStatus::Incomplete,
    action: LocalShellAction::Exec(exec_action),
};
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **状态模糊**：`Incomplete` 涵盖失败、超时、取消等多种情况，不够精确
2. **缺少退出码**：没有直接包含命令的退出码信息
3. **缺少错误信息**：`Incomplete` 状态没有说明具体原因

### 改进建议

1. **细化状态**：将 `Incomplete` 拆分为更具体的状态
   ```rust
   pub enum LocalShellStatus {
       Completed { exit_code: i32 },
       InProgress,
       Failed { exit_code: i32, error: Option<String> },
       Cancelled,
       TimedOut,
   }
   ```

2. **添加退出码**：
   ```rust
   pub struct LocalShellStatusInfo {
       pub status: LocalShellStatus,
       pub exit_code: Option<i32>,
       pub error_message: Option<String>,
   }
   ```

3. **添加时间信息**：
   ```rust
   pub started_at: Option<i64>,
   pub completed_at: Option<i64>,
   ```

4. **添加输出信息**：
   ```rust
   pub stdout_preview: Option<String>,
   pub stderr_preview: Option<String>,
   ```

### 测试建议

- 测试各状态的序列化/反序列化
- 测试状态流转的正确性
- 验证与 `ResponseItem::LocalShellCall` 的集成
- 测试边界情况（快速完成、长时间运行等）

### 与 Responses API 的对比

注意：此类型用于 `LocalShellCall`，而 Responses API 使用不同的命令执行模型。在 v2 API 中，命令执行使用 `CommandExecution` 相关的类型和通知。
