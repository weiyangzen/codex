# basic_streaming.ts 深度研究文档

## 场景与职责

`basic_streaming.ts` 是 OpenAI Codex TypeScript SDK 的**核心交互式示例程序**，展示如何使用 SDK 构建一个完整的命令行对话界面。它是 SDK 的「Hello World」级别的演示，同时也是理解 SDK 事件驱动架构的最佳入口点。

该示例实现了一个 REPL（Read-Eval-Print Loop）风格的交互式终端，允许用户：
- 持续输入自然语言指令
- 实时接收 AI 助手的响应
- 观察命令执行、文件变更、待办事项等中间状态

**典型使用场景**：
- 开发者首次体验 Codex SDK 功能
- 作为构建自定义 CLI 工具的参考模板
- 验证本地 Codex 可执行文件与 SDK 的集成

## 功能点目的

### 1. 实时流式事件处理
与同步调用 `thread.run()` 不同，本示例使用 `thread.runStreamed()` 方法，核心目的是展示**增量式事件消费**模式：
- 用户输入后立即获得 `AsyncGenerator<ThreadEvent>`
- 无需等待完整回合结束即可看到 AI 思考过程
- 支持展示动态更新的待办事项列表 (`todo_list`)

### 2. 多类型事件分类处理
示例实现了完整的事件类型分发逻辑，覆盖：

| 事件类型 | 处理函数 | 展示内容 |
|---------|---------|---------|
| `item.completed` | `handleItemCompleted` | 助手消息、推理过程、命令执行结果、文件变更 |
| `item.updated` / `item.started` | `handleItemUpdated` | 待办事项列表更新 |
| `turn.completed` | `handleEvent` | Token 使用量统计 |
| `turn.failed` | `handleEvent` | 错误信息 |

### 3. 会话状态管理
通过 `Codex` 和 `Thread` 对象维护：
- 长期会话上下文（Thread ID 自动管理）
- 跨回合的对话历史

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        main() 主循环                             │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐ │
│  │ readline    │───▶│ thread.run   │───▶│ for await event of  │ │
│  │ .question() │    │ Streamed()   │    │ result.events       │ │
│  └─────────────┘    └──────────────┘    └─────────────────────┘ │
│                                                    │              │
│                              ┌─────────────────────┘              │
│                              ▼                                    │
│                    ┌─────────────────┐                            │
│                    │  handleEvent()  │                            │
│                    │   (事件分发)     │                            │
│                    └────────┬────────┘                            │
│              ┌──────────────┼──────────────┐                      │
│              ▼              ▼              ▼                      │
│    ┌─────────────────┐ ┌──────────┐ ┌──────────────┐             │
│    │handleItemCompleted│ │handleItem│ │ turn.completed│            │
│    │                 │ │ Updated  │ │ turn.failed  │             │
│    └─────────────────┘ └──────────┘ └──────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### 核心数据结构

**ThreadEvent 联合类型**（来自 `@openai/codex-sdk`）：
```typescript
type ThreadEvent =
  | ThreadStartedEvent      // { type: "thread.started", thread_id: string }
  | TurnStartedEvent        // { type: "turn.started" }
  | TurnCompletedEvent      // { type: "turn.completed", usage: Usage }
  | TurnFailedEvent         // { type: "turn.failed", error: ThreadError }
  | ItemStartedEvent        // { type: "item.started", item: ThreadItem }
  | ItemUpdatedEvent        // { type: "item.updated", item: ThreadItem }
  | ItemCompletedEvent      // { type: "item.completed", item: ThreadItem }
  | ThreadErrorEvent;       // { type: "error", message: string }
```

**ThreadItem 联合类型**（事件载体）：
```typescript
type ThreadItem =
  | AgentMessageItem       // AI 文本响应
  | ReasoningItem          // 推理过程
  | CommandExecutionItem   // 命令执行（含 exit_code, status）
  | FileChangeItem         // 文件变更（add/delete/update）
  | TodoListItem           // 待办事项列表
  | McpToolCallItem        // MCP 工具调用
  | WebSearchItem          // 网络搜索
  | ErrorItem;             // 错误信息
```

### 协议与命令

**Shebang 指令**（第1行）：
```typescript
#!/usr/bin/env -S NODE_NO_WARNINGS=1 pnpm ts-node-esm --files
```
- `NODE_NO_WARNINGS=1`: 抑制 Node.js 警告输出
- `pnpm ts-node-esm`: 使用 ts-node 直接运行 TypeScript ESM 模块
- `--files`: 确保加载所有类型声明文件

**Codex 可执行文件定位**：
```typescript
const codex = new Codex({ codexPathOverride: codexPathOverride() });
```
通过 `helpers.ts` 的 `codexPathOverride()` 函数，按以下优先级定位：
1. 环境变量 `CODEX_EXECUTABLE`
2. 相对路径 `../../codex-rs/target/debug/codex`（开发模式）

**底层 CLI 调用协议**：
SDK 内部通过 `CodexExec` 类生成子进程：
```bash
codex exec --experimental-json [options] [resume <thread_id>]
```
输入通过 `child.stdin.write(input)` 传递，输出通过 `readline` 解析 JSON Lines。

## 关键代码路径与文件引用

### 直接依赖

| 文件路径 | 导入内容 | 用途 |
|---------|---------|------|
| `node:readline/promises` | `createInterface` | 终端交互 |
| `node:process` | `stdin`, `stdout` | 标准输入输出 |
| `@openai/codex-sdk` | `Codex`, `ThreadEvent`, `ThreadItem` | SDK 核心 API |
| `./helpers.ts` | `codexPathOverride` | 可执行文件路径解析 |

### SDK 内部调用链

```
basic_streaming.ts
    │
    ├──▶ new Codex(options) ────────────────────────┐
    │       └── src/codex.ts                         │
    │           └── new CodexExec(codexPathOverride) │
    │                                                │
    ├──▶ codex.startThread() ────────────────────────┤
    │       └── src/codex.ts                         │
    │           └── new Thread(exec, options)        │
    │                                                │
    └──▶ thread.runStreamed(input) ──────────────────┘
            └── src/thread.ts
                └── this._exec.run({...args})
                    └── src/exec.ts
                        └── spawn(codexPath, ["exec", "--experimental-json", ...])
```

### 事件来源

JSON Lines 事件由 `codex-rs/exec` crate 生成：
- **Rust 源文件**: `codex-rs/exec/src/event_processor_with_jsonl_output.rs`
- **事件定义**: `codex-rs/exec/src/exec_events.rs`
- **协议转换**: Rust `protocol::Event` → JSON → TypeScript `ThreadEvent`

## 依赖与外部交互

### 运行时依赖

| 依赖项 | 版本要求 | 说明 |
|-------|---------|------|
| Node.js | >=18 | ESM 模块支持 |
| pnpm | 10.29.3+ | 包管理器（由 shebang 指定） |
| ts-node | ^10.9.2 | TypeScript 直接执行 |
| @openai/codex-sdk | 0.0.0-dev | SDK 本身 |
| codex (Rust binary) | 对应版本 | 核心执行引擎 |

### 环境变量

| 变量名 | 作用 | 示例值 |
|-------|------|-------|
| `CODEX_EXECUTABLE` | 覆盖 Codex 可执行文件路径 | `/usr/local/bin/codex` |
| `CODEX_API_KEY` | OpenAI API 密钥（由 SDK 传递） | `sk-...` |

### 外部进程交互

```
Node.js Process
    │ spawn()
    ▼
┌─────────────┐
│ codex exec  │──▶ OpenAI API (Responses/Chat Completion)
│  (Rust)     │
└─────────────┘──▶ Local shell commands (sandboxed)
    │
    └── stdout (JSON Lines) ──▶ SDK parse ──▶ ThreadEvent
```

## 风险、边界与改进建议

### 已知风险

1. **无限循环风险**（第70-80行）
   ```typescript
   while (true) {
     const inputText = await rl.question(">");
     // ...
   }
   ```
   - 无退出命令处理（如 `/quit` 或 `Ctrl+C`）
   - 仅能通过 `SIGINT` 信号终止进程
   - **建议**: 添加特定退出指令检测（如输入 `exit` 或 `quit` 时 break）

2. **异常处理不完整**
   - `handleItemCompleted` 未处理所有 `ThreadItem` 类型（如 `mcp_tool_call`, `web_search`, `error`）
   - 这些类型会被静默忽略，可能导致信息丢失
   - **建议**: 添加 `default` case 或明确处理剩余类型

3. **资源泄漏风险**
   - `finally` 块中仅关闭 `readline`，未显式清理 Thread 资源
   - 长时间运行可能积累未清理的临时文件（如输出模式生成的 schema 文件）

### 边界条件

| 场景 | 当前行为 | 潜在问题 |
|-----|---------|---------|
| 空输入 | `continue` 跳过 | 合理 |
| 仅空白字符输入 | `trim().length === 0` 过滤 | 合理 |
| AI 返回非零 exit code | 显示 `Exit code N` | 不中断流程，仅展示 |
| 网络中断 | `turn.failed` 事件 | 当前仅打印错误，不尝试恢复 |
| 超大输出 | 全量加载到内存 | 无流式分块处理 |

### 改进建议

1. **增强交互体验**
   ```typescript
   // 建议添加
   if (trimmed === 'exit' || trimmed === 'quit') {
     console.log('Goodbye!');
     break;
   }
   ```

2. **完善事件处理**
   ```typescript
   // 在 handleItemCompleted 中添加
   default:
     console.log(`Unhandled item type: ${(item as any).type}`);
   ```

3. **添加信号处理**
   ```typescript
   process.on('SIGINT', () => {
     rl.close();
     process.exit(0);
   });
   ```

4. **配置化扩展**
   - 支持通过环境变量或 CLI 参数配置模型、沙盒模式
   - 示例：`MODEL=gpt-4o pnpm ts-node basic_streaming.ts`

5. **历史记录持久化**
   - 当前每次启动都是新会话
   - 可添加 `resume_thread_id` 环境变量支持恢复历史会话

### 相关测试

- `sdk/typescript/tests/runStreamed.test.ts`: 验证流式事件序列
- 测试覆盖：事件顺序、线程恢复、schema 选项传递
