# setupCodexHome.ts 研究文档

## 场景与职责

本模块是 Jest 测试框架的 **setupFilesAfterEnv** 配置脚本，负责在每个测试执行前后设置和清理隔离的 `CODEX_HOME` 环境。这是确保测试间状态隔离、防止测试污染的关键基础设施。

主要使用场景：
1. 为每个测试创建独立的 Codex 配置目录
2. 隔离测试间的会话状态和配置文件
3. 测试结束后自动清理临时目录
4. 恢复原始环境变量状态

## 功能点目的

### 环境隔离目的
- **配置隔离**：每个测试使用独立的 `~/.codex` 目录
- **会话隔离**：防止测试间的会话数据相互干扰
- **状态清理**：确保测试不会留下副作用
- **可重复性**：测试可以在任何顺序下重复执行

### 解决的问题
| 问题 | 解决方案 |
|-----|---------|
| 测试间会话污染 | 每个测试使用独立的 CODEX_HOME |
| 配置文件冲突 | 临时目录隔离配置 |
| 测试后残留文件 | afterEach 自动清理 |
| 环境变量泄漏 | 保存和恢复原始值 |

## 具体技术实现

### 关键流程

#### 1. 模块级别状态
```typescript
const originalCodexHome = process.env.CODEX_HOME;  // 保存原始值
let currentCodexHome: string | undefined;          // 当前测试的临时目录
```

#### 2. 测试前设置 (beforeEach)
```typescript
beforeEach(async () => {
  // 创建临时目录，如 /tmp/codex-sdk-test-abc123
  currentCodexHome = await fs.mkdtemp(path.join(os.tmpdir(), "codex-sdk-test-"));
  // 设置环境变量指向临时目录
  process.env.CODEX_HOME = currentCodexHome;
});
```

#### 3. 测试后清理 (afterEach)
```typescript
afterEach(async () => {
  const codexHomeToDelete = currentCodexHome;
  currentCodexHome = undefined;

  // 恢复原始环境变量
  if (originalCodexHome === undefined) {
    delete process.env.CODEX_HOME;  // 原始未设置则删除
  } else {
    process.env.CODEX_HOME = originalCodexHome;  // 恢复原始值
  }

  // 删除临时目录
  if (codexHomeToDelete) {
    await fs.rm(codexHomeToDelete, { recursive: true, force: true });
  }
});
```

### 数据结构

#### 环境变量状态
```typescript
// 模块级别保存的状态
const originalCodexHome: string | undefined = process.env.CODEX_HOME;

// 每个测试的临时目录
let currentCodexHome: string | undefined;
// 示例值: "/tmp/codex-sdk-test-a1b2c3d4"
```

#### 临时目录结构
```
/tmp/codex-sdk-test-<random>/
├── config.toml          # Codex 配置文件（如果测试创建）
├── sessions/            # 会话存储目录
│   ├── <session-id-1>/
│   └── <session-id-2>/
└── ...                  # 其他 Codex 数据
```

### Jest 集成

#### jest.config.cjs 配置
```javascript
module.exports = {
  setupFilesAfterEnv: ["<rootDir>/tests/setupCodexHome.ts"],
  // ...
};
```

#### 执行顺序
```
Jest 测试生命周期:
1. 加载测试文件
2. 执行 setupFilesAfterEnv (本模块)
3. beforeEach (本模块) → 创建临时目录
4. 执行测试用例
5. afterEach (本模块) → 清理临时目录
6. 重复 3-5 对所有测试用例
7. 测试套件结束
```

## 关键代码路径与文件引用

### 本模块
- `sdk/typescript/tests/setupCodexHome.ts` - 本文件 (28 行)

### 配置文件
- `sdk/typescript/jest.config.cjs` - Jest 配置文件
  - Line 6: `setupFilesAfterEnv: ["<rootDir>/tests/setupCodexHome.ts"]`

### 受影响的测试
所有在 `sdk/typescript/tests/` 目录下的测试文件：
- `abort.test.ts`
- `exec.test.ts`
- `run.test.ts`
- `runStreamed.test.ts`

### 被隔离的代码
- `sdk/typescript/src/exec.ts` - `CodexExec` 类
  - Rust CLI 使用 `CODEX_HOME` 确定配置和会话存储位置

### 调用链
```
Jest Test Runner
  → jest.config.cjs
    → setupFilesAfterEnv: ["setupCodexHome.ts"]
      → 模块加载: 保存 originalCodexHome
      → beforeEach (每个测试前)
        → fs.mkdtemp("/tmp/codex-sdk-test-XXXXXX")
        → process.env.CODEX_HOME = <temp-dir>
      → 执行测试
        → new Codex()
          → spawn(codex-cli)
            → CLI 读取 $CODEX_HOME 环境变量
              → 使用临时目录作为配置根
      → afterEach (每个测试后)
        → 恢复 process.env.CODEX_HOME
        → fs.rm(<temp-dir>, { recursive: true })
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `node:fs/promises` | 异步文件操作 |
| `node:os` | 获取系统临时目录 |
| `node:path` | 路径拼接 |
| `@jest/globals` | `beforeEach`, `afterEach` |

### Node.js API 使用
| API | 用途 |
|-----|------|
| `fs.mkdtemp()` | 创建唯一临时目录 |
| `fs.rm()` | 递归删除目录 |
| `os.tmpdir()` | 获取系统临时目录路径 |
| `path.join()` | 跨平台路径拼接 |

### 与 Rust CLI 的交互
```rust
// Rust CLI 代码（概念性）
let codex_home = std::env::var("CODEX_HOME")
    .unwrap_or_else(|_| dirs::home_dir().unwrap().join(".codex").to_string_lossy().to_string());
```
- CLI 优先使用 `CODEX_HOME` 环境变量
- 如果未设置，使用默认的 `~/.codex`
- 测试通过设置 `CODEX_HOME` 控制 CLI 的行为

## 风险、边界与改进建议

### 当前风险

1. **异步清理失败**
   ```typescript
   await fs.rm(codexHomeToDelete, { recursive: true, force: true });
   ```
   - `force: true` 抑制了所有错误
   - 如果目录被占用，删除可能失败但无提示
   - 长期运行可能导致 `/tmp` 目录堆积

2. **并发测试问题**
   - Jest 默认串行执行测试，但 `--parallel` 模式下可能并发
   - 每个测试有独立的临时目录，理论上安全
   - 但如果测试间共享其他资源，仍可能冲突

3. **环境变量恢复时机**
   ```typescript
   const codexHomeToDelete = currentCodexHome;
   currentCodexHome = undefined;  // 先清空
   // ... 恢复环境变量
   await fs.rm(codexHomeToDelete, { ... });  // 后删除
   ```
   - 如果恢复环境变量后、删除目录前测试崩溃，目录可能残留

4. **Windows 兼容性**
   ```typescript
   path.join(os.tmpdir(), "codex-sdk-test-")
   ```
   - Windows 的 `tmpdir()` 可能包含空格或特殊字符
   - 虽然 `path.join` 处理正确，但某些工具可能有问题

5. **原始值未定义处理**
   ```typescript
   if (originalCodexHome === undefined) {
     delete process.env.CODEX_HOME;
   }
   ```
   - 区分 "未设置" 和 "设置为空字符串"
   - 但 `process.env` 中值总是字符串，不存在 `undefined`

### 边界情况

1. **临时目录创建失败**
   - 磁盘空间不足
   - 权限问题
   - 临时目录不可写
   - 当前实现没有错误处理

2. **大量测试执行**
   - 每个测试创建和删除目录
   - 如果测试套件很大，I/O 开销显著
   - 可能需要考虑内存文件系统（如 `tmpfs`）

3. **嵌套测试描述**
   - Jest 支持嵌套的 `describe` 块
   - `beforeEach`/`afterEach` 在每个测试前/后都执行
   - 即使嵌套也正确工作

4. **跳过测试**
   - `it.skip()` 或 `describe.skip()` 跳过的测试
   - `beforeEach`/`afterEach` 不会执行
   - 这是期望行为

### 改进建议

1. **添加错误处理和日志**
   ```typescript
   afterEach(async () => {
     const codexHomeToDelete = currentCodexHome;
     currentCodexHome = undefined;

     if (originalCodexHome === undefined) {
       delete process.env.CODEX_HOME;
     } else {
       process.env.CODEX_HOME = originalCodexHome;
     }

     if (codexHomeToDelete) {
       try {
         await fs.rm(codexHomeToDelete, { recursive: true, force: true });
       } catch (error) {
         console.warn(`Failed to cleanup CODEX_HOME directory: ${codexHomeToDelete}`, error);
         // 不抛出错误，避免影响测试执行
       }
     }
   });
   ```

2. **使用更安全的临时目录命名**
   ```typescript
   import { randomBytes } from "node:crypto";
   
   beforeEach(async () => {
     const randomSuffix = randomBytes(8).toString("hex");
     currentCodexHome = await fs.mkdtemp(
       path.join(os.tmpdir(), `codex-sdk-test-${randomSuffix}-`)
     );
     process.env.CODEX_HOME = currentCodexHome;
   });
   ```

3. **添加目录内容验证（调试）**
   ```typescript
   afterEach(async () => {
     if (codexHomeToDelete && process.env.DEBUG_CODEX_HOME) {
       try {
         const files = await fs.readdir(codexHomeToDelete, { recursive: true });
         console.log(`CODEX_HOME contents:`, files);
       } catch {
         // ignore
       }
     }
     // ... 清理
   });
   ```

4. **支持并发测试的优化**
   ```typescript
   // 使用测试唯一的标识符
   import { jest } from "@jest/globals";
   
   beforeEach(async () => {
     const testName = expect.getState().currentTestName?.replace(/[^a-zA-Z0-9]/g, "_") ?? "unknown";
     const workerId = process.env.JEST_WORKER_ID ?? "0";
     currentCodexHome = await fs.mkdtemp(
       path.join(os.tmpdir(), `codex-sdk-test-${workerId}-${testName}-`)
     );
     // ...
   });
   ```

5. **验证目录确实被使用**
   ```typescript
   // 可选：验证 CLI 确实读取了 CODEX_HOME
   afterEach(async () => {
     if (codexHomeToDelete) {
       try {
         const stats = await fs.stat(codexHomeToDelete);
         if (stats.mtimeMs === stats.ctimeMs) {
           // 目录未被修改，可能测试未使用 CLI
           console.warn(`CODEX_HOME directory was not modified: ${codexHomeToDelete}`);
         }
       } catch {
         // 目录可能已被删除
       }
       await fs.rm(codexHomeToDelete, { recursive: true, force: true });
     }
   });
   ```

6. **处理进程信号**
   ```typescript
   // 在测试进程被信号终止时尝试清理
   process.on("SIGINT", async () => {
     if (currentCodexHome) {
       await fs.rm(currentCodexHome, { recursive: true, force: true });
     }
     process.exit(130);
   });
   ```

7. **文档和注释**
   ```typescript
   /**
    * Jest setup file that isolates each test's CODEX_HOME directory.
    * 
    * This ensures tests don't interfere with each other's:
    * - Configuration files (~/.codex/config.toml)
    * - Session storage (~/.codex/sessions/)
    * - Other persistent state
    * 
    * Each test gets a fresh temporary directory that is cleaned up after.
    */
   ```

8. **考虑使用内存文件系统**
   ```typescript
   // 对于性能敏感的测试套件
   import { tmpdir } from "os";
   
   function getTempDir(): string {
     // 优先使用 tmpfs（Linux）或 RAM disk
     const memTempDir = process.env.TMPFS_DIR || process.env.RAM_DISK;
     return memTempDir || tmpdir();
   }
   ```
