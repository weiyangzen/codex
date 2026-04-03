# codexOptions.ts 研究文档

## 场景与职责

`codexOptions.ts` 定义 TypeScript SDK 的全局配置类型系统，是连接 SDK 用户与底层 Codex CLI 配置的桥梁。核心职责：

1. **类型契约**：为 `Codex` 类构造函数提供强类型配置接口
2. **配置序列化规范**：定义嵌套配置对象如何转换为 CLI 的 `--config key=value` 参数格式
3. **跨层数据传递**：承载从 SDK → `CodexExec` → CLI 进程的完整配置信息

该模块是 SDK 配置系统的源头，影响所有下游组件的行为。

## 功能点目的

### 1. CodexOptions 类型

```typescript
export type CodexOptions = {
  codexPathOverride?: string;
  baseUrl?: string;
  apiKey?: string;
  config?: CodexConfigObject;
  env?: Record<string, string>;
};
```

**字段详解**：

| 字段 | 类型 | 用途 | 映射到 CLI |
|------|------|------|------------|
| `codexPathOverride` | `string?` | 覆盖自动发现的 CLI 二进制路径 | 直接作为 `spawn` 的 `command` 参数 |
| `baseUrl` | `string?` | API 端点基础 URL | `--config openai_base_url="..."` |
| `apiKey` | `string?` | OpenAI API 密钥 | `CODEX_API_KEY` 环境变量 |
| `config` | `CodexConfigObject?` | 嵌套配置对象 | 扁平化为多个 `--config key=value` |
| `env` | `Record<string, string>?` | 环境变量覆盖 | `spawn` 的 `env` 选项（完全替换） |

### 2. 递归配置类型系统

```typescript
export type CodexConfigValue = 
  | string 
  | number 
  | boolean 
  | CodexConfigValue[] 
  | CodexConfigObject;

export type CodexConfigObject = { [key: string]: CodexConfigObject };
```

**设计意图**：
- 支持任意深度的嵌套配置（对应 TOML 的表结构）
- 与 Rust 端的 `Config` 结构保持兼容
- 允许用户以自然 JSON 方式书写配置，SDK 负责扁平化

**示例**：
```typescript
const config = {
  approval_policy: "on-request",
  sandbox_workspace_write: { network_access: true },
  tool_rules: { allow: ["git status", "git diff"] }
};
// 序列化为：
// --config 'approval_policy="on-request"'
// --config 'sandbox_workspace_write.network_access=true'
// --config 'tool_rules.allow=["git status", "git diff"]'
```

## 具体技术实现

### 配置扁平化算法

配置序列化在 `exec.ts` 中实现，核心逻辑：

```typescript
function flattenConfigOverrides(
  value: CodexConfigValue,
  prefix: string,
  overrides: string[]
): void {
  if (!isPlainObject(value)) {
    // 叶子节点：生成 key=value
    overrides.push(`${prefix}=${toTomlValue(value, prefix)}`);
    return;
  }
  // 递归处理对象属性
  for (const [key, child] of Object.entries(value)) {
    const path = prefix ? `${prefix}.${key}` : key;
    flattenConfigOverrides(child, path, overrides);
  }
}
```

### TOML 值序列化

```typescript
function toTomlValue(value: CodexConfigValue, path: string): string {
  if (typeof value === "string") {
    return JSON.stringify(value);  // "value"
  } else if (typeof value === "number") {
    return `${value}`;             // 123
  } else if (typeof value === "boolean") {
    return value ? "true" : "false";  // true/false
  } else if (Array.isArray(value)) {
    return `[${value.map(toTomlValue).join(", ")}]`;  // [a, b, c]
  } else if (isPlainObject(value)) {
    return `{${entries.map(e => `${key} = ${value}`).join(", ")}}`;  // {k = v}
  }
}
```

**关键约束**：
- 数字必须是有限值（`Number.isFinite` 检查）
- 不支持 `null` 值
- 对象键必须符合 TOML bare key 规范（`^[A-Za-z0-9_-]+$`），否则使用 JSON 字符串转义

## 关键代码路径与文件引用

### 类型依赖图

```
codexOptions.ts
├── 导出类型
│   ├── CodexOptions         # 主配置接口
│   ├── CodexConfigObject    # 嵌套配置对象
│   └── CodexConfigValue     # 配置值联合类型
│
├── 被导入
│   ├── codex.ts             # Codex 类构造函数
│   ├── exec.ts              # CodexExec 配置序列化
│   ├── thread.ts            # 通过 CodexOptions 传递配置
│   └── index.ts             # 重新导出
│
└── 测试引用
    └── tests/testCodex.ts   # createTestClient 辅助函数
```

### 配置流向

```
用户代码
   │
   │ new Codex({
   │   baseUrl: "...",
   │   config: { approval_policy: "never" }
   │ })
   ▼
┌─────────────┐
│  codex.ts   │ ──提取──> codexPathOverride, env
│  Codex类    │ ──传递──> config 对象
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  exec.ts    │
│ CodexExec   │ ──序列化──> --config key=value
│  构造函数   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  CLI 进程   │
│  codex exec │ ──解析──> Rust Config 结构
└─────────────┘
```

## 依赖与外部交互

### 内部依赖

无直接运行时依赖，纯类型定义模块。

### 外部契约

| 消费者 | 消费内容 | 用途 |
|--------|----------|------|
| `codex.ts` | `CodexOptions` | 类构造函数参数类型 |
| `exec.ts` | `CodexConfigObject`, `CodexConfigValue` | 配置序列化算法输入类型 |
| `thread.ts` | `CodexOptions` | 透传配置到执行器 |
| 测试辅助 | `CodexConfigObject` | 构造测试配置 |

### 与 Rust 端的配置对应

TypeScript 的 `CodexConfigObject` 最终映射到 Rust 的 `codex_core::config::Config`：

| TypeScript 路径 | Rust 字段 | 说明 |
|-----------------|-----------|------|
| `approval_policy` | `approval_policy` | 审批策略枚举 |
| `sandbox_workspace_write.network_access` | `sandbox.workspace_write.network_access` | 沙箱网络权限 |
| `model_reasoning_effort` | `model.reasoning.effort` | 模型推理强度 |
| `web_search` | `features.web_search` | 网页搜索模式 |

## 风险、边界与改进建议

### 类型系统风险

1. **递归类型深度**
   - 当前：`CodexConfigValue` 是递归类型
   - 风险：极端嵌套可能导致 TypeScript 类型检查性能下降
   - 实际：正常配置深度 < 5，不构成问题

2. **类型安全缺口**
   - 当前：`config` 字段使用 `CodexConfigObject`（`{ [key: string]: CodexConfigValue }`）
   - 风险：无法阻止无效配置键（如 `approvl_policy` 拼写错误）
   - 运行时：CLI 会忽略未知配置，静默失败

### 序列化边界

| 场景 | 行为 | 位置 |
|------|------|------|
| 空对象 `{}` | 不产生任何 `--config` 参数 | `exec.ts:250-252` |
| 空数组 `[]` | 序列化为 `[]` | `exec.ts:285-287` |
| `undefined` 值 | 被跳过（`continue`） | `exec.ts:263-265` |
| `null` 值 | 抛出错误 | `exec.ts:300-301` |
| 非有限数字 | 抛出错误 | `exec.ts:279-281` |
| 特殊键名（含空格等） | JSON 字符串转义 | `exec.ts:308-311` |

### 改进建议

1. **配置键校验**
   ```typescript
   // 建议：引入已知配置键的联合类型
   type KnownConfigKey = 
     | "approval_policy" 
     | "model_reasoning_effort"
     | `sandbox_workspace_write.${string}`
     | ...;
   
   type StrictConfigObject = {
     [K in KnownConfigKey]?: CodexConfigValue;
   };
   ```
   - 权衡：灵活性 vs. 类型安全

2. **配置文档内联**
   - 当前：JSDoc 仅说明格式
   - 建议：使用 TypeScript 模板字面量类型提供自动完成
   ```typescript
   type ConfigPath = 
     | "approval_policy" 
     | "sandbox_workspace_write.network_access"
     | ...;
   ```

3. **序列化错误上下文**
   - 当前：`toTomlValue` 在错误时仅提供路径
   - 建议：包含完整配置子树，便于调试

4. **环境变量继承**
   - 当前：`env` 选项完全替换环境
   - 建议：增加 `envExtend` 选项，支持增量覆盖
   ```typescript
   type CodexOptions = {
     env?: Record<string, string>;
     envExtend?: Record<string, string>; // 与 process.env 合并
   };
   ```

### 测试覆盖

配置序列化测试：`tests/exec.test.ts`

关键测试：
- `passes CodexOptions config overrides as TOML --config flags` - 验证完整序列化链路
- `lets thread options override CodexOptions config overrides` - 验证配置优先级
- `allows overriding the env passed to the Codex CLI` - 验证环境变量隔离
