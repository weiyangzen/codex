# codex-rs/artifacts/src/client.rs 研究文档

## 场景与职责

`client.rs` 是 `codex-artifacts` crate 的核心执行模块，负责**执行 Artifact 构建命令**。它提供了一个高级客户端 `ArtifactsClient`，用于在已解析的 JavaScript 运行时上执行 artifact-building JavaScript 代码。

主要使用场景：
- Codex CLI/TUI 需要执行用户提供的 artifact 构建脚本时
- 需要将用户代码包装后运行在隔离的 JavaScript 运行时环境中
- 支持多种 JavaScript 运行时（Node.js、Electron）执行 artifact 工具

## 功能点目的

### 1. ArtifactsClient - 构建执行客户端

提供两种构造方式：
- `from_runtime_manager()`: 懒加载模式，按需解析或下载运行时
- `from_installed_runtime()`: 预绑定模式，使用已加载的运行时

### 2. execute_build - 执行构建请求

核心功能流程：
1. 解析/获取 JavaScript 运行时
2. 创建临时 staging 目录
3. 生成包装后的 JavaScript 脚本
4. 配置并执行子进程命令
5. 捕获 stdout/stderr 和退出码
6. 处理超时和错误

### 3. 脚本包装机制 (build_wrapped_script)

将用户代码包装在一个模块导入上下文中：
- 动态导入 artifact 工具入口点
- 将工具导出绑定到 `globalThis`
- 在全局作用域暴露工具函数，使用户代码可直接调用

### 4. 命令执行与超时控制 (run_command)

- 使用 `tokio::process::Command` 异步执行
- 并行读取 stdout/stderr
- 支持可配置的执行超时（默认 30 秒）
- 超时后自动 kill 子进程

## 具体技术实现

### 关键数据结构

```rust
/// 构建请求参数
pub struct ArtifactBuildRequest {
    pub source: String,                    // 用户 JavaScript 代码
    pub cwd: PathBuf,                      // 工作目录
    pub timeout: Option<Duration>,         // 可选超时
    pub env: BTreeMap<String, String>,     // 环境变量
}

/// 命令执行结果
pub struct ArtifactCommandOutput {
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

/// 运行时源（内部枚举）
enum RuntimeSource {
    Managed(ArtifactRuntimeManager),       // 托管模式，可自动下载
    Installed(InstalledArtifactRuntime),   // 已安装模式
}
```

### 关键流程

#### execute_build 流程

```
execute_build(request)
    ├── resolve_runtime().await           // 获取运行时
    │   ├── RuntimeSource::Installed -> 直接返回
    │   └── RuntimeSource::Managed -> manager.ensure_installed()
    ├── resolve_js_runtime()              // 解析 JS 可执行文件
    ├── TempDir::new()                    // 创建临时目录
    ├── build_wrapped_script()            // 生成包装脚本
    ├── fs::write(script_path)            // 写入临时文件
    ├── Command::new(js_executable)
    │   ├── arg(script_path)
    │   ├── current_dir(request.cwd)
    │   ├── env(ELECTRON_RUN_AS_NODE=1)   // 如需要
    │   └── envs(request.env)
    └── run_command(command, timeout).await
```

#### 脚本包装逻辑

```javascript
// 生成的包装脚本结构
const artifactTool = await import("file:///path/to/artifact_tool.mjs");
globalThis.artifactTool = artifactTool;
for (const [name, value] of Object.entries(artifactTool)) {
  if (name === "default" || Object.prototype.hasOwnProperty.call(globalThis, name)) {
    continue;
  }
  globalThis[name] = value;
}
// 用户代码插入此处
{user_source}
```

#### run_command 并发处理

```rust
// 1. 启动子进程
let mut child = command.spawn()?;

// 2. 获取管道
let mut stdout = child.stdout.take().unwrap();
let mut stderr = child.stderr.take().unwrap();

// 3. 并发读取输出
let stdout_task = tokio::spawn(async { read_to_end(&mut stdout).await });
let stderr_task = tokio::spawn(async { read_to_end(&mut stderr).await });

// 4. 带超时等待进程结束
let status = timeout(execution_timeout, child.wait()).await;

// 5. 收集结果
let stdout_bytes = stdout_task.await??;
let stderr_bytes = stderr_task.await??;
```

### 错误处理

```rust
pub enum ArtifactsError {
    Runtime(ArtifactRuntimeError),         // 运行时相关错误
    Io { context, source },                // IO 错误（带上下文）
    TimedOut { timeout },                  // 执行超时
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `ArtifactRuntimeManager` | `runtime/manager.rs` | 托管运行时，支持自动下载 |
| `InstalledArtifactRuntime` | `runtime/installed.rs` | 已安装运行时，包含 JS 路径 |
| `ArtifactRuntimeError` | `runtime/error.rs` | 运行时错误类型 |
| `JsRuntime` | `runtime/js_runtime.rs` | JavaScript 运行时抽象 |

### 关键代码行

- **行 16**: 默认执行超时 `30秒`
- **行 47-92**: `execute_build` 主函数
- **行 94-99**: `resolve_runtime` 运行时解析
- **行 103-109**: `ArtifactBuildRequest` 结构定义
- **行 112-124**: `ArtifactCommandOutput` 结果结构
- **行 141-163**: `build_wrapped_script` 脚本包装
- **行 165-229**: `run_command` 命令执行与超时处理

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、进程管理、文件操作 |
| `tempfile` | 临时目录创建 |
| `url` | 文件 URL 转换 |
| `serde_json` | URL 序列化到 JS 字符串 |
| `thiserror` | 错误派生宏 |

## 依赖与外部交互

### 运行时依赖

1. **JavaScript 运行时**: 需要系统中存在 Node.js 或 Electron
2. **Artifact 工具包**: 需要 `@oai/artifact-tool` 包已安装

### 文件系统交互

- 创建临时目录（`tempfile::TempDir`）
- 写入包装脚本到临时文件
- 在指定工作目录执行命令

### 环境变量处理

- 支持注入自定义环境变量到子进程
- 自动设置 `ELECTRON_RUN_AS_NODE=1`（当使用 Electron 时）

### 调用关系图

```
ArtifactsClient::execute_build
    ├── InstalledArtifactRuntime::resolve_js_runtime
    │   └── resolve_js_runtime_from_candidates
    │       ├── system_node_runtime()      [js_runtime.rs]
    │       ├── system_electron_runtime()  [js_runtime.rs]
    │       └── codex_app_runtime_candidates() [js_runtime.rs]
    └── run_command
        └── tokio::process::Command
```

## 风险、边界与改进建议

### 已知风险

1. **超时处理风险**
   - 超时后 kill 进程使用 `let _ = child.kill().await`，忽略错误
   - 僵尸进程风险：如果 kill 失败，进程可能继续运行

2. **脚本注入风险**
   - 用户代码直接拼接到包装脚本中
   - 虽然运行在隔离进程，但需确保 artifact 工具权限控制

3. **临时文件清理**
   - 依赖 `TempDir` 的 Drop 实现清理
   - 如果进程异常退出，可能留下临时文件

4. **编码问题**
   - 使用 `String::from_utf8_lossy` 转换输出，可能丢失无效 UTF-8 数据

### 边界情况

1. **Electron 环境变量**
   - 仅当 `js_runtime.requires_electron_run_as_node()` 返回 true 时设置环境变量
   - 边界：如果 Electron 检测逻辑有误，可能导致工具运行失败

2. **路径转换**
   - `Url::from_file_path` 可能失败（虽然理论上不应失败）
   - 已处理错误，但属于防御性编程

3. **并发执行**
   - 每个 `execute_build` 调用创建独立进程
   - 无全局并发限制，大量并发可能导致资源耗尽

### 改进建议

1. **增强超时处理**
   ```rust
   // 建议：添加更完善的清理逻辑
   Err(_) => {
       let _ = child.kill().await;
       let _ = child.wait().await;  // 确保收割僵尸进程
       // 考虑添加 SIGKILL 后备
       return Err(ArtifactsError::TimedOut { ... });
   }
   ```

2. **资源限制**
   - 添加内存限制（通过 cgroup 或 ulimit）
   - 添加并发执行限制

3. **输出流处理优化**
   - 当前实现等待进程结束后再读取输出
   - 对于长时间运行的构建，可考虑流式输出

4. **缓存包装脚本**
   - 相同 artifact 工具版本的包装脚本可以缓存
   - 避免重复创建临时文件

5. **增强错误上下文**
   - 在 IO 错误中包含更多上下文（如命令行参数）
   - 便于调试构建失败

6. **测试覆盖**
   - 当前测试主要覆盖正常路径
   - 建议添加：
     - 超时场景测试
     - 无效 JavaScript 代码测试
     - 大输出处理测试
     - 并发执行测试
