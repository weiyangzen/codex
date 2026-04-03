# events.ts 研究文档

## 场景与职责

`events.ts` 定义 TypeScript SDK 的事件类型系统，对应 Codex CLI 通过 JSONL 流输出的结构化事件。核心职责：

1. **事件契约定义**：完整描述 CLI 输出的 JSONL 事件结构
2. **类型安全保证**：为事件流处理提供 TypeScript 类型支持
3. **与 Rust 端同步**：保持与 `codex-rs/exec/src/exec_events.rs` 的类型一致

该模块是 SDK 事件驱动架构的基础，所有实时状态更新都通过这些类型表达。

## 功能点目的

### 1. 事件类型体系

```typescript
export type ThreadEvent =
  | ThreadStartedEvent      // 会话开始
  | TurnStartedEvent        // 单次交互开始
  | TurnCompletedEvent      // 单次交互完成
  | TurnFailedEvent         // 单次交互失败
  | ItemStartedEvent        // 线程项开始
  | ItemUpdatedEvent        // 线程项更新
  | ItemCompletedEvent      // 线程项完成
  | ThreadErrorEvent;       // 致命错误
```

**设计原则**：
- **Discriminated Union**：通过 `type` 字段区分事件类型
- **生命周期完整**：覆盖从会话创建到交互完成的完整生命周期
- **粒度适中**：平衡信息完整性和处理复杂度

### 2. 核心事件详解

#### ThreadStartedEvent
```typescript
export type ThreadStartedEvent = {
  type: "thread.started";
  thread_id: string;  // 会话唯一标识，用于恢复
};
```
**触发时机**：CLI 成功初始化会话后发送的第一个事件
**用途**：获取会话 ID，后续 `resumeThread()` 依赖此 ID

#### TurnStartedEvent / TurnCompletedEvent
```typescript
export type TurnStartedEvent = { type: "turn.started" };

export type TurnCompletedEvent = {
  type: "turn.completed";
  usage: Usage;  // Token 消耗统计
};
```
**概念**：Turn（交互轮次）= 用户输入 → 模型处理 → 响应完成
**边界**：包含所有中间产生的 Item（命令执行、文件变更等）

#### Item 事件家族
```typescript
export type ItemStartedEvent = { type: "item.started"; item: ThreadItem };
export type ItemUpdatedEvent = { type: "item.updated"; item: ThreadItem };
export type ItemCompletedEvent = { type: "item.completed"; item: ThreadItem };
```
**状态机**：
```
item.started (in_progress)
    │
    ├──► [optional] item.updated (状态变更)
    │
    └──► item.completed (completed/failed)
```

### 3. Usage 统计

```typescript
export type Usage = {
  input_tokens: number;         // 输入 token 数
  cached_input_tokens: number;  // 缓存命中 token 数
  output_tokens: number;        // 输出 token 数
};
```
**数据来源**：OpenAI Responses API 的 `usage` 字段
**用途**：成本估算、性能监控

## 具体技术实现

### 与 Rust 端的类型映射

| TypeScript (events.ts) | Rust (exec_events.rs) | 说明 |
|------------------------|----------------------|------|
| `ThreadEvent` | `ThreadEvent` | 顶层联合类型 |
| `ThreadStartedEvent` | `ThreadStartedEvent` | 会话开始 |
| `TurnCompletedEvent` | `TurnCompletedEvent` | 交互完成 |
| `Usage` | `Usage` | Token 统计 |
| `ThreadError` | `ThreadErrorEvent` | 错误信息 |

**同步机制**：
- Rust 端使用 `ts_rs::TS` derive 宏自动生成 TypeScript 类型
- 手动维护的 `events.ts` 作为备用，确保类型可用

### 事件流处理模式

```typescript
// thread.ts 中的事件处理
async *runStreamedInternal(): AsyncGenerator<ThreadEvent> {
  for await (const line of generator) {
    const parsed = JSON.parse(line) as ThreadEvent;
    
    if (parsed.type === "thread.started") {
      this._id = parsed.thread_id;  // 捕获会话 ID
    }
    
    yield parsed;  // 传递给调用者
  }
}
```

### 事件聚合（thread.ts）

```typescript
async run(input: Input): Promise<Turn> {
  const generator = this.runStreamedInternal(input, turnOptions);
  const items: ThreadItem[] = [];
  
  for await (const event of generator) {
    switch (event.type) {
      case "item.completed":
        items.push(event.item);  // 收集完成的项
        break;
      case "turn.completed":
        usage = event.usage;     // 捕获用量
        break;
      case "turn.failed":
        throw new Error(event.error.message);  // 异常终止
    }
  }
  
  return { items, finalResponse, usage };
}
```

## 关键代码路径与文件引用

### 类型依赖图

```
events.ts
├── 导入
│   └── items.ts           # ThreadItem 类型
│
├── 导出类型
│   ├── ThreadEvent        # 顶层联合类型
│   ├── ThreadStartedEvent # 会话生命周期
│   ├── Turn*Event         # 交互轮次事件
│   ├── Item*Event         # 线程项事件
│   ├── ThreadError        # 错误类型
│   └── Usage              # Token 统计
│
├── 被导入
│   ├── thread.ts          # 事件流处理
│   ├── index.ts           # 重新导出
│   └── samples/*.ts       # 示例代码
│
└── 与 Rust 对应
    └── codex-rs/exec/src/exec_events.rs
```

### 事件流向

```
┌─────────────────────────────────────────┐
│  Codex CLI (Rust)                       │
│  - EventProcessorWithJsonOutput         │
│  - serde_json::to_string()              │
└─────────────────┬───────────────────────┘
                  │ JSONL 流
┌─────────────────▼───────────────────────┐
│  Node.js Child Process                  │
│  - stdout 管道                          │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  exec.ts                                │
│  - readline.createInterface()           │
│  - yield line (string)                  │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  thread.ts                              │
│  - JSON.parse()                         │
│  - 类型断言 as ThreadEvent              │
│  - 分发到具体处理逻辑                   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  User Application                       │
│  - for await (const event of events)    │
│  - switch (event.type) 处理             │
└─────────────────────────────────────────┘
```

## 依赖与外部交互

### 内部依赖

| 模块 | 类型 | 用途 |
|------|------|------|
| `items.ts` | 类型 | `ThreadItem` 定义 |

### 外部契约

| 消费者 | 消费内容 | 用途 |
|--------|----------|------|
| `thread.ts` | `ThreadEvent`, `Usage` | 事件流解析与聚合 |
| `index.ts` | 所有事件类型 | 重新导出供外部使用 |
| `samples/basic_streaming.ts` | `ThreadEvent`, `ThreadItem` | 示例事件处理 |

### 与 CLI 的协议契约

事件格式（JSONL - JSON Lines）：
```jsonl
{"type":"thread.started","thread_id":"thread_abc123"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Hello!"}}
{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}
```

**协议版本**：`--experimental-json` 标志启用（`exec.ts:73`）

## 风险、边界与改进建议

### 类型一致性风险

1. **与 Rust 端不同步**
   - 风险：Rust 端更新事件结构后，TypeScript 类型未同步
   - 当前：手动维护，无自动化检查
   - 缓解：Rust 使用 `ts_rs` 生成类型，但 SDK 使用手动版本

2. **JSON 解析失败**
   - 风险：CLI 输出非 JSON 内容（如 panic 信息）
   - 处理：`thread.ts:99-103` 捕获解析错误并抛出
   ```typescript
   try {
     parsed = JSON.parse(item) as ThreadEvent;
   } catch (error) {
     throw new Error(`Failed to parse item: ${item}`, { cause: error });
   }
   ```

### 事件处理边界

| 场景 | 行为 |
|------|------|
| 未知事件类型 | TypeScript 编译错误（Discriminated Union 保护） |
| 事件顺序异常 | 依赖 CLI 保证，SDK 无重排序逻辑 |
| 流中断 | `finally` 块清理资源，`turn.failed` 事件可能未到达 |
| 重复 `thread.started` | 后到达的会覆盖 `_id`（理论不应发生） |

### 改进建议

1. **类型生成自动化**
   - 建议：从 Rust 的 `ts_rs` 输出自动生成 `events.ts`
   - 实现：构建时脚本复制生成的 `.d.ts` 文件

2. **事件校验**
   - 当前：仅依赖 TypeScript 类型断言
   - 建议：运行时校验（如 zod schema）
   ```typescript
   import { z } from 'zod';
   const ThreadEventSchema = z.discriminatedUnion('type', [...]);
   const parsed = ThreadEventSchema.parse(JSON.parse(line));
   ```

3. **心跳/保活机制**
   - 当前：无心跳事件，长连接可能静默断开
   - 建议：CLI 定期发送 `ping` 事件，SDK 检测超时

4. **事件时间戳**
   - 当前：事件无时间戳
   - 建议：增加 `timestamp` 字段，便于性能分析

5. **批量事件**
   - 当前：每个 JSON 行一个事件
   - 建议：支持 `events` 数组类型，减少 IPC 开销

### 测试覆盖

事件处理测试：`tests/runStreamed.test.ts`

关键测试：
- `returns thread events` - 验证完整事件序列
- `sends previous items when runStreamed is called twice` - 验证跨轮次状态
- `resumes thread by id when streaming` - 验证恢复后的事件流

事件类型测试：无直接测试，通过集成测试间接覆盖

### 示例用法

```typescript
import { Codex, ThreadEvent } from "@openai/codex-sdk";

const codex = new Codex();
const thread = codex.startThread();
const { events } = await thread.runStreamed("Hello!");

for await (const event of events) {
  switch (event.type) {
    case "thread.started":
      console.log(`Thread ID: ${event.thread_id}`);
      break;
    case "item.completed":
      if (event.item.type === "agent_message") {
        console.log(`Assistant: ${event.item.text}`);
      }
      break;
    case "turn.completed":
      console.log(`Tokens: ${event.usage.input_tokens} in, ${event.usage.output_tokens} out`);
      break;
    case "turn.failed":
      console.error(`Error: ${event.error.message}`);
      break;
  }
}
```
