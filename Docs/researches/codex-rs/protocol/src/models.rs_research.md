# Research Document: `codex-rs/protocol/src/models.rs`

## 1. 场景与职责

### 1.1 文件定位

`models.rs` 是 Codex 协议层（`codex-protocol` crate）的核心数据模型定义文件，位于 `codex-rs/protocol/src/models.rs`。该文件在整个 Codex CLI 架构中承担**协议数据模型中枢**的角色，负责定义：

- **OpenAI Responses API 兼容的数据结构**：与 OpenAI API 交互的请求/响应模型
- **沙箱权限模型**：细粒度的文件系统、网络、macOS 系统权限控制
- **开发者指令生成**：基于沙箱策略和审批策略动态生成系统提示词
- **图像处理**：本地图像加载、编码、转换为模型可消费的格式
- **工具调用载荷**：Shell 命令、MCP 工具、自定义工具的参数结构

### 1.2 架构位置

```
codex-cli (TUI/CLI 入口)
    ↓
codex-core (核心业务逻辑)
    ↓
codex-protocol (协议层) ← models.rs 位于此处
    ↓
codex-api (OpenAI API 客户端)
    ↓
OpenAI Responses API
```

### 1.3 核心职责

| 职责领域 | 说明 |
|---------|------|
| API 数据模型 | 定义与 OpenAI Responses API 交互的所有数据结构 |
| 权限系统 | 沙箱权限枚举、权限配置、权限验证 |
| 指令生成 | 根据配置动态生成 developer instructions 系统提示 |
| 图像处理 | 本地图像读取、base64 编码、data URL 生成 |
| 工具调用 | Shell 工具、MCP 工具、自定义工具的参数定义 |
| 序列化/反序列化 | serde 支持，ts-rs 生成 TypeScript 类型，schemars 生成 JSON Schema |

---

## 2. 功能点目的

### 2.1 沙箱权限系统 (SandboxPermissions)

**目的**：控制模型执行 shell 命令时的沙箱行为，支持三种模式：

```rust
pub enum SandboxPermissions {
    UseDefault,                    // 使用当前 turn 的默认沙箱策略
    RequireEscalated,             // 请求无沙箱执行（需要用户批准）
    WithAdditionalPermissions,    // 在沙箱内临时扩展权限
}
```

**使用场景**：
- 当模型需要执行超出当前沙箱限制的操作时（如访问受限目录、网络请求）
- 通过 `shell` 或 `container.exec` 工具的 `sandbox_permissions` 参数传递

### 2.2 权限配置 (PermissionProfile)

**目的**：定义细粒度的权限配置，包括：

```rust
pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}
```

**macOS 特有扩展**：
- `MacOsPreferencesPermission`: 访问 macOS 偏好设置 (None/ReadOnly/ReadWrite)
- `MacOsContactsPermission`: 访问通讯录权限
- `MacOsAutomationPermission`: 自动化权限（支持 bundle ID 白名单）

### 2.3 开发者指令生成 (DeveloperInstructions)

**目的**：根据沙箱策略和审批策略动态生成系统提示词，告知模型当前环境的限制和能力。

**关键方法**：
- `DeveloperInstructions::from_policy()`: 从 SandboxPolicy 生成指令
- `DeveloperInstructions::from_collaboration_mode()`: 从协作模式生成指令
- `DeveloperInstructions::realtime_start_message()`: 实时会话启动指令

**嵌入式提示模板**：
- `BASE_INSTRUCTIONS_DEFAULT`: 基础系统提示（275 行 Markdown）
- `APPROVAL_POLICY_*`: 各种审批策略的说明文本
- `SANDBOX_MODE_*`: 沙箱模式说明文本

### 2.4 Responses API 数据模型

**ResponseItem**: 定义从 OpenAI API 接收的所有可能的响应项类型：

```rust
pub enum ResponseItem {
    Message { role, content, phase, ... },           // 普通文本消息
    Reasoning { summary, content, ... },            // 推理内容
    LocalShellCall { status, action, ... },         // 本地 shell 调用
    FunctionCall { name, arguments, call_id, ... }, // 函数调用
    FunctionCallOutput { call_id, output, ... },    // 函数调用结果
    WebSearchCall { status, action, ... },          // 网页搜索调用
    ImageGenerationCall { status, result, ... },    // 图像生成调用
    GhostSnapshot { ghost_commit },                 // Git 快照
    Compaction { encrypted_content },               // 上下文压缩
    ...
}
```

**ResponseInputItem**: 发送到 API 的输入项：
- `Message`: 用户消息
- `FunctionCallOutput`: 工具执行结果
- `McpToolCallOutput`: MCP 工具调用结果
- `CustomToolCallOutput`: 自定义工具调用结果

### 2.5 图像处理

**目的**：支持用户上传本地图像，转换为模型可消费的 base64 data URL。

**关键函数**：
- `local_image_content_items_with_label_number()`: 读取本地图像并包装为 ContentItem
- `load_for_prompt_bytes()`: 图像加载和格式转换（依赖 `codex_utils_image`）
- 图像标签包装：`<image name="[Image #N]">...</image>`

**错误处理**：
- 文件读取失败 → 生成文本占位符
- 不支持的格式（如 SVG）→ 生成错误提示
- 图像解码失败 → 生成无效图像提示

### 2.6 工具调用参数

**ShellToolCallParams**: `shell` 和 `container.exec` 工具的参数：

```rust
pub struct ShellToolCallParams {
    pub command: Vec<String>,
    pub workdir: Option<String>,
    pub timeout_ms: Option<u64>,
    pub sandbox_permissions: Option<SandboxPermissions>,
    pub prefix_rule: Option<Vec<String>>,        // 建议的命令前缀规则
    pub additional_permissions: Option<PermissionProfile>,
    pub justification: Option<String>,           // 权限提升的理由
}
```

**ShellCommandToolCallParams**: `shell_command` 工具的参数（单字符串命令）。

---

## 3. 具体技术实现

### 3.1 序列化架构

所有核心类型都实现了以下 trait：

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
```

- **serde**: JSON 序列化/反序列化
- **schemars::JsonSchema**: 生成 JSON Schema 用于配置验证
- **ts_rs::TS**: 生成 TypeScript 类型定义（用于前端）

**特殊序列化处理**：

```rust
// FunctionCallOutputPayload 支持两种 wire 格式：
// 1. 纯文本字符串
// 2. 结构化内容项数组
impl Serialize for FunctionCallOutputPayload {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match &self.body {
            FunctionCallOutputBody::Text(content) => serializer.serialize_str(content),
            FunctionCallOutputBody::ContentItems(items) => items.serialize(serializer),
        }
    }
}
```

### 3.2 开发者指令生成流程

```rust
DeveloperInstructions::from_policy(
    sandbox_policy: &SandboxPolicy,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    cwd: &Path,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self
```

**流程**：
1. 确定网络访问状态（Enabled/Restricted）
2. 确定沙箱模式（DangerFullAccess/WorkspaceWrite/ReadOnly）
3. 获取可写根目录列表
4. 调用 `DeveloperInstructions::from_permissions_with_network()`
5. 拼接沙箱说明 + 审批策略说明 + 已批准命令前缀列表

**模板拼接结构**：
```
<permissions instructions>
{沙箱模式说明}
{审批策略说明}
{已批准命令前缀列表}
{可写根目录说明}
</permissions instructions>
```

### 3.3 图像处理流程

```rust
pub fn local_image_content_items_with_label_number(
    path: &std::path::Path,
    file_bytes: Vec<u8>,
    label_number: Option<usize>,
    mode: PromptImageMode,
) -> Vec<ContentItem>
```

**流程**：
1. 调用 `load_for_prompt_bytes()` 处理图像（可能涉及 resize、格式转换）
2. 成功：生成 `[Image #N]` 标签 + InputImage + 关闭标签
3. 失败：根据错误类型生成相应的文本占位符

### 3.4 MCP 内容转换

```rust
fn convert_mcp_content_to_items(
    contents: &[serde_json::Value],
) -> Option<Vec<FunctionCallOutputContentItem>>
```

**功能**：将 MCP (Model Context Protocol) 工具返回的内容转换为 Responses API 格式：
- `text` 类型 → `FunctionCallOutputContentItem::InputText`
- `image` 类型 → `FunctionCallOutputContentItem::InputImage`（自动构建 data URL）

### 3.5 命令前缀格式化

```rust
pub fn format_allow_prefixes(prefixes: Vec<Vec<String>>) -> Option<String>
```

**功能**：将 execpolicy 允许的命令前缀格式化为 Markdown 列表：
- 排序：先按长度，再按字母顺序
- 截断：最多显示 100 个前缀，最多 5000 字节
- 格式：`["git", "pull"]`

---

## 4. 关键代码路径与文件引用

### 4.1 核心类型定义位置

| 类型 | 行号 | 说明 |
|------|------|------|
| `SandboxPermissions` | 33-65 | 沙箱权限枚举 |
| `PermissionProfile` | 212-223 | 权限配置结构体 |
| `ResponseItem` | 295-448 | API 响应项枚举 |
| `ResponseInputItem` | 227-258 | API 输入项枚举 |
| `ContentItem` | 262-266 | 内容项枚举 |
| `DeveloperInstructions` | 469-696 | 开发者指令结构体 |
| `FunctionCallOutputPayload` | 1268-1507 | 工具调用输出载荷 |
| `ShellToolCallParams` | 1148-1168 | Shell 工具参数 |

### 4.2 嵌入式提示模板

| 常量 | 引用的文件 | 说明 |
|------|-----------|------|
| `BASE_INSTRUCTIONS_DEFAULT` | `prompts/base_instructions/default.md` | 基础系统提示 |
| `APPROVAL_POLICY_NEVER` | `prompts/permissions/approval_policy/never.md` | 从不审批策略 |
| `APPROVAL_POLICY_UNLESS_TRUSTED` | `prompts/permissions/approval_policy/unless_trusted.md` | 除非信任策略 |
| `APPROVAL_POLICY_ON_FAILURE` | `prompts/permissions/approval_policy/on_failure.md` | 失败时审批策略 |
| `APPROVAL_POLICY_ON_REQUEST_RULE` | `prompts/permissions/approval_policy/on_request_rule.md` | 请求时审批规则 |
| `SANDBOX_MODE_DANGER_FULL_ACCESS` | `prompts/permissions/sandbox_mode/danger_full_access.md` | 完全访问模式 |
| `SANDBOX_MODE_WORKSPACE_WRITE` | `prompts/permissions/sandbox_mode/workspace_write.md` | 工作区写入模式 |
| `SANDBOX_MODE_READ_ONLY` | `prompts/permissions/sandbox_mode/read_only.md` | 只读模式 |
| `REALTIME_START_INSTRUCTIONS` | `prompts/realtime/realtime_start.md` | 实时会话启动 |
| `REALTIME_END_INSTRUCTIONS` | `prompts/realtime/realtime_end.md` | 实时会话结束 |

### 4.3 调用方分析

**protocol 内部调用**：
- `protocol.rs`: 使用 `BaseInstructions`, `ContentItem`, `ResponseItem`, `WebSearchAction`
- `items.rs`: 使用 `MessagePhase`, `WebSearchAction`
- `approvals.rs`: 使用 `MacOsSeatbeltProfileExtensions`, `PermissionProfile`
- `request_permissions.rs`: 使用 `FileSystemPermissions`, `NetworkPermissions`, `PermissionProfile`

**外部 crate 调用**（通过 `codex_protocol::models`）：
- `codex-api`: 使用 `ResponseItem` 处理 SSE 响应
- `codex-core`: 广泛使用所有模型类型
- `app-server-protocol`: 类型转换和 API 兼容
- `tui_app_server`: UI 渲染相关类型
- `hooks`: 使用 `SandboxPermissions`
- `shell-escalation`: 使用 `PermissionProfile`, `NetworkPermissions`

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```rust
// 序列化/反序列化
use serde::Deserialize;
use serde::Deserializer;
use serde::Serialize;
use serde::ser::Serializer;

// JSON Schema 生成
use schemars::JsonSchema;

// TypeScript 类型生成
use ts_rs::TS;

// 图像处理
use codex_utils_image::PromptImageMode;
use codex_utils_image::load_for_prompt_bytes;
use codex_utils_image::error::ImageProcessingError;

// 路径处理
use codex_utils_absolute_path::AbsolutePathBuf;

// 执行策略
use codex_execpolicy::Policy;

// Git 集成
use codex_git::GhostCommit;
```

### 5.2 依赖关系图

```
models.rs
├── serde (序列化)
├── schemars (JSON Schema)
├── ts_rs (TypeScript 类型)
├── codex_utils_image (图像处理)
├── codex_utils_absolute_path (绝对路径)
├── codex_execpolicy (执行策略)
├── codex_git (Git 集成)
└── protocol 内部模块
    ├── config_types (配置类型)
    ├── protocol (核心协议)
    ├── user_input (用户输入)
    └── mcp (MCP 协议)
```

### 5.3 跨 crate 类型共享

通过 `ts-rs` 和 `schemars` 实现类型共享：
- **TypeScript**: 生成 `.d.ts` 文件供前端使用
- **JSON Schema**: 用于配置验证和文档生成

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 图像处理安全风险
- **风险**: `local_image_content_items_with_label_number` 读取任意路径的图像文件
- **缓解**: 依赖调用方（如 TUI）在传入前验证路径合法性
- **建议**: 考虑在协议层增加路径白名单验证

#### 6.1.2 序列化兼容性
- **风险**: `FunctionCallOutputPayload` 的自定义序列化逻辑与标准 serde 行为不同
- **缓解**: 大量单元测试覆盖（见测试部分）
- **潜在问题**: 如果 API 格式变更，需要同步更新序列化逻辑

#### 6.1.3 指令注入风险
- **风险**: `DeveloperInstructions` 拼接用户可控内容（如 writable_roots）到系统提示
- **缓解**: 使用 Markdown 代码块包装路径，避免提示注入
- **代码**: `format!("`{}`", r.root.to_string_lossy())`

### 6.2 边界情况

#### 6.2.1 权限枚举默认值
```rust
#[default]
ReadOnly,  // MacOsPreferencesPermission 的默认值是 ReadOnly（安全敏感）
```

**注意**: `MacOsPreferencesPermission` 默认是 `ReadOnly` 而非 `None`，这是有意为之的安全设计，以保持 CFPreferences 正常工作。

#### 6.2.2 命令前缀截断
```rust
const MAX_RENDERED_PREFIXES: usize = 100;
const MAX_ALLOW_PREFIX_TEXT_BYTES: usize = 5000;
```

当批准的命令前缀过多时，指令会被截断，可能导致模型不知道某些已批准的命令。

#### 6.2.3 图像大小限制
```rust
// UserInput 中的文本长度限制
pub const MAX_USER_INPUT_TEXT_CHARS: usize = 1 << 20; // 1MB
```

但图像处理没有明确的尺寸限制，依赖 `codex_utils_image` 的实现。

### 6.3 改进建议

#### 6.3.1 模块化拆分
当前 `models.rs` 约 2950 行，建议按功能拆分为：
- `models/permissions.rs`: 权限相关类型
- `models/instructions.rs`: 开发者指令生成
- `models/responses.rs`: API 响应模型
- `models/images.rs`: 图像处理
- `models/tools.rs`: 工具调用参数

#### 6.3.2 增强类型安全
- 将 `String` 类型的 ID 包装为 newtype（如 `CallId(String)`）
- 使用 `chrono::DateTime` 替代裸的 `i64` 时间戳

#### 6.3.3 文档改进
- 为复杂的序列化行为添加更多示例
- 为 `DeveloperInstructions` 的生成逻辑添加流程图文档

#### 6.3.4 测试覆盖
当前测试非常全面（约 85 个测试用例），但可补充：
- 图像处理的压力测试（大文件、恶意文件）
- 并发场景下的序列化测试

### 6.4 维护注意事项

1. **修改权限类型时**: 需要同步更新 `request_permissions.rs` 和 `approvals.rs`
2. **修改 DeveloperInstructions 时**: 需要检查 TUI 和 app-server 的提示渲染
3. **添加新的 ResponseItem 变体时**: 需要更新 `items.rs` 中的 `TurnItem` 映射
4. **修改序列化行为时**: 必须确保与 OpenAI API 的兼容性

---

## 7. 测试覆盖分析

文件包含约 85 个单元测试，覆盖：

| 测试类别 | 数量 | 关键测试 |
|---------|------|---------|
| 权限枚举 | 5 | `sandbox_permissions_helpers_match_documented_semantics` |
| MCP 内容转换 | 4 | `convert_mcp_content_to_items_preserves_data_urls` |
| 图像生成解析 | 2 | `response_item_parses_image_generation_call` |
| 权限配置 | 6 | `permission_profile_deserializes_macos_seatbelt_profile_extensions` |
| macOS 自动化权限 | 3 | `macos_automation_permission_deserializes_all_and_none` |
| 开发者指令 | 15 | `builds_permissions_with_network_access_override` |
| 命令前缀格式化 | 3 | `render_command_prefix_list_sorts_by_len_then_total_len_then_alphabetical` |
| 序列化/反序列化 | 8 | `serializes_success_as_plain_string`, `deserializes_array_payload_into_items` |
| WebSearch 动作 | 1 | `roundtrips_web_search_call_actions` |
| Shell 工具参数 | 1 | `deserialize_shell_tool_call_params` |
| 图像处理 | 6 | `mixed_remote_and_local_images_share_label_sequence` |
| 工具搜索 | 3 | `tool_search_call_roundtrips` |

---

## 8. 总结

`models.rs` 是 Codex 协议层的**核心数据模型文件**，承担以下关键职责：

1. **协议桥梁**: 定义与 OpenAI API 交互的所有数据结构
2. **权限系统**: 实现细粒度的沙箱权限控制
3. **指令生成**: 根据配置动态生成系统提示词
4. **图像处理**: 支持本地图像上传和处理
5. **类型安全**: 通过 serde/schemars/ts-rs 实现跨语言类型共享

该文件的设计体现了**安全优先**的原则（如默认只读权限、沙箱隔离），同时保持了**灵活性**（支持多种审批策略、权限组合）。代码质量高，测试覆盖全面，但文件规模较大，建议未来进行模块化拆分。
