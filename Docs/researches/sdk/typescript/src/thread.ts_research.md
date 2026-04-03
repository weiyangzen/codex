# thread.ts 研究文档

## 场景与职责

`thread.ts` 是 TypeScript SDK 的核心业务逻辑模块，实现对话线程（Thread）的生命周期管理。核心职责：

1. **会话状态管理**：维护线程 ID，支持新建和恢复会话
2. **交互执行**：提供同步（`run`）和流式（`runStreamed`）两种调用模式
3. **事件聚合**：将底层 JSONL 事件流聚合为高层结果对象
4. **输入规范化**：支持多种输入格式（字符串、结构化输入、图片）
5. **资源清理**：确保临时文件（如 outputSchema）被正确清理

该模块是用户与 Codex Agent 交互的主要接口，封装了进程管理、事件解析等复杂性。

## 功能点目的

### 1. Thread 类

```typescript
export class Thread {
  private _exec: CodexExec;
  private _options: CodexOptions;
  private _id: string | null;
  private _threadOptions: ThreadOptions;

  public get id(): string | null { return this._id; }
}
```

**状态属性**：
- `_id`: 线程标识符，首次 `run()` 后通过 `thread.started` 事件填充
- `_exec`: 共享的执行器实例（多线程间复用）
- `_options` / `_threadOptions`: 全局与线程级配置

### 2. 同步执行模式（run）

```typescript
async run(input: Input, turnOptions: TurnOptions = {}): Promise<Turn>
```

**返回结构**：
```typescript
export type Turn = {
  items: ThreadItem[];      // 所有完成的线程项
  finalResponse: string;    // 最终文本响应
  usage: Usage | null;      // Token 使用统计
};
```

**事件聚合逻辑**：
```typescript
for await (const event of generator) {
  if (event.type === "item.completed") {
    if (event.item.type === "agent_message") {
      finalResponse = event.item.text;  // 提取最后一条消息
    }
    items.push(event.item);  // 收集所有项
  } else if (event.type === "turn.completed") {
    usage = event.usage;
  } else if (event.type === "turn.failed") {
    turnFailure = event.error;
    break;  // 提前终止
  }
}
```

### 3. 流式执行模式（runStreamed）

```typescript
async runStreamed(input: Input, turnOptions: TurnOptions = {}): Promise<StreamedTurn>

export type StreamedTurn = {
  events: AsyncGenerator<ThreadEvent>;  // 原始事件流
};
```

**设计模式**：生成器委托（Generator Delegation）
```typescript
async runStreamed(input, turnOptions): Promise<StreamedTurn> {
  return { events: this.runStreamedInternal(input, turnOptions) };
}
```

**用途**：允许调用者实时处理事件，实现渐进式 UI 更新

### 4. 输入规范化（normalizeInput）

```typescript
export type Input = string | UserInput[];

export type UserInput =
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };
```

**转换规则**：
| 输入类型 | prompt | images |
|----------|--------|--------|
| `string` | 原字符串 | `[]` |
| `UserInput[]` | 所有 `text` 类型用 `\n\n` 连接 | 所有 `local_image` 类型的 `path` |

## 具体技术实现

### 架构流程

```
┌─────────────────────────────────────────────────────────────┐
│  User Application                                             │
│  thread.run("Hello!") / thread.runStreamed("Hello!")         │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│  Thread.run() / runStreamed()                               │
│  ├─ normalizeInput(input) ──► { prompt, images }            │
│  ├─ createOutputSchemaFile(turnOptions.outputSchema)        │
│  │      └─ { schemaPath, cleanup }                          │
│  │                                                          │
│  └─ runStreamedInternal()                                   │
│         └─ this._exec.run({ ... })  // 调用执行器           │
│                ├─ input: prompt                             │
│                ├─ images                                    │
│                ├─ outputSchemaFile: schemaPath              │
│                └─ ... 其他选项                              │
└───────────────────────┬─────────────────────────────────────┘
                        │ AsyncGenerator<string> (JSONL)
┌───────────────────────▼─────────────────────────────────────┐
│  runStreamedInternal                                        │
│  ├─ for await (const line of exec.run())                    │
│  │    ├─ JSON.parse(line) as ThreadEvent                    │
│  │    ├─ if (type === "thread.started") this._id = thread_id│
│  │    └─ yield parsed                                       │
│  │                                                          │
│  └─ finally { await cleanup() }  // 清理 schema 文件        │
└───────────────────────┬─────────────────────────────────────┘
                        │ AsyncGenerator<ThreadEvent>
┌───────────────────────▼─────────────────────────────────────┐
│  run() [同步模式]                                           │
│  └─ 聚合事件为 Turn 对象                                    │
│       ├─ 收集 item.completed                                │
│       ├─ 提取 agent_message.text 作为 finalResponse         │
│       ├─ 捕获 turn.completed.usage                          │
│       └─ 处理 turn.failed（抛出错误）                       │
└─────────────────────────────────────────────────────────────┘
```

### 配置继承链

```
CodexOptions (全局)
    │
    ├──► baseUrl ───────────────────────┐
    ├──► apiKey ────────────────────────┤
    └──► config ────────────────────────┤
                                        ▼
ThreadOptions (线程级)              CodexExecArgs
    │                                   │
    ├──► model ────────────────────────┤
    ├──► sandboxMode ──────────────────┤
    ├──► workingDirectory ─────────────┤
    ├──► modelReasoningEffort ─────────┤
    ├──► networkAccessEnabled ─────────┤
    ├──► webSearchMode ────────────────┤
    ├──► approvalPolicy ───────────────┤
    └──► additionalDirectories ────────┘
                                        ▲
TurnOptions (单次调用)                  │
    │                                   │
    ├──► outputSchema ──► schemaPath ──┤
    └──► signal ───────────────────────┘
```

### 关键数据结构

#### 执行参数构建
```typescript
this._exec.run({
  input: prompt,
  baseUrl: this._options.baseUrl,
  apiKey: this._options.apiKey,
  threadId: this._id,  // 恢复模式时有效
  images,
  model: options?.model,
  sandboxMode: options?.sandboxMode,
  workingDirectory: options?.workingDirectory,
  skipGitRepoCheck: options?.skipGitRepoCheck,
  outputSchemaFile: schemaPath,
  modelReasoningEffort: options?.modelReasoningEffort,
  signal: turnOptions.signal,
  networkAccessEnabled: options?.networkAccessEnabled,
  webSearchMode: options?.webSearchMode,
  webSearchEnabled: options?.webSearchEnabled,
  approvalPolicy: options?.approvalPolicy,
  additionalDirectories: options?.additionalDirectories,
});
```

## 关键代码路径与文件引用

### 模块依赖图

```
thread.ts
├── 导入
│   ├── codexOptions.ts    # CodexOptions
│   ├── events.ts          # ThreadEvent, ThreadError, Usage
│   ├── exec.ts            # CodexExec
│   ├── items.ts           # ThreadItem
│   ├── threadOptions.ts   # ThreadOptions
│   ├── turnOptions.ts     # TurnOptions
│   └── outputSchemaFile.ts # createOutputSchemaFile
│
├── 导出
│   ├── Thread 类
│   ├── Turn / RunResult
│   ├── StreamedTurn / RunStreamedResult
│   ├── UserInput / Input
│
├── 被导入
│   ├── codex.ts           # startThread(), resumeThread()
│   └── index.ts           # 重新导出
│
└── 测试
    ├── tests/run.test.ts
    ├── tests/runStreamed.test.ts
    └── tests/abort.test.ts
```

### 调用时序

```
时间轴 ──────────────────────────────────────────────────────►

[初始化]
  │
  ├─ new Codex() ──► new CodexExec()
  │
  ├─ codex.startThread(options) ──► new Thread(exec, globalOpts, threadOpts, null)
  │   └─ _id = null
  │
  └─ codex.resumeThread(id, options) ──► new Thread(exec, globalOpts, threadOpts, id)
      └─ _id = id

[首次执行]
  │
  ├─ thread.run(input) / runStreamed(input)
  │   │
  │   ├─ normalizeInput(input) ──► { prompt, images }
  │   │
  │   ├─ createOutputSchemaFile(schema) ──► { schemaPath, cleanup }
  │   │
  │   └─ exec.run({ threadId: null, ... })  // 新建会话
  │       │
  │       └─ CLI 输出: {"type":"thread.started","thread_id":"abc123"}
  │           │
  │           └─ this._id = "abc123"  // 设置线程 ID
  │
  └─ finally { cleanup() }

[后续执行]
  │
  ├─ thread.run(input)
  │   │
  │   └─ exec.run({ threadId: "abc123", ... })  // 恢复会话
  │       └─ CLI 自动关联历史上下文
  │
  └─ finally { cleanup() }
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codexOptions.ts` | 全局配置类型 |
| `events.ts` | 事件类型定义 |
| `exec.ts` | CLI 执行器 |
| `items.ts` | 线程项类型 |
| `threadOptions.ts` | 线程级配置 |
| `turnOptions.ts` | 单次调用配置 |
| `outputSchemaFile.ts` | Schema 临时文件管理 |

### 外部契约

| 消费者 | 用途 |
|--------|------|
| `codex.ts` | 创建 Thread 实例 |
| `index.ts` | 重新导出公共 API |
| 用户应用 | 主要交互接口 |

### 与 CLI 的交互

**输入传递**：
- `input` → CLI stdin
- `images` → `--image` 参数（可重复）
- `threadId` → `resume <id>` 子命令

**输出生成**：
- CLI stdout → JSONL 事件流
- SDK 解析并转换为 `ThreadEvent` 对象

## 风险、边界与改进建议

### 状态管理风险

1. **线程 ID 竞态**
   - 风险：并发调用 `run()` 时 `_id` 可能被覆盖
   - 当前：依赖 CLI 序列化处理，SDK 无锁机制
   - 建议：添加执行状态锁，防止并发调用

2. **会话恢复失败**
   - 风险：`resumeThread()` 时传入无效 ID
   - 行为：CLI 报错，通过 `turn.failed` 事件传递
   - 建议：提供会话有效性预检 API

### 资源管理

1. **临时文件泄漏**
   - 风险：`cleanup()` 在极端情况下可能未执行
   - 缓解：使用 `try/finally` 确保清理
   - 改进：考虑 `AbortSignal` 集成到清理流程

2. **生成器资源**
   - 风险：流式模式下消费者可能不消费完所有事件
   - 当前：`finally` 块在生成器结束时执行
   - 建议：文档明确说明需要完整消费或显式关闭

### 边界条件

| 场景 | 行为 |
|------|------|
| 空字符串输入 | 有效，传递给 CLI |
| 空图片数组 | 不产生 `--image` 参数 |
| 无效图片路径 | CLI 报错 |
| `run()` 中 `turn.failed` | 抛出 `Error`，包含错误消息 |
| `runStreamed()` 中 `turn.failed` | 事件流中返回，不抛出 |
| 多次调用 `run()` | 同一会话继续，历史上下文累积 |
| 跨线程历史共享 | 不支持，每个 Thread 实例独立 |

### 改进建议

1. **执行锁**
   ```typescript
   private _running = false;
   
   async run(...) {
     if (this._running) throw new Error("Thread is already running");
     this._running = true;
     try { /* ... */ } finally { this._running = false; }
   }
   ```

2. **会话元数据**
   - 当前：仅暴露 `id`
   - 建议：增加 `createdAt`, `messageCount` 等属性

3. **批量输入**
   - 当前：单次 `run()` 处理一个输入
   - 建议：支持批量输入，减少进程启动开销

4. **流式结果增强**
   - 当前：`StreamedTurn` 仅包含事件流
   - 建议：增加 `abort()` 方法，支持外部取消

5. **类型安全增强**
   - 当前：`Input` 为 `string | UserInput[]`
   - 建议：提供模板字面量类型辅助
   ```typescript
   type InputBuilder = TemplateStringsArray | string | UserInput[];
   ```

### 测试覆盖

测试文件：
- `tests/run.test.ts` - 同步模式测试
- `tests/runStreamed.test.ts` - 流式模式测试
- `tests/abort.test.ts` - 取消信号测试

关键测试：
| 测试 | 覆盖点 |
|------|--------|
| `returns thread events` | 基本事件流 |
| `sends previous items when run is called twice` | 会话连续性 |
| `resumes thread by id` | 会话恢复 |
| `passes turn options to exec` | 配置传递 |
| `writes output schema to a temporary file` | Schema 处理 |
| `aborts run() when signal is aborted` | 取消机制 |

### 性能考量

| 操作 | 复杂度 | 优化建议 |
|------|--------|----------|
| 输入规范化 | O(n) | n = 输入数组长度 |
| 事件聚合 | O(m) | m = 事件数量 |
| 字符串连接 | O(k) | k = 总文本长度，使用数组 join 已优化 |
| 进程启动 | - | 主要开销，考虑连接池 |
