# turnOptions.ts 研究文档

## 场景与职责

`turnOptions.ts` 定义 TypeScript SDK 的单次调用级配置类型，用于控制单个交互轮次（Turn）的行为。核心职责：

1. **单次调用配置**：定义仅影响当前 `run()` 或 `runStreamed()` 调用的选项
2. **结构化输出支持**：提供 `outputSchema` 用于约束 Agent 输出格式
3. **取消机制**：支持 `AbortSignal` 实现调用取消

该模块是 SDK 配置层级中最细粒度的控制层，位于 `ThreadOptions` 之下。

## 功能点目的

### 1. TurnOptions 类型

```typescript
export type TurnOptions = {
  /** JSON schema describing the expected agent output. */
  outputSchema?: unknown;
  /** AbortSignal to cancel the turn. */
  signal?: AbortSignal;
};
```

**设计意图**：
- **最小化原则**：仅包含真正需要单次调用级控制的选项
- **扩展性**：使用 `unknown` 类型允许任意 JSON Schema 对象
- **现代 API**：`AbortSignal` 是 Web 标准的取消机制

### 2. outputSchema 字段

**用途**：要求 Agent 返回符合指定 JSON Schema 的结构化数据

**使用示例**：
```typescript
const schema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    status: { type: "string", enum: ["ok", "action_required"] }
  },
  required: ["summary", "status"]
} as const;

const turn = await thread.run("Summarize repository status", { outputSchema: schema });
console.log(turn.finalResponse);  // JSON 字符串，符合 schema
```

**实现机制**：
1. SDK 将 schema 写入临时文件
2. 通过 `--output-schema <path>` 传递给 CLI
3. CLI 在 Responses API 请求中设置结构化输出格式
4. 返回的 `agent_message` 项的 `text` 字段为 JSON 字符串

### 3. signal 字段

**用途**：通过标准 `AbortSignal` 接口取消正在进行的调用

**使用示例**：
```typescript
const controller = new AbortController();

// 5 秒后自动取消
setTimeout(() => controller.abort("Timeout"), 5000);

try {
  const result = await thread.run("Long task", { signal: controller.signal });
} catch (error) {
  if (error.name === "AbortError") {
    console.log("Operation was cancelled");
  }
}
```

**实现机制**：
- `signal` 传递给 `child_process.spawn()` 的 `options.signal`
- Node.js 在信号触发时自动终止子进程
- 适用于 `run()` 和 `runStreamed()` 两种模式

## 具体技术实现

### 配置层级位置

```
TurnOptions（单次调用）──► 本模块定义
    │
    ├──► outputSchema ──► outputSchemaFile.ts ──► 临时文件
    │
    └──► signal ──► exec.ts ──► spawn({ signal })

ThreadOptions（线程级）
    │
    ▼
CodexOptions（全局）
```

### 代码路径

```typescript
// thread.ts
async runStreamedInternal(input: Input, turnOptions: TurnOptions = {}) {
  // 1. 处理 outputSchema
  const { schemaPath, cleanup } = await createOutputSchemaFile(turnOptions.outputSchema);
  
  // 2. 调用执行器，传递 signal
  const generator = this._exec.run({
    // ... 其他参数
    outputSchemaFile: schemaPath,
    signal: turnOptions.signal,
  });
  
  try {
    for await (const item of generator) {
      // 处理事件
    }
  } finally {
    await cleanup();  // 确保清理临时文件
  }
}
```

### AbortSignal 集成

```typescript
// exec.ts
const child = spawn(this.executablePath, commandArgs, {
  env,
  signal: args.signal,  // 直接传递给 spawn
});
```

**行为**：
- 信号触发前：`spawn` 正常执行
- 信号触发后：Node.js 向子进程发送终止信号
- 流处理：`for await` 循环因进程终止而结束，抛出 `AbortError`

## 关键代码路径与文件引用

### 模块依赖图

```
turnOptions.ts
├── 导出类型
│   └── TurnOptions
│
├── 被导入
│   ├── thread.ts            # run() 和 runStreamed() 参数类型
│   └── index.ts             # 重新导出
│
└── 测试引用
    ├── tests/run.test.ts    # outputSchema 测试
    └── tests/abort.test.ts  # AbortSignal 测试
```

### 调用链

```
用户代码
    │
    ├─ thread.run(input, { outputSchema: schema, signal: abortSignal })
    │
    ▼
thread.ts
    │
    ├─ createOutputSchemaFile(turnOptions.outputSchema)
    │       └─ { schemaPath, cleanup }
    │
    └─ this._exec.run({ signal: turnOptions.signal, outputSchemaFile: schemaPath, ... })
            │
            ▼
exec.ts
    │
    └─ spawn(codex, args, { signal })
            │
            ▼
    ┌───────┴────────┐
    │                │
    ▼                ▼
outputSchema        AbortSignal
临时文件            进程终止
```

## 依赖与外部交互

### 内部依赖

无其他内部模块依赖（纯类型定义）。

### 外部契约

| 消费者 | 用途 |
|--------|------|
| `thread.ts` | `run()` 和 `runStreamed()` 的参数类型 |
| `index.ts` | 重新导出公共类型 |
| 用户应用 | 单次调用配置 |

### 与相关模块的关系

```
turnOptions.ts
    │
    ├── outputSchema ────────► outputSchemaFile.ts
    │                            └─ 临时文件管理
    │
    └── signal ──────────────► exec.ts
                                     └─ spawn({ signal })
```

## 风险、边界与改进建议

### 类型安全

1. **outputSchema 类型**
   - 当前：`unknown`
   - 优点：最大灵活性，接受任何 JSON Schema 对象
   - 缺点：无编译时验证
   - 改进建议：
   ```typescript
   import type { JSONSchema7 } from "json-schema";
   export type TurnOptions = {
     outputSchema?: JSONSchema7;  // 更精确的类型
   };
   ```

2. **泛型支持**
   - 建议：提供泛型版本推断返回类型
   ```typescript
   export type TurnOptions<T = unknown> = {
     outputSchema?: JSONSchema7;
   };
   
   export type Turn<T = unknown> = {
     items: ThreadItem[];
     finalResponse: T;  // 推断为具体类型
     usage: Usage | null;
   };
   ```

### 边界条件

| 场景 | 行为 |
|------|------|
| `outputSchema === undefined` | 正常文本输出 |
| `outputSchema` 非对象 | `createOutputSchemaFile` 抛出错误 |
| `signal` 已中止 | `spawn` 立即抛出 `AbortError` |
| `signal` 执行中中止 | 流迭代抛出错误 |
| 同时设置多个选项 | 正常处理，无冲突 |

### 改进建议

1. **Schema 验证**
   - 当前：仅验证是 JSON 对象
   - 建议：可选的 JSON Schema 有效性验证
   ```typescript
   import { validate } from "jsonschema";
   
   export type TurnOptions = {
     outputSchema?: unknown;
     /** Validate schema before sending to API */
     validateSchema?: boolean;
   };
   ```

2. **超时封装**
   - 当前：用户需自行创建 `AbortController` 和定时器
   - 建议：提供便捷的超时选项
   ```typescript
   export type TurnOptions = {
     outputSchema?: unknown;
     signal?: AbortSignal;
     /** Timeout in milliseconds */
     timeout?: number;  // 内部创建 AbortController
   };
   ```

3. **进度回调**
   - 建议：增加进度通知选项
   ```typescript
   export type TurnOptions = {
     outputSchema?: unknown;
     signal?: AbortSignal;
     onProgress?: (event: ThreadEvent) => void;  // 实时通知
   };
   ```

4. **元数据传递**
   - 建议：允许传递自定义元数据
   ```typescript
   export type TurnOptions = {
     outputSchema?: unknown;
     signal?: AbortSignal;
     metadata?: Record<string, unknown>;  // 透传到事件
   };
   ```

### 测试覆盖

测试文件：
- `tests/run.test.ts` - `outputSchema` 功能测试
- `tests/runStreamed.test.ts` - 流式模式 schema 测试
- `tests/abort.test.ts` - `AbortSignal` 功能测试

关键测试：
| 测试 | 覆盖点 |
|------|--------|
| `writes output schema to a temporary file and forwards it` | Schema 文件创建和传递 |
| `applies output schema turn options when streaming` | 流式模式 schema |
| `aborts run() when signal is aborted` | 信号取消 |
| `aborts runStreamed() when signal is aborted during iteration` | 迭代中取消 |

### 使用模式

**结构化输出与 Zod**：
```typescript
import z from "zod";
import zodToJsonSchema from "zod-to-json-schema";

const schema = z.object({
  summary: z.string(),
  status: z.enum(["ok", "action_required"])
});

const turn = await thread.run("Analyze", {
  outputSchema: zodToJsonSchema(schema, { target: "openAi" })
});

const result = JSON.parse(turn.finalResponse) as z.infer<typeof schema>;
```

**取消与超时**：
```typescript
function runWithTimeout(thread: Thread, input: string, ms: number) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), ms);
  
  return thread.run(input, { signal: controller.signal })
    .finally(() => clearTimeout(timeout));
}
```

### 与 OpenAI API 的对应

`outputSchema` 映射到 Responses API 的 `text.format`：

```typescript
// SDK 生成的 API 请求片段
{
  "text": {
    "format": {
      "type": "json_schema",
      "name": "codex_output_schema",
      "strict": true,
      "schema": { /* outputSchema 内容 */ }
    }
  }
}
```

**约束**：
- Schema 必须符合 JSON Schema Draft 2020-12
- `strict: true` 要求 schema 必须定义 `additionalProperties: false`
