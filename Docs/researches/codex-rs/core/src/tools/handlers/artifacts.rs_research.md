# artifacts.rs 深度研究文档

## 场景与职责

`artifacts.rs` 实现了 Codex 的 **Artifact 工具处理器**，用于执行 JavaScript 代码片段并生成可运行的 Artifact（如 React 组件、可视化图表、交互式应用等）。该工具允许模型生成 JavaScript 代码，在隔离的运行时环境中执行，并返回执行结果。

**核心使用场景：**
1. **生成交互式组件** - 创建 React/Vue 组件
2. **数据可视化** - 生成图表、图形展示
3. **原型验证** - 快速验证代码逻辑
4. **教学演示** - 生成可运行的示例代码

## 功能点目的

### 1. JavaScript 代码执行
- 在隔离的 Node.js 运行时中执行 JavaScript
- 支持超时控制（默认 30 秒）
- 支持自定义超时配置（通过 pragma）

### 2. Artifact 运行时管理
- 使用 `codex_artifacts` crate 管理运行时
- 支持运行时版本控制
- 从 GitHub Release 下载预构建运行时

### 3. 输入解析
- 支持 freeform 输入（原始 JavaScript 代码）
- 支持 pragma 配置（`// codex-artifact-tool: timeout_ms=15000`）
- 拒绝 JSON 包装或 Markdown 代码块

### 4. 事件发射
- 发射 ExecCommandBegin/End 事件
- 支持 stdout/stderr 捕获
- 格式化输出结果

### 5. 功能开关
- 通过 `Feature::Artifact` 控制是否启用
- 可在配置中禁用

## 具体技术实现

### 关键数据结构

```rust
pub struct ArtifactsHandler;

const ARTIFACTS_TOOL_NAME: &str = "artifacts";
const ARTIFACT_TOOL_PRAGMA_PREFIX: &str = "// codex-artifact-tool:";
const DEFAULT_EXECUTION_TIMEOUT: Duration = Duration::from_secs(30);

// 解析后的参数结构
#[derive(Debug, Clone, PartialEq, Eq)]
struct ArtifactsToolArgs {
    source: String,        // JavaScript 源代码
    timeout_ms: Option<u64>, // 可选超时（毫秒）
}

// Artifact 构建请求
pub struct ArtifactBuildRequest {
    pub source: String,
    pub cwd: PathBuf,
    pub timeout: Option<Duration>,
    pub env: HashMap<String, String>,
}

// Artifact 执行输出
pub struct ArtifactCommandOutput {
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}
```

### 关键流程

#### 1. Handler 入口 (`ArtifactsHandler::handle`)

```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 检查功能开关
    if !session.enabled(Feature::Artifact) {
        return Err(FunctionCallError::RespondToModel(
            "artifacts is disabled by feature flag".to_string(),
        ));
    }

    // 2. 解析参数
    let args = match payload {
        ToolPayload::Custom { input } => parse_freeform_args(&input)?,
        _ => error,
    };

    // 3. 创建客户端
    let client = ArtifactsClient::from_runtime_manager(default_runtime_manager(
        turn.config.codex_home.clone(),
    ));

    // 4. 发射开始事件
    emit_exec_begin(session.as_ref(), turn.as_ref(), &call_id).await;

    // 5. 执行构建
    let result = client.execute_build(ArtifactBuildRequest {
        source: args.source,
        cwd: turn.cwd.clone(),
        timeout: Some(Duration::from_millis(args.timeout_ms.unwrap_or(...))),
        env: Default::default(),
    }).await;

    // 6. 处理结果
    let (success, output) = match result {
        Ok(output) => (output.success(), output),
        Err(error) => (false, error_output(&error)),
    };

    // 7. 发射结束事件
    emit_exec_end(session, turn, &call_id, &output, started_at.elapsed(), success).await;

    // 8. 返回结果
    Ok(FunctionToolOutput::from_text(format_artifact_output(&output), Some(success)))
}
```

#### 2. 参数解析流程 (`parse_freeform_args`)

```rust
fn parse_freeform_args(input: &str) -> Result<ArtifactsToolArgs, FunctionCallError> {
    // 1. 空内容检查
    if input.trim().is_empty() { error }

    let mut args = ArtifactsToolArgs { source: input.to_string(), timeout_ms: None };

    // 2. 分割第一行和剩余内容
    let mut lines = input.splitn(2, '\n');
    let first_line = lines.next().unwrap_or_default();
    let rest = lines.next().unwrap_or_default();

    // 3. 检查 pragma 前缀
    let trimmed = first_line.trim_start();
    let Some(pragma) = parse_pragma_prefix(trimmed) else {
        // 无 pragma，验证并返回
        reject_json_or_quoted_source(&args.source)?;
        return Ok(args);
    };

    // 4. 解析 pragma 指令
    let mut timeout_ms = None;
    for token in directive.split_whitespace() {
        let (key, value) = token.split_once('=').ok_or_else(...)?;
        match key {
            "timeout_ms" => { timeout_ms = Some(value.parse::<u64>()?); }
            _ => error,
        }
    }

    // 5. 验证剩余内容非空
    if rest.trim().is_empty() { error }

    // 6. 拒绝 JSON/引号包装
    reject_json_or_quoted_source(rest)?;
    args.source = rest.to_string();
    args.timeout_ms = timeout_ms;
    Ok(args)
}
```

#### 3. 拒绝非原始代码 (`reject_json_or_quoted_source`)

```rust
fn reject_json_or_quoted_source(code: &str) -> Result<(), FunctionCallError> {
    let trimmed = code.trim();
    
    // 拒绝 Markdown 代码块
    if trimmed.starts_with("```") {
        return Err(FunctionCallError::RespondToModel(
            "artifacts expects raw JavaScript source, not markdown code fences...".to_string(),
        ));
    }
    
    // 拒绝 JSON 对象或字符串
    let Ok(value) = serde_json::from_str::<JsonValue>(trimmed) else {
        return Ok(());  // 不是 JSON，允许
    };
    match value {
        JsonValue::Object(_) | JsonValue::String(_) => Err(...),
        _ => Ok(()),
    }
}
```

#### 4. 运行时管理器创建

```rust
fn default_runtime_manager(codex_home: PathBuf) -> ArtifactRuntimeManager {
    ArtifactRuntimeManager::new(ArtifactRuntimeManagerConfig::with_default_release(
        codex_home,
        versions::ARTIFACT_RUNTIME,  // 版本号常量
    ))
}
```

### 事件发射

```rust
async fn emit_exec_begin(session: &Session, turn: &TurnContext, call_id: &str) {
    let emitter = ToolEmitter::shell(
        vec![ARTIFACTS_TOOL_NAME.to_string()],
        turn.cwd.clone(),
        ExecCommandSource::Agent,
        /*freeform*/ true,
    );
    let ctx = ToolEventCtx::new(session, turn, call_id, /*turn_diff_tracker*/ None);
    emitter.emit(ctx, ToolEventStage::Begin).await;
}

async fn emit_exec_end(...) {
    let exec_output = ExecToolCallOutput {
        exit_code: output.exit_code.unwrap_or(1),
        stdout: StreamOutput::new(output.stdout.clone()),
        stderr: StreamOutput::new(output.stderr.clone()),
        aggregated_output: StreamOutput::new(format_artifact_output(output)),
        duration,
        timed_out: false,
    };
    // ... 发射事件
}
```

### 输出格式化

```rust
fn format_artifact_output(output: &ArtifactCommandOutput) -> String {
    let stdout = output.stdout.trim();
    let stderr = output.stderr.trim();
    let mut sections = vec![format!("exit_code: {}", output.exit_code.map(...))];
    if !stdout.is_empty() { sections.push(format!("stdout:\n{stdout}")); }
    if !stderr.is_empty() { sections.push(format!("stderr:\n{stderr}")); }
    if stdout.is_empty() && stderr.is_empty() && output.success() {
        sections.push("artifact JS completed successfully.".to_string());
    }
    sections.join("\n\n")
}
```

## 关键代码路径与文件引用

### 当前文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `ArtifactsHandler::handle` | 58-121 | 主处理入口 |
| `parse_freeform_args` | 123-188 | 参数解析 |
| `reject_json_or_quoted_source` | 190-208 | 拒绝非原始代码 |
| `parse_pragma_prefix` | 210-212 | 解析 pragma 前缀 |
| `default_runtime_manager` | 214-219 | 创建运行时管理器 |
| `emit_exec_begin` | 221-230 | 发射开始事件 |
| `emit_exec_end` | 232-261 | 发射结束事件 |
| `format_artifact_output` | 263-283 | 格式化输出 |
| `error_output` | 285-291 | 错误输出构造 |

### 外部依赖

| 模块/Crate | 用途 |
|------------|------|
| `codex_artifacts` | Artifact 运行时管理 |
| `codex_artifacts::ArtifactRuntimeManager` | 运行时生命周期 |
| `codex_artifacts::ArtifactsClient` | 客户端接口 |
| `crate::packages::versions::ARTIFACT_RUNTIME` | 运行时版本 |
| `ToolEmitter` | 事件发射 |
| `Feature::Artifact` | 功能开关 |

## 依赖与外部交互

### 与 Artifact 系统集成

```rust
// 创建客户端
let client = ArtifactsClient::from_runtime_manager(default_runtime_manager(codex_home));

// 执行构建
let result = client.execute_build(ArtifactBuildRequest {
    source: args.source,
    cwd: turn.cwd.clone(),
    timeout: Some(Duration::from_millis(timeout)),
    env: Default::default(),
}).await;
```

### 与事件系统集成

```rust
// 使用 ToolEmitter 发射事件
let emitter = ToolEmitter::shell(
    vec![ARTIFACTS_TOOL_NAME.to_string()],
    turn.cwd.clone(),
    ExecCommandSource::Agent,
    /*freeform*/ true,
);
emitter.emit(ctx, ToolEventStage::Begin).await;
```

### 与功能开关集成

```rust
// 检查功能是否启用
if !session.enabled(Feature::Artifact) {
    return Err(FunctionCallError::RespondToModel(
        "artifacts is disabled by feature flag".to_string(),
    ));
}
```

## 风险、边界与改进建议

### 已知风险

1. **代码执行安全**
   - 执行用户/模型提供的 JavaScript 代码存在安全风险
   - 依赖 `codex_artifacts` 的沙箱隔离
   - 建议：定期审计运行时安全

2. **资源耗尽**
   - 无限循环或内存泄漏可能耗尽资源
   - 已通过超时控制缓解
   - 建议：添加内存限制

3. **网络访问**
   - Artifact 运行时可能有网络访问权限
   - 建议：明确网络策略，默认禁用

### 边界情况

1. **空代码**
   - 返回错误："artifacts expects raw JavaScript source text (non-empty)"

2. **只有 pragma 无代码**
   - 返回错误："artifacts pragma must be followed by JavaScript source"

3. **无效 pragma 格式**
   - 返回错误："artifacts pragma expects space-separated key=value pairs"

4. **未知 pragma 键**
   - 返回错误："artifacts pragma only supports timeout_ms"

5. **Markdown 代码块**
   - 返回错误："artifacts expects raw JavaScript source, not markdown code fences"

6. **JSON 包装**
   - 返回错误："artifacts is a freeform tool and expects raw JavaScript source"

### 改进建议

1. **安全性增强**
   - 添加代码静态分析，检测危险操作
   - 实现更严格的沙箱策略
   - 添加执行资源限制（CPU、内存）

2. **功能扩展**
   - 支持 TypeScript
   - 支持 npm 包安装
   - 支持多文件 Artifact

3. **可观测性**
   - 添加执行指标收集
   - 支持结构化日志
   - 添加性能分析

4. **用户体验**
   - 支持实时输出流
   - 添加错误位置提示
   - 支持代码热重载

5. **测试覆盖**
   - 当前测试 98 行，覆盖基础场景
   - 建议添加：
     - 超时场景测试
     - 错误处理测试
     - 并发执行测试
