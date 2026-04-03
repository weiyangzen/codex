# structured_output_zod.ts 深度研究文档

## 场景与职责

`structured_output_zod.ts` 是 OpenAI Codex TypeScript SDK 的**类型安全结构化输出示例**，演示如何结合 Zod 库实现端到端的类型安全。它是 `structured_output.ts` 的增强版本，解决了手写 JSON Schema 的以下痛点：

- **类型重复定义**: 无需分别为 TypeScript 类型和 JSON Schema 维护两份定义
- **运行时验证**: 除 API 层约束外，本地可再次验证 AI 输出
- **IDE 支持**: 获得完整的自动补全和类型推断

**典型使用场景**：
- 生产环境中的数据提取管道
- 需要强类型契约的 AI 工作流
- 复杂嵌套结构的响应解析

## 功能点目的

### 1. Zod Schema 定义

使用 Zod 的链式 API 定义数据结构：
```typescript
const schema = z.object({
  summary: z.string(),
  status: z.enum(["ok", "action_required"]),
});
```

对比手写 JSON Schema：
| 特性 | Zod | JSON Schema |
|-----|-----|-------------|
| 类型推断 | `z.infer<typeof schema>` | 无 |
| 运行时验证 | `schema.parse()` | 需额外库 |
| 组合能力 | `.merge()`, `.pick()`, `.omit()` | 手动拼接 |
| 错误信息 | 详细的 ZodError | 依赖 API 错误 |

### 2. Schema 转换管道

```
Zod Schema ──▶ zodToJsonSchema() ──▶ OpenAI JSON Schema ──▶ AI 响应
     │                                                  │
     └──────────▶ schema.parse() ◄──────────────────────┘
                  (运行时验证)
```

`zod-to-json-schema` 库负责将 Zod 定义转换为 OpenAI API 兼容的 JSON Schema：
```typescript
import zodToJsonSchema from "zod-to-json-schema";

zodToJsonSchema(schema, { target: "openAi" })
// 输出:
// {
//   "type": "object",
//   "properties": {
//     "summary": { "type": "string" },
//     "status": { "enum": ["ok", "action_required"], "type": "string" }
//   },
//   "required": ["summary", "status"]
// }
```

### 3. 类型推导消费

```typescript
type ResponseType = z.infer<typeof schema>;
// 等效于:
// type ResponseType = {
//   summary: string;
//   status: "ok" | "action_required";
// }
```

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                      structured_output_zod.ts                        │
│                                                                      │
│  ┌─────────────────┐                                                │
│  │  Zod Schema     │───┐                                            │
│  │  Definition     │   │                                            │
│  └─────────────────┘   │                                            │
│                        │                                            │
│           ┌────────────┴────────────┐                               │
│           ▼                         ▼                               │
│  ┌─────────────────┐    ┌──────────────────────┐                   │
│  │ z.infer<typeof  │    │ zodToJsonSchema()    │                   │
│  │   schema>       │    │ { target: "openAi" } │                   │
│  │  (TypeScript    │    │  (JSON Schema)       │                   │
│  │   Type)         │    │                      │                   │
│  └─────────────────┘    └──────────┬───────────┘                   │
│                                    │                                │
│                                    ▼                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ thread.run("Summarize repository status", {                  │   │
│  │   outputSchema: zodToJsonSchema(schema, { target: "openAi" })│   │
│  │ })                                                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                    │                                │
│                                    ▼                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ console.log(turn.finalResponse)  // JSON 字符串              │   │
│  │ // 可进一步: schema.parse(JSON.parse(turn.finalResponse))    │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 核心依赖

**Zod 库** (`zod`):
```typescript
import z from "zod";
```
- 版本: `^3.24.2` (devDependency)
- 功能: Schema 定义、类型推断、运行时验证

**转换库** (`zod-to-json-schema`):
```typescript
import zodToJsonSchema from "zod-to-json-schema";
```
- 版本: `^3.24.6` (devDependency)
- 功能: Zod Schema → JSON Schema 转换
- 关键选项: `target: "openAi"` 生成 OpenAI 兼容格式

### 转换细节

**Zod 定义**:
```typescript
const schema = z.object({
  summary: z.string(),
  status: z.enum(["ok", "action_required"]),
});
```

**转换后 JSON Schema**:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "summary": { "type": "string" },
    "status": {
      "type": "string",
      "enum": ["ok", "action_required"]
    }
  },
  "required": ["summary", "status"]
}
```

**OpenAI 特定格式**（`target: "openAi"`）:
```json
{
  "type": "object",
  "properties": { ... },
  "required": ["summary", "status"],
  "additionalProperties": false
}
```

注意：`target: "openAi"` 会自动添加 `additionalProperties: false`，启用严格模式验证。

## 关键代码路径与文件引用

### 直接依赖

| 文件/包 | 导入内容 | 用途 |
|---------|---------|------|
| `@openai/codex-sdk` | `Codex` | SDK 主类 |
| `./helpers.ts` | `codexPathOverride` | 可执行文件路径 |
| `zod` | `z` | Schema 定义 |
| `zod-to-json-schema` | `zodToJsonSchema` | 格式转换 |

### 包配置

`sdk/typescript/package.json` 中的 devDependencies：
```json
{
  "zod": "^3.24.2",
  "zod-to-json-schema": "^3.24.6"
}
```

注意：这两个包是 `devDependencies` 而非 `dependencies`，意味着：
- SDK 本身不强制依赖 Zod
- 用户若需此功能需自行安装
- 示例代码通过 `pnpm` workspace 继承这些依赖

### SDK 调用链

与 `structured_output.ts` 相同，核心差异在 `outputSchema` 的生成方式：

```
structured_output_zod.ts
    │
    ├──▶ z.object({...})  // Zod schema 定义
    │
    ├──▶ zodToJsonSchema(schema, { target: "openAi" })
    │       └── 生成 JSON Schema 对象
    │
    └──▶ thread.run("...", { outputSchema: generatedSchema })
            └── 后续流程与 structured_output.ts 完全一致
```

## 依赖与外部交互

### 运行时依赖

| 依赖项 | 类型 | 说明 |
|-------|------|------|
| Node.js >=18 | 引擎 | ESM 支持 |
| @openai/codex-sdk | 核心 | SDK |
| zod | 开发 | Schema 定义（示例运行时） |
| zod-to-json-schema | 开发 | 格式转换（示例运行时） |
| codex (Rust binary) | 核心 | CLI 执行 |

### Zod 生态系统

- **官网**: https://zod.dev/
- **GitHub**: https://github.com/colinhacks/zod
- **关键特性**:
  - 零依赖（本身无运行时依赖）
  - TypeScript 优先设计
  - 丰富的验证器（`.email()`, `.url()`, `.regex()` 等）
  - 错误映射和自定义错误消息

### zod-to-json-schema 转换规则

| Zod 类型 | JSON Schema 输出 | 备注 |
|---------|-----------------|------|
| `z.string()` | `{ "type": "string" }` | |
| `z.number()` | `{ "type": "number" }` | |
| `z.boolean()` | `{ "type": "boolean" }` | |
| `z.enum([...])` | `{ "enum": [...] }` | |
| `z.literal("x")` | `{ "const": "x" }` | |
| `z.optional()` | 从 `required` 数组移除 | |
| `z.default(x)` | 包含 `default: x` | |
| `z.array(T)` | `{ "type": "array", "items": ... }` | |
| `z.object({})` | `{ "type": "object", "properties": {} }` | `additionalProperties: false` |

## 风险、边界与改进建议

### 已知风险

1. **转换不完全等价**
   - Zod 的某些高级特性（如 `.refine()`, `.transform()`）无法转换为 JSON Schema
   - 转换后的 schema 可能丢失部分验证逻辑
   - **示例**: `z.string().email()` 只转换为 `{ "type": "string" }`，email 验证丢失

2. **缺少运行时验证闭环**
   ```typescript
   // 当前代码只打印原始响应
   console.log(turn.finalResponse);
   
   // 未执行:
   // const parsed = schema.parse(JSON.parse(turn.finalResponse));
   ```
   虽然 AI 被约束输出符合 schema 的 JSON，但本地未再次验证。

3. **类型推断未使用**
   ```typescript
   // 本可以:
   type Response = z.infer<typeof schema>;
   const parsed: Response = schema.parse(JSON.parse(turn.finalResponse));
   ```
   示例代码未展示类型推断的实际应用。

4. **错误处理缺失**
   - 无 `try/catch` 处理 Zod 验证失败
   - 无处理 `turn.failed` 事件

### 边界条件

| 场景 | 行为 | 风险 |
|-----|------|------|
| Zod schema 包含 `.transform()` | 转换后丢失 transform | AI 收到简化 schema |
| 模型返回有效 JSON 但违反 Zod 约束 | 无本地验证，直接打印 | 下游消费可能出错 |
| `zod-to-json-schema` 版本不兼容 | 可能生成无效 schema | 运行时错误 |
| 复杂嵌套 schema | OpenAI API 可能拒绝 | 需简化结构 |

### 改进建议

1. **完整的类型安全闭环**
   ```typescript
   import { z } from "zod";
   import zodToJsonSchema from "zod-to-json-schema";
   import { Codex } from "@openai/codex-sdk";

   // 1. 定义 schema
   const schema = z.object({
     summary: z.string(),
     status: z.enum(["ok", "action_required"]),
   });

   // 2. 提取类型
   type RepositoryStatus = z.infer<typeof schema>;

   // 3. 执行请求
   const codex = new Codex({ codexPathOverride: codexPathOverride() });
   const thread = codex.startThread();

   try {
     const turn = await thread.run("Summarize repository status", {
       outputSchema: zodToJsonSchema(schema, { target: "openAi" }),
     });

     // 4. 解析并验证
     const raw = JSON.parse(turn.finalResponse);
     const validated: RepositoryStatus = schema.parse(raw);
     
     // 5. 类型安全使用
     console.log(`Status: ${validated.status}`);  // 自动补全可用
     if (validated.status === "action_required") {
       // 精确的类型收窄
     }
   } catch (error) {
     if (error instanceof z.ZodError) {
       console.error("Response validation failed:", error.issues);
     } else {
       console.error("Request failed:", error);
     }
   }
   ```

2. **Schema 组合复用**
   ```typescript
   // 定义可复用的子 schema
   const statusSchema = z.enum(["ok", "action_required", "error"]);
   const summarySchema = z.object({
     text: z.string(),
     confidence: z.number().min(0).max(1).optional(),
   });

   // 组合成完整 schema
   const fullSchema = z.object({
     summary: summarySchema,
     status: statusSchema,
   });
   ```

3. **错误处理增强**
   ```typescript
   // 检查 turn 状态
   if (turn.items.some(item => item.type === "error")) {
     console.error("Agent encountered errors during processing");
   }

   // Zod 验证错误美化
   import { fromZodError } from "zod-validation-error";
   
   try {
     schema.parse(data);
   } catch (error) {
     if (error instanceof z.ZodError) {
       const validationError = fromZodError(error);
       console.error(validationError.message);
     }
   }
   ```

4. **文档和注释**
   ```typescript
   /**
    * Repository status summary schema
    * @example
    * {
    *   "summary": "Repository has 3 uncommitted changes",
    *   "status": "action_required"
    * }
    */
   const schema = z.object({
     summary: z.string().describe("Human-readable summary"),
     status: z.enum(["ok", "action_required"]).describe("Action status"),
   });
   ```

### 与 structured_output.ts 的对比总结

| 维度 | structured_output.ts | structured_output_zod.ts (当前) | 理想状态 |
|-----|---------------------|-------------------------------|---------|
| 类型安全 | ❌ 无 | ⚠️ 部分（仅定义） | ✅ 端到端 |
| 运行时验证 | ❌ 无 | ❌ 无 | ✅ Zod parse |
| 代码可维护性 | ⚠️ 手动同步 | ✅ 单一数据源 | ✅ 单一数据源 |
| 学习成本 | 低（JSON Schema） | 中（Zod） | 中 |
| 生产就绪 | ❌ | ⚠️ 需增强 | ✅ |

### 相关文件

- `structured_output.ts`: 手写 JSON Schema 版本
- `sdk/typescript/package.json`: Zod 依赖声明
- `sdk/typescript/tests/run.test.ts`: 结构化输出测试
- Zod 生态: `zod-validation-error`, `zod-to-openapi` 等扩展库
