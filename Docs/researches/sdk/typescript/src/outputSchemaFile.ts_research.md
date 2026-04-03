# outputSchemaFile.ts 研究文档

## 场景与职责

`outputSchemaFile.ts` 提供结构化输出（Structured Output）的临时文件管理功能。当用户需要 Agent 返回符合特定 JSON Schema 的数据时，该模块负责：

1. **Schema 持久化**：将内存中的 JSON Schema 对象写入临时文件
2. **生命周期管理**：确保临时文件在使用后被清理
3. **错误安全**：即使写入失败也能正确清理资源

该模块是 `TurnOptions.outputSchema` 功能的基础设施，架起了 TypeScript SDK 与 CLI `--output-schema` 参数之间的桥梁。

## 功能点目的

### 1. OutputSchemaFile 类型

```typescript
export type OutputSchemaFile = {
  schemaPath?: string;    // 临时文件路径（undefined = 无 schema）
  cleanup: () => Promise<void>;  // 异步清理函数
};
```

**设计决策**：
- `schemaPath` 可选：支持 `schema === undefined` 的便捷处理
- 清理函数异步：文件删除是异步操作
- 幂等清理：多次调用 `cleanup()` 安全

### 2. createOutputSchemaFile 函数

```typescript
export async function createOutputSchemaFile(
  schema: unknown
): Promise<OutputSchemaFile>
```

**功能流程**：
```
schema === undefined?
    │
    ├──► yes ──► 返回 { cleanup: noop }
    │
    └──► no ──► isJsonObject(schema)?
                    │
                    ├──► no ──► 抛出错误 "outputSchema must be a plain JSON object"
                    │
                    └──► yes ──► 创建临时目录
                                    │
                                    ├──► 写入 schema.json
                                    │       │
                                    │       └──► 成功 ──► 返回 { schemaPath, cleanup }
                                    │
                                    └──► 写入失败 ──► cleanup() ──► 抛出错误
```

**临时文件路径**：
```typescript
const schemaDir = await fs.mkdtemp(path.join(os.tmpdir(), "codex-output-schema-"));
const schemaPath = path.join(schemaDir, "schema.json");
// 示例: /tmp/codex-output-schema-abc123/schema.json
```

## 具体技术实现

### 错误处理策略

```typescript
try {
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  return { schemaPath, cleanup };
} catch (error) {
  await cleanup();  // 确保清理临时目录
  throw error;      // 重新抛出原始错误
}
```

**关键特性**：
- 写入失败时自动清理已创建的目录
- 保留原始错误堆栈
- 清理错误被抑制（`catch { /* suppress */ }`）

### 资源生命周期

```typescript
// thread.ts 中的使用模式
const { schemaPath, cleanup } = await createOutputSchemaFile(turnOptions.outputSchema);

try {
  // 使用 schemaPath 调用 CLI
  const generator = this._exec.run({
    // ...
    outputSchemaFile: schemaPath,
    // ...
  });
  
  for await (const item of generator) {
    // 处理事件
  }
} finally {
  await cleanup();  // 确保清理
}
```

**保证**：无论执行成功或失败，临时文件都会被清理

### JSON 对象验证

```typescript
function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
```

**验证规则**：
- 必须是对象类型（`typeof === "object"`）
- 不能是 `null`
- 不能是数组

**注意**：不验证 schema 内容的有效性（如是否符合 JSON Schema 规范），由 CLI 负责验证

## 关键代码路径与文件引用

### 模块依赖图

```
outputSchemaFile.ts
├── 导入
│   ├── node:fs/promises   # 异步文件操作
│   ├── node:os            # 临时目录
│   └── node:path          # 路径拼接
│
├── 导出
│   ├── OutputSchemaFile 类型
│   └── createOutputSchemaFile 函数
│
├── 被导入
│   └── thread.ts          # runStreamedInternal 方法
│
└── 测试引用
    └── tests/run.test.ts  # 结构化输出测试
```

### 调用链

```
thread.run(input, { outputSchema: schema })
    │
    ▼
thread.runStreamedInternal(input, { outputSchema })
    │
    ▼
createOutputSchemaFile(schema)
    │
    ├──► schema === undefined ──► 返回空结果
    │
    └──► 创建临时目录 ──► 写入 schema.json ──► 返回路径
    │
    ▼
this._exec.run({ outputSchemaFile: schemaPath, ... })
    │
    ▼
CLI 读取文件 ──► 验证 schema ──► 应用结构化输出
    │
    ▼
finally { await cleanup() }  // 删除临时目录
```

## 依赖与外部交互

### Node.js 内置模块

| 模块 | API | 用途 |
|------|-----|------|
| `fs/promises` | `mkdtemp`, `writeFile`, `rm` | 异步文件操作 |
| `os` | `tmpdir()` | 获取系统临时目录 |
| `path` | `join` | 路径拼接 |

### 外部契约

| 消费者 | 用途 |
|--------|------|
| `thread.ts` | 在 `runStreamedInternal` 中调用，管理 schema 文件生命周期 |

### 与 CLI 的交互

**参数传递**：
```typescript
// SDK 侧
commandArgs.push("--output-schema", schemaPath);

// CLI 侧
// --output-schema /tmp/codex-output-schema-abc123/schema.json
```

**CLI 行为**：
1. 读取指定路径的 JSON 文件
2. 解析为 JSON Schema
3. 在 Responses API 请求中设置 `text.format = { type: "json_schema", schema: ... }`

## 风险、边界与改进建议

### 资源管理风险

1. **临时文件残留**
   - 风险：进程崩溃导致 `cleanup()` 未执行
   - 缓解：使用系统临时目录，通常有定期清理机制
   - 改进：考虑 `process.on('exit')` 注册清理钩子

2. **并发目录创建**
   - 当前：`mkdtemp` 使用随机后缀，并发安全
   - 边界：极端并发下可能耗尽临时目录空间

3. **大 Schema 文件**
   - 风险：超大 schema 可能占用大量磁盘/内存
   - 当前：无大小限制
   - 建议：增加 schema 大小警告或限制

### 边界条件

| 场景 | 行为 |
|------|------|
| `schema === undefined` | 返回空 `cleanup`，`schemaPath` 未定义 |
| `schema === null` | 抛出错误（`isJsonObject` 返回 false） |
| `schema` 是数组 | 抛出错误 |
| `schema` 是原始值 | 抛出错误 |
| 写入权限不足 | 抛出错误，已创建目录被清理 |
| 磁盘已满 | 抛出错误，已创建目录被清理 |
| 清理时文件已被删除 | 静默忽略（`force: true`） |

### 改进建议

1. **同步版本**
   - 当前：仅提供异步 API
   - 建议：考虑同步版本用于特定场景（需评估必要性）

2. **Schema 缓存**
   - 当前：每次调用都创建新文件
   - 建议：相同 schema 可复用文件（需哈希比较）

3. **自定义临时目录**
   - 当前：固定使用 `os.tmpdir()`
   - 建议：允许通过环境变量或选项覆盖
   ```typescript
   createOutputSchemaFile(schema, { tmpDir: "/custom/tmp" })
   ```

4. **Schema 验证**
   - 当前：仅验证是 JSON 对象
   - 建议：可选的 JSON Schema 有效性验证
   ```typescript
   import { validate } from "jsonschema";
   // 验证 schema 自身是有效的 JSON Schema
   ```

5. **调试支持**
   - 当前：临时文件对开发者不可见
   - 建议：调试模式下保留文件或记录路径
   ```typescript
   if (process.env.CODEX_DEBUG) {
     console.log(`Schema file: ${schemaPath}`);
   }
   ```

### 测试覆盖

测试文件：`tests/run.test.ts`

关键测试用例：
```typescript
it("writes output schema to a temporary file and forwards it", async () => {
  const schema = {
    type: "object",
    properties: { answer: { type: "string" } },
    required: ["answer"],
  };
  
  await thread.run("structured", { outputSchema: schema });
  
  // 验证 CLI 接收到 --output-schema 参数
  const schemaFlagIndex = commandArgs!.indexOf("--output-schema");
  expect(schemaFlagIndex).toBeGreaterThan(-1);
  
  // 验证文件已被清理
  expect(fs.existsSync(schemaPath)).toBe(false);
});
```

测试覆盖点：
- Schema 文件正确创建和传递
- 文件在完成后被清理
- 请求中包含正确的 `text.format` 结构

### 性能考量

| 操作 | 复杂度 | 说明 |
|------|--------|------|
| 目录创建 | O(1) | 系统调用 |
| JSON 序列化 | O(n) | n = schema 对象大小 |
| 文件写入 | O(m) | m = 序列化后字节数 |
| 文件删除 | O(1) | 系统调用（递归删除目录） |

**优化建议**：对于高频调用且相同 schema 的场景，可考虑缓存序列化结果和文件路径。
