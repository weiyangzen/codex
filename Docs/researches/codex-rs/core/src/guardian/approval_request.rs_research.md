# approval_request.rs 研究文档

## 场景与职责

`approval_request.rs` 是 Guardian 子代理系统的核心数据定义模块，负责定义所有需要 Guardian 审查的批准请求类型及其序列化/反序列化逻辑。该模块充当 Codex 核心系统与 Guardian 审查子代理之间的数据契约层，确保各类工具调用（Shell、ApplyPatch、NetworkAccess、McpToolCall 等）能够被统一地转换为 Guardian 可理解的评估格式。

**核心职责：**
1. 定义 `GuardianApprovalRequest` 枚举，涵盖所有需要 Guardian 审查的操作类型
2. 提供请求到 JSON 的序列化（用于 Guardian 提示词构建）
3. 提供评估动作值的生成（用于事件追踪和日志记录，会敏感数据脱敏）
4. 实现文本截断逻辑，确保提示词不会超出 Token 限制

## 功能点目的

### 1. GuardianApprovalRequest 枚举

定义了六种需要 Guardian 审查的操作类型：

| 变体 | 用途 | 关键字段 |
|------|------|----------|
| `Shell` | Shell 命令执行审查 | command, cwd, sandbox_permissions, justification |
| `ExecCommand` | 交互式命令执行审查 | command, cwd, tty |
| `Execve` (Unix only) | 底层 execve 调用审查 | program, argv, tool_name |
| `ApplyPatch` | 代码补丁应用审查 | files, change_count, patch |
| `NetworkAccess` | 网络访问审查 | target, host, protocol, port, turn_id |
| `McpToolCall` | MCP 工具调用审查 | server, tool_name, arguments, annotations |

**设计考量：**
- `turn_id` 字段仅在 `NetworkAccess` 中显式存在，因为网络访问需要关联到特定的 turn 上下文
- `ApplyPatch` 包含完整的 patch 内容，但评估时会脱敏处理
- `McpToolCall` 包含丰富的元数据（connector 信息、annotations）用于风险评估

### 2. GuardianMcpAnnotations 结构体

```rust
pub(crate) struct GuardianMcpAnnotations {
    pub(crate) destructive_hint: Option<bool>,
    pub(crate) open_world_hint: Option<bool>,
    pub(crate) read_only_hint: Option<bool>,
}
```

用于传递 MCP 工具的危险性提示，帮助 Guardian 做出更准确的风险评估。

### 3. 序列化函数

**`guardian_approval_request_to_json`**：将请求转换为完整的 JSON 表示，用于构建 Guardian 提示词中的 "Planned action JSON" 部分。

**`guardian_assessment_action_value`**：生成用于事件追踪的简化动作摘要，会移除敏感信息（如 ApplyPatch 的完整 patch 内容）。

**`format_guardian_action_pretty`**：生成格式化的、截断后的 JSON 字符串，用于提示词展示。

### 4. 文本截断逻辑

**`truncate_guardian_action_value`**：递归截断 JSON 值中的字符串字段，确保不超过 `GUARDIAN_MAX_ACTION_STRING_TOKENS`（默认 1000 tokens）。

**`guardian_truncate_text`**：智能文本截断，保留前缀和后缀，中间用 XML 标记替代。

## 具体技术实现

### 关键数据结构

```rust
// 命令批准动作（内部序列化结构）
struct CommandApprovalAction<'a> {
    tool: &'a str,
    command: &'a [String],
    cwd: &'a PathBuf,
    sandbox_permissions: crate::sandboxing::SandboxPermissions,
    additional_permissions: Option<&'a PermissionProfile>,
    justification: Option<&'a String>,
    tty: Option<bool>,
}

// MCP 工具调用批准动作
struct McpToolCallApprovalAction<'a> {
    tool: &'static str,
    server: &'a str,
    tool_name: &'a str,
    arguments: Option<&'a Value>,
    // ... 其他可选字段
}
```

### 关键流程

1. **请求创建流程**（以 Shell 为例）：
   ```
   ShellRuntime::start_approval_async
   └── 创建 GuardianApprovalRequest::Shell { id, command, cwd, ... }
       └── review_approval_request()
           └── guardian_approval_request_to_json() → JSON 提示词
   ```

2. **评估动作值生成流程**：
   ```
   run_guardian_review()
   └── guardian_assessment_action_value(&request)
       └── 生成脱敏的 action_summary 用于事件追踪
   ```

3. **文本截断算法**：
   - 计算可用字节预算：`approx_bytes_for_tokens(token_cap)`
   - 如果内容超出预算，计算省略的 token 数量
   - 生成标记：`<truncated omitted_approx_tokens="{count}" />`
   - 将可用预算平分给前缀和后缀
   - 使用 UTF-8 安全的方式分割字符串（通过 `char_indices`）

### 序列化细节

- 使用 `serde(skip_serializing_if = "Option::is_none")` 减少 JSON 体积
- Command 使用 `shlex_join` 生成人类可读的命令字符串
- 路径使用标准 PathBuf 序列化

## 关键代码路径与文件引用

### 主要调用方

| 文件 | 函数 | 用途 |
|------|------|------|
| `tools/runtimes/shell.rs` | `start_approval_async` | Shell 命令 Guardian 审查 |
| `tools/runtimes/apply_patch.rs` | `build_guardian_review_request` | ApplyPatch Guardian 审查 |
| `tools/network_approval.rs` | `handle_inline_policy_request` | 网络访问 Guardian 审查 |
| `mcp_tool_call.rs` | `start_approval_async` | MCP 工具调用 Guardian 审查 |
| `guardian/review.rs` | `run_guardian_review` | 核心审查流程 |

### 常量定义

在 `guardian/mod.rs` 中定义：
- `GUARDIAN_MAX_ACTION_STRING_TOKENS: usize = 1_000`
- `TRUNCATION_TAG: &str = "truncated"`

### 测试覆盖

`guardian/tests.rs` 中的相关测试：
- `format_guardian_action_pretty_truncates_large_string_fields`：验证大字段截断
- `guardian_approval_request_to_json_renders_mcp_tool_call_shape`：验证 MCP 序列化
- `guardian_assessment_action_value_redacts_apply_patch_patch_text`：验证脱敏逻辑
- `guardian_request_turn_id_prefers_network_access_owner_turn`：验证 turn_id 解析

## 依赖与外部交互

### 外部依赖

| Crate/模块 | 用途 |
|------------|------|
| `codex_protocol::approvals::NetworkApprovalProtocol` | 网络协议类型定义 |
| `codex_protocol::models::PermissionProfile` | 权限配置 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径类型 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 处理 |
| `codex_shell_command::parse_command::shlex_join` | 命令字符串化 |

### 内部依赖

- `super::prompt::guardian_truncate_text`：文本截断实现
- `super::GUARDIAN_MAX_ACTION_STRING_TOKENS`：截断限制常量
- `crate::sandboxing::SandboxPermissions`：沙箱权限类型

## 风险、边界与改进建议

### 已知风险

1. **敏感数据泄露风险**：
   - `ApplyPatch` 请求包含完整 patch 内容，虽然 `format_guardian_action_pretty` 会截断，但在某些路径下仍可能泄露到日志
   - `Shell` 命令可能包含敏感参数（如密码、token）

2. **Token 预算溢出**：
   - 虽然实现了截断，但极长的命令列表或大量文件路径仍可能超出预算
   - 当前实现是最佳努力（best-effort），而非严格保证

3. **Unix 平台差异**：
   - `Execve` 变体仅在 Unix 平台可用，可能导致跨平台行为不一致

### 边界情况

1. **空内容处理**：
   - `guardian_truncate_text` 对空字符串直接返回空
   - 如果标记长度超过预算，直接返回标记

2. **UTF-8 边界**：
   - `split_guardian_truncation_bounds` 使用 `char_indices` 确保安全的 UTF-8 分割
   - 但如果前缀/后缀预算落在多字节字符中间，可能导致字符被截断

3. **非常大的 JSON**：
   - `truncate_guardian_action_value` 递归处理，对于嵌套极深的 JSON 可能导致栈溢出（虽然概率极低）

### 改进建议

1. **敏感数据检测**：
   - 添加启发式规则检测命令中的敏感参数（如 `--password`、`--token` 后的值）
   - 对 `ApplyPatch` 的 patch 内容进行更智能的脱敏（如只保留文件路径和变更统计）

2. **Token 预算优化**：
   - 考虑使用更精确的 token 计数（如 tiktoken）替代基于字节的估算
   - 为不同类型的字段设置不同的预算权重

3. **可观测性增强**：
   - 添加 metrics 记录截断发生的频率和截断量
   - 在 debug 日志中记录原始内容长度和截断后长度

4. **测试覆盖**：
   - 添加针对非 UTF-8 内容的测试
   - 添加针对极大 JSON（如包含数千个文件路径的 ApplyPatch）的测试
   - 添加针对边界 token 预算的测试

5. **代码结构**：
   - 考虑将 `GuardianApprovalRequest` 的构建逻辑提取到专门的 builder 模块，减少重复代码
   - 考虑使用宏减少变体间相似的序列化代码
