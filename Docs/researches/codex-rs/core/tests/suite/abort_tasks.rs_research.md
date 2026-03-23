# abort_tasks.rs 研究文档

## 场景与职责

`abort_tasks.rs` 是 Codex Core 的集成测试文件，专注于测试**任务中断（Task Abort）**功能。该功能允许用户在长时间运行的工具执行过程中发送中断信号，使系统能够优雅地终止当前操作并记录中断状态。

核心测试场景包括：
1. 用户主动中断长时间运行的 shell 命令（如 `sleep 60`）
2. 中断后历史记录正确保存，包含中断标记
3. 后续对话轮次能够正确携带中断上下文

## 功能点目的

### 1. 中断信号传递 (`Op::Interrupt`)
- 允许用户通过提交 `Interrupt` 操作来终止当前正在执行的 turn
- 中断信号通过 `CodexThread` 的事件循环传播到正在执行的工具

### 2. TurnAborted 事件
- 当工具执行被成功中断后，系统会发出 `TurnAborted` 事件
- 该事件标志着当前 turn 的异常终止，与正常完成的 `TurnComplete` 区分

### 3. 中断历史记录
- 中断发生后，系统会在对话历史中记录 `function_call_output`，包含：
  - 已执行的 wall time（实际运行时间）
  - "aborted by user" 标记
- 后续请求会携带 `<turn_aborted>` 标记，让模型了解上下文

## 具体技术实现

### 关键流程

```
用户提交 Op::Interrupt
    ↓
CodexThread 处理中断信号
    ↓
正在执行的 ToolRuntime 收到取消信号
    ↓
工具执行终止，生成部分输出
    ↓
发送 TurnAborted 事件
    ↓
记录 function_call_output 到历史
    ↓
后续请求携带 <turn_aborted> 标记
```

### 核心数据结构

**EventMsg 枚举（协议层）**:
```rust
pub enum EventMsg {
    ExecCommandBegin(ExecCommandBeginEvent),
    TurnAborted(TurnAbortedEvent),
    TurnComplete(TurnCompleteEvent),
    // ... 其他事件
}
```

**Op 枚举（操作类型）**:
```rust
pub enum Op {
    UserInput { items: Vec<UserInput>, ... },
    Interrupt,
    // ... 其他操作
}
```

### 测试辅助函数

**等待特定事件** (`wait_for_event`):
```rust
pub async fn wait_for_event<F>(
    codex: &CodexThread,
    predicate: F,
) -> EventMsg
where F: FnMut(&EventMsg) -> bool
```

**SSE 事件构造** (来自 `core_test_support::responses`):
- `ev_function_call(call_id, name, args)` - 构造函数调用事件
- `ev_completed(id)` - 构造响应完成事件
- `sse(events)` - 将事件列表序列化为 SSE 格式

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/abort_tasks.rs` - 本测试文件

### 被测试的核心代码
- `codex-rs/core/src/agent/control.rs` - Agent 控制逻辑，包含中断处理
- `codex-rs/core/src/codex.rs` - Codex 核心逻辑，处理 `Op::Interrupt`
- `codex-rs/core/src/tasks/mod.rs` - 任务管理，支持取消操作

### 测试支持代码
- `codex-rs/core/tests/common/responses.rs` - Mock SSE 响应服务器
- `codex-rs/core/tests/common/test_codex.rs` - 测试辅助工具
- `codex-rs/core/tests/common/lib.rs` - 通用测试工具（`wait_for_event`）

### 协议定义
- `codex-rs/protocol/src/protocol.rs` - `EventMsg`, `Op` 定义

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|------|------|
| `assert_matches` | 模式匹配断言 |
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化 |
| `regex_lite` | 正则匹配中断输出 |

### Mock 服务器交互
测试使用 `wiremock::MockServer` 模拟 OpenAI Responses API：
1. `start_mock_server()` - 启动 Mock 服务器
2. `mount_sse_once(&server, body)` - 挂载单次 SSE 响应
3. `mount_sse_sequence(&server, bodies)` - 挂载顺序响应序列

### 核心 crate 依赖
- `codex_protocol` - 协议类型（`EventMsg`, `Op`, `UserInput`）
- `core_test_support` - 测试支持库

## 风险、边界与改进建议

### 当前风险点

1. **竞态条件**
   - 测试使用 `wait_for_event(&codex, |ev| matches!(ev, EventMsg::ExecCommandBegin(_)))` 等待命令开始
   - 如果命令在订阅事件前就开始，可能导致等待超时
   - 缓解：测试使用 0.1 秒延迟确保执行已开始

2. **时间依赖断言**
   - `interrupt_tool_records_history_entries` 测试断言 wall time >= 0.1 秒
   - 在极度缓慢的 CI 环境中可能不稳定

3. **Mock 服务器限制**
   - 测试依赖精确的事件顺序，如果实现改变事件发射顺序，测试会失败

### 边界情况

1. **空输入中断**
   - 测试未覆盖用户在中断后立即发送新消息的场景

2. **多工具调用中断**
   - 当前测试只覆盖单工具调用中断，未测试并行工具调用的中断行为

3. **网络中断 vs 用户中断**
   - 测试只覆盖用户主动中断，未测试网络断开导致的被动中断

### 改进建议

1. **增强测试稳定性**
   ```rust
   // 建议：使用更宽松的 time 断言
   assert!(secs >= 0.05, "expected at least 50ms of elapsed time");
   ```

2. **增加并发测试**
   - 添加测试用例验证多个并行工具调用时中断其中一个的行为

3. **增加恢复测试**
   - 测试中断后 session 状态的一致性
   - 验证中断后能否正确恢复对话流程

4. **代码覆盖率**
   - 当前测试覆盖主流程，建议增加对边缘情况的覆盖：
     - 中断已完成的 turn
     - 重复中断
     - 中断后快速连续发送多条消息

5. **文档改进**
   - 建议在 `TurnAborted` 事件中增加更多上下文信息（如被中断的工具调用 ID）
