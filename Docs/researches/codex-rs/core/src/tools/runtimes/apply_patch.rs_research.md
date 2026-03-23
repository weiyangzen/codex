# apply_patch.rs 深入研究

## 场景与职责

`apply_patch.rs` 实现了 Codex 的 **Apply Patch 运行时**，负责在沙箱环境中执行经过验证的文件补丁操作。它是 Codex 文件编辑功能的核心执行层，处理从 AI 模型接收到的文件修改指令（添加、删除、更新文件）的实际执行。

**核心职责：**
1. **补丁执行**：在沙箱环境中运行 `codex --codex-run-as-apply-patch` 命令应用补丁
2. **审批集成**：与 Guardian 审批系统交互，确保敏感操作获得用户授权
3. **权限管理**：处理文件系统权限、沙箱权限和额外权限配置
4. **执行编排**：通过 `ToolOrchestrator` 管理审批→沙箱选择→执行→重试的完整流程

**架构定位：**
- 位于工具运行时层（`tools/runtimes/`）
- 被 `ApplyPatchHandler`（`handlers/apply_patch.rs`）调用
- 依赖 `ToolOrchestrator` 进行审批和沙箱管理
- 最终调用 `codex_apply_patch` crate 执行实际补丁操作

---

## 功能点目的

### 1. ApplyPatchRequest - 请求数据结构

```rust
pub struct ApplyPatchRequest {
    pub action: ApplyPatchAction,                    // 补丁操作详情
    pub file_paths: Vec<AbsolutePathBuf>,           // 受影响的文件路径
    pub changes: HashMap<PathBuf, FileChange>,      // 文件变更映射
    pub exec_approval_requirement: ExecApprovalRequirement,  // 执行审批要求
    pub sandbox_permissions: SandboxPermissions,    // 沙箱权限配置
    pub additional_permissions: Option<PermissionProfile>,   // 额外权限
    pub permissions_preapproved: bool,              // 权限是否已预批准
    pub timeout_ms: Option<u64>,                    // 超时配置
    pub codex_exe: Option<PathBuf>,                 // Codex 可执行文件路径
}
```

**设计目的：**
- 封装一次补丁操作的所有上下文信息
- 支持多文件批量修改（`file_paths` 和 `changes` 的关联）
- 携带完整的权限和审批配置，供审批流程使用

### 2. ApplyPatchRuntime - 运行时实现

实现了三个核心 trait：

#### `Sandboxable` - 沙箱偏好配置
```rust
impl Sandboxable for ApplyPatchRuntime {
    fn sandbox_preference(&self) -> SandboxablePreference { SandboxablePreference::Auto }
    fn escalate_on_failure(&self) -> bool { true }
}
```
- **Auto 模式**：根据策略自动选择是否使用沙箱
- **escalate_on_failure**：沙箱执行失败时允许升级到无沙箱执行

#### `Approvable<ApplyPatchRequest>` - 审批逻辑

**审批键生成**（`approval_keys`）：
- 使用 `file_paths` 作为审批键，实现**按文件路径的细粒度审批**
- 支持 "Allow for session" 语义：如果所有文件都已批准，则跳过审批

**审批流程**（`start_approval_async`）：
1. **Guardian 路由检查**：如果配置为 Guardian 模式，构建 `GuardianApprovalRequest::ApplyPatch` 请求
2. **预批准检查**：如果 `permissions_preapproved` 为 true 且非重试，直接批准
3. **重试处理**：如果是重试（有 `retry_reason`），带原因请求补丁审批
4. **缓存审批**：使用 `with_cached_approval` 检查会话级审批缓存

**沙箱审批策略**（`wants_no_sandbox_approval`）：
```rust
fn wants_no_sandbox_approval(&self, policy: AskForApproval) -> bool {
    match policy {
        AskForApproval::Never => false,
        AskForApproval::Granular(config) => config.allows_sandbox_approval(),
        AskForApproval::OnFailure | AskForApproval::OnRequest | AskForApproval::UnlessTrusted => true,
    }
}
```
- 控制何时允许请求无沙箱执行
- `Never` 策略下禁止无沙箱审批

#### `ToolRuntime<ApplyPatchRequest, ExecToolCallOutput>` - 执行逻辑

```rust
async fn run(&mut self, req: &ApplyPatchRequest, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) 
    -> Result<ExecToolCallOutput, ToolError>
```

执行流程：
1. **构建命令规范**（`build_command_spec`）：
   - 解析 `codex_exe` 或使用当前可执行文件
   - Windows 特殊处理：`codex_windows_sandbox::resolve_current_exe_for_launch`
   - 构建参数：`[CODEX_CORE_APPLY_PATCH_ARG1, patch_content]`
   - 最小环境变量（`HashMap::new()`）确保确定性执行

2. **准备执行环境**（`attempt.env_for`）：
   - 使用 `SandboxAttempt` 转换 `CommandSpec` 为 `ExecRequest`
   - 应用沙箱策略（Seatbelt/Landlock/Windows Sandbox）

3. **执行**（`execute_env`）：
   - 调用 `sandboxing::execute_env` 实际执行
   - 支持 stdout 流式传输（通过 `stdout_stream`）

---

## 具体技术实现

### 关键流程

#### 1. 命令构建流程

```rust
fn build_command_spec(req: &ApplyPatchRequest, _codex_home: &Path) -> Result<CommandSpec, ToolError> {
    // 1. 确定可执行文件
    let exe = req.codex_exe.clone()
        .or_else(|| std::env::current_exe()?)  // Unix fallback
        .or_else(|| codex_windows_sandbox::resolve_current_exe_for_launch(...));  // Windows

    // 2. 构建 CommandSpec
    Ok(CommandSpec {
        program: exe.to_string_lossy().to_string(),
        args: vec![CODEX_CORE_APPLY_PATCH_ARG1.to_string(), req.action.patch.clone()],
        cwd: req.action.cwd.clone(),
        env: HashMap::new(),  // 最小环境
        expiration: req.timeout_ms.into(),
        sandbox_permissions: req.sandbox_permissions,
        additional_permissions: req.additional_permissions.clone(),
        justification: None,
    })
}
```

#### 2. Guardian 审批请求构建

```rust
fn build_guardian_review_request(req: &ApplyPatchRequest, call_id: &str) -> GuardianApprovalRequest {
    GuardianApprovalRequest::ApplyPatch {
        id: call_id.to_string(),
        cwd: req.action.cwd.clone(),
        files: req.file_paths.clone(),
        change_count: req.changes.len(),
        patch: req.action.patch.clone(),
    }
}
```

#### 3. 审批缓存键策略

```rust
type ApprovalKey = AbsolutePathBuf;

fn approval_keys(&self, req: &ApplyPatchRequest) -> Vec<Self::ApprovalKey> {
    req.file_paths.clone()
}
```

- 每个文件路径是一个独立的审批键
- 所有文件都必须已批准才能跳过审批
- 批准按路径缓存，支持子集自动批准

### 数据结构

| 结构 | 用途 |
|------|------|
| `ApplyPatchRequest` | 封装单次补丁请求的所有参数 |
| `ApplyPatchRuntime` | 运行时实例（无状态，使用 Default） |
| `ApplyPatchAction` | 来自 `codex_apply_patch` crate 的补丁操作 |
| `FileChange` | 协议层文件变更表示 |

### 协议与命令

**内部命令协议：**
```
codex --codex-run-as-apply-patch <patch_content>
```

- `CODEX_CORE_APPLY_PATCH_ARG1` = `"--codex-run-as-apply-patch"`
- 补丁内容作为第二个参数传递
- 由 `codex_apply_patch` crate 解析和执行

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/tools/runtimes/apply_patch.rs` | 本文件，Apply Patch 运行时实现 |
| `codex-rs/core/src/tools/handlers/apply_patch.rs` | Handler 层，解析输入并调用运行时 |
| `codex-rs/core/src/tools/orchestrator.rs` | 编排器，管理审批→沙箱→执行→重试流程 |
| `codex-rs/core/src/tools/sandboxing.rs` | 沙箱 trait 定义（`ToolRuntime`, `Approvable` 等） |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱实现，`SandboxManager`, `execute_env` |

### 调用链

```
[Model] apply_patch tool call
    ↓
[ApplyPatchHandler::handle] (handlers/apply_patch.rs:146)
    ↓
[codex_apply_patch::maybe_parse_apply_patch_verified]
    ↓
[apply_patch::apply_patch] (core/src/apply_patch.rs)
    ↓ (if needs exec)
[ApplyPatchRequest 构建]
    ↓
[ToolOrchestrator::run] (orchestrator.rs:100)
    ↓
[ApplyPatchRuntime::start_approval_async] (本文件:129)
    ↓ (if approved)
[ApplyPatchRuntime::run] (本文件:201)
    ↓
[build_command_spec → execute_env] (sandboxing/mod.rs:727)
    ↓
[codex --codex-run-as-apply-patch]
```

### 依赖 crate

| Crate | 用途 |
|-------|------|
| `codex_apply_patch` | 补丁解析和执行 |
| `codex_protocol` | 协议类型（`FileChange`, `ReviewDecision` 等） |
| `codex_utils_absolute_path` | 绝对路径处理 |

---

## 依赖与外部交互

### 外部依赖

1. **`codex_apply_patch` crate**
   - `ApplyPatchAction`: 补丁操作结构
   - `CODEX_CORE_APPLY_PATCH_ARG1`: 命令行参数常量
   - `maybe_parse_apply_patch_verified()`: 补丁验证

2. **Guardian 系统** (`guardian` module)
   - `GuardianApprovalRequest::ApplyPatch`: Guardian 审批请求变体
   - `review_approval_request()`: 提交审批请求
   - `routes_approval_to_guardian()`: 检查是否路由到 Guardian

3. **沙箱系统** (`sandboxing` module)
   - `SandboxAttempt::env_for()`: 准备执行环境
   - `execute_env()`: 实际执行命令
   - `CommandSpec`: 命令规范结构

4. **会话系统** (`codex` module)
   - `Session::request_patch_approval()`: 请求补丁审批
   - `SessionServices::tool_approvals`: 审批缓存存储

### 配置依赖

| 配置项 | 来源 |
|--------|------|
| `codex_home` | `TurnContext::config.codex_home` |
| `codex_linux_sandbox_exe` | `TurnContext::codex_linux_sandbox_exe` |
| `approval_policy` | `TurnContext::approval_policy` |
| `file_system_sandbox_policy` | `TurnContext::file_system_sandbox_policy` |

---

## 风险、边界与改进建议

### 风险点

1. **命令注入风险**
   - **现状**：补丁内容作为命令行参数传递
   - **风险**：虽然经过 `codex_apply_patch` 验证，但长补丁可能触及操作系统命令行长度限制
   - **缓解**：`codex_apply_patch` 负责验证补丁格式，但大文件修改仍可能失败

2. **权限提升绕过**
   - **现状**：`permissions_preapproved` 可跳过审批
   - **风险**：如果 Handler 层错误设置此标志，可能绕过用户审批
   - **缓解**：仅在 `request_permissions` 工具明确授予权限时设置

3. **环境泄漏**
   - **现状**：执行时使用 `HashMap::new()` 最小环境
   - **风险**：某些必要环境变量可能被清除导致执行失败
   - **缓解**：设计意图，补丁应用应自包含，不依赖外部环境

4. **Windows 可执行文件解析**
   - **现状**：使用 `codex_windows_sandbox::resolve_current_exe_for_launch`
   - **风险**：Windows 路径解析复杂，可能解析到错误可执行文件
   - **缓解**：通过测试覆盖和 `codex_home` 显式配置

### 边界条件

| 边界 | 处理 |
|------|------|
| 空文件列表 | `with_cached_approval` 会跳过缓存检查 |
| 超时 | 通过 `timeout_ms` 配置，默认使用系统默认值 |
| 沙箱拒绝 | 由 `ToolOrchestrator` 处理重试逻辑 |
| Guardian 模式 | 完全绕过本地审批，由 Guardian 决策 |

### 改进建议

1. **命令行长度优化**
   - 当前：补丁内容通过命令行参数传递
   - 建议：大补丁可通过临时文件或 stdin 传递，避免命令行长度限制

2. **审批粒度细化**
   - 当前：按文件路径审批
   - 建议：考虑按目录或 glob 模式审批，减少重复审批

3. **错误信息增强**
   - 当前：沙箱拒绝时返回通用错误
   - 建议：区分沙箱策略拒绝和实际执行错误，提供更具体的重试建议

4. **环境变量传递**
   - 当前：完全空环境
   - 建议：考虑传递必要的最小环境（如 `HOME`, `USER`），提高兼容性

5. **测试覆盖**
   - 当前：单元测试覆盖审批策略（`apply_patch_tests.rs`）
   - 建议：增加集成测试，覆盖完整执行流程和沙箱交互

### 相关测试

- `apply_patch_tests.rs`：单元测试，覆盖审批策略和 Guardian 请求构建
- `handlers/apply_patch_tests.rs`：Handler 层测试
- `core/tests/suite/prompt_caching.rs`：审批缓存测试
