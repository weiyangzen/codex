# exec.ts 研究文档

## 场景与职责

`exec.ts` 是 TypeScript SDK 的核心执行层，负责与 Codex CLI 二进制进程的底层交互。核心职责：

1. **进程生命周期管理**：通过 Node.js `child_process.spawn` 启动、监控和终止 CLI 进程
2. **跨平台二进制发现**：根据操作系统和架构自动定位正确的平台包
3. **配置序列化**：将嵌套配置对象转换为 CLI 可识别的 `--config key=value` TOML 格式
4. **JSONL 流处理**：通过生成器模式逐行输出 CLI 的 stdout 内容
5. **环境隔离**：支持完全自定义的环境变量传递

该模块是 SDK 与 Rust CLI 之间的桥梁，所有上层功能最终都通过此模块落地。

## 功能点目的

### 1. CodexExec 类

```typescript
export class CodexExec {
  private executablePath: string;
  private envOverride?: Record<string, string>;
  private configOverrides?: CodexConfigObject;

  constructor(
    executablePath: string | null = null,
    env?: Record<string, string>,
    configOverrides?: CodexConfigObject,
  )
}
```

**设计模式**：封装器（Wrapper），隐藏进程管理复杂性

**关键参数**：
- `executablePath`: 显式指定 CLI 路径（测试/调试用途）
- `env`: 完全替换 `process.env` 的环境变量
- `configOverrides`: 全局配置覆盖，应用于所有执行

### 2. 平台二进制发现（findCodexPath）

```typescript
function findCodexPath() {
  const { platform, arch } = process;
  // 平台映射表
  const PLATFORM_PACKAGE_BY_TARGET: Record<string, string> = {
    "x86_64-unknown-linux-musl": "@openai/codex-linux-x64",
    "aarch64-unknown-linux-musl": "@openai/codex-linux-arm64",
    // ... 共 6 个平台
  };
  // 解析 npm 包路径 → vendor/ 目录 → 二进制
}
```

**解析链**：
```
@openai/codex/package.json
    ↓
@openai/codex-<platform>/package.json
    ↓
vendor/<target-triple>/codex/codex[.exe]
```

### 3. 配置序列化系统

**入口**：`serializeConfigOverrides` → `flattenConfigOverrides` → `toTomlValue`

**示例转换**：
```typescript
const config = {
  approval_policy: "never",
  sandbox_workspace_write: { network_access: true },
  tool_rules: { allow: ["git status"] }
};

// 输出：
[
  'approval_policy="never"',
  'sandbox_workspace_write.network_access=true',
  'tool_rules.allow=["git status"]'
]
```

**TOML 值规则**：
| 类型 | 序列化结果 | 示例 |
|------|-----------|------|
| `string` | JSON 字符串 | `"value"` |
| `number` | 十进制 | `123` |
| `boolean` | 小写 | `true` / `false` |
| `array` | 方括号 | `[1, 2, 3]` |
| `object` | 花括号 | `{a = 1, b = 2}` |

### 4. 命令参数构建（run 方法）

```typescript
async *run(args: CodexExecArgs): AsyncGenerator<string> {
  const commandArgs: string[] = ["exec", "--experimental-json"];
  
  // 1. 全局配置覆盖
  if (this.configOverrides) { ... }
  
  // 2. 单次调用参数
  if (args.baseUrl) commandArgs.push("--config", ...);
  if (args.model) commandArgs.push("--model", args.model);
  if (args.sandboxMode) commandArgs.push("--sandbox", args.sandboxMode);
  // ... 其他参数
  
  // 3. 恢复命令（必须在 image 参数之前）
  if (args.threadId) commandArgs.push("resume", args.threadId);
  
  // 4. 图片路径
  if (args.images?.length) { ... }
}
```

**参数顺序约束**：`resume <thread_id>` 必须在 `--image` 之前（测试验证：`exec.test.ts:71-95`）

### 5. 进程 I/O 管理

```typescript
const child = spawn(this.executablePath, commandArgs, { env, signal });

// 标准输入：写入用户输入
child.stdin.write(args.input);
child.stdin.end();

// 标准输出：readline 逐行读取
const rl = readline.createInterface({ input: child.stdout });
for await (const line of rl) {
  yield line;  // JSONL 行
}

// 标准错误：聚合用于错误报告
child.stderr.on("data", (data) => stderrChunks.push(data));
```

**错误处理**：
- 进程退出码非 0 → 抛出包含 stderr 内容的错误
- 信号终止 → 报告信号类型
- spawn 失败 → 立即抛出

## 具体技术实现

### 架构流程

```
┌─────────────────────────────────────────────────────────────┐
│  Thread.run() / runStreamed()                               │
└───────────────────────┬─────────────────────────────────────┘
                        │ CodexExecArgs
┌───────────────────────▼─────────────────────────────────────┐
│  CodexExec.run(args)                                        │
│  ├─ 构建 commandArgs 数组                                   │
│  ├─ 设置环境变量（含 CODEX_INTERNAL_ORIGINATOR_OVERRIDE）   │
│  ├─ spawn 子进程                                            │
│  ├─ 写入 stdin → end()                                      │
│  ├─ readline 逐行读取 stdout                                │
│  └─ yield 每行 JSON                                         │
└───────────────────────┬─────────────────────────────────────┘
                        │ AsyncGenerator<string>
┌───────────────────────▼─────────────────────────────────────┐
│  Thread.runStreamedInternal()                               │
│  ├─ JSON.parse()                                            │
│  ├─ 类型断言为 ThreadEvent                                  │
│  └─ yield 解析后的事件                                      │
└─────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### CodexExecArgs
```typescript
export type CodexExecArgs = {
  input: string;                    // 用户输入文本
  baseUrl?: string;                 // API 端点
  apiKey?: string;                  // API 密钥
  threadId?: string | null;         // 恢复会话 ID
  images?: string[];                // 本地图片路径
  model?: string;                   // --model
  sandboxMode?: SandboxMode;        // --sandbox
  workingDirectory?: string;        // --cd
  additionalDirectories?: string[]; // --add-dir（可重复）
  skipGitRepoCheck?: boolean;       // --skip-git-repo-check
  outputSchemaFile?: string;        // --output-schema
  modelReasoningEffort?: ModelReasoningEffort;  // --config
  signal?: AbortSignal;             // 取消信号
  networkAccessEnabled?: boolean;   // --config sandbox_workspace_write.network_access
  webSearchMode?: WebSearchMode;    // --config web_search
  webSearchEnabled?: boolean;       // 向后兼容
  approvalPolicy?: ApprovalMode;    // --config approval_policy
};
```

#### 内部状态
```typescript
const INTERNAL_ORIGINATOR_ENV = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE";
const TYPESCRIPT_SDK_ORIGINATOR = "codex_sdk_ts";
```
- 用于追踪请求来源，在 CLI 日志/遥测中标识 SDK 类型

### 配置扁平化算法详解

```typescript
function flattenConfigOverrides(
  value: CodexConfigValue,
  prefix: string,
  overrides: string[]
): void {
  // 基本情况：非对象值，生成 key=value
  if (!isPlainObject(value)) {
    overrides.push(`${prefix}=${toTomlValue(value, prefix)}`);
    return;
  }
  
  // 递归情况：遍历对象属性
  for (const [key, child] of Object.entries(value)) {
    if (child === undefined) continue;  // 跳过 undefined
    const path = prefix ? `${prefix}.${key}` : key;
    flattenConfigOverrides(child, path, overrides);
  }
}
```

**复杂度**：O(n)，n 为配置对象叶子节点数量

## 关键代码路径与文件引用

### 文件依赖图

```
exec.ts
├── 导入
│   ├── node:child_process   # spawn
│   ├── node:path            # 路径解析
│   ├── node:readline        # 流解析
│   ├── node:module          # createRequire
│   ├── codexOptions.ts      # CodexConfigObject
│   └── threadOptions.ts     # SandboxMode, ApprovalMode, etc.
│
├── 导出
│   ├── CodexExec 类
│   └── CodexExecArgs 类型
│
├── 被导入
│   ├── codex.ts             # Codex 类初始化
│   ├── thread.ts            # Thread 执行调用
│   └── index.ts             # 重新导出
│
└── 测试
    ├── tests/exec.test.ts   # 进程管理测试
    ├── tests/run.test.ts    # 集成测试（间接）
    └── tests/codexExecSpy.ts # 测试辅助（mock spawn）
```

### 执行时序

```
时间轴 ──────────────────────────────────────────────────────►

[初始化阶段]
  │
  ├─ new Codex() ──► new CodexExec() ──► findCodexPath()
  │                                         └─ 解析平台包路径
  │
[执行阶段 - 单次 run()]
  │
  ├─ thread.run(input) ──► exec.run(args)
  │                          │
  │                          ├─ 构建 commandArgs[]
  │                          ├─ spawn(codex, args, {env})
  │                          │      │
  │                          │      └─ 子进程启动
  │                          ├─ stdin.write(input) ──► stdin.end()
  │                          │
  │                          ├─ [stdout] ──► readline ──► yield line
  │                          │      │
  │                          │      ├─ {"type":"thread.started",...}
  │                          │      ├─ {"type":"turn.started"}
  │                          │      ├─ {"type":"item.completed",...}
  │                          │      └─ {"type":"turn.completed",...}
  │                          │
  │                          └─ [stderr] ──► Buffer[]（聚合）
  │
  └─ 子进程 exit ──► 校验 exit code ──► 成功/抛出错误
```

## 依赖与外部交互

### Node.js 内置模块

| 模块 | 用途 |
|------|------|
| `child_process` | 进程创建与管理 |
| `path` | 跨平台路径处理 |
| `readline` | 流式行读取 |
| `module` | `createRequire` 解析 npm 包 |

### 外部 npm 包

| 包名 | 用途 |
|------|------|
| `@openai/codex-*` | 平台特定的 CLI 二进制（optionalDependencies） |

### 与 CLI 的协议

**命令格式**：
```bash
codex exec --experimental-json \
  --config 'key=value' \
  --model gpt-4 \
  --sandbox workspace-write \
  [--image path/to/img.png ...] \
  [resume <thread_id>]
```

**输入**：通过 stdin 传递用户提示
**输出**：stdout 输出 JSONL 事件流
**错误**：stderr 聚合，非 0 退出码表示失败

## 风险、边界与改进建议

### 进程管理风险

1. **僵尸进程**
   - 风险：异常退出时子进程可能残留
   - 缓解：`finally` 块调用 `child.kill()`，但忽略错误
   - 代码：`exec.ts:217-225`

2. **流背压**
   - 风险：CLI 输出速度快于 SDK 消费速度
   - 当前：生成器模式天然支持背压（`yield` 暂停）
   - 边界：无显式背压控制

3. **信号处理**
   - 行为：`AbortSignal` 传递给 `spawn`，Node.js 负责终止子进程
   - 风险：信号可能无法立即传递（进程未完全启动）

### 平台兼容性

| 平台 | 支持状态 | 测试覆盖 |
|------|----------|----------|
| Linux x64 | ✅ 完全支持 | CI |
| Linux arm64 | ✅ 完全支持 | CI |
| macOS x64 | ✅ 完全支持 | CI |
| macOS arm64 | ✅ 完全支持 | CI |
| Windows x64 | ✅ 完全支持 | CI |
| Windows arm64 | ✅ 完全支持 | 有限 |
| 其他 | ❌ 抛出错误 | - |

### 配置序列化边界

| 场景 | 行为 | 风险 |
|------|------|------|
| 循环引用 | 堆栈溢出 | 未检测，应避免 |
| 大数组 | 长命令行 | 可能超出系统限制 |
| 特殊字符键 | JSON 转义 | 正确但可读性差 |
| `undefined` | 静默跳过 | 可能非预期 |
| `null` | 抛出错误 | 明确失败 |

### 改进建议

1. **二进制缓存**
   - 当前：每次 `new CodexExec()` 重新解析路径
   - 建议：模块级缓存 `findCodexPath()` 结果

2. **配置验证**
   - 当前：无验证，直接传递给 CLI
   - 建议：增加已知配置键的白名单校验

3. **命令行长度保护**
   - 当前：无限制
   - 建议：检测长配置，考虑临时文件传递

4. **进程健康检查**
   - 当前：依赖 exit 事件
   - 建议：增加心跳检测，及时发现僵死进程

5. **错误上下文增强**
   - 当前：错误包含 stderr 内容
   - 建议：增加命令行参数（脱敏后）便于调试

6. **流式 stderr**
   - 当前：仅聚合，不实时暴露
   - 建议：增加 `onStderr` 回调，支持实时日志

### 测试覆盖

测试文件：`tests/exec.test.ts`

| 测试用例 | 覆盖点 |
|----------|--------|
| `rejects when exit happens before stdout closes` | 异常退出处理 |
| `places resume args before image args` | 参数顺序约束 |
| `allows overriding the env passed to the Codex CLI` | 环境变量隔离 |

测试辅助：`tests/codexExecSpy.ts`
- 使用 Jest mock 拦截 `child_process.spawn`
- 捕获实际传递的参数和环境变量

### 性能考量

| 操作 | 复杂度 | 说明 |
|------|--------|------|
| 配置扁平化 | O(n) | n = 叶子节点数 |
| 二进制发现 | O(1) | 模块加载时一次 |
| 流处理 | O(m) | m = JSONL 行数 |
| 内存占用 | O(s) | s = stderr 聚合大小 |

**优化点**：大 stderr 输出可能占用大量内存，考虑流式处理或大小限制。
