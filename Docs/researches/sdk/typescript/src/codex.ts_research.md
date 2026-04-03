# codex.ts 研究文档

## 场景与职责

`codex.ts` 是 TypeScript SDK 的入口模块，提供 `Codex` 主类作为与 Codex Agent 交互的 facade。它是 SDK 的对外 API 门面，负责：

1. **会话生命周期管理**：创建新会话 (`startThread`) 和恢复已有会话 (`resumeThread`)
2. **配置聚合**：整合全局选项 (`CodexOptions`) 和线程级选项 (`ThreadOptions`)
3. **执行器初始化**：创建并持有 `CodexExec` 实例，管理底层 CLI 进程

该模块面向终端用户，提供简洁的 API 设计，隐藏了底层进程管理、事件流处理等复杂性。

## 功能点目的

### 1. Codex 类

```typescript
export class Codex {
  private exec: CodexExec;
  private options: CodexOptions;
  
  constructor(options: CodexOptions = {}) {
    const { codexPathOverride, env, config } = options;
    this.exec = new CodexExec(codexPathOverride, env, config);
    this.options = options;
  }
}
```

**目的**：封装 SDK 初始化逻辑，解耦配置与执行器创建。

**关键参数**：
- `codexPathOverride`: 覆盖自动发现的 CLI 二进制路径（用于测试或自定义安装）
- `env`: 传递给 CLI 进程的环境变量（完全替代 `process.env`）
- `config`: 嵌套配置对象，会被扁平化为 `--config key=value` 参数

### 2. startThread 方法

```typescript
startThread(options: ThreadOptions = {}): Thread {
  return new Thread(this.exec, this.options, options);
}
```

**目的**：启动全新对话线程。

**行为**：
- 创建新的 `Thread` 实例，传入共享的 `CodexExec` 执行器
- 合并全局 `CodexOptions` 和线程级 `ThreadOptions`
- 线程 ID 在首次调用 `run()` 或 `runStreamed()` 时由 CLI 生成并通过 `thread.started` 事件返回

### 3. resumeThread 方法

```typescript
resumeThread(id: string, options: ThreadOptions = {}): Thread {
  return new Thread(this.exec, this.options, options, id);
}
```

**目的**：基于持久化的线程 ID 恢复对话。

**背景**：Codex CLI 在 `~/.codex/sessions` 中持久化会话状态，通过 `resume <thread_id>` 命令行参数可恢复上下文。

## 具体技术实现

### 架构层次

```
┌─────────────────────────────────────┐
│  User Application                   │
│  (使用 Codex 类)                     │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│  Codex (facade)                     │
│  - 配置聚合                          │
│  - 线程工厂                          │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│  Thread (会话管理)                   │
│  - 单次/流式调用                     │
│  - 事件聚合                          │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│  CodexExec (进程管理)                │
│  - CLI 子进程生命周期                │
│  - JSONL 流解析                      │
└─────────────────────────────────────┘
```

### 配置继承链

配置优先级（高到低）：
1. `TurnOptions`（单次调用级，如 `outputSchema`）
2. `ThreadOptions`（线程级，如 `model`, `sandboxMode`）
3. `CodexOptions.config`（全局配置覆盖）
4. CLI 配置文件 / 环境变量

### 线程状态机

```
┌──────────┐    startThread()     ┌──────────┐
│  Initial │ ───────────────────> │ Thread   │
│  State   │                      │ Created  │
└──────────┘                      └────┬─────┘
                                       │
                    run() / runStreamed() ─────┐
                                       │       │
                                       ▼       │
                              ┌──────────────┐ │
                              │  Waiting for │ │ thread.started event
                              │  thread_id   │ │
                              └──────┬───────┘ │
                                     │         │
                                     ▼         │
                            ┌────────────────┐ │
                            │  Active Thread │<─┘
                            │  (id populated)│
                            └────────────────┘
```

## 关键代码路径与文件引用

### 核心文件关系

```
codex.ts
├── 依赖导入
│   ├── codexOptions.ts    # CodexOptions, CodexConfigObject 类型
│   ├── exec.ts            # CodexExec 执行器类
│   ├── thread.ts          # Thread 会话类
│   └── threadOptions.ts   # ThreadOptions 类型
│
├── 导出
│   └── Codex 类（默认导出）
│
└── 被引用
    ├── index.ts           # 重新导出供外部使用
    └── tests/*.test.ts    # 测试用例
```

### 关键调用链

**创建线程并执行**：
```
new Codex(options)
  └─> new CodexExec(codexPathOverride, env, config)
      └─> findCodexPath() [自动发现平台二进制]
          └─> 解析 @openai/codex-* 平台包

codex.startThread(threadOptions)
  └─> new Thread(exec, globalOptions, threadOptions, id?)
      └─> thread.run(input, turnOptions)
          └─> exec.run(args) [生成器返回 JSONL 流]
```

## 依赖与外部交互

### 内部依赖

| 模块 | 类型 | 用途 |
|------|------|------|
| `codexOptions.ts` | 类型 | 全局配置定义 |
| `exec.ts` | 类 | CLI 进程管理 |
| `thread.ts` | 类 | 会话生命周期 |
| `threadOptions.ts` | 类型 | 线程级配置定义 |

### 外部运行时依赖

| 组件 | 交互方式 | 说明 |
|------|----------|------|
| Codex CLI 二进制 | `child_process.spawn` | `@openai/codex-*` 平台包中的原生二进制 |
| 环境变量 | `process.env` | 继承或覆盖系统环境 |
| 文件系统 | 间接通过 CLI | 会话持久化到 `~/.codex/sessions` |

### 平台包映射

```typescript
const PLATFORM_PACKAGE_BY_TARGET: Record<string, string> = {
  "x86_64-unknown-linux-musl": "@openai/codex-linux-x64",
  "aarch64-unknown-linux-musl": "@openai/codex-linux-arm64",
  "x86_64-apple-darwin": "@openai/codex-darwin-x64",
  "aarch64-apple-darwin": "@openai/codex-darwin-arm64",
  "x86_64-pc-windows-msvc": "@openai/codex-win32-x64",
  "aarch64-pc-windows-msvc": "@openai/codex-win32-arm64",
};
```

## 风险、边界与改进建议

### 已知风险

1. **平台包缺失**
   - 风险：若 npm 安装时未下载可选依赖（平台包），`findCodexPath()` 会抛出错误
   - 缓解：错误消息明确提示 "Ensure @openai/codex is installed with optional dependencies"

2. **环境变量隔离**
   - 行为：提供 `env` 选项时，**完全替代** `process.env`，而非合并
   - 风险：用户可能意外丢失必要环境变量（如 `PATH`）
   - 代码位置：`exec.ts:147-156`

3. **线程 ID 时序**
   - `_id` 在构造时为 `null`，首次 `run()` 调用后通过 `thread.started` 事件填充
   - 风险：并发调用 `run()` 可能导致竞态条件（尽管 CLI 会序列化处理）

### 边界条件

| 场景 | 行为 |
|------|------|
| 空配置对象 `{}` | 使用 CLI 默认配置 |
| `codexPathOverride` 指向无效路径 | `spawn` 抛出 ENOENT 错误 |
| 恢复不存在的线程 ID | CLI 报错，通过 `turn.failed` 事件传递 |
| 重复调用 `startThread()` | 创建独立线程，无共享状态 |

### 改进建议

1. **配置验证**
   - 当前：配置在传递给 CLI 前无类型验证
   - 建议：增加运行时校验，提前发现无效配置

2. **线程 ID 同步**
   - 当前：依赖事件回调设置 `_id`
   - 建议：考虑 Promise 化线程初始化，确保 ID 可用后再返回

3. **环境变量合并**
   - 当前：`env` 选项完全替换环境
   - 建议：提供 `envMerge` 选项，允许增量覆盖

4. **文档增强**
   - 补充平台包安装说明（`npm install @openai/codex --include=optional`）
   - 明确线程持久化机制和存储位置

### 测试覆盖

测试文件：`tests/run.test.ts`, `tests/runStreamed.test.ts`

关键测试用例：
- 线程创建与恢复 (`resumes thread by id`)
- 配置传递链 (`passes turn options to exec`, `passes CodexOptions config overrides`)
- 环境变量隔离 (`allows overriding the env passed to the Codex CLI`)
