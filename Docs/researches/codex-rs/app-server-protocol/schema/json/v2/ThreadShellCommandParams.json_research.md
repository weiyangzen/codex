# ThreadShellCommandParams.json 研究文档

## 场景与职责

`ThreadShellCommandParams` 是 Codex App Server Protocol v2 中 `thread/shellCommand` 方法的请求参数结构，用于在指定线程的上下文中执行 shell 命令。这是一个特殊的命令执行 API，与 `command/exec` 有重要区别。

该功能允许用户：
- 在线程上下文中执行任意 shell 命令
- 利用线程配置的 shell 环境（工作目录、环境变量等）
- 将命令执行作为独立的 turn 记录到线程历史中

**重要区别**: 与 `command/exec` 不同，`thread/shellCommand`：
- 保留完整的 shell 语法（管道、重定向、引号等）
- **在非沙箱环境下运行，具有完全访问权限**
- 不继承线程的沙箱策略

## 功能点目的

### 核心功能
- **Shell 命令执行**: 在线程上下文中执行用户提供的 shell 命令
- **历史记录**: 命令执行作为 `CommandExecution` 项记录到线程历史中
- **实时输出**: 通过 `CommandExecutionOutputDelta` 通知流式输出

### 使用场景
1. 用户需要在线程工作目录下执行快速命令
2. 利用 shell 管道和重定向进行复杂操作
3. 需要完整系统访问权限的特殊操作（非沙箱限制）

### 安全警告
- 该命令在**非沙箱环境**下运行
- 具有**完全系统访问权限**
- 客户端应明确提示用户此风险

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadShellCommandParams {
    /// 目标线程 ID
    pub thread_id: String,
    
    /// Shell 命令字符串，由线程配置的 shell 执行
    /// 
    /// 与 `command/exec` 不同，此字段保留完整的 shell 语法：
    /// - 管道 (|)
    /// - 重定向 (>, <, >>)
    /// - 引号和转义
    /// 
    /// 注意：此命令在非沙箱环境下运行，具有完全访问权限
    pub command: String,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "command": {
      "description": "Shell command string evaluated by the thread's configured shell...",
      "type": "string"
    },
    "threadId": {
      "type": "string"
    }
  },
  "required": ["command", "threadId"],
  "title": "ThreadShellCommandParams",
  "type": "object"
}
```

### 关键流程

1. **请求处理入口**: `CodexMessageProcessor::thread_shell_command()` (codex_message_processor.rs:2983)
2. **命令清理**: 去除首尾空白字符
3. **空命令检查**: 拒绝空字符串命令
4. **线程加载**: 获取目标线程实例
5. **核心操作提交**: 发送 `Op::RunUserShellCommand { command }` 到线程执行器
6. **响应返回**: 立即返回空的 `ThreadShellCommandResponse`
7. **异步执行**: 命令在后台执行，通过通知发送输出

### 命令执行流程

```rust
match self
    .submit_core_op(
        &request_id,
        thread.as_ref(),
        Op::RunUserShellCommand { command },
    )
    .await
{
    Ok(_) => {
        self.outgoing
            .send_response(request_id, ThreadShellCommandResponse {})
            .await;
    }
    Err(err) => {
        self.send_internal_error(
            request_id,
            format!("failed to start shell command: {err}"),
        )
        .await;
    }
}
```

### 执行源标识

命令执行在 ThreadItem 中标记为 `CommandExecutionSource::UserShell`：

```rust
pub enum CommandExecutionSource {
    Agent,                  // 代理执行的命令
    UserShell,             // 用户通过 thread/shellCommand 执行
    UnifiedExecStartup,    // 统一执行启动
    UnifiedExecInteraction, // 统一执行交互
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadShellCommandParams 结构体定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: ClientRequest 枚举 ThreadShellCommand 变体

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_shell_command()` 方法 (line 2983-3033)

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs`:
  - `thread_shell_command_runs_as_standalone_turn_and_persists_history`: 独立 turn 执行和历史持久化
  - `thread_shell_command_uses_existing_active_turn`: 复用活跃 turn

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadShellCommandParams.ts`

## 依赖与外部交互

### 内部依赖
- **codex_core**: `Op::RunUserShellCommand` 操作码
- **codex_protocol**: `CommandExecutionSource` 枚举

### 外部交互
- **Shell 进程**: 启动系统 shell（bash/zsh 等）执行命令
- **PTY**: 可能使用伪终端支持交互式命令
- **文件系统**: 在线程的当前工作目录下执行

### 响应结构
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadShellCommandResponse {}
```

### 关联通知
- `ItemStartedNotification`: 命令开始执行
- `CommandExecutionOutputDeltaNotification`: 输出增量
- `ItemCompletedNotification`: 命令执行完成

## 风险、边界与改进建议

### 已知风险

1. **安全漏洞**: 命令在非沙箱环境下运行，具有完全系统访问权限
2. **命令注入**: 如果命令字符串包含用户输入，可能存在注入风险
3. **资源耗尽**: 长时间运行的命令可能占用系统资源
4. **并发冲突**: 多个 shell 命令同时执行可能产生竞态条件

### 边界情况

1. **空命令**: 服务端拒绝空字符串，返回无效请求错误
2. **长时间运行**: 命令可能超时或被中断
3. **大输出**: 大量输出可能导致内存问题
4. **交互式命令**: 需要终端输入的命令可能挂起

### 改进建议

1. **超时控制**: 添加命令执行超时机制
2. **输出限制**: 限制最大输出大小，防止内存溢出
3. **沙箱选项**: 考虑提供可选的沙箱执行模式
4. **命令白名单**: 可选的危险命令拦截机制
5. **审计日志**: 记录所有执行的 shell 命令用于安全审计
6. **取消支持**: 允许客户端取消正在执行的命令

### 安全最佳实践
- 客户端应明确警告用户此命令在非沙箱环境下运行
- 考虑对命令进行预检查，拦截已知的危险操作
- 限制可执行命令的范围（如禁止 rm -rf /）
- 记录命令执行日志用于安全审计
