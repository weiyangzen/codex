# codex_tool_config.rs 研究文档

## 场景与职责

`codex_tool_config.rs` 是 Codex MCP 服务器的核心配置文件，负责定义和解析 `codex` 和 `codex-reply` 两个 MCP 工具的参数结构。该文件桥接了 MCP 协议与 Codex 核心配置系统，使外部 MCP 客户端能够通过标准化的 JSON-RPC 接口调用 Codex 功能。

**核心职责：**
1. 定义 `codex` 工具的输入参数结构 (`CodexToolCallParam`)
2. 定义 `codex-reply` 工具的输入参数结构 (`CodexToolCallReplyParam`)
3. 将 MCP 工具参数转换为 Codex 内部 `Config` 配置对象
4. 生成符合 JSON Schema 规范的工具定义，供 MCP 客户端发现和使用

## 功能点目的

### 1. CodexToolCallParam - 初始会话参数

用于启动新的 Codex 会话，包含完整的配置选项：

| 字段 | 类型 | 说明 |
|------|------|------|
| `prompt` | `String` | 初始用户提示（必填） |
| `model` | `Option<String>` | 模型名称覆盖 |
| `profile` | `Option<String>` | 配置 profile |
| `cwd` | `Option<String>` | 工作目录 |
| `approval_policy` | `Option<CodexToolCallApprovalPolicy>` | 命令审批策略 |
| `sandbox` | `Option<CodexToolCallSandboxMode>` | 沙箱模式 |
| `config` | `Option<HashMap<String, serde_json::Value>>` | 额外配置覆盖 |
| `base_instructions` | `Option<String>` | 基础指令覆盖 |
| `developer_instructions` | `Option<String>` | 开发者指令 |
| `compact_prompt` | `Option<String>` | 压缩提示词 |

### 2. CodexToolCallReplyParam - 继续会话参数

用于在现有会话中继续对话：

| 字段 | 类型 | 说明 |
|------|------|------|
| `conversation_id` | `Option<String>` | 已废弃，使用 thread_id |
| `thread_id` | `Option<String>` | 会话线程 ID |
| `prompt` | `String` | 后续用户提示（必填） |

### 3. 审批策略枚举

```rust
pub enum CodexToolCallApprovalPolicy {
    Untrusted,   // 除非受信任，否则需要审批
    OnFailure,   // 失败时需要审批
    OnRequest,   // 请求时需要审批
    Never,       // 永不审批
}
```

映射到内部 `AskForApproval` 类型，实现策略转换。

### 4. 沙箱模式枚举

```rust
pub enum CodexToolCallSandboxMode {
    ReadOnly,          // 只读模式
    WorkspaceWrite,    // 工作区可写
    DangerFullAccess,  // 完全访问（危险）
}
```

映射到内部 `SandboxMode` 类型。

## 具体技术实现

### 配置转换流程

```rust
impl CodexToolCallParam {
    pub async fn into_config(
        self,
        arg0_paths: Arg0DispatchPaths,
    ) -> std::io::Result<(String, Config)> {
        // 1. 构建 ConfigOverrides
        let overrides = ConfigOverrides {
            model,
            config_profile: profile,
            cwd: cwd.map(PathBuf::from),
            approval_policy: approval_policy.map(Into::into),
            sandbox_mode: sandbox.map(Into::into),
            codex_linux_sandbox_exe: arg0_paths.codex_linux_sandbox_exe.clone(),
            main_execve_wrapper_exe: arg0_paths.main_execve_wrapper_exe.clone(),
            base_instructions,
            developer_instructions,
            compact_prompt,
            ..Default::default()
        };

        // 2. 转换 CLI 覆盖配置（JSON -> TOML）
        let cli_overrides = cli_overrides
            .unwrap_or_default()
            .into_iter()
            .map(|(k, v)| (k, json_to_toml(v)))
            .collect();

        // 3. 加载最终配置
        let cfg = Config::load_with_cli_overrides_and_harness_overrides(
            cli_overrides, 
            overrides
        ).await?;

        Ok((prompt, cfg))
    }
}
```

### JSON Schema 生成

使用 `schemars` 库自动生成 JSON Schema：

```rust
pub(crate) fn create_tool_for_codex_tool_call_param() -> Tool {
    let schema = SchemaSettings::draft2019_09()
        .with(|s| {
            s.inline_subschemas = true;      // 内联子模式
            s.option_add_null_type = false;  // 不添加 null 类型
        })
        .into_generator()
        .into_root_schema_for::<CodexToolCallParam>();
    
    // 提取核心 schema 字段
    let input_schema = create_tool_input_schema(schema, "...");
    
    Tool {
        name: "codex".into(),
        title: Some("Codex".to_string()),
        input_schema,
        output_schema: Some(codex_tool_output_schema()),
        description: Some("Run a Codex session...".into()),
        ...
    }
}
```

### 输出 Schema 定义

```rust
fn codex_tool_output_schema() -> Arc<JsonObject> {
    let schema = serde_json::json!({
        "type": "object",
        "properties": {
            "threadId": { "type": "string" },
            "content": { "type": "string" }
        },
        "required": ["threadId", "content"],
    });
    ...
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `Arg0DispatchPaths` | `codex_arg0` | 传递辅助可执行文件路径 |
| `Config` | `codex_core::config` | 核心配置对象 |
| `ConfigOverrides` | `codex_core::config` | 配置覆盖项 |
| `ThreadId` | `codex_protocol` | 线程标识 |
| `SandboxMode` | `codex_protocol::config_types` | 沙箱模式定义 |
| `AskForApproval` | `codex_protocol::protocol` | 审批策略定义 |
| `json_to_toml` | `codex_utils_json_to_toml` | JSON 到 TOML 转换 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `rmcp::model::Tool` | MCP 工具定义 |
| `schemars::JsonSchema` | JSON Schema 派生宏 |
| `serde::{Serialize, Deserialize}` | 序列化/反序列化 |

### 调用关系

```
message_processor.rs::handle_tool_call_codex()
    └─> CodexToolCallParam::into_config()
        └─> Config::load_with_cli_overrides_and_harness_overrides()

codex_tool_runner.rs::run_codex_tool_session()
    └─> 使用返回的 (prompt, config) 启动会话
```

## 依赖与外部交互

### 配置加载流程

1. **参数解析**：从 MCP `tools/call` 请求解析 JSON 参数
2. **转换覆盖**：将 JSON 配置项转换为 TOML 格式（与 CLI `-c` 选项兼容）
3. **配置合并**：
   - 基础配置（来自 `CODEX_HOME/config.toml`）
   - CLI 覆盖（`config` 字段）
   - 结构化覆盖（`model`, `profile`, `approval_policy` 等字段）
4. **验证加载**：调用 `Config::load_with_cli_overrides_and_harness_overrides()`

### 向后兼容性

`CodexToolCallReplyParam` 支持两种 ID 字段：
- `thread_id`：新字段（推荐）
- `conversation_id`：已废弃字段（向后兼容）

```rust
pub(crate) fn get_thread_id(&self) -> anyhow::Result<ThreadId> {
    if let Some(thread_id) = &self.thread_id {
        ThreadId::from_string(thread_id)
    } else if let Some(conversation_id) = &self.conversation_id {
        ThreadId::from_string(conversation_id)  // 兼容旧客户端
    } else {
        Err(anyhow::anyhow!("either threadId or conversationId must be provided"))
    }
}
```

## 风险、边界与改进建议

### 已知风险

1. **序列化失败**：`create_tool_input_schema` 中的 `expect` 调用在极端情况下可能 panic
   ```rust
   let schema_value = serde_json::to_value(&schema).expect(panic_message);
   ```

2. **路径解析**：`cwd` 字段如果是相对路径，依赖于服务器进程的当前工作目录，可能产生意外行为

3. **配置验证延迟**：配置错误（如无效的 model 名称）直到 `into_config().await` 才被发现

### 边界情况

| 场景 | 行为 |
|------|------|
| `prompt` 为空字符串 | 允许，但可能导致模型行为不确定 |
| `config` 包含未知键 | 由 `Config::load_with_cli_overrides` 决定（通常忽略） |
| `thread_id` 和 `conversation_id` 同时提供 | 优先使用 `thread_id` |
| 无效的 `approval_policy` 值 | JSON 解析失败，返回错误响应 |

### 改进建议

1. **增强验证**：在 `CodexToolCallParam` 上添加 `validate()` 方法，提前检查必填字段和格式

2. **路径规范化**：使用 `std::fs::canonicalize` 处理 `cwd` 路径，避免相对路径歧义

3. **错误细化**：将 `into_config` 的 `std::io::Result` 改为自定义错误类型，提供更具体的错误上下文

4. **Schema 文档**：为 `config` 字段的额外属性添加文档链接，说明支持的配置键

5. **废弃策略**：为 `conversation_id` 添加废弃警告日志，推动客户端迁移

### 测试覆盖

文件包含两个 JSON Schema 快照测试：
- `verify_codex_tool_json_schema`：验证 `codex` 工具的完整 schema
- `verify_codex_tool_reply_json_schema`：验证 `codex-reply` 工具的 schema

这些测试作为"可执行文档"，确保 schema 变更可被审计。
