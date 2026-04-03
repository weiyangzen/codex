# TurnInterruptParams.json 研究文档

## 场景与职责

`TurnInterruptParams` 是 Codex App-Server Protocol v2 中定义的客户端请求参数类型，用于中断正在进行的 Turn（对话轮次）。这是用户控制对话流程的重要机制，允许用户在 AI 生成响应的过程中随时停止当前操作。

典型使用场景：
- 用户发现输入有误，需要立即停止当前生成
- AI 生成的内容不符合预期，用户想重新开始
- 长时间运行的操作需要被取消
- 用户需要紧急切换到其他任务

## 功能点目的

该参数类型的主要目的是：
1. **用户控制**：给予用户对对话流程的完全控制权
2. **响应取消**：停止正在进行的 AI 响应生成
3. **资源释放**：取消后可以释放相关资源
4. **快速迭代**：支持快速试错和重新输入

### Turn 中断流程

```
Client -> Server: turn/start (TurnStartParams)
Server -> Client: TurnStartedNotification
n... (AI 正在生成响应) ...n
Client -> Server: turn/interrupt (TurnInterruptParams)
Server -> Client: TurnInterruptResponse
Server -> Client: TurnCompletedNotification (status: interrupted)
```

### 中断时机

| 时机 | 行为 |
|------|------|
| AI 生成内容时 | 立即停止生成，返回已生成的内容 |
| 工具调用执行时 | 等待当前工具调用完成或尝试取消 |
| 文件变更时 | 根据配置决定是否回滚变更 |
| 命令执行时 | 发送 SIGINT 信号中断命令 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["threadId", "turnId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 3959-3970）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnInterruptParams {
    pub thread_id: String,
    pub turn_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnInterruptResponse {}
```

### 对应的 Response 类型

`TurnInterruptResponse` 是一个空对象，表示中断请求已被接收。实际的中断结果通过 `TurnCompletedNotification` 通知传递。

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
client_request_definitions! {
    TurnInterrupt => "turn/interrupt" {
        params: v2::TurnInterruptParams,
        response: v2::TurnInterruptResponse,
    },
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/TurnInterruptParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 3959-3970） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求注册（行 360-363） |

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `turn/interrupt` 请求
- 验证 Thread ID 和 Turn ID
- 向核心 Codex 引擎发送中断信号
- 返回 `TurnInterruptResponse`

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs` | Turn 中断功能测试 |

### 使用场景代码

位于 `codex-rs/exec/src/lib.rs`：
- Exec 模式下的中断处理

位于 `codex-rs/tui_app_server/src/app_server_session.rs`：
- TUI 应用服务器的中断处理

## 依赖与外部交互

### 上游依赖

1. **Turn 管理服务**：管理 Turn 的生命周期
2. **核心 Codex 引擎**：执行实际的中断操作
3. **命令执行系统**：中断正在执行的命令

### 下游消费者

1. **通知系统**：发送 `TurnCompletedNotification`（status: interrupted）
2. **资源管理**：释放被中断 Turn 占用的资源

### 相关类型

| 类型 | 说明 |
|------|------|
| `TurnInterruptResponse` | 中断请求的响应（空对象） |
| `TurnStatus::Interrupted` | 中断状态 |
| `TurnCompletedNotification` | Turn 完成通知（包含中断状态） |

## 风险、边界与改进建议

### 潜在风险

1. **中断延迟**：某些操作（如网络请求）可能无法立即中断
2. **状态不一致**：中断后可能留下部分完成的操作
3. **资源泄漏**：中断可能导致资源未正确释放
4. **数据丢失**：中断可能导致未保存的数据丢失

### 边界情况

1. **Turn 已完成**：尝试中断已完成的 Turn 应返回错误
2. **Turn 不存在**：Turn ID 不存在时应返回错误
3. **Thread 不存在**：Thread ID 不存在时应返回错误
4. **重复中断**：多次中断同一 Turn 应幂等处理
5. **中断超时**：中断操作本身可能超时

### 改进建议

1. **中断原因**：添加可选的中断原因字段
2. **优雅中断**：支持优雅中断（等待当前操作完成）和强制中断
3. **中断超时**：添加中断操作的超时控制
4. **回滚选项**：支持中断时自动回滚文件变更
5. **中断确认**：添加中断完成的确认机制

### 客户端最佳实践

```typescript
// 示例：客户端中断处理
async function interruptTurn(threadId: string, turnId: string): Promise<void> {
    try {
        // 发送中断请求
        await sendRequest('turn/interrupt', { threadId, turnId });
        
        // 等待 TurnCompletedNotification
        const notification = await waitForNotification('turn/completed', 
            n => n.turnId === turnId
        );
        
        if (notification.turn.status === 'interrupted') {
            console.log('Turn 已成功中断');
            updateUIState('interrupted');
        } else {
            console.warn('Turn 状态异常:', notification.turn.status);
        }
    } catch (error) {
        console.error('中断失败:', error);
        showErrorMessage('无法中断当前操作');
    }
}

// UI 中的中断按钮
function InterruptButton({ threadId, activeTurnId }: Props) {
    const [isInterrupting, setIsInterrupting] = useState(false);
    
    const handleInterrupt = async () => {
        setIsInterrupting(true);
        await interruptTurn(threadId, activeTurnId);
        setIsInterrupting(false);
    };
    
    return (
        <button 
            onClick={handleInterrupt}
            disabled={isInterrupting}
        >
            {isInterrupting ? '正在中断...' : '中断'}
        </button>
    );
}
```

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 与 v1 API 不兼容
- 中断响应为空对象，实际结果通过通知传递
