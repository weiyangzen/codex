# 研究报告: codex-rs/protocol/src/prompts 目录

## 目录结构

```
codex-rs/protocol/src/prompts/
├── base_instructions/
│   └── default.md                    # 基础系统指令 (275行)
├── permissions/
│   ├── approval_policy/
│   │   ├── never.md                  # 永不批准策略提示
│   │   ├── on_failure.md             # 失败时批准策略提示
│   │   ├── on_request_rule.md        # 请求时批准策略提示 (含权限请求)
│   │   ├── on_request_rule_request_permission.md  # 请求权限工具说明
│   │   └── unless_trusted.md         # 非信任时批准策略提示
│   └── sandbox_mode/
│       ├── danger_full_access.md     # 危险完全访问模式
│       ├── read_only.md              # 只读沙箱模式
│       └── workspace_write.md        # 工作区写入模式
└── realtime/
    ├── realtime_end.md               # 实时对话结束提示
    └── realtime_start.md             # 实时对话开始提示
```

---

## 场景与职责

### 核心职责

`codex-rs/protocol/src/prompts` 目录是 Codex CLI 的**系统提示词模板库**，负责存储和管理所有注入到 LLM 对话中的系统级指令。这些提示词在编译期通过 `include_str!` 宏嵌入到二进制中，确保运行时无需依赖外部文件。

### 使用场景

1. **会话初始化**: 为新会话注入基础行为准则 (`base_instructions/default.md`)
2. **权限策略说明**: 根据用户配置的批准策略和沙箱模式，动态生成相应的开发者指令
3. **实时对话切换**: 在语音/文本交互模式切换时注入上下文转换提示
4. **安全边界定义**: 明确告知模型当前执行环境的安全限制和批准机制

---

## 功能点目的

### 1. 基础指令 (base_instructions/default.md)

**目的**: 定义 Codex CLI 的核心身份、行为准则和能力边界。

**关键内容**:
- **身份定义**: "You are a coding agent running in the Codex CLI, a terminal-based coding assistant."
- **AGENTS.md 规范**: 详细说明如何读取和遵循项目中的 `AGENTS.md` 文件
- **响应风格**: 简洁、直接、友好的默认人格
- **工具使用规范**: 
  - `apply_patch` 工具的正确使用方式
  - 禁止使用的工具名称（如 `applypatch`）
- **前置消息 (Preamble)**: 工具调用前的简要说明规范（8-12词）
- **计划工具**: `update_plan` 的使用场景和最佳实践
- **任务执行准则**: 自主解决问题、验证工作、适度主动
- **最终答案格式**: 章节标题、列表、代码块的规范使用

### 2. 批准策略提示 (permissions/approval_policy/)

| 文件 | 策略类型 | 用途 |
|------|----------|------|
| `never.md` | Never | 完全自动执行，永不请求用户批准 |
| `on_failure.md` | On-Failure | 沙箱内执行，失败时请求批准升级 |
| `on_request_rule.md` | On-Request | 模型主动请求批准，支持 `prefix_rule` |
| `on_request_rule_request_permission.md` | On-Request + 权限工具 | 扩展版，包含 `request_permissions` 工具说明 |
| `unless_trusted.md` | Unless-Trusted | 仅非信任命令需要批准 |

**关键机制**:
- **命令分段**: 在管道符、逻辑运算符处分割命令，独立评估每段
- **升级请求**: 通过 `sandbox_permissions: "require_escalated"` 请求沙箱外执行
- **权限请求工具**: 通过 `request_permissions` 工具请求额外网络/文件权限
- **前缀规则**: 用户可持久化批准的命令前缀模式（如 `["cargo", "test"]`）

### 3. 沙箱模式提示 (permissions/sandbox_mode/)

| 文件 | 模式 | 描述 |
|------|------|------|
| `danger_full_access.md` | danger-full-access | 无文件系统限制，网络访问可配置 |
| `read_only.md` | read-only | 仅允许读取文件 |
| `workspace_write.md` | workspace-write | 允许读取和写入工作区目录 |

**模板变量**: `{network_access}` 在运行时被替换为 `enabled` 或 `restricted`。

### 4. 实时对话提示 (realtime/)

| 文件 | 触发时机 | 内容 |
|------|----------|------|
| `realtime_start.md` | 语音对话开始时 | 告知模型作为后端执行器，响应会被中介处理，用户输入为转录文本 |
| `realtime_end.md` | 语音对话结束时 | 告知模型返回正常聊天模式，不再假设有识别错误 |

**标签包裹**: 提示词被 `<realtime_conversation>` 标签包裹注入。

---

## 具体技术实现

### 编译期嵌入

所有提示词文件通过 `include_str!` 宏在编译时嵌入到 `models.rs` 中：

```rust
// codex-rs/protocol/src/models.rs:450-492
pub const BASE_INSTRUCTIONS_DEFAULT: &str = include_str!("prompts/base_instructions/default.md");

const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str = include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str = include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str = include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str = include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");

const SANDBOX_MODE_DANGER_FULL_ACCESS: &str = include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str = include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = include_str!("prompts/permissions/sandbox_mode/read_only.md");

const REALTIME_START_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_start.md");
const REALTIME_END_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_end.md");
```

### Bazel 构建配置

```python
# codex-rs/protocol/BUILD.bazel
codex_rust_crate(
    name = "protocol",
    crate_name = "codex_protocol",
    compile_data = glob(["src/prompts/**/*.md"]),  # 确保 MD 文件被打包
)
```

### DeveloperInstructions 构建流程

```rust
// DeveloperInstructions::from_policy() 调用链:
// 1. 根据 SandboxPolicy 确定 sandbox_mode 和 writable_roots
// 2. 调用 DeveloperInstructions::from_permissions_with_network()
// 3. 拼接多个部分：
//    - <permissions instructions> 开始标签
//    - sandbox_text() - 沙箱模式说明
//    - DeveloperInstructions::from() - 批准策略说明
//    - from_writable_roots() - 可写根目录列表
//    - </permissions instructions> 结束标签
```

### 动态提示词生成

```rust
// 沙箱模式文本生成（带网络状态替换）
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

### Granular 策略组合

```rust
// granular_instructions() 函数逻辑:
// 1. 根据 GranularApprovalConfig 确定各分类的允许状态
// 2. 生成 "prompted_categories" 和 "rejected_categories" 列表
// 3. 条件性添加 shell 权限请求说明
// 4. 条件性添加 request_permissions 工具说明
// 5. 添加已批准的命令前缀列表
```

---

## 关键代码路径与文件引用

### 主要调用路径

```
codex-core/src/codex.rs
  └── spawn_internal()
      └── 创建 Session 时注入 DeveloperInstructions

codex-protocol/src/models.rs
  ├── DeveloperInstructions::from_policy()          [L590-623]
  ├── DeveloperInstructions::from_permissions_with_network() [L639-663]
  ├── DeveloperInstructions::sandbox_text()         [L686-695]
  ├── DeveloperInstructions::from()                 [L499-545]
  └── granular_instructions()                       [L711-781]

codex-protocol/src/protocol.rs
  ├── AskForApproval 枚举定义                      [L542-589]
  ├── GranularApprovalConfig 结构体                [L591-628]
  ├── SandboxPolicy 枚举定义                       [L719-784]
  └── 各类标签常量                                 [L82-98]

codex-core/src/custom_prompts.rs
  └── 用户自定义提示词加载（与系统提示词区分）
```

### 关键数据结构

```rust
// 开发者指令封装
pub struct DeveloperInstructions {
    text: String,
}

// 批准策略枚举
pub enum AskForApproval {
    Never,
    UnlessTrusted,
    OnFailure,
    OnRequest,
    Granular(GranularApprovalConfig),
}

// 细粒度批准配置
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,
    pub rules: bool,
    pub skill_approval: bool,
    pub request_permissions: bool,
    pub mcp_elicitations: bool,
}

// 沙箱策略
pub enum SandboxPolicy {
    DangerFullAccess,
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    WorkspaceWrite { writable_roots: Vec<AbsolutePathBuf>, ... },
    ExternalSandbox { network_access: NetworkAccess },
}
```

### 标签常量

```rust
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
pub const COLLABORATION_MODE_CLOSE_TAG: &str = "</collaboration_mode>";
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const REALTIME_CONVERSATION_CLOSE_TAG: &str = "</realtime_conversation>";
pub const USER_MESSAGE_BEGIN: &str = "## My request for Codex:";
```

---

## 依赖与外部交互

### 上游依赖（调用方）

| 调用方 | 用途 |
|--------|------|
| `codex-core/src/codex.rs` | 会话初始化时构建 DeveloperInstructions |
| `codex-core/src/context_manager/updates.rs` | 上下文更新时重新生成指令 |
| `codex-core/src/models_manager/collaboration_mode_presets.rs` | 协作模式的开发者指令注入 |
| `codex-app-server/src/codex_message_processor.rs` | 处理模型切换时的指令更新 |
| `codex-tui/src/chatwidget.rs` | TUI 中实时对话状态切换 |

### 下游依赖（被调用方）

| 被调用方 | 用途 |
|----------|------|
| `codex-execpolicy` | 获取已批准的命令前缀列表 |
| `codex-protocol/src/config_types.rs` | SandboxMode、CollaborationMode 类型定义 |

### 相关配置

- **config.toml**: `approval_policy`, `sandbox_mode`, `writable_roots`
- **环境变量**: `CODEX_HOME/prompts/` 用于用户自定义提示词（与系统提示词区分）

---

## 风险、边界与改进建议

### 已知风险

1. **提示词注入风险**
   - 用户自定义提示词（custom_prompts）与系统提示词分离，但自定义提示词内容仍可能被恶意构造
   - 建议: 对用户自定义提示词进行内容过滤或沙箱化

2. **模板变量未替换风险**
   - `{network_access}` 等模板变量如果在某些路径未被替换，会直接暴露给模型
   - 缓解: `sandbox_text()` 函数强制替换，不存在未处理路径

3. **提示词长度膨胀**
   - `format_allow_prefixes()` 限制最大 100 条前缀和 5000 字节，但 Granular 策略组合后仍可能过长
   - 缓解: 已实现截断逻辑和 `TRUNCATED_MARKER`

4. **Bazel 沙箱依赖**
   - `include_str!` 需要编译期文件可用，BUILD.bazel 中 `compile_data` 必须包含所有 MD 文件
   - 风险: 新增提示词文件但未更新 BUILD.bazel 会导致编译失败

### 边界情况

| 场景 | 行为 |
|------|------|
| 空 exec_policy | `approved_command_prefixes_text()` 返回 `None`，不显示前缀列表 |
| 100+ 批准前缀 | 截断至 100 条，添加 `[Some commands were truncated]` |
| 超长前缀内容 | 截断至 5000 字节，添加截断标记 |
| Granular 全 false | 显示 "自动拒绝" 列表，模型知晓无法请求任何批准 |
| 实时对话嵌套 | 每次切换都包裹新标签，可能累积（需验证是否有清理逻辑） |

### 改进建议

1. **国际化支持**
   - 当前所有提示词为英文，建议增加多语言模板支持
   - 实现: 按 `LANG` 环境变量加载对应语言模板

2. **提示词版本控制**
   - 建议增加提示词版本标识，便于 A/B 测试和回滚
   - 实现: 在 `DeveloperInstructions` 中添加 `version` 字段

3. **动态提示词热更新**
   - 当前编译期嵌入，无法热更新
   - 建议: 开发模式下支持从文件系统加载，生产模式嵌入

4. **提示词效果度量**
   - 建议增加提示词 token 计数和效果追踪
   - 实现: 在 `TokenUsage` 中区分 "system_instructions" 类别

5. **Granular 策略优化**
   - 当前分类较粗（5个布尔值），建议支持更细粒度的工具级控制
   - 实现: 将 `request_permissions` 细分为网络/文件/macOS 子类别

---

## 附录: 文件哈希与变更追踪

| 文件 | 相对路径 | 内容摘要 |
|------|----------|----------|
| default.md | `base_instructions/default.md` | 275行，核心系统提示 |
| never.md | `permissions/approval_policy/never.md` | 1行，简单拒绝 |
| on_failure.md | `permissions/approval_policy/on_failure.md` | 1行，失败时升级 |
| on_request_rule.md | `permissions/approval_policy/on_request_rule.md` | 56行，详细升级指南 |
| on_request_rule_request_permission.md | `permissions/approval_policy/on_request_rule_request_permission.md` | 33行，权限工具说明 |
| unless_trusted.md | `permissions/approval_policy/unless_trusted.md` | 1行，信任模式 |
| danger_full_access.md | `permissions/sandbox_mode/danger_full_access.md` | 1行，含 `{network_access}` 模板 |
| read_only.md | `permissions/sandbox_mode/read_only.md` | 1行，含 `{network_access}` 模板 |
| workspace_write.md | `permissions/sandbox_mode/workspace_write.md` | 1行，含 `{network_access}` 模板 |
| realtime_start.md | `realtime/realtime_start.md` | 9行，实时模式开始 |
| realtime_end.md | `realtime/realtime_end.md` | 3行，实时模式结束 |

---

*研究完成时间: 2026-03-21*
*研究者: Kimi Code CLI (k2p5)*
