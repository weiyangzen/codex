# codex-rs/core/src/tools/spec.rs 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`spec.rs` 是 Codex 工具系统的**核心规范定义与构建模块**，负责：

1. **工具规范定义**：定义所有可用工具的 JSON Schema、参数结构、输出格式
2. **工具配置管理**：通过 `ToolsConfig` 统一管理工具启用/禁用状态
3. **工具注册构建**：通过 `build_specs_with_discoverable_tools` 函数构建完整的工具注册表
4. **MCP 工具转换**：将外部 MCP (Model Context Protocol) 工具转换为 OpenAI Responses API 兼容格式
5. **动态工具支持**：支持运行时动态添加工具

### 1.2 架构位置

```
codex-rs/core/src/tools/
├── spec.rs          # 本文件：工具规范定义与构建
├── registry.rs      # 工具注册表：处理器注册与分发
├── router.rs        # 工具路由：调用解析与调度
├── context.rs       # 工具上下文：调用上下文与输出定义
├── handlers/        # 各工具的具体实现
│   ├── shell.rs
│   ├── unified_exec.rs
│   ├── apply_patch.rs
│   ├── multi_agents.rs
│   └── ...
└── mod.rs           # 工具模块聚合
```

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| 会话初始化 | 根据模型能力、特性开关、沙箱策略构建可用工具集 |
| MCP 服务器连接 | 将外部 MCP 工具转换为内部 ToolSpec |
| 动态工具加载 | 运行时从配置文件或 API 加载额外工具 |
| 多代理协作 | 为子代理构建受限的工具集 |
| Code Mode | 构建嵌套工具集供代码模式使用 |

---

## 2. 功能点目的

### 2.1 核心数据结构

#### 2.1.1 ToolsConfig - 工具配置中心

```rust
pub(crate) struct ToolsConfig {
    pub available_models: Vec<ModelPreset>,
    pub shell_type: ConfigShellToolType,           // Shell 工具类型
    shell_command_backend: ShellCommandBackendConfig,
    pub unified_exec_shell_mode: UnifiedExecShellMode,
    pub allow_login_shell: bool,
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    pub web_search_mode: Option<WebSearchMode>,
    pub web_search_config: Option<WebSearchConfig>,
    pub web_search_tool_type: WebSearchToolType,
    pub image_gen_tool: bool,
    pub agent_roles: BTreeMap<String, AgentRoleConfig>,
    pub search_tool: bool,                         // 工具搜索
    pub tool_suggest: bool,                        // 工具建议
    pub exec_permission_approvals_enabled: bool,   // 执行权限审批
    pub request_permissions_tool_enabled: bool,    // 请求权限工具
    pub code_mode_enabled: bool,                   // 代码模式
    pub code_mode_only_enabled: bool,
    pub js_repl_enabled: bool,                     // JS REPL
    pub js_repl_tools_only: bool,
    pub can_request_original_image_detail: bool,
    pub collab_tools: bool,                        // 协作工具（多代理）
    pub artifact_tools: bool,                      // 制品工具
    pub request_user_input: bool,                  // 请求用户输入
    pub default_mode_request_user_input: bool,
    pub experimental_supported_tools: Vec<String>, // 实验性工具
    pub agent_jobs_tools: bool,                    // Agent 任务批处理
    pub agent_jobs_worker_tools: bool,
}
```

**设计目的**：
- 集中管理所有工具相关的配置状态
- 支持基于 Feature 标志的条件编译式启用
- 支持模型特定的能力覆盖

#### 2.1.2 JsonSchema - 简化版 JSON Schema

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum JsonSchema {
    Boolean { description: Option<String> },
    String { description: Option<String> },
    Number { description: Option<String> },   // 包含 integer 别名
    Array { items: Box<JsonSchema>, description: Option<String> },
    Object {
        properties: BTreeMap<String, JsonSchema>,
        required: Option<Vec<String>>,
        additional_properties: Option<AdditionalProperties>,
    },
}
```

**设计目的**：
- 提供足够的 JSON Schema 表达能力用于工具定义
- 避免引入完整的 JSON Schema 库依赖
- 与 OpenAI Responses API 兼容

### 2.2 工具类型覆盖

| 工具类别 | 代表工具 | 功能说明 |
|---------|---------|---------|
| **Shell 执行** | `shell`, `shell_command`, `exec_command`, `write_stdin` | 命令执行与交互 |
| **文件操作** | `read_file`, `list_dir`, `grep_files`, `view_image` | 文件系统访问 |
| **代码编辑** | `apply_patch` | 代码补丁应用 |
| **多代理** | `spawn_agent`, `send_input`, `wait_agent`, `close_agent`, `resume_agent` | 子代理生命周期管理 |
| **批处理** | `spawn_agents_on_csv`, `report_agent_job_result` | CSV 批量任务处理 |
| **Web 搜索** | `web_search` | 网络搜索能力 |
| **图像生成** | `image_generation` | AI 图像生成 |
| **交互** | `request_user_input`, `request_permissions` | 用户交互 |
| **MCP 集成** | `list_mcp_resources`, `read_mcp_resource` | MCP 资源访问 |
| **开发** | `js_repl`, `artifacts`, `test_sync_tool` | 开发辅助工具 |
| **计划** | `update_plan` | 任务计划管理 |
| **代码模式** | `exec`, `wait` | Code Mode 执行框架 |

---

## 3. 具体技术实现

### 3.1 工具规范构建流程

```rust
// 核心构建函数
pub(crate) fn build_specs_with_discoverable_tools(
    config: &ToolsConfig,
    mcp_tools: Option<HashMap<String, rmcp::model::Tool>>,
    app_tools: Option<HashMap<String, ToolInfo>>,
    discoverable_tools: Option<Vec<DiscoverableTool>>,
    dynamic_tools: &[DynamicToolSpec],
) -> ToolRegistryBuilder
```

**构建流程**：

1. **创建 Builder**：初始化空的 `ToolRegistryBuilder`
2. **注册处理器**：为每个工具创建对应的 `ToolHandler` Arc 实例
3. **条件添加工具**：根据 `config` 中的开关条件添加工具规范
4. **Code Mode 处理**：如启用 code_mode，递归构建嵌套工具集
5. **Shell 工具选择**：根据 `shell_type` 添加对应的 shell 工具
6. **MCP 工具转换**：将外部 MCP 工具转换为 `ToolSpec::Function`
7. **动态工具添加**：处理运行时动态工具

### 3.2 MCP 工具转换

```rust
pub(crate) fn mcp_tool_to_openai_tool(
    fully_qualified_name: String,
    tool: rmcp::model::Tool,
) -> Result<ResponsesApiTool, serde_json::Error>
```

**转换逻辑**：
1. 提取 MCP 工具的 `description`, `input_schema`, `output_schema`
2. 确保 `properties` 字段存在（OpenAI API 要求）
3. 调用 `sanitize_json_schema` 清理和规范化 schema
4. 包装为 `mcp_call_tool_result_output_schema` 格式的输出 schema

**关键代码路径**（lines 2338-2378）：
```rust
fn mcp_tool_to_openai_tool_parts(
    tool: rmcp::model::Tool,
) -> Result<(String, JsonSchema, Option<JsonValue>), serde_json::Error> {
    // 1. 序列化输入 schema
    let mut serialized_input_schema = serde_json::Value::Object(input_schema.as_ref().clone());
    
    // 2. 确保 properties 存在
    if obj.get("properties").is_none_or(serde_json::Value::is_null) {
        obj.insert("properties".to_string(), serde_json::Value::Object(...));
    }
    
    // 3. 清理 schema
    sanitize_json_schema(&mut serialized_input_schema);
    let input_schema = serde_json::from_value::<JsonSchema>(serialized_input_schema)?;
    
    // 4. 构建输出 schema
    let output_schema = Some(mcp_call_tool_result_output_schema(structured_content_schema));
}
```

### 3.3 JSON Schema 清理

```rust
fn sanitize_json_schema(value: &mut JsonValue)
```

**清理规则**（lines 2406-2508）：

| 问题 | 处理方式 |
|------|---------|
| 布尔形式的 schema (`true`/`false`) | 转换为 `{"type": "string"}` |
| 缺少 `type` 字段 | 根据关键字推断：properties→object, items→array, enum→string |
| 数组形式的 type (联合类型) | 选择第一个支持的类型 |
| 对象缺少 `properties` | 添加空对象 |
| 数组缺少 `items` | 添加 `{"type": "string"}` |

### 3.4 输出 Schema 定义

多个工具定义了结构化的输出 schema：

```rust
// Unified Exec 输出（lines 67-99）
fn unified_exec_output_schema() -> JsonValue {
    json!({
        "type": "object",
        "properties": {
            "chunk_id": { "type": "string" },
            "wall_time_seconds": { "type": "number" },
            "exit_code": { "type": "number" },
            "session_id": { "type": "number" },
            "original_token_count": { "type": "number" },
            "output": { "type": "string" }
        },
        "required": ["wall_time_seconds", "output"],
        "additionalProperties": false
    })
}

// Agent 状态输出（lines 101-130）
fn agent_status_output_schema() -> JsonValue {
    // 支持多种状态：pending_init, running, shutdown, not_found, completed, errored
}
```

### 3.5 Shell 工具变体

根据配置选择不同的 Shell 实现：

| 配置 | 工具 | 说明 |
|------|------|------|
| `ConfigShellToolType::Default` | `shell` | 传统 shell 工具 |
| `ConfigShellToolType::Local` | `local_shell` | 本地 shell |
| `ConfigShellToolType::UnifiedExec` | `exec_command` + `write_stdin` | 统一执行框架 |
| `ConfigShellToolType::ShellCommand` | `shell_command` | 命令式 shell |
| `ConfigShellToolType::Disabled` | - | 禁用 shell |

**ZshFork 模式**（lines 226-254）：
```rust
pub fn for_session(
    shell_command_backend: ShellCommandBackendConfig,
    user_shell: &Shell,
    shell_zsh_path: Option<&PathBuf>,
    main_execve_wrapper_exe: Option<&PathBuf>,
) -> Self {
    // Unix + ZshFork 特性 + Zsh shell 类型时启用
    if cfg!(unix)
        && shell_command_backend == ShellCommandBackendConfig::ZshFork
        && matches!(user_shell.shell_type, ShellType::Zsh)
        && let (Some(shell_zsh_path), Some(main_execve_wrapper_exe)) = ...
    {
        Self::ZshFork(ZshForkConfig { ... })
    } else {
        Self::Direct
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 主要调用链

```
会话初始化
├── codex.rs: Session::new()
│   └── tools::spec::ToolsConfig::new(&ToolsConfigParams { ... })
│       └── 根据 model_info, features, sandbox_policy 等决定工具配置
│
├── tools::router::ToolRouter::from_config(config, params)
│   └── tools::spec::build_specs_with_discoverable_tools(...)
│       ├── 创建 ToolRegistryBuilder
│       ├── 注册各类 ToolHandler
│       ├── push_tool_spec() 添加工具规范
│       └── builder.build() -> (Vec<ConfiguredToolSpec>, ToolRegistry)
│
└── 使用 router.model_visible_specs() 发送给模型
```

### 4.2 关键文件引用

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/client_common.rs` | `ToolSpec` 枚举定义（lines 159-312） |
| `codex-rs/core/src/tools/registry.rs` | `ToolRegistryBuilder`, `ToolRegistry` |
| `codex-rs/core/src/tools/router.rs` | `ToolRouter`, 调用路由 |
| `codex-rs/core/src/tools/context.rs` | `ToolInvocation`, `ToolPayload`, `ToolOutput` |
| `codex-rs/protocol/src/dynamic_tools.rs` | `DynamicToolSpec` 定义 |
| `codex-rs/core/src/tools/handlers/*.rs` | 各工具的具体处理器实现 |
| `codex-rs/core/templates/search_tool/*.md` | 工具搜索描述模板 |

### 4.3 代码行号索引

| 功能 | 行号范围 |
|------|---------|
| 输出 Schema 定义 | 67-206 |
| Shell 模式配置 | 208-254 |
| ToolsConfig 定义 | 256-464 |
| JsonSchema 定义 | 470-524 |
| 权限 Schema 构建 | 526-588 |
| 各工具 create_* 函数 | 643-2246 |
| MCP 工具转换 | 2284-2398 |
| Schema 清理 | 2399-2508 |
| 构建函数 | 2521-3035 |

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde`/`serde_json` | Schema 序列化/反序列化 |
| `rmcp::model::Tool` | MCP 工具模型 |
| `codex_protocol` | 协议类型定义 |
| `codex_protocol::dynamic_tools::DynamicToolSpec` | 动态工具 |
| `codex_protocol::openai_models::*` | OpenAI 模型相关类型 |
| `codex_protocol::config_types::*` | 配置类型 |

### 5.2 内部模块依赖

```rust
// 来自 client_common
use crate::client_common::tools::{
    FreeformTool, FreeformToolFormat, ResponsesApiTool, ToolSpec
};

// 来自 tools 子模块
use crate::tools::{
    code_mode::*,
    code_mode_description::*,
    discoverable::*,
    handlers::*,
    registry::*,
};

// 来自其他核心模块
use crate::{
    config::AgentRoleConfig,
    features::{Feature, Features},
    mcp_connection_manager::ToolInfo,
    models_manager::collaboration_mode_presets::CollaborationModesConfig,
    shell::{Shell, ShellType},
};
```

### 5.3 与 OpenAI API 的兼容性

- **Responses API**: 工具定义格式严格遵循 OpenAI Responses API 规范
- **Function Calling**: `ResponsesApiTool` 结构对应 OpenAI 的 function tool 定义
- **Web Search**: `ToolSpec::WebSearch` 对应 OpenAI 的 web_search 工具类型
- **Image Generation**: `ToolSpec::ImageGeneration` 对应 OpenAI 的 image_generation 工具类型

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Schema 兼容性问题

**风险**：MCP 服务器可能返回复杂的 JSON Schema（如 `anyOf`, `oneOf`, 嵌套引用），`sanitize_json_schema` 可能过度简化导致信息丢失。

**代码位置**：lines 2399-2508

**缓解措施**：
- 递归清理嵌套 schema
- 对无法推断的类型默认使用 `string`
- 保留原始 schema 的 `additionalProperties` 设置

#### 6.1.2 工具名称冲突

**风险**：MCP 工具名称可能包含 `/` 或 `__` 分隔符，与内部工具命名可能冲突。

**代码位置**：lines 124-130 in `registry.rs`

```rust
pub(crate) fn tool_handler_key(tool_name: &str, namespace: Option<&str>) -> String {
    if let Some(namespace) = namespace {
        format!("{namespace}:{tool_name}")
    } else {
        tool_name.to_string()
    }
}
```

#### 6.1.3 Windows 沙箱限制

**风险**：Windows 沙箱环境下 `UnifiedExec` 被禁用，可能导致功能回退。

**代码位置**：lines 297-308

```rust
fn unified_exec_allowed_in_environment(
    is_windows: bool,
    sandbox_policy: &SandboxPolicy,
    windows_sandbox_level: WindowsSandboxLevel,
) -> bool {
    !(is_windows
        && windows_sandbox_level != WindowsSandboxLevel::Disabled
        && !matches!(sandbox_policy, SandboxPolicy::DangerFullAccess | ...))
}
```

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| MCP 工具无 `properties` | 自动插入空对象（line 2353-2359） |
| MCP 工具无 `type` | 根据关键字推断或默认 `string` |
| 空动态工具列表 | 跳过处理（line 3012） |
| Code Mode 嵌套 | 递归构建，禁用 code_mode 自身防止无限递归（line 458-464） |
| Agent Jobs Worker | 根据 session_source 标签判断（line 382-387） |

### 6.3 改进建议

#### 6.3.1 Schema 验证增强

当前 `strict` 字段始终为 `false`，建议：
- 对已知安全的内部工具启用 `strict: true`
- 添加 Schema 验证确保 `required` 和 `properties` 一致性

#### 6.3.2 工具版本管理

当前工具描述是静态字符串，建议：
- 添加工具版本字段
- 支持工具描述的动态更新

#### 6.3.3 性能优化

`build_specs_with_discoverable_tools` 在每次会话初始化时执行，建议：
- 对静态工具配置添加缓存机制
- 延迟加载 MCP 工具描述

#### 6.3.4 错误处理改进

当前 MCP 工具转换失败仅记录错误日志（line 3005-3007）：
```rust
Err(e) => {
    tracing::error!("Failed to convert {name:?} MCP tool to OpenAI tool: {e:?}");
}
```

建议：
- 添加指标监控转换失败率
- 对关键工具失败提供降级方案

#### 6.3.5 文档生成

建议从 `ToolSpec` 定义自动生成：
- API 文档
- TypeScript 类型定义
- 工具使用示例

---

## 7. 测试覆盖

### 7.1 测试文件

- `codex-rs/core/src/tools/spec_tests.rs`：主要单元测试

### 7.2 关键测试场景

| 测试 | 说明 |
|------|------|
| `mcp_tool_to_openai_tool_inserts_empty_properties` | 验证无 properties 时的默认处理 |
| `mcp_tool_to_openai_tool_preserves_top_level_output_schema` | 验证输出 schema 保留 |
| `search_tool_deferred_tools_always_set_defer_loading_true` | 验证延迟加载标记 |
| `test_full_toolset_specs_for_gpt5_codex_unified_exec_web_search` | 完整工具集验证 |
| `unified_exec_is_blocked_for_windows_sandboxed_policies_only` | Windows 沙箱限制验证 |
| `js_repl_freeform_grammar_blocks_common_non_js_prefixes` | Freeform 工具语法验证 |

---

## 8. 总结

`spec.rs` 是 Codex 工具系统的**中央配置与规范定义中心**，其核心价值在于：

1. **统一抽象**：将内部工具、MCP 工具、动态工具统一为 `ToolSpec` 表示
2. **灵活配置**：通过 `ToolsConfig` 支持细粒度的工具启用控制
3. **协议兼容**：确保与 OpenAI Responses API 的兼容性
4. **扩展性**：支持 MCP 和动态工具的运行时扩展

理解本文件对于维护和扩展 Codex 的工具能力至关重要。
