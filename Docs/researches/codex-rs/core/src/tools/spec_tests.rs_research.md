# spec_tests.rs 深度研究文档

## 文件位置
- **目标文件**: `codex-rs/core/src/tools/spec_tests.rs`
- **关联文件**: 
  - `codex-rs/core/src/tools/spec.rs` (主实现)
  - `codex-rs/core/src/tools/router.rs` (工具路由)
  - `codex-rs/core/src/tools/registry.rs` (工具注册)
  - `codex-rs/core/src/tools/discoverable.rs` (可发现工具)
  - `codex-rs/core/src/client_common.rs` (ToolSpec 定义)
  - `codex-rs/core/src/features.rs` (功能标志)

---

## 1. 场景与职责

### 1.1 文件定位
`spec_tests.rs` 是 Codex 核心工具系统的**综合测试套件**，位于 `codex-core` crate 的 tools 模块中。它是 `spec.rs` 的配套测试文件（通过 `#[path = "spec_tests.rs"]` 关联）。

### 1.2 核心职责
该测试文件承担以下关键职责：

| 职责领域 | 说明 |
|---------|------|
| **工具规格生成验证** | 验证 `build_specs()` 和 `build_specs_with_discoverable_tools()` 生成的工具规格是否符合预期 |
| **MCP 工具转换测试** | 测试 MCP (Model Context Protocol) 工具到 OpenAI Responses API 格式的转换逻辑 |
| **功能标志集成测试** | 验证各种 `Feature` 标志（如 UnifiedExec、Collab、JsRepl 等）对工具集的影响 |
| **模型特定工具集验证** | 针对不同模型（gpt-5-codex、o3 等）验证默认工具集的正确性 |
| **沙盒策略兼容性** | 测试 Windows Sandbox、权限系统等与工具选择的交互 |
| **搜索工具描述生成** | 验证 tool_search 工具描述的动态生成逻辑 |

### 1.3 测试覆盖范围

```
总测试用例数: ~80+ 个测试函数
├── MCP 工具转换测试 (mcp_tool_to_openai_tool_*)
├── 延迟加载工具测试 (deferred_*)
├── 功能标志测试 (test_build_specs_*)
├── 模型默认工具集测试 (test_gpt_*_defaults)
├── WebSearch 配置测试 (web_search_*)
├── 代码模式测试 (code_mode_*)
├── 权限工具测试 (request_permissions_*)
└── 边界情况测试 (test_mcp_tool_*)
```

---

## 2. 功能点目的

### 2.1 主要测试类别

#### 2.1.1 MCP 工具转换验证
```rust
// 测试 MCP 工具 schema 转换时自动插入空 properties
fn mcp_tool_to_openai_tool_inserts_empty_properties()

// 验证 output_schema 的保留和包装
fn mcp_tool_to_openai_tool_preserves_top_level_output_schema()

// 测试 enum 类型 output_schema 的处理
fn mcp_tool_to_openai_tool_preserves_output_schema_without_inferred_type()
```

**目的**: 确保外部 MCP 服务器的工具定义能正确转换为 OpenAI Responses API 兼容格式，包括：
- 自动补全缺失的 `properties` 字段
- 保留结构化输出 schema
- 正确处理枚举类型

#### 2.1.2 功能标志与工具集组合
```rust
fn test_build_specs_collab_tools_enabled()           // Collab 功能
fn test_build_specs_enable_fanout_enables_agent_jobs_and_collab_tools()  // SpawnCsv
fn test_build_specs_artifact_tool_enabled()          // Artifact 功能
fn js_repl_requires_feature_flag()                   // JsRepl 功能
fn request_permissions_requires_feature_flag()       // RequestPermissionsTool
```

**目的**: 验证功能标志系统正确控制工具的可见性，确保：
- 功能启用时才暴露对应工具
- 功能依赖关系正确处理（如 SpawnCsv 自动启用 Collab）
- 子代理与主代理工具集差异（agent_jobs_worker_tools）

#### 2.1.3 模型特定默认工具集
```rust
fn test_build_specs_gpt5_codex_default()
fn test_build_specs_gpt51_codex_unified_exec_web_search()
fn test_gpt_5_defaults()
fn test_gpt_5_1_defaults()
fn test_o3_defaults()
```

**目的**: 确保不同模型预设获得正确的默认工具集，包括：
- gpt-5 系列使用 `shell` 或 `shell_command`
- gpt-5-codex 系列使用 `shell_command` 或 `exec_command/write_stdin` (UnifiedExec)
- o3 等模型使用 `shell_command`

#### 2.1.4 搜索工具描述生成
```rust
fn search_tool_description_lists_each_codex_apps_connector_once()
fn search_tool_description_handles_no_enabled_apps()
fn search_tool_description_falls_back_to_connector_name_without_description()
fn search_tool_registers_namespaced_app_tool_aliases()
```

**目的**: 验证 `tool_search` 工具的描述模板正确渲染，包括：
- 连接器列表去重
- 空状态处理（"None currently enabled"）
- 回退到连接器名称（无描述时）

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 ToolSpec 枚举
```rust
// 定义于 client_common.rs
pub(crate) enum ToolSpec {
    #[serde(rename = "function")]
    Function(ResponsesApiTool),
    #[serde(rename = "tool_search")]
    ToolSearch { execution: String, description: String, parameters: JsonSchema },
    #[serde(rename = "local_shell")]
    LocalShell {},
    #[serde(rename = "image_generation")]
    ImageGeneration { output_format: String },
    #[serde(rename = "web_search")]
    WebSearch { external_web_access: Option<bool>, ... },
    #[serde(rename = "custom")]
    Freeform(FreeformTool),
}
```

#### 3.1.2 ToolsConfig 配置结构
```rust
pub(crate) struct ToolsConfig {
    pub shell_type: ConfigShellToolType,           // 壳工具类型
    pub unified_exec_shell_mode: UnifiedExecShellMode,
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    pub web_search_mode: Option<WebSearchMode>,
    pub search_tool: bool,                         // 是否启用搜索
    pub collab_tools: bool,                        // 协作工具
    pub agent_jobs_tools: bool,                    // Agent 作业工具
    pub agent_jobs_worker_tools: bool,             // 工作器专用工具
    pub experimental_supported_tools: Vec<String>, // 实验性工具白名单
    // ... 更多字段
}
```

#### 3.1.3 测试辅助结构
```rust
// 测试用工具名称提取
fn tool_name(tool: &ToolSpec) -> &str

// 工具存在性断言
fn assert_contains_tool_names(tools: &[ConfiguredToolSpec], expected: &[&str])
fn assert_lacks_tool_name(tools: &[ConfiguredToolSpec], absent: &str)

// 工具查找
fn find_tool<'a>(tools: &'a [ConfiguredToolSpec], name: &str) -> &'a ConfiguredToolSpec

// Schema 描述剥离（用于比较时忽略描述差异）
fn strip_descriptions_tool(spec: &mut ToolSpec)
```

### 3.2 关键流程

#### 3.2.1 工具规格构建流程
```
ToolsConfigParams (输入配置)
    ↓
ToolsConfig::new() (创建配置)
    ↓
build_specs() / build_specs_with_discoverable_tools() (构建规格)
    ↓
ToolRegistryBuilder (收集规格和处理器)
    ↓
.build() → (Vec<ConfiguredToolSpec>, ToolRegistry)
```

#### 3.2.2 MCP 工具转换流程
```rust
pub(crate) fn mcp_tool_to_openai_tool(
    fully_qualified_name: String,
    tool: rmcp::model::Tool,
) -> Result<ResponsesApiTool, serde_json::Error> {
    // 1. 提取 input/output schema
    // 2. 确保 properties 字段存在（OpenAI 要求）
    // 3. sanitize_json_schema() - 清理和规范化 schema
    // 4. 包装 output_schema 到标准格式
    // 5. 返回 ResponsesApiTool
}
```

#### 3.2.3 JSON Schema 清理逻辑
```rust
fn sanitize_json_schema(value: &mut JsonValue) {
    // - 推断缺失的 type 字段（从 properties/items/enum 等推断）
    // - 处理 anyOf/oneOf/allOf - 取第一个支持的类型
    // - 确保 array 类型有 items
    // - 确保 object 类型有 properties
    // - 将 integer 归一化为 number
}
```

### 3.3 测试模式

#### 3.3.1 标准测试模板
```rust
#[test]
fn test_build_specs_some_feature() {
    let config = test_config();
    let model_info = ModelsManager::construct_model_info_offline_for_tests("gpt-5-codex", &config);
    let mut features = Features::with_defaults();
    features.enable(Feature::SomeFeature);
    
    let tools_config = ToolsConfig::new(&ToolsConfigParams {
        model_info: &model_info,
        available_models: &Vec::new(),
        features: &features,
        web_search_mode: Some(WebSearchMode::Cached),
        session_source: SessionSource::Cli,
        sandbox_policy: &SandboxPolicy::DangerFullAccess,
        windows_sandbox_level: WindowsSandboxLevel::Disabled,
    });
    
    let (tools, _) = build_specs(&tools_config, None, None, &[]).build();
    
    // 断言验证
    assert_contains_tool_names(&tools, &["expected_tool"]);
}
```

#### 3.3.2 模型工具集验证模式
```rust
fn assert_model_tools(
    model_slug: &str,
    features: &Features,
    web_search_mode: Option<WebSearchMode>,
    expected_tools: &[&str],
) {
    // 构建 ToolsConfig
    // 创建 ToolRouter
    // 比较实际工具名与预期
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
spec_tests.rs 测试函数
    ├──→ spec.rs
    │       ├──→ ToolsConfig::new()           [行 310-418]
    │       ├──→ build_specs()                [行 2510-2519]
    │       ├──→ build_specs_with_discoverable_tools() [行 2521-3035]
    │       ├──→ mcp_tool_to_openai_tool()    [行 2284-2298]
    │       ├──→ sanitize_json_schema()       [行 2399-2508]
    │       └──→ create_*_tool() 系列函数      [行 643-2246]
    ├──→ router.rs
    │       └──→ ToolRouter::from_config()    [行 51-89]
    ├──→ registry.rs
    │       ├──→ ToolRegistryBuilder::new()   [行 336-341]
    │       ├──→ ToolRegistryBuilder::push_spec() [行 343-354]
    │       └──→ ToolRegistryBuilder::build() [行 389-392]
    └──→ client_common.rs
            └──→ ToolSpec 定义                [行 173-218]
```

### 4.2 关键文件引用

| 文件 | 作用 |
|-----|------|
| `codex-rs/core/src/tools/spec.rs` | 工具规格生成主实现，约 3000 行 |
| `codex-rs/core/src/tools/router.rs` | 工具路由，连接规格与执行器 |
| `codex-rs/core/src/tools/registry.rs` | 工具注册表，管理处理器映射 |
| `codex-rs/core/src/tools/discoverable.rs` | 可发现工具（连接器/插件）定义 |
| `codex-rs/core/src/tools/handlers/*.rs` | 各工具的具体处理器实现 |
| `codex-rs/core/src/client_common.rs` | ToolSpec 和相关类型定义 |
| `codex-rs/core/src/features.rs` | Feature 枚举和功能标志系统 |
| `codex-rs/protocol/src/openai_models.rs` | ConfigShellToolType、ModelInfo 等 |

### 4.3 模板文件
```
codex-rs/core/src/templates/search_tool/tool_description.md
├── 用于 tool_search 工具描述模板
└── 占位符 {{app_descriptions}} 被动态替换
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
// 核心内部模块依赖
use crate::client_common::tools::{FreeformTool, ToolSpec, ResponsesApiTool};
use crate::config::test_config;
use crate::models_manager::manager::ModelsManager;
use crate::tools::ToolRouter;
use crate::tools::registry::{ConfiguredToolSpec, ToolRegistryBuilder};
use crate::tools::spec::{ToolsConfig, ToolsConfigParams, build_specs, ...};
use crate::features::{Feature, Features};
use crate::shell::{Shell, ShellType};
```

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `rmcp::model::Tool` | MCP 工具模型定义 |
| `codex_protocol::openai_models::*` | ModelInfo、ConfigShellToolType 等 |
| `codex_protocol::protocol::*` | SandboxPolicy、SessionSource |
| `codex_app_server_protocol::AppInfo` | 连接器信息 |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 测试断言美化 |
| `tempfile` | 临时目录创建 |

### 5.3 协议交互

#### 5.3.1 OpenAI Responses API 格式
测试验证生成的工具规格符合 OpenAI Responses API 要求：
```json
{
  "type": "function",
  "name": "tool_name",
  "description": "...",
  "strict": false,
  "parameters": {
    "type": "object",
    "properties": {...},
    "required": [...]
  }
}
```

#### 5.3.2 MCP 协议交互
- 接收 `rmcp::model::Tool` 格式
- 转换为内部 `ResponsesApiTool` 格式
- 处理 schema 差异（如 properties 可选性）

---

## 6. 风险、边界与改进建议

### 6.1 已知风险点

#### 6.1.1 Schema 兼容性风险
```rust
// sanitize_json_schema 中的类型推断可能过度简化
// 例如 anyOf 被简化为第一个类型，可能丢失语义
"anyOf": [{"type": "string"}, {"type": "number"}] → "type": "string"
```
**风险**: 复杂 JSON Schema 可能无法准确表示。

#### 6.1.2 功能标志组合爆炸
测试覆盖了主要组合，但功能标志之间存在复杂交互：
- `CodeMode` + `CodeModeOnly`
- `UnifiedExec` + `ShellZshFork`
- `SpawnCsv` + `Collab`

**风险**: 新功能标志可能引入未预期的交互。

#### 6.1.3 平台特定行为
```rust
// Windows 与 Unix 在 shell 工具选择上的差异
let expected_shell_type = if cfg!(target_os = "windows") {
    ConfigShellToolType::ShellCommand
} else {
    ConfigShellToolType::UnifiedExec
};
```
**风险**: 跨平台行为差异可能导致测试在特定平台失败。

### 6.2 边界情况

#### 6.2.1 已处理的边界
| 边界情况 | 处理方式 |
|---------|---------|
| MCP 工具无 properties | 自动插入空对象 `{}` |
| MCP 工具无 type | 从 properties/items/enum 推断，默认 string |
| Array 无 items | 默认 `{"type": "string"}` |
| 空 app_tools | 显示 "None currently enabled" |
| 重复工具名 | 断言检测，防止重复注册 |

#### 6.2.2 潜在未覆盖边界
- 极深层嵌套的 JSON Schema
- 包含 `$ref` 的 schema（当前未处理）
- 非常大的 MCP 工具集合（性能影响）

### 6.3 改进建议

#### 6.3.1 测试组织优化
```rust
// 建议：使用模块组织相关测试
mod mcp_conversion_tests { ... }
mod feature_flag_tests { ... }
mod model_defaults_tests { ... }
```

#### 6.3.2 参数化测试
当前大量重复的测试配置可提取为宏或参数化测试：
```rust
// 建议引入 test-case 或类似宏
#[test_case("gpt-5-codex", vec!["shell_command", "web_search"]; "gpt5 codex")]
#[test_case("o3", vec!["shell_command", "update_plan"]; "o3")]
fn test_model_defaults(model: &str, expected_tools: Vec<&str>) { ... }
```

#### 6.3.3 Schema 验证增强
```rust
// 建议：添加与 OpenAI API 的 schema 兼容性验证
fn validate_openai_compatibility(schema: &JsonSchema) -> Result<(), Vec<String>> {
    // 验证 strict 模式要求
    // 验证参数命名规范
    // 验证描述长度限制
}
```

#### 6.3.4 文档化测试用例意图
部分测试缺乏注释说明其验证的具体场景，建议添加：
```rust
/// 验证：当 ExecPermissionApprovals 功能启用时，
/// shell 工具应包含 additional_permissions 参数
#[test]
fn shell_tool_with_request_permission_includes_additional_permissions() { ... }
```

### 6.4 维护注意事项

1. **模型更新**: 新增模型时需要添加对应的默认工具集测试
2. **功能标志变更**: 新增/修改 Feature 枚举时需更新相关测试
3. **MCP 协议变更**: rmcp crate 升级时需验证 schema 转换兼容性
4. **模板变更**: 修改 `tool_description.md` 模板时需同步更新描述生成测试

---

## 7. 总结

`spec_tests.rs` 是 Codex 工具系统的**关键质量保障文件**，通过 80+ 个测试用例覆盖了：

1. **MCP 生态集成** - 外部工具的无缝接入
2. **功能标志系统** - 细粒度的工具可见性控制
3. **多模型支持** - 不同模型的差异化工具集
4. **平台兼容性** - Windows/Unix 的差异处理
5. **安全策略** - 沙盒与权限系统的工具选择影响

该测试文件与 `spec.rs` 紧密耦合，任何对工具规格生成逻辑的修改都应同步更新或验证相关测试。测试采用**白盒测试**风格，深入验证内部状态而非仅外部行为，这提供了高置信度但也增加了维护成本。
