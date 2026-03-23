# shell-tool-mcp/tsup.config.ts 研究文档

## 场景与职责

`tsup.config.ts` 是 tsup 打包工具的配置文件，负责：

1. **定义构建入口**：指定哪些文件作为构建起点
2. **配置输出目录**：定义编译后的文件存放位置
3. **设置输出格式**：指定模块格式（ESM/CJS）
4. **添加文件头**：如 shebang 行
5. **优化构建产物**：清理、压缩、sourcemap 等

## 功能点目的

### 配置项解析

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `entry` | `{ "mcp-server": "src/index.ts" }` | 构建入口文件 |
| `outDir` | `"bin"` | 输出目录 |
| `format` | `["cjs"]` | 输出 CommonJS 格式 |
| `target` | `"node18"` | 目标 Node.js 版本 |
| `clean` | `true` | 构建前清理输出目录 |
| `sourcemap` | `false` | 不生成 sourcemap |
| `banner.js` | `"#!/usr/bin/env node"` | 文件头 shebang |

### 详细说明

#### entry（入口配置）

```typescript
entry: {
  "mcp-server": "src/index.ts"
}
```

- 键名 `mcp-server` 决定输出文件名：`bin/mcp-server.js`
- 值 `src/index.ts` 是源代码入口
- 支持多入口：`{ "a": "src/a.ts", "b": "src/b.ts" }`

#### outDir（输出目录）

```typescript
outDir: "bin"
```

- 编译后的文件输出到 `bin/` 目录
- 与 `.gitignore` 中的 `/bin/` 对应（不提交到版本控制）
- 与 `package.json` 的 `scripts.clean` 对应（`rm -rf bin`）

#### format（模块格式）

```typescript
format: ["cjs"]
```

- 只输出 CommonJS 格式
- 可选值：`"cjs"`, `"esm"`, `"iife"`
- 与 `tsconfig.json` 的 `module: "CommonJS"` 一致

#### target（目标环境）

```typescript
target: "node18"
```

- 针对 Node.js 18 优化输出
- 使用 Node.js 18 支持的语法特性
- 与 `package.json` 的 `engines.node: ">=18"` 一致

#### clean（清理选项）

```typescript
clean: true
```

- 每次构建前删除 `outDir`
- 避免旧文件残留
- 确保构建产物干净

#### sourcemap（源码映射）

```typescript
sourcemap: false
```

- 不生成 `.map` 文件
- 减小输出体积
- 生产环境通常不需要（但调试时有用）

#### banner（文件头）

```typescript
banner: {
  js: "#!/usr/bin/env node"
}
```

- 在输出文件顶部添加 shebang
- 使文件可直接执行：`./bin/mcp-server.js`
- 无需显式调用 `node`：
  ```bash
  # 添加 shebang 后
  ./bin/mcp-server.js
  
  # 未添加 shebang 时需要
  node ./bin/mcp-server.js
  ```

## 具体技术实现

### 构建流程

```
tsup 构建流程：
1. 读取 tsup.config.ts
2. 解析 entry 配置
3. 使用 esbuild 编译 TypeScript
4. 应用 banner（添加 shebang）
5. 输出到 outDir

详细步骤：
1. 清理 bin/ 目录（clean: true）
2. 读取 src/index.ts
3. 解析导入依赖（src/bashSelection.ts, src/osRelease.ts 等）
4. 使用 esbuild 转换为 JavaScript
5. 应用 Node.js 18 兼容性转换
6. 添加 shebang 头
7. 写入 bin/mcp-server.js
```

### esbuild 集成

tsup 基于 esbuild，提供：
- **极速编译**：比 tsc 快 10-100 倍
- **Tree shaking**：自动移除未使用的代码
- **代码压缩**：可选的 minification
- **TypeScript 支持**：内置，无需额外配置

### 与 tsconfig.json 的关系

```
配置分离：
┌─────────────────┐     ┌─────────────────┐
│  tsconfig.json  │     │  tsup.config.ts │
├─────────────────┤     ├─────────────────┤
│ target: ES2022  │     │ target: node18  │
│ module: CommonJS│     │ format: ["cjs"] │
│ noEmit: true    │     │ outDir: "bin"   │
│ strict: true    │     │ clean: true     │
└─────────────────┘     └─────────────────┘
        │                       │
        │   不同用途            │
        ▼                       ▼
   类型检查（tsc）         构建输出（tsup）
```

- `tsconfig.json`：开发时类型检查，不输出文件
- `tsup.config.ts`：构建时编译，输出可执行文件

### shebang 的重要性

```javascript
#!/usr/bin/env node
// 编译后的 bin/mcp-server.js 顶部

// 这允许直接执行：
./bin/mcp-server.js

// 而不是：
node ./bin/mcp-server.js
```

在 MCP 服务器场景中的作用：
```toml
# ~/.codex/config.toml
[mcp_servers.shell-tool]
command = "npx"
args = ["-y", "@openai/codex-shell-tool-mcp"]
```

当 npx 执行包时，会查找 package.json 的 `bin` 字段或默认执行入口文件。

## 关键代码路径与文件引用

| 文件 | 关联关系 |
|------|----------|
| `src/index.ts` | 构建入口，定义 main() 函数 |
| `package.json` | `scripts.build` 调用 `tsup` |
| `.gitignore` | 忽略 `bin/` 目录 |
| `tsconfig.json` | 独立的类型检查配置 |
| `bin/mcp-server.js` | 构建输出（运行时生成） |

## 依赖与外部交互

### tsup 版本

```json
{
  "devDependencies": {
    "tsup": "^8.5.0"
  }
}
```

- tsup 8.5 是较新版本
- 基于 esbuild 0.24+
- 支持 TypeScript 5.x

### 命令行使用

```bash
# 开发构建
pnpm run build
# 等价于：tsup

# 监听模式
pnpm run build:watch
# 等价于：tsup --watch
```

### 与 npm 包的集成

```json
{
  "name": "@openai/codex-shell-tool-mcp",
  "files": ["vendor", "README.md"]
  // 注意：不包含 "bin"
}
```

- 构建输出 `bin/` 不随 npm 包发布
- 该包的核心是 `vendor/` 中的原生二进制文件
- TypeScript 代码仅用于开发时

## 风险、边界与改进建议

### 当前风险

1. **不生成 sourcemap**：
   - `sourcemap: false` 导致无法调试编译后的代码
   - 如果生产环境出现问题，难以定位
   - 建议开发环境启用 sourcemap

2. **单入口限制**：
   - 只有一个入口 `mcp-server`
   - 如果未来需要多个 CLI 工具，需要修改配置

3. **无代码压缩**：
   - 默认不启用 minification
   - 输出文件可能较大
   - 对于 CLI 工具，压缩可以减小体积

4. **target 与 tsconfig 不一致**：
   - tsup: `node18`
   - tsconfig: `ES2022`
   - 虽然 Node.js 18 支持 ES2022，但配置应保持一致

### 边界情况

1. **Windows 兼容性**：
   - shebang (`#!/usr/bin/env node`) 在 Windows 上无效
   - 但 Node.js 在 Windows 上会忽略 shebang
   - 不影响功能，只是无法直接双击执行

2. **权限问题**：
   - 输出文件可能丢失可执行权限
   - 需要 `chmod +x bin/mcp-server.js`
   - 通常在 npm 包的 `bin` 字段中配置

3. **依赖打包**：
   - tsup 默认不打包 node_modules 依赖
   - 如果 `src/index.ts` 导入外部包，会保留 `require()`
   - 当前项目无外部依赖，无此问题

### 改进建议

1. **环境区分配置**：

```typescript
import { defineConfig } from "tsup";

export default defineConfig((options) => ({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: options.watch, // 开发模式启用 sourcemap
  minify: !options.watch,   // 生产模式压缩代码
  banner: {
    js: "#!/usr/bin/env node",
  },
}));
```

2. **添加元数据**：

```typescript
import { defineConfig } from "tsup";
import { version } from "./package.json";

export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: false,
  banner: {
    js: `#!/usr/bin/env node
// @openai/codex-shell-tool-mcp v${version}
// Generated at ${new Date().toISOString()}
`,
  },
});
```

3. **添加 shims**：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: false,
  shims: true, // 添加 Node.js shims
  banner: {
    js: "#!/usr/bin/env node",
  },
});
```

4. **统一 target 配置**：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "es2022", // 与 tsconfig.json 一致
  platform: "node", // 明确指定 Node.js 平台
  clean: true,
  sourcemap: false,
  banner: {
    js: "#!/usr/bin/env node",
  },
});
```

5. **添加 splitting 配置**：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: false,
  splitting: true, // 代码分割（多入口时有用）
  banner: {
    js: "#!/usr/bin/env node",
  },
});
```

6. **添加外部依赖配置**：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: false,
  external: ["node:*"], // 明确标记 Node.js 内置模块为外部依赖
  noExternal: [], // 不打包任何外部依赖
  banner: {
    js: "#!/usr/bin/env node",
  },
});
```

7. **添加 onSuccess 钩子**：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs"],
  target: "node18",
  clean: true,
  sourcemap: false,
  banner: {
    js: "#!/usr/bin/env node",
  },
  onSuccess: async () => {
    console.log("✅ Build completed successfully!");
    // 可以在这里添加额外的构建后步骤
  },
});
```

8. **考虑 ESM 输出**：

如果未来需要支持 ESM：

```typescript
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  outDir: "bin",
  format: ["cjs", "esm"], // 双格式输出
  target: "node18",
  clean: true,
  sourcemap: false,
  banner: {
    js: "#!/usr/bin/env node",
  },
});
```

输出：
- `bin/mcp-server.js` (CommonJS)
- `bin/mcp-server.mjs` (ESM)
