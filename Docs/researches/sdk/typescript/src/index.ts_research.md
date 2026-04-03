# index.ts 研究文档

## 场景与职责

`index.ts` 是 TypeScript SDK 的公共 API 入口模块，遵循 Node.js 包规范（`package.json` 中 `"module": "./dist/index.js"`）。核心职责：

1. **统一导出接口**：聚合所有子模块的公共类型和类，提供单一导入点
2. **命名空间组织**：区分类型导出（`export type`）和值导出（`export`）
3. **版本契约**：作为 SDK 的公共 API 表面，定义向后兼容承诺

该模块是用户与 SDK 交互的首要接触点，其设计直接影响开发者体验。

## 功能点目的

### 1. 分层导出结构

```typescript
// 事件类型（纯类型）
export type {
  ThreadEvent,
  ThreadStartedEvent,
  // ... 其他事件类型
} from "./events";

// 线程项类型（纯类型）
export type {
  ThreadItem,
  AgentMessageItem,
  // ... 其他项类型
} from "./items";

// 类 + 类型（混合导出）
export { Thread } from "./thread";
export type { RunResult, RunStreamedResult, Input, UserInput } from "./thread";

// 主类
export { Codex } from "./codex";

// 配置类型
export type { CodexOptions } from "./codexOptions";
export type { ThreadOptions, /* ... */ } from "./threadOptions";
export type { TurnOptions } from "./turnOptions";
```

**设计决策**：
- 使用 `export type` 明确标记纯类型导出，帮助打包工具进行 Tree Shaking
- 类和类型分离导出，便于用户按需导入

### 2. 公共 API 表面

| 类别 | 导出内容 | 用途 |
|------|----------|------|
| **核心类** | `Codex`, `Thread` | 主要交互接口 |
| **事件类型** | `ThreadEvent` 及子类型 | 流式事件处理 |
| **项类型** | `ThreadItem` 及子类型 | 线程内容访问 |
| **配置类型** | `CodexOptions`, `ThreadOptions`, `TurnOptions` | 类型安全配置 |
| **辅助类型** | `RunResult`, `RunStreamedResult`, `Input`, `UserInput` | 方法签名支持 |

## 具体技术实现

### 导出模式分析

```typescript
// 模式 1：从子模块重新导出特定成员
export type { A, B } from "./module";  // 仅类型
export { C, D } from "./module";        // 值（含类型）

// 模式 2：值和类型分离（Thread 类）
export { Thread } from "./thread";                    // 类本身
export type { RunResult, ... } from "./thread";       // 关联类型
```

**技术细节**：
- TypeScript 的 `export type` 在编译后完全擦除，不影响运行时
- 分离导出允许用户精确控制导入内容：
  ```typescript
  import { Thread } from "@openai/codex-sdk";           // 仅运行时
  import type { ThreadEvent } from "@openai/codex-sdk"; // 仅类型
  ```

### 包入口配置

`package.json` 中的配置：
```json
{
  "type": "module",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  }
}
```

**构建流程**：
```
src/index.ts ──tsup──► dist/index.js     (ESM)
              ──tsc──► dist/index.d.ts   (类型声明)
```

## 关键代码路径与文件引用

### 模块依赖图

```
index.ts
├── 从子模块导入/导出
│   ├── events.ts          ──► ThreadEvent, ThreadStartedEvent, ...
│   ├── items.ts           ──► ThreadItem, AgentMessageItem, ...
│   ├── thread.ts          ──► Thread (类), RunResult, ...
│   ├── codex.ts           ──► Codex (类)
│   ├── codexOptions.ts    ──► CodexOptions
│   ├── threadOptions.ts   ──► ThreadOptions, ApprovalMode, ...
│   └── turnOptions.ts     ──► TurnOptions
│
├── 被外部导入
│   ├── 用户应用程序
│   ├── samples/*.ts       # SDK 示例
│   └── tests/*.ts         # 测试文件
│
└── 构建产物
    ├── dist/index.js      # ESM 输出
    └── dist/index.d.ts    # 类型声明
```

### 使用模式

**完整导入**：
```typescript
import { Codex, Thread, ThreadEvent } from "@openai/codex-sdk";
```

**按需导入**：
```typescript
import { Codex } from "@openai/codex-sdk";
import type { ThreadEvent, ThreadItem } from "@openai/codex-sdk";
```

**命名空间导入**：
```typescript
import * as CodexSDK from "@openai/codex-sdk";
const codex = new CodexSDK.Codex();
```

## 依赖与外部交互

### 内部依赖

| 模块 | 导入内容 | 类别 |
|------|----------|------|
| `events.ts` | 所有事件类型 | 类型 |
| `items.ts` | 所有线程项类型 | 类型 |
| `thread.ts` | `Thread` 类 + 关联类型 | 混合 |
| `codex.ts` | `Codex` 类 | 值 |
| `codexOptions.ts` | `CodexOptions` | 类型 |
| `threadOptions.ts` | `ThreadOptions` 及枚举 | 类型 |
| `turnOptions.ts` | `TurnOptions` | 类型 |

### 外部契约

**向后兼容性承诺**：
- 公共 API 变更需遵循 SemVer
- 类型重命名/删除为破坏性变更
- 新增导出为次要版本变更

**未导出内容（内部实现细节）**：
- `CodexExec` 类（执行层）
- `createOutputSchemaFile` 辅助函数
- 配置序列化内部函数

## 风险、边界与改进建议

### API 演化风险

1. **类型膨胀**
   - 风险：随着功能增加，导出类型数量膨胀
   - 当前：约 20+ 类型，尚在可控范围
   - 建议：考虑按功能子包组织（如 `@openai/codex-sdk/events`）

2. **命名冲突**
   - 风险：子模块间类型命名重复
   - 当前：使用前缀区分（`Thread*`, `Turn*`）
   - 建议：保持命名规范，避免短名称（如 `Event` → `ThreadEvent`）

3. **Tree Shaking 友好性**
   - 当前：使用具名导出，支持静态分析
   - 风险：用户导入整个命名空间可能增加包体积
   - 建议：文档推荐按需导入

### 边界条件

| 场景 | 行为 |
|------|------|
| 导入未导出成员 | TypeScript 编译错误 |
| 循环导入 | 由构建工具处理（tsup） |
| 类型/值混淆 | `export type` 明确区分 |

### 改进建议

1. **子路径导出**
   ```json
   // package.json
   "exports": {
     ".": { ... },
     "./types": { "types": "./dist/types.d.ts" },
     "./events": { "types": "./dist/events.d.ts" }
   }
   ```
   - 允许：`import { ThreadEvent } from "@openai/codex-sdk/events"`

2. **命名空间版本控制**
   ```typescript
   // 为未来 API 版本预留
   export * as v1 from "./v1";
   ```

3. **JSDoc 增强**
   - 当前：无模块级 JSDoc
   - 建议：添加包描述和使用示例

4. **弃用标记**
   ```typescript
   /** @deprecated Use webSearchMode instead */
   export type { WebSearchEnabled } from "./threadOptions";
   ```

### 测试覆盖

`index.ts` 本身无直接测试，通过以下方式间接验证：

1. **类型检查**：`tsc --noEmit` 验证导出有效性
2. **集成测试**：`tests/*.test.ts` 使用公共 API
3. **示例验证**：`samples/*.ts` 验证实际使用场景

### 与 Rust 端的类型同步

TypeScript 类型与 Rust 生成的类型关系：

```
Rust (ts_rs)
  │
  ├─ exec_events.rs ──► exec_events.ts (自动生成)
  │
  └─ 手动维护对应 ─────► TypeScript SDK
                         │
                         ├─ events.ts (手动)
                         ├─ items.ts (手动)
                         │
                         └─ index.ts (聚合导出)
```

**同步策略**：
- 关键类型（`ThreadEvent`, `ThreadItem`）需人工核对
- 建议：CI 检查 Rust 生成类型与手动类型的兼容性
