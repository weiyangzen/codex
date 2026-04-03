# threadOptions.ts 研究文档

## 场景与职责

`threadOptions.ts` 定义 TypeScript SDK 的线程级配置类型，用于控制单个对话线程（Thread）的行为。核心职责：

1. **线程行为配置**：定义模型选择、沙箱模式、审批策略等线程级选项
2. **类型安全枚举**：为离散选项提供强类型枚举（如 `SandboxMode`, `ApprovalMode`）
3. **与 CLI 参数映射**：确保选项能正确转换为 CLI 命令行参数

该模块是 `CodexOptions` 的补充，提供比全局配置更细粒度的控制。

## 功能点目的

### 1. ThreadOptions 类型

```typescript
export type ThreadOptions = {
  model?: string;                    // 模型标识符
  sandboxMode?: SandboxMode;         // 沙箱权限模式
  workingDirectory?: string;         // 工作目录
  skipGitRepoCheck?: boolean;        // 跳过 Git 仓库检查
  modelReasoningEffort?: ModelReasoningEffort;  // 推理强度
  networkAccessEnabled?: boolean;    // 网络访问开关
  webSearchMode?: WebSearchMode;     // 搜索模式（新）
  webSearchEnabled?: boolean;        // 搜索开关（向后兼容）
  approvalPolicy?: ApprovalMode;     // 审批策略
  additionalDirectories?: string[];  // 附加目录
};
```

**配置层级**：
```
TurnOptions（单次调用）
    │
    ▼
ThreadOptions（线程级）──► 本模块定义
    │
    ▼
CodexOptions.config（全局）
    │
    ▼
CLI 配置文件 / 环境变量
```

### 2. 枚举类型详解

#### SandboxMode
```typescript
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```
| 值 | CLI 参数 | 权限说明 |
|----|----------|----------|
| `read-only` | `--sandbox read-only` | 只读访问 |
| `workspace-write` | `--sandbox workspace-write` | 工作区写入 |
| `danger-full-access` | `--sandbox danger-full-access` | 完全访问（危险） |

#### ApprovalMode
```typescript
export type ApprovalMode = "never" | "on-request" | "on-failure" | "untrusted";
```
| 值 | 触发审批场景 |
|----|--------------|
| `never` | 永不审批 |
| `on-request` | 按需审批 |
| `on-failure` | 失败时审批 |
| `untrusted` | 不信任代码时审批 |

#### ModelReasoningEffort
```typescript
export type ModelReasoningEffort = "minimal" | "low" | "medium" | "high" | "xhigh";
```
映射到 CLI：`--config model_reasoning_effort="<value>"`

#### WebSearchMode
```typescript
export type WebSearchMode = "disabled" | "cached" | "live";
```
| 值 | 说明 |
|----|------|
| `disabled` | 禁用搜索 |
| `cached` | 使用缓存结果 |
| `live` | 实时搜索 |

**向后兼容**：`webSearchEnabled: boolean` 映射为 `live` / `disabled`

## 具体技术实现

### 到 CLI 参数的转换

```typescript
// exec.ts 中的参数构建逻辑

if (args.sandboxMode) {
  commandArgs.push("--sandbox", args.sandboxMode);
}

if (args.modelReasoningEffort) {
  commandArgs.push("--config", `model_reasoning_effort="${args.modelReasoningEffort}"`);
}

if (args.networkAccessEnabled !== undefined) {
  commandArgs.push(
    "--config",
    `sandbox_workspace_write.network_access=${args.networkAccessEnabled}`
  );
}

if (args.webSearchMode) {
  commandArgs.push("--config", `web_search="${args.webSearchMode}"`);
} else if (args.webSearchEnabled === true) {
  commandArgs.push("--config", `web_search="live"`);
} else if (args.webSearchEnabled === false) {
  commandArgs.push("--config", `web_search="disabled"`);
}

if (args.approvalPolicy) {
  commandArgs.push("--config", `approval_policy="${args.approvalPolicy}"`);
}

if (args.additionalDirectories?.length) {
  for (const dir of args.additionalDirectories) {
    commandArgs.push("--add-dir", dir);
  }
}
```

### 配置优先级示例

```typescript
const codex = new Codex({
  config: {
    approval_policy: "never",        // 全局默认
    model_reasoning_effort: "low"
  }
});

const thread = codex.startThread({
  approvalPolicy: "on-request",      // 覆盖全局
  model: "gpt-4"                     // 线程级特有
});

await thread.run("Hello", {
  outputSchema: schema               // 单次调用级
});
```

生成的 CLI 参数顺序：
```bash
codex exec \
  --config 'approval_policy="never"' \
  --config 'model_reasoning_effort="low"' \
  --config 'approval_policy="on-request"' \
  --model gpt-4
```

**注意**：后出现的 `--config` 覆盖先出现的（CLI 行为）

## 关键代码路径与文件引用

### 模块依赖图

```
threadOptions.ts
├── 导出类型
│   ├── ThreadOptions
│   ├── ApprovalMode
│   ├── SandboxMode
│   ├── ModelReasoningEffort
│   └── WebSearchMode
│
├── 被导入
│   ├── codex.ts             # startThread() 参数类型
│   ├── thread.ts            # Thread 构造函数和配置传递
│   ├── exec.ts              # CodexExecArgs 和参数构建
│   ├── index.ts             # 重新导出
│   └── tests/testCodex.ts   # 测试辅助函数
│
└── 测试引用
    └── tests/run.test.ts    # 配置传递测试
```

### 配置流向

```
threadOptions.ts (类型定义)
        │
        ▼
codex.ts ──► thread.startThread(options: ThreadOptions)
        │
        ▼
thread.ts ──► new Thread(exec, globalOpts, threadOptions)
        │
        ▼
thread.run() ──► exec.run({
                    model: options?.model,
                    sandboxMode: options?.sandboxMode,
                    ...
                  })
        │
        ▼
exec.ts ──► 构建 CLI 参数
        │
        ▼
CLI 进程
```

## 依赖与外部交互

### 内部依赖

无其他内部模块依赖（纯类型定义）。

### 外部契约

| 消费者 | 用途 |
|--------|------|
| `codex.ts` | `startThread()` 和 `resumeThread()` 的参数类型 |
| `thread.ts` | `Thread` 构造函数和配置传递 |
| `exec.ts` | `CodexExecArgs` 类型定义和参数构建 |
| `index.ts` | 重新导出公共类型 |
| `tests/testCodex.ts` | 测试客户端配置 |

### 与 CLI 的映射

| ThreadOptions 字段 | CLI 参数 | 配置键 |
|--------------------|----------|--------|
| `model` | `--model` | - |
| `sandboxMode` | `--sandbox` | - |
| `workingDirectory` | `--cd` | - |
| `skipGitRepoCheck` | `--skip-git-repo-check` | - |
| `modelReasoningEffort` | `--config` | `model_reasoning_effort` |
| `networkAccessEnabled` | `--config` | `sandbox_workspace_write.network_access` |
| `webSearchMode` | `--config` | `web_search` |
| `approvalPolicy` | `--config` | `approval_policy` |
| `additionalDirectories` | `--add-dir`（可重复） | - |

## 风险、边界与改进建议

### 向后兼容性

1. **webSearchEnabled 弃用**
   - 当前：`webSearchEnabled?: boolean` 仍可用
   - 建议：标记为 `@deprecated`，引导使用 `webSearchMode`
   - 实现：
   ```typescript
   export type ThreadOptions = {
     /** @deprecated Use webSearchMode instead */
     webSearchEnabled?: boolean;
     webSearchMode?: WebSearchMode;
   };
   ```

### 类型安全

1. **字符串枚举 vs 联合类型**
   - 当前：使用 `type` 定义（联合类型）
   - 替代：考虑使用 `enum` 提供运行时值
   ```typescript
   enum SandboxMode {
     ReadOnly = "read-only",
     WorkspaceWrite = "workspace-write",
     // ...
   }
   ```
   - 权衡：`enum` 有运行时开销，但支持反向映射

2. **配置验证**
   - 当前：无运行时验证
   - 建议：增加模式验证（如 zod）
   ```typescript
   const ThreadOptionsSchema = z.object({
     model: z.string().optional(),
     sandboxMode: z.enum(["read-only", "workspace-write", "danger-full-access"]).optional(),
     // ...
   });
   ```

### 边界条件

| 场景 | 行为 |
|------|------|
| 空字符串 `model` | 传递给 CLI，由 CLI 处理 |
| 无效 `sandboxMode` | TypeScript 编译错误 |
| 空数组 `additionalDirectories` | 不产生参数 |
| `workingDirectory` 不存在 | CLI 报错 |
| `skipGitRepoCheck` 为 true | 跳过 Git 安全检查 |

### 改进建议

1. **配置继承文档**
   - 当前：无显式文档说明优先级
   - 建议：添加 JSDoc 说明配置继承链

2. **默认值暴露**
   - 当前：默认值在 CLI 侧
   - 建议：SDK 侧提供默认值常量
   ```typescript
   export const DEFAULT_THREAD_OPTIONS: Partial<ThreadOptions> = {
     sandboxMode: "read-only",
     approvalPolicy: "on-request"
   };
   ```

3. **配置组合辅助**
   - 建议：提供配置合并工具
   ```typescript
   export function mergeThreadOptions(
     base: ThreadOptions,
     override: ThreadOptions
   ): ThreadOptions;
   ```

4. **验证模式**
   - 建议：增加路径存在性检查选项
   ```typescript
   export type ThreadOptions = {
     // ...
     /** Validate that workingDirectory exists before execution */
     validatePaths?: boolean;
   };
   ```

### 测试覆盖

测试文件：`tests/run.test.ts`

相关测试：
| 测试 | 覆盖点 |
|------|--------|
| `passes turn options to exec` | 基本选项传递 |
| `passes modelReasoningEffort to exec` | 配置序列化 |
| `passes networkAccessEnabled to exec` | 嵌套配置 |
| `passes webSearchEnabled to exec` | 布尔映射 |
| `passes webSearchMode to exec` | 枚举传递 |
| `passes approvalPolicy to exec` | 审批策略 |
| `passes additionalDirectories as repeated flags` | 数组处理 |
| `runs in provided working directory` | 工作目录 |

### 与 Rust 端的对应

ThreadOptions 映射到 Rust 的 `Config` 结构：

| TypeScript | Rust | 路径 |
|------------|------|------|
| `model` | `model` | - |
| `sandboxMode` | `sandbox` | - |
| `workingDirectory` | `cwd` | - |
| `modelReasoningEffort` | `model.reasoning.effort` | - |
| `networkAccessEnabled` | `sandbox.workspace_write.network_access` | - |
| `webSearchMode` | `features.web_search` | - |
| `approvalPolicy` | `approval_policy` | - |
