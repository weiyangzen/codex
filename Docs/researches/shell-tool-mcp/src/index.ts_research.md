# index.ts 研究文档

## 场景与职责

`index.ts` 是 `@openai/codex-shell-tool-mcp` 包的 CLI 入口点。该模块作为简单的命令行工具，负责在运行时检测宿主环境并输出对应的 Bash 二进制文件路径。它是整个 shell-tool-mcp 包的启动器/启动脚本。

**核心职责：**
1. 解析当前运行平台的 target triple（架构-平台-ABI）
2. 读取 Linux 系统的 `/etc/os-release` 或获取 macOS 的 Darwin 版本
3. 调用选择逻辑确定最佳 Bash 变体
4. 输出最终 Bash 路径到 stdout

## 功能点目的

### `main()` - 主流程

**目的：** 协调各模块完成 Bash 路径解析并输出结果。

**执行流程：**
```
1. resolveTargetTriple(process.platform, process.arch)
   → "x86_64-unknown-linux-musl" | "aarch64-apple-darwin" | ...

2. 构造 vendor 路径
   __dirname/../vendor/{targetTriple}

3. 获取 OS 信息
   Linux: readOsRelease() → OsReleaseInfo
   Darwin: null（版本从 os.release() 获取）

4. resolveBashPath(targetRoot, platform, os.release(), osInfo)
   → { path: "/path/to/bash", variant: "ubuntu-24.04" }

5. 输出结果
   console.log(`Platform Bash is: ${bashPath}`)
```

**设计特点：**
- 异步设计（`async/await`），为将来可能的异步操作预留扩展空间
- 当前实现实际全同步，但接口保持异步一致性

## 具体技术实现

### 路径构造逻辑

```typescript
const targetTriple = resolveTargetTriple(process.platform, process.arch);
// 例如："x86_64-unknown-linux-musl"

const vendorRoot = path.resolve(__dirname, "..", "vendor");
// 解析为绝对路径：/path/to/shell-tool-mcp/vendor

const targetRoot = path.join(vendorRoot, targetTriple);
// 最终：/path/to/shell-tool-mcp/vendor/x86_64-unknown-linux-musl
```

### 平台条件逻辑

```typescript
const osInfo = process.platform === "linux" ? readOsRelease() : null;
```

- Linux：必须读取 `/etc/os-release` 以确定发行版和版本
- macOS/其他：跳过，使用 `os.release()` 获取 Darwin 版本

### 错误处理

```typescript
void main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- 使用 `void` 操作符显式标记不等待 Promise（避免 ESLint 未处理 Promise 警告）
- 全局捕获：任何未处理的异常都会输出到 stderr 并以退出码 1 终止

## 关键代码路径与文件引用

### 内部依赖

| 导入 | 来源 | 用途 |
|------|------|------|
| `resolveBashPath` | `./bashSelection` | 核心选择逻辑 |
| `readOsRelease` | `./osRelease` | Linux OS 信息读取 |
| `resolveTargetTriple` | `./platform` | 平台三元组解析 |

### Node.js 内置模块

| 模块 | 用途 |
|------|------|
| `node:os` | `os.release()` 获取 Darwin 内核版本 |
| `node:path` | 跨平台路径拼接和解析 |

### 构建输出

- **入口配置**：`tsup.config.ts` 中 `entry: { "mcp-server": "src/index.ts" }`
- **输出路径**：`bin/mcp-server.js`
- **Shebang**：通过 `banner: { js: "#!/usr/bin/env node" }` 添加

### 包配置关联

`package.json` 中未显式定义 `bin` 字段，说明此 CLI 可能通过以下方式调用：
1. 直接执行 `node bin/mcp-server.js`
2. 通过 MCP 配置中的 `command` 引用
3. 作为 npx 包的一部分被调用

## 依赖与外部交互

### 文件系统约定

期望的目录结构（运行时）：
```
shell-tool-mcp/
├── bin/mcp-server.js      # 本文件编译输出
├── src/                   # 源码（__dirname 指向编译后位置）
└── vendor/                # 预编译二进制
    ├── x86_64-unknown-linux-musl/
    │   └── bash/
    │       ├── ubuntu-24.04/bash
    │       └── ...
    └── aarch64-apple-darwin/
        └── bash/
            ├── macos-15/bash
            └── ...
```

**注意：** `__dirname` 在编译后的 `bin/mcp-server.js` 中指向 `bin/` 目录，因此 `..` 回到包根目录。

### MCP 集成

根据 `README.md`，此包作为 MCP 服务器运行：
```toml
[mcp_servers.shell-tool]
command = "npx"
args = ["-y", "@openai/codex-shell-tool-mcp"]
```

这意味着 `index.ts` 的输出（Bash 路径）会被 MCP 框架消费，用于启动实际的 shell 进程。

## 风险、边界与改进建议

### 已知风险

1. **`__dirname` 假设脆弱性**
   - 假设编译输出位于 `bin/` 目录下
   - 若构建配置更改（如输出到 `dist/`），路径解析会失败
   - 打包工具（如 pkg、nexe）可能改变 `__dirname` 行为

2. **无输入验证**
   - 直接信任 `process.platform` 和 `process.arch`
   - 虽然 Node.js 保证这些值，但异常值会导致难以调试的错误

3. **错误信息不够友好**
   - 直接 `console.error(err)` 输出原始 Error 对象
   - 用户可能看到堆栈跟踪而非清晰的错误说明

4. **无帮助信息/版本输出**
   - 不支持 `--help` 或 `--version` 参数
   - 不符合常规 CLI 工具预期

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| `vendor/` 目录不存在 | `resolveBashPath` 可能抛出或返回无效路径 | 错误信息可能不清晰 |
| `/etc/os-release` 不存在 | `readOsRelease` 返回空对象，导致回退 | 已处理 |
| 权限不足 | 抛出 EACCES 错误 | 需用户检查权限 |
| 非标准架构（如 `arm`） | `resolveTargetTriple` 抛出明确错误 | 正确 |

### 改进建议

1. **添加 CLI 参数支持**
   ```typescript
   import { parseArgs } from "node:util";
   
   const { values } = parseArgs({
     options: {
       help: { type: "boolean", short: "h" },
       version: { type: "boolean", short: "v" },
     },
   });
   ```

2. **改进错误处理与日志**
   ```typescript
   .catch((err) => {
     if (err.code === "ENOENT") {
       console.error(`Error: vendor directory not found at ${vendorRoot}`);
       console.error("Please ensure the package is properly installed.");
     } else {
       console.error(`Error: ${err.message}`);
     }
     process.exit(1);
   });
   ```

3. **路径存在性验证**
   ```typescript
   import { existsSync } from "node:fs";
   
   if (!existsSync(bashPath)) {
     throw new Error(`Bash binary not found: ${bashPath}`);
   }
   ```

4. **调试模式**
   ```typescript
   const DEBUG = process.env.SHELL_TOOL_DEBUG === "1";
   if (DEBUG) {
     console.error(`[debug] targetTriple: ${targetTriple}`);
     console.error(`[debug] osInfo: ${JSON.stringify(osInfo)}`);
     console.error(`[debug] selected variant: ${variant}`);
   }
   ```

5. **异步操作实际化**
   - 当前 `main()` 为 async 但全同步操作
   - 考虑添加实际的异步初始化（如检查二进制签名、加载配置）

6. **信号处理**
   ```typescript
   process.on("SIGINT", () => {
     process.exit(130);  // 128 + SIGINT(2)
   });
   ```

### 架构演进建议

当前 `index.ts` 职责过于简单（纯路径查询），未来可考虑：
- 直接启动 Bash 进程并建立 MCP 通信
- 实现完整的 MCP 服务器协议（initialize、tools/list、tools/call）
- 将路径查询作为内部工具而非主入口

根据 `README.md` 描述，完整的 MCP 服务器功能可能在 Rust 实现中（`codex-rs/shell-escalation`），此 TypeScript 包仅作为启动器/分发机制。
