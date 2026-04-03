# ThreadShellCommandParams 类型研究报告

## 场景与职责

`ThreadShellCommandParams` 是 Codex App-Server Protocol v2 中的参数类型，用于在特定线程上下文中执行 shell 命令。与通用的 `command/exec` 不同，此接口专门为线程提供 shell 命令执行能力。

**主要使用场景：**
- 在特定对话线程的上下文中执行 shell 命令
- 需要保留完整 shell 语法（管道、重定向、引号等）的场景
- 需要访问线程工作目录的 shell 操作
- 需要线程环境变量的命令执行

**职责范围：**
- 标识目标线程（`threadId`）
- 提供要执行的 shell 命令字符串（`command`）
- 明确命令执行的边界和安全特性

**重要安全警告**（来自代码注释）：
- 此命令**以非沙箱模式运行，拥有完全访问权限**
- 不继承线程的沙箱策略
- 可以执行任意系统命令

## 功能点目的

该类型的核心目的是为 `thread/shell_command` RPC 调用提供参数，使客户端能够：

1. **在线程上下文中执行命令**: 使用线程配置的工作目录和环境
2. **保留完整 shell 语法**: 支持管道、重定向、变量扩展等高级特性
3. **灵活的系统访问**: 绕过沙箱限制，执行需要完全访问权限的操作

**与 `command/exec` 的区别：**

| 特性 | ThreadShellCommandParams | command/exec |
|------|-------------------------|--------------|
| 沙箱策略 | 无沙箱，完全访问 | 继承线程沙箱策略 |
| Shell 语法 | 完整保留 | 可能简化或限制 |
| 使用场景 | 需要完整 shell 功能 | 安全受限的执行 |
| 线程上下文 | 明确关联线程 | 独立执行 |

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadShellCommandParams = {
  threadId: string,
  /**
   * Shell command string evaluated by the thread's configured shell.
   * Unlike `command/exec`, this intentionally preserves shell syntax
   * such as pipes, redirects, and quoting. This runs unsandboxed with full
   * access rather than inheriting the thread sandbox policy.
   */
  command: string,
};
```

### Rust 源类型定义

```rust
// Line 2876-2886
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadShellCommandParams {
    pub thread_id: String,
    /// Shell command string evaluated by the thread's configured shell.
    /// Unlike `command/exec`, this intentionally preserves shell syntax
    /// such as pipes, redirects, and quoting. This runs unsandboxed with full
    /// access rather than inheriting the thread sandbox policy.
    pub command: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 目标线程的唯一标识符 |
| `command` | `string` | 要在线程 shell 中执行的命令字符串 |

### 命令字符串特性

支持的标准 shell 语法：
- **管道**: `cat file.txt | grep "pattern" | wc -l`
- **重定向**: `echo "content" > file.txt`, `command >> log.txt 2>&1`
- **引号**: `"double quotes"`, `'single quotes'`
- **变量**: `$HOME`, `${VAR}`, `$(command substitution)`
- **逻辑操作**: `&&`, `||`, `;`
- **后台执行**: `&`
- **通配符**: `*`, `?`, `[...]`

### 执行上下文

- **工作目录**: 线程的 `cwd`（当前工作目录）
- **Shell**: 线程配置的 shell（如 bash、zsh、fish）
- **环境变量**: 继承线程的环境变量
- **权限**: 完全系统访问权限（无沙箱限制）

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadShellCommandParams.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2879-2886

### 相关类型
| 类型 | 说明 | 路径 |
|------|------|------|
| ThreadShellCommandResponse | 命令执行的响应（空对象） | `v2/ThreadShellCommandResponse.ts` |
| Thread | 线程对象，提供执行上下文 | `v2/Thread.ts` |
| CommandExecParams | 通用命令执行参数 | `v2/CommandExecParams.ts` |
| SandboxPolicy | 线程的沙箱策略（此接口不继承） | `v2/SandboxPolicy.ts` |

### 使用场景
- 与 `ThreadShellCommandResponse` 配对使用
- 用于需要完整 shell 功能的场景
- 通常需要用户明确确认（由于安全原因）

## 依赖与外部交互

### 内部依赖

1. **Thread 类型**: 提供执行上下文（cwd、shell、环境变量）
2. **系统 Shell**: 实际执行命令的 shell 程序

### 外部交互

1. **与 ThreadShellCommandResponse 的交互**:
   - 发送命令执行请求
   - 返回空对象表示命令已启动（非完成）

2. **与输出通知的交互**:
   - 命令输出通过 `CommandExecOutputDeltaNotification` 流式传输
   - 客户端需要订阅通知以获取实时输出

3. **与线程状态的关系**:
   - 命令执行可能影响线程状态
   - 文件变更、环境变量修改等

### 安全模型

```
┌─────────────────────────────────────────────────────────────┐
│                    ThreadShellCommand                        │
│                                                              │
│  ┌─────────────────┐      ┌──────────────────────────────┐  │
│  │  Thread Context │      │     Execution Environment    │  │
│  │  - thread_id    │─────▶│     ⚠️ UNSANDBOXED           │  │
│  │  - cwd          │      │     ⚠️ FULL ACCESS           │  │
│  │  - shell        │      │                              │  │
│  │  - env vars     │      │  - System commands           │  │
│  └─────────────────┘      │  - File system access        │  │
│                           │  - Network access            │  │
│  ┌─────────────────┐      │  - Process management        │  │
│  │  Command String │─────▶│                              │  │
│  │  - pipes        │      │  No sandbox restrictions!    │  │
│  │  - redirects    │      └──────────────────────────────┘  │
│  │  - variables    │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

### 与 command/exec 的对比

```rust
// command/exec - 受沙箱限制
CommandExecParams {
    command: "ls",  // 可能只支持简单命令
    // 继承线程沙箱策略
}

// thread/shell_command - 完全访问
ThreadShellCommandParams {
    thread_id: "thread-123",
    command: "cat /etc/passwd | grep user > output.txt && echo done",
    // 无沙箱限制，完整 shell 语法
}
```

## 风险、边界与改进建议

### 潜在风险

1. **安全风险（严重）**:
   - 无沙箱限制，可执行任意系统命令
   - 可能导致数据丢失、系统损坏
   - 恶意命令可能窃取敏感信息
   - 建议：添加严格的权限检查和用户确认

2. **注入攻击**:
   - 如果 `command` 包含用户输入，可能存在命令注入
   - 示例危险场景：`command: "echo " + userInput`
   - 建议：对输入进行严格验证和转义

3. **资源耗尽**:
   - 命令可能消耗大量 CPU、内存、磁盘
   - 无限循环或 fork 炸弹
   - 建议：添加资源限制和超时机制

4. **状态不一致**:
   - 命令可能修改线程工作目录外的文件
   - 与线程历史记录不同步
   - 建议：明确记录命令执行日志

### 边界情况

1. **空命令**: `command: ""` 应如何处理？
2. **超长命令**: 命令字符串长度限制
3. **特殊字符**: Unicode、控制字符的处理
4. **并发执行**: 多个 shell 命令同时执行
5. **线程不存在**: 应返回明确的错误
6. **Shell 不可用**: 配置的 shell 不存在时的降级

### 改进建议

1. **添加安全限制**:
   ```rust
   pub struct ThreadShellCommandParams {
       pub thread_id: String,
       pub command: String,
       pub timeout_seconds: Option<u32>,  // 超时限制
       pub max_output_size: Option<u64>,  // 输出大小限制
       pub working_directory: Option<PathBuf>,  // 可选覆盖 cwd
   }
   ```

2. **添加确认机制**:
   ```rust
   pub struct ThreadShellCommandParams {
       pub thread_id: String,
       pub command: String,
       pub require_confirmation: bool,  // 是否需要用户确认
       pub confirmation_token: Option<String>,  // 预授权令牌
   }
   ```

3. **返回执行信息**:
   ```typescript
   export type ThreadShellCommandResponse = {
     executionId: string,      // 用于追踪和取消
     pid: number,              // 进程 ID
     startedAt: number,        // 开始时间戳
   };
   ```

4. **添加审计日志**:
   - 记录所有执行的命令
   - 记录执行者、时间、结果
   - 支持安全审计

5. **输入验证**:
   ```rust
   impl ThreadShellCommandParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.command.is_empty() {
               return Err(ValidationError::EmptyCommand);
           }
           if self.command.len() > 10_000 {
               return Err(ValidationError::CommandTooLong);
           }
           // 可选：危险命令检测
           if contains_dangerous_patterns(&self.command) {
               return Err(ValidationError::PotentiallyDangerous);
           }
           Ok(())
       }
   }
   ```

6. **渐进式权限**:
   - 为常用操作提供安全的替代 API
   - 仅在必要时使用完全访问的 shell 命令
   - 建立权限分级体系

7. **命令模板**:
   - 支持预定义的命令模板
   - 参数化替换而非直接拼接
   - 减少注入风险

8. **取消机制**:
   - 添加 `ThreadShellCommandCancelParams`
   - 允许中断长时间运行的命令
   - 防止资源占用
