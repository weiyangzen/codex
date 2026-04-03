# README.md 研究文档

## 场景与职责

`README.md` 是 TypeScript SDK 的官方文档入口，位于 `sdk/typescript/` 目录下。它面向开发者用户，提供 SDK 的安装、配置和使用指南。该文档是用户接触 SDK 的第一印象，承担着产品说明和快速上手的双重职责。

## 功能点目的

文档涵盖以下核心功能模块：

1. **项目介绍**: 说明 SDK 的定位——通过包装 `codex` CLI 实现程序化调用
2. **安装指南**: 提供 npm 安装命令和 Node.js 版本要求
3. **快速开始**: 展示最基本的 SDK 使用模式
4. **高级功能**:
   - 流式响应 (`runStreamed`)
   - 结构化输出 (JSON Schema / Zod)
   - 图片输入支持
   - 会话恢复
   - 工作目录控制
   - 环境变量配置
   - CLI 配置覆盖

## 具体技术实现

### 架构说明

文档明确指出 SDK 的底层实现机制：

> "The TypeScript SDK wraps the `codex` CLI from `@openai/codex`. It spawns the CLI and exchanges JSONL events over stdin/stdout."

这意味着：
- SDK 是 CLI 的包装器，而非直接调用 API
- 通信协议: JSONL (JSON Lines) over stdio
- 进程模型: 子进程 spawned，通过 stdin/stdout 交互

### 核心 API 设计

#### 1. 基础使用模式

```typescript
const codex = new Codex();
const thread = codex.startThread();
const turn = await thread.run("Diagnose the test failure and propose a fix");
```

关键概念：
- **`Codex`**: 客户端实例，管理全局配置
- **`Thread`**: 对话线程，维护会话状态
- **`Turn`**: 单次交互回合，包含输入和响应

#### 2. 流式响应

```typescript
const { events } = await thread.runStreamed("...");
for await (const event of events) {
  switch (event.type) {
    case "item.completed":
      console.log("item", event.item);
      break;
    case "turn.completed":
      console.log("usage", event.usage);
      break;
  }
}
```

事件类型系统：
- `item.completed`: 单个项目完成
- `turn.completed`: 整个回合完成，包含 usage 统计

#### 3. 结构化输出

支持两种 Schema 定义方式：

**原生 JSON Schema**:
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

**Zod Schema** (推荐):
```typescript
const schema = z.object({
  summary: z.string(),
  status: z.enum(["ok", "action_required"]),
});
```

#### 4. 多模态输入

支持文本和图片混合输入：

```typescript
const turn = await thread.run([
  { type: "text", text: "Describe these screenshots" },
  { type: "local_image", path: "./ui.png" },
  { type: "local_image", path: "./diagram.jpg" },
]);
```

输入类型：
- `text`: 纯文本
- `local_image`: 本地图片文件路径

#### 5. 会话持久化

线程会话存储在 `~/.codex/sessions`，支持会话恢复：

```typescript
const thread = codex.resumeThread(savedThreadId);
```

#### 6. 配置系统

**环境变量控制**:
```typescript
const codex = new Codex({
  env: {
    PATH: "/usr/local/bin",
  },
});
```

**CLI 配置覆盖**:
```typescript
const codex = new Codex({
  config: {
    show_raw_agent_reasoning: true,
    sandbox_workspace_write: { network_access: true },
  },
});
```

配置传递机制：
- SDK 将 JSON 对象扁平化为点分路径
- 值被序列化为 TOML 字面量
- 通过 `--config key=value` 参数传递给 CLI

### 工作目录约束

文档强调安全约束：

> "To avoid unrecoverable errors, Codex requires the working directory to be a Git repository."

可通过 `skipGitRepoCheck: true` 跳过此检查。

## 关键代码路径与文件引用

### 文档引用的源代码文件

| 文档提及 | 对应源文件 | 说明 |
|----------|-----------|------|
| `Codex` 类 | `src/codex.ts` | 主客户端类 |
| `Thread` 类 | `src/thread.ts` | 线程管理 |
| `run()` / `runStreamed()` | `src/thread.ts` | 执行方法 |
| 事件类型 | `src/events.ts` | 事件定义 |
| 输入类型 | `src/thread.ts` | `Input`, `UserInput` |
| 配置选项 | `src/codexOptions.ts` | `CodexOptions` |
| 线程选项 | `src/threadOptions.ts` | `ThreadOptions` |
| 回合选项 | `src/turnOptions.ts` | `TurnOptions` |

### 依赖的外部包

- `@openai/codex`: 底层 CLI 工具
- `zod`: Schema 验证库 (可选)
- `zod-to-json-schema`: Zod 到 JSON Schema 转换

## 依赖与外部交互

### 运行时依赖

- **Node.js**: >= 18 (文档明确要求)
- **codex CLI**: 通过 npm 依赖 `@openai/codex` 提供

### 文件系统交互

- **会话存储**: `~/.codex/sessions`
- **工作目录**: 默认当前工作目录，需为 Git 仓库

### 环境变量

- `CODEX_API_KEY`: API 密钥 (SDK 自动注入)
- `CODEX_THREAD_ID`: 用于会话恢复
- `CODEX_HOME`: 配置和会话根目录

## 风险、边界与改进建议

### 潜在风险

1. **子进程模型限制**:
   - 通过 stdio 通信可能存在性能瓶颈
   - 大图片传输可能受缓冲区限制
   - 进程崩溃会导致会话中断

2. **Git 仓库强制检查**:
   - 在非 Git 环境中使用需要显式设置 `skipGitRepoCheck`
   - 可能阻碍某些 CI/CD 场景的使用

3. **会话存储位置**:
   - 硬编码使用 `~/.codex/sessions`，在多用户或容器环境中可能需要覆盖

### 边界情况

1. **图片路径处理**:
   - 文档示例使用相对路径 `"./ui.png"`
   - 实际实现中需要处理绝对路径和路径验证

2. **Schema 验证**:
   - 原生 JSON Schema 缺乏运行时验证
   - Zod Schema 需要额外依赖

3. **配置合并优先级**:
   - 文档提到 "Thread options still take precedence for overlapping settings"
   - 配置优先级: 全局 Codex 配置 < Thread 配置 < run() 调用参数

### 改进建议

1. **文档增强**:
   - 添加错误处理示例 (try/catch 模式)
   - 说明并发限制和速率限制
   - 提供完整的 TypeScript 类型导出列表

2. **配置灵活性**:
   - 支持自定义会话存储路径
   - 允许配置 stdio 缓冲区大小

3. **示例代码**:
   - 添加错误处理示例
   - 展示如何优雅地关闭线程
   - 提供 Electron 等沙箱环境的完整示例

4. **API 设计**:
   - 考虑添加 `thread.close()` 或 `codex.dispose()` 方法用于资源清理
   - 支持取消进行中的操作 (AbortController)

5. **与 samples 目录联动**:
   - `samples/basic_streaming.ts` 展示流式响应
   - `samples/structured_output.ts` 展示结构化输出
   - 建议在 README 中直接链接这些示例文件
