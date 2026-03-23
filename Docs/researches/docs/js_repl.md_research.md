# js_repl.md 研究文档

## 场景与职责

js_repl.md 是 Codex CLI 项目中关于 JavaScript REPL（Read-Eval-Print Loop）功能的详细文档。该功能允许在持久的 Node.js 后端内核中运行 JavaScript 代码，支持顶层 await。

**适用场景：**
- 用户需要使用 JavaScript REPL 功能
- 开发者需要理解 js_repl 的工作原理和限制
- 调试 js_repl 相关问题

## 功能点目的

### 1. 功能开关
**默认状态**：禁用

**启用方式**：
```toml
[features]
js_repl = true
```

**仅工具模式**：
```toml
[features]
js_repl = true
js_repl_tools_only = true
```
- 强制直接模型工具调用通过 `js_repl`
- 其他工具仍可通过 `await codex.tool(...)` 在 js_repl 内部使用

### 2. Node 运行时要求
- **版本要求**：必须符合或超过 `codex-rs/node-version.txt` 中的版本

**运行时解析顺序**：
1. `CODEX_JS_REPL_NODE_PATH` 环境变量
2. `js_repl_node_path` 配置/配置文件
3. `PATH` 上发现的 `node`

**显式配置**：
```toml
js_repl_node_path = "/absolute/path/to/node"
```

### 3. 模块解析
**支持的导入**：
- 裸指定符（如 `await import("pkg")`）
- 相对路径本地文件
- 绝对路径
- `file://` URL 指向 ESM `.js` / `.mjs` 文件

**模块搜索路径顺序**：
1. `CODEX_JS_REPL_NODE_MODULE_DIRS`（PATH 分隔的列表）
2. `js_repl_node_module_dirs` 配置/配置文件（绝对路径数组）
3. 线程工作目录（cwd，始终作为最后回退）

**重要说明**：
- 裸包导入使用 REPL 范围的搜索路径
- 即使从导入的本地文件发起，也不相对于导入文件位置解析

### 4. 使用方式
- **自由格式工具**：发送原始 JavaScript 源码文本
- **可选首行 pragma**：`// codex-js-repl: timeout_ms=15000`
- **状态持久化**：顶层绑定在调用间持久化
- **错误处理**：
  - 单元格抛出错误时，之前的绑定仍可用
  - 初始化在抛出前完成的词法绑定在后续调用中保持可用
  - 提升的 `var` / `function` 绑定仅在执行明确到达声明或支持的写入站点时持久化

**支持的提升 var 失败单元格情况**：
- 声明前的直接顶层标识符写入和更新（如 `x = 1`, `x += 1`, `x++`, `x &&= 1`）
- 非空顶层 `for...in` / `for...of` 循环

**故意不支持的失败单元格情况**：
- 声明前的提升函数读取
- 别名或直接基于 IIFE 的推断
- 嵌套块或其他嵌套语句结构中的写入
- 已检测赋值 RHS 表达式内的嵌套写入
- 提升 `var` 的解构赋值恢复
- 部分 `var` 解构恢复
- 声明前的 `undefined` 读取
- 空顶层 `for...in` / `for...of` 循环变量

**导入限制**：
- 顶层静态导入声明（如 `import x from "pkg"`）当前不支持
- 使用动态导入 `await import("pkg")`

**本地文件导入规则**：
- 必须是 ESM `.js` / `.mjs` 文件
- 在与调用单元格相同的 REPL VM 上下文中运行
- 导入的本地文件中的静态导入只能针对其他本地 `.js` / `.mjs` 文件
- 裸包和内置导入必须通过 `await import(...)` 保持动态
- `import.meta.resolve()` 返回可导入字符串
- 本地文件模块在 exec 之间重新加载

**状态重置**：使用 `js_repl_reset` 清除内核状态

### 5. 内核中的辅助 API
**全局暴露**：
- `codex.cwd`：REPL 工作目录路径
- `codex.homeDir`：内核环境中的有效主目录路径
- `codex.tmpDir`：每会话临时目录路径
- `codex.tool(name, args?)`：从 js_repl 内部执行普通 Codex 工具调用
- `codex.emitImage(imageLike)`：显式添加图像到外层 `js_repl` 函数输出

**API 特性**：
- `codex.tool(...)` 和 `codex.emitImage(...)` 在单元格间保持稳定的辅助身份
- 保存的引用和持久化对象可在后续单元格中重用
- 单元格完成后触发的异步回调仍会失败（没有活动的 exec）
- 导入的本地文件也可访问 `codex.*`、捕获的 `console` 和 Node 风格的 `import.meta` 辅助
- 每个 `codex.tool(...)` 调用从 `codex_core::tools::js_repl` 记录器发出有界摘要（`info` 级别）
- `trace` 级别记录 JavaScript 看到的精确序列化响应对象或错误字符串
- 嵌套 `codex.tool(...)` 输出除非显式发出，否则保留在 JavaScript 内部

**codex.emitImage 参数**：
- 数据 URL
- 单个 `input_image` 项
- 对象如 `{ bytes, mimeType }`
- 包含恰好一个图像且无文本的原始工具响应对象
- 多次调用可发出多个图像
- 拒绝混合文本和图像内容

**图像处理细节**：
- 仅当 `view_image` 工具模式包含 `detail` 参数时，才能使用 `detail: "original"` 请求全分辨率图像处理
- `codex.emitImage(...)` 同样适用：如果 `view_image.detail` 存在，也可传递 `detail: "original"`
- 示例（Playwright 截图）：`await codex.emitImage({ bytes: await page.screenshot({ type: "jpeg", quality: 85 }), mimeType: "image/jpeg", detail: "original" })`
- 示例（本地图像）：`await codex.emitImage(codex.tool("view_image", { path: "/absolute/path", detail: "original" }))`
- 编码图像时，如果可接受有损压缩，优先使用 JPEG 约 85 质量；当透明度或无损细节重要时使用 PNG

**重要警告**：
- 避免直接写入 `process.stdout` / `process.stderr` / `process.stdin`
- 内核使用 stdio 上的 JSON 行传输

### 6. 调试日志
**日志级别**：
- `info`：记录有界摘要
- `trace`：记录精确序列化响应对象或错误字符串

**日志输出位置**：
- `codex app-server`：写入服务器进程 `stderr`

**示例命令**：
```bash
# info 级别
RUST_LOG=codex_core::tools::js_repl=info \
  LOG_FORMAT=json \
  codex app-server \
  2> /tmp/codex-app-server.log

# trace 级别
RUST_LOG=codex_core::tools::js_repl=trace \
  LOG_FORMAT=json \
  codex app-server \
  2> /tmp/codex-app-server.log
```

### 7. Vendored 解析器资源
**资源位置**：`codex-rs/core/src/tools/js_repl/meriyah.umd.min.js`

**来源**：`meriyah@7.0.0` from npm (`dist/meriyah.umd.min.js`)

**许可跟踪**：
- `third_party/meriyah/LICENSE`
- `NOTICE`

**更新流程**：
1. 替换版本号
2. 复制新的 `dist/meriyah.umd.min.js`
3. 复制包许可
4. 更新文件头注释中的版本字符串
5. 如果上游版权声明更改，更新 `NOTICE`
6. 运行相关 `js_repl` 测试

## 具体技术实现

### 架构概览

```
Codex CLI
    ↓
js_repl 工具调用
    ↓
Node.js 子进程（持久内核）
    ↓
JavaScript 执行
    ↓
JSON 行响应
```

### 执行流程

```
用户输入 JavaScript 代码
    ↓
Meriyah 解析器解析 AST
    ↓
代码转换（变量提升处理等）
    ↓
发送到 Node.js 内核
    ↓
执行代码
    ↓
捕获输出和返回值
    ↓
JSON 序列化响应
    ↓
返回给 Codex
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/js_repl.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/core/src/tools/js_repl/` | js_repl 实现目录 |
| `/home/sansha/Github/codex/codex-rs/core/src/tools/js_repl/meriyah.umd.min.js` | Meriyah 解析器 |
| `/home/sansha/Github/codex/codex-rs/node-version.txt` | Node 版本要求 |
| `/home/sansha/Github/codex/third_party/meriyah/LICENSE` | Meriyah 许可 |
| `/home/sansha/Github/codex/NOTICE` | 版权声明 |

### 关键组件

1. **Meriyah 解析器**
   - JavaScript AST 解析
   - 用于代码分析和转换

2. **Node.js 内核**
   - 持久化 JavaScript 执行环境
   - 维护状态

3. **codex.* API**
   - 与 Codex 工具集成
   - 图像处理

## 依赖与外部交互

### 外部依赖

1. **Node.js**
   - JavaScript 运行时
   - 版本要求见 `node-version.txt`

2. **Meriyah**
   - JavaScript 解析器
   - npm 包

3. **npm 包**
   - 通过模块解析导入

### 内部依赖

1. **工具系统**
   - 与 Codex 工具框架集成

2. **日志系统**
   - `tracing` 用于日志

3. **配置系统**
   - 读取 `js_repl` 相关配置

## 风险、边界与改进建议

### 潜在风险

1. **安全风险**
   - JavaScript 代码可以执行任意操作
   - 需要适当的沙盒
   - 建议：确保内核在受限环境中运行

2. **状态管理复杂性**
   - 变量提升和错误处理逻辑复杂
   - 可能导致意外的状态行为
   - 建议：添加更多测试覆盖边界情况

3. **Node.js 版本兼容性**
   - 严格的版本要求可能导致部署问题
   - 建议：提供更清晰的版本检查和错误消息

### 边界情况

1. **内存限制**
   - 持久内核可能积累大量状态
   - 建议：添加内存使用监控和限制

2. **长时间运行**
   - 无限循环或长时间计算
   - 建议：强化超时机制

3. **模块缓存**
   - 本地文件重新加载行为
   - npm 包的缓存行为

### 改进建议

1. **TypeScript 支持**
   - 添加 TypeScript 支持
   - 提供类型定义

2. **调试工具**
   - 添加断点支持
   - 提供 REPL 检查器

3. **性能优化**
   - 代码缓存
   - 并行执行

4. **安全增强**
   - 更严格的沙盒
   - 资源限制（CPU、内存）

5. **文档增强**
   - 更多使用示例
   - 常见模式指南

6. **测试覆盖**
   - 添加更多边界情况测试
   - 集成测试
