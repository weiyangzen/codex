# structured_output.ts 深度研究文档

## 场景与职责

`structured_output.ts` 是 OpenAI Codex TypeScript SDK 的**结构化输出示例**，演示如何使用 JSON Schema 约束 AI 的响应格式。这是实现「函数调用」和「数据提取」模式的基础，适用于：

- **数据提取**: 从非结构化文本中提取结构化字段
- **API 响应生成**: 确保 AI 输出符合下游 API 的契约
- **分类任务**: 强制输出预定义的枚举值
- **工作流集成**: 与类型安全的代码库无缝集成

与 `basic_streaming.ts` 的交互式对话不同，本示例采用**单次调用模式**（one-shot），直接获取结构化结果并打印。

## 功能点目的

### 1. JSON Schema 约束输出

通过 `outputSchema` 选项，强制 AI 返回符合指定结构的 JSON：
```typescript
const schema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    status: { type: "string", enum: ["ok", "action_required"] },
  },
  required: ["summary", "status"],
  additionalProperties: false,
} as const;
```

**关键约束**：
- `type: "object"`: 根类型必须是对象
- `required`: 强制包含的字段
- `additionalProperties: false`: 禁止额外字段（严格模式）
- `enum`: 限制字符串取值范围

### 2. 同步结果获取

使用 `thread.run()` 而非 `runStreamed()`，适用于：
- 无需实时反馈的批处理任务
- 简单的请求-响应模式
- 需要直接获得 `finalResponse` 字符串的场景

### 3. 类型安全提示

`as const` 断言使 schema 获得 TypeScript 字面量类型推断：
```typescript
// 无 as const: type: string
// 有 as const: type: "object" (字面量)
```
这允许 TypeScript 在编译期验证 schema 结构，但不影响运行时行为。

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────┐
│                    structured_output.ts                      │
│                                                              │
│  ┌─────────────────┐                                        │
│  │  Define schema  │──────────────────────────────┐         │
│  │  (JSON Schema)  │                              │         │
│  └────────┬────────┘                              │         │
│           │                                       │         │
│           ▼                                       ▼         │
│  ┌─────────────────┐    ┌─────────────────────────────────┐│
│  │ thread.run()    │───▶│ SDK 创建临时 schema.json 文件   ││
│  │ { outputSchema  │    │ (src/outputSchemaFile.ts)       ││
│  │   : schema }    │    └─────────────────────────────────┘│
│  └────────┬────────┘                              │         │
│           │                                       │         │
│           ▼                                       ▼         │
│  ┌─────────────────┐    ┌─────────────────────────────────┐│
│  │ turn.final      │◄───│ CLI 调用: codex exec            ││
│  │ Response        │    │ --output-schema /tmp/...json    ││
│  └─────────────────┘    └─────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 核心数据结构

**TurnOptions 接口**（`src/turnOptions.ts`）：
```typescript
export type TurnOptions = {
  /** JSON schema describing the expected agent output. */
  outputSchema?: unknown;
  /** AbortSignal to cancel the turn. */
  signal?: AbortSignal;
};
```

**Turn 返回类型**（`src/thread.ts`）：
```typescript
export type Turn = {
  items: ThreadItem[];
  finalResponse: string;  // 当使用 outputSchema 时，这是 JSON 字符串
  usage: Usage | null;
};
```

### 临时文件机制

SDK 内部通过 `createOutputSchemaFile()` 函数（`src/outputSchemaFile.ts`）处理 schema：

```typescript
export async function createOutputSchemaFile(schema: unknown): Promise<OutputSchemaFile> {
  if (schema === undefined) {
    return { cleanup: async () => {} };
  }

  const schemaDir = await fs.mkdtemp(path.join(os.tmpdir(), "codex-output-schema-"));
  const schemaPath = path.join(schemaDir, "schema.json");
  
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  
  return {
    schemaPath,
    cleanup: async () => {
      await fs.rm(schemaDir, { recursive: true, force: true });
    },
  };
}
```

**设计考量**：
- 使用 `os.tmpdir()` 确保跨平台兼容
- `mkdtemp` 生成唯一目录，避免冲突
- `finally` 块确保清理（见 `thread.ts` 第110行）

### CLI 协议

生成的命令行参数：
```bash
codex exec --experimental-json \
  --output-schema /tmp/codex-output-schema-XXXXXX/schema.json \
  "Summarize repository status"
```

底层 Rust 代码读取 schema 文件，通过 OpenAI Responses API 的 `text.format` 字段传递：
```json
{
  "text": {
    "format": {
      "name": "codex_output_schema",
      "type": "json_schema",
      "strict": true,
      "schema": { ... }
    }
  }
}
```

## 关键代码路径与文件引用

### 直接依赖

| 文件路径 | 导入内容 | 用途 |
|---------|---------|------|
| `@openai/codex-sdk` | `Codex` | SDK 主类 |
| `./helpers.ts` | `codexPathOverride` | 可执行文件路径 |

### SDK 内部调用链

```
structured_output.ts
    │
    ├──▶ thread.run("Summarize repository status", { outputSchema: schema })
    │       └── src/thread.ts:run()
    │           └── this.runStreamedInternal(input, turnOptions)
    │               ├──▶ createOutputSchemaFile(turnOptions.outputSchema)
    │               │       └── src/outputSchemaFile.ts
    │               │           └── 写入 /tmp/codex-output-schema-XXXX/schema.json
    │               │
    │               └──▶ this._exec.run({ outputSchemaFile: schemaPath, ... })
    │                       └── src/exec.ts
    │                           └── spawn(codex, [..., "--output-schema", schemaPath])
    │
    └──▶ console.log(turn.finalResponse)  // JSON 字符串
```

### 测试覆盖

`sdk/typescript/tests/run.test.ts` 包含相关测试：
```typescript
it("writes output schema to a temporary file and forwards it", async () => {
  const schema = {
    type: "object",
    properties: { answer: { type: "string" } },
    required: ["answer"],
    additionalProperties: false,
  } as const;

  const thread = client.startThread();
  await thread.run("structured", { outputSchema: schema });

  // 验证: --output-schema 标志被传递
  // 验证: 请求体包含 text.format = { type: "json_schema", ... }
});
```

## 依赖与外部交互

### 运行时依赖

| 依赖项 | 说明 |
|-------|------|
| Node.js >=18 | ESM 支持 |
| @openai/codex-sdk | SDK |
| codex (Rust binary) | 支持 `--output-schema` 参数的 CLI |

### OpenAI API 交互

通过 Responses API 的结构化输出功能：
- 文档: https://platform.openai.com/docs/guides/structured-outputs
- 限制: 某些模型可能不支持 `strict: true` 的复杂嵌套 schema

### 文件系统交互

| 操作 | 路径 | 说明 |
|-----|------|------|
| 创建 | `/tmp/codex-output-schema-XXXXXX/schema.json` | 临时 schema 文件 |
| 删除 | 同上 | `finally` 块自动清理 |

## 风险、边界与改进建议

### 已知风险

1. **无运行时类型验证**
   ```typescript
   console.log(turn.finalResponse);  // 只是字符串，未验证是否为有效 JSON
   ```
   - 虽然 AI 被约束输出 JSON，但无运行时解析验证
   - 若模型违反约束，返回的是错误文本而非 JSON
   - **建议**: 添加 `JSON.parse()` 和验证逻辑

2. **缺乏错误处理**
   - 无 `try/catch` 块处理可能的异常
   - 可能的失败场景：
     - Schema 语法无效
     - 模型拒绝遵循 schema
     - 网络/API 错误
   - **建议**: 包装在 try/catch 中，处理 `turn.failed` 情况

3. **`as const` 的误导性**
   ```typescript
   } as const;  // 第19行
   ```
   - 提供编译时类型安全，但不影响运行时
   - 不会验证 AI 输出是否符合 schema
   - 真正的验证由 OpenAI API 执行

### 边界条件

| 场景 | 行为 | 建议 |
|-----|------|------|
| Schema 过于复杂 | API 可能拒绝或模型难以遵循 | 保持 schema 扁平 |
| `additionalProperties: true` | AI 可能返回额外字段 | 本示例使用 `false` 严格模式 |
| 模型返回非 JSON | `finalResponse` 包含错误文本 | 添加 `JSON.parse()` 验证 |
| 临时文件清理失败 | 静默忽略（`suppress`） | 可能积累垃圾文件 |

### 改进建议

1. **添加运行时验证**
   ```typescript
   import { z } from "zod";

   const ResponseSchema = z.object({
     summary: z.string(),
     status: z.enum(["ok", "action_required"]),
   });

   const turn = await thread.run("Summarize repository status", { outputSchema: schema });
   
   try {
     const parsed = JSON.parse(turn.finalResponse);
     const validated = ResponseSchema.parse(parsed);
     console.log(validated);
   } catch (e) {
     console.error("Failed to parse/validate response:", e);
   }
   ```

2. **错误处理增强**
   ```typescript
   try {
     const turn = await thread.run("...", { outputSchema: schema });
     if (turn.items.some(item => item.type === "error")) {
       console.error("Agent returned error items");
     }
     console.log(JSON.parse(turn.finalResponse));
   } catch (error) {
     console.error("Request failed:", error);
   }
   ```

3. **类型推导辅助函数**
   ```typescript
   // helpers.ts 扩展
   export function createSchema<T extends Record<string, unknown>>(schema: T) {
     return schema as T;
   }

   // 使用
   const schema = createSchema({
     type: "object" as const,
     properties: { ... },
     // 自动获得类型推断
   });
   ```

4. **与 Zod 集成**（见 `structured_output_zod.ts`）
   本示例的手写 JSON Schema 可替换为 Zod 定义，通过 `zod-to-json-schema` 自动转换。

### 对比: structured_output.ts vs structured_output_zod.ts

| 特性 | 手写 JSON Schema | Zod 版本 |
|-----|-----------------|---------|
| 类型安全 | 编译时（有限） | 编译时 + 运行时 |
| 代码冗余 | 需手动维护 schema | 从 Zod 对象生成 |
| 验证能力 | 依赖 API | API + 本地 Zod 验证 |
| 学习曲线 | 需了解 JSON Schema | 需了解 Zod |
| 适用场景 | 简单结构、快速原型 | 复杂结构、生产环境 |

### 相关文件

- `structured_output_zod.ts`: Zod 版本的相同功能
- `src/outputSchemaFile.ts`: 临时文件管理
- `src/turnOptions.ts`: `outputSchema` 选项定义
- `tests/run.test.ts`: 结构化输出测试用例
