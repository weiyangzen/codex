# apply_patch.rs 深度研究文档

## 场景与职责

`apply_patch.rs` 实现了 Codex 核心的**代码编辑工具**，用于处理模型生成的代码补丁（patch）。该 Handler 支持两种输入格式：

1. **Function 调用** - 通过标准函数调用方式传入 patch 参数
2. **Custom/Freeform 调用** - 直接传入 patch 文本（适用于 GPT-5 等支持 grammar 约束的模型）

**核心使用场景：**
- 文件创建、修改、删除
- 文件重命名（Move）
- 多文件批量编辑
- 代码审查后的自动修复

## 功能点目的

### 1. Patch 解析与验证
- 使用 `codex_apply_patch` crate 解析 patch 格式
- 验证 patch 语法正确性
- 提取文件变更列表

### 2. 权限计算
- 根据 patch 涉及的路径计算所需写权限
- 合并 session 和 turn 级别已授予的权限
- 确定沙箱策略

### 3. 执行策略选择
- **直接应用** - 简单变更直接应用（通过 `apply_patch::apply_patch`）
- **委托执行** - 复杂变更委托给执行运行时（通过 `ApplyPatchRuntime`）

### 4. 工具规格生成
- `create_apply_patch_freeform_tool()` - 生成带 Lark grammar 约束的 freeform 工具
- `create_apply_patch_json_tool()` - 生成标准 JSON 参数工具

### 5. Exec 拦截
- `intercept_apply_patch` - 拦截通过 shell 命令发送的 patch，引导使用专用工具

## 具体技术实现

### 关键数据结构

```rust
pub struct ApplyPatchHandler;

// 内部使用的 patch 动作结构（来自 codex_apply_patch crate）
pub struct ApplyPatchAction {
    pub cwd: PathBuf,
    // changes: BTreeMap<PathBuf, ApplyPatchFileChange>
}

pub enum ApplyPatchFileChange {
    Add { content: Vec<String> },
    Delete,
    Update { move_path: Option<PathBuf>, hunks: Vec<Hunk> },
}

// 权限相关结构
struct EffectiveAdditionalPermissions {
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
    permissions_preapproved: bool,
}

// ApplyPatchRuntime 请求
pub struct ApplyPatchRequest {
    pub action: ApplyPatchAction,
    pub file_paths: Vec<AbsolutePathBuf>,
    pub changes: HashMap<PathBuf, FileChange>,
    pub exec_approval_requirement: ExecApprovalRequirement,
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
    pub permissions_preapproved: bool,
    pub timeout_ms: Option<u64>,
    pub codex_exe: Option<PathBuf>,
}
```

### 核心常量

```rust
const APPLY_PATCH_LARK_GRAMMAR: &str = include_str!("tool_apply_patch.lark");
```

### 关键流程

#### 1. Handler 入口 (`ApplyPatchHandler::handle`)

```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 提取 patch 输入
    let patch_input = match payload {
        ToolPayload::Function { arguments } => { ... }
        ToolPayload::Custom { input } => input,
        _ => error,
    };

    // 2. 解析并验证 patch
    match codex_apply_patch::maybe_parse_apply_patch_verified(&command, &cwd) {
        MaybeApplyPatchVerified::Body(changes) => {
            // 3. 计算权限
            let (file_paths, effective_additional_permissions, file_system_sandbox_policy) =
                effective_patch_permissions(session.as_ref(), turn.as_ref(), &changes).await;

            // 4. 尝试直接应用
            match apply_patch::apply_patch(turn.as_ref(), &file_system_sandbox_policy, changes).await {
                InternalApplyPatchInvocation::Output(item) => {
                    // 直接成功
                    Ok(ApplyPatchToolOutput::from_text(content))
                }
                InternalApplyPatchInvocation::DelegateToExec(apply) => {
                    // 5. 委托给运行时
                    delegate_to_exec(...).await
                }
            }
        }
        MaybeApplyPatchVerified::CorrectnessError(parse_error) => { ... }
        MaybeApplyPatchVerified::ShellParseError(error) => { ... }
        MaybeApplyPatchVerified::NotApplyPatch => { ... }
    }
}
```

#### 2. 权限计算流程 (`effective_patch_permissions`)

```rust
async fn effective_patch_permissions(...) -> (...) {
    // 1. 提取所有涉及的文件路径
    let file_paths = file_paths_for_action(action);
    
    // 2. 合并已授予权限
    let granted_permissions = merge_permission_profiles(
        session.granted_session_permissions().await.as_ref(),
        session.granted_turn_permissions().await.as_ref(),
    );
    
    // 3. 计算有效权限
    let effective_additional_permissions = apply_granted_turn_permissions(
        session,
        SandboxPermissions::UseDefault,
        write_permissions_for_paths(&file_paths),
    ).await;
    
    // 4. 计算沙箱策略
    let file_system_sandbox_policy = effective_file_system_sandbox_policy(
        &turn.file_system_sandbox_policy,
        granted_permissions.as_ref(),
    );
    
    (file_paths, effective_additional_permissions, file_system_sandbox_policy)
}
```

#### 3. 委托执行流程

```rust
// 构建请求
let req = ApplyPatchRequest {
    action: apply.action,
    file_paths,
    changes,
    exec_approval_requirement: apply.exec_approval_requirement,
    sandbox_permissions: effective_additional_permissions.sandbox_permissions,
    additional_permissions: effective_additional_permissions.additional_permissions,
    permissions_preapproved: effective_additional_permissions.permissions_preapproved,
    timeout_ms: None,
    codex_exe: turn.codex_linux_sandbox_exe.clone(),
};

// 使用 orchestrator 运行
let mut orchestrator = ToolOrchestrator::new();
let mut runtime = ApplyPatchRuntime::new();
let tool_ctx = ToolCtx { ... };
let out = orchestrator
    .run(&mut runtime, &req, &tool_ctx, turn.as_ref(), turn.approval_policy.value())
    .await
    .map(|result| result.output);
```

#### 4. 文件路径提取 (`file_paths_for_action`)

```rust
fn file_paths_for_action(action: &ApplyPatchAction) -> Vec<AbsolutePathBuf> {
    let mut keys = Vec::new();
    let cwd = action.cwd.as_path();

    for (path, change) in action.changes() {
        // 源文件路径
        if let Some(key) = to_abs_path(cwd, path) {
            keys.push(key);
        }

        // Move 目标路径
        if let ApplyPatchFileChange::Update { move_path, .. } = change
            && let Some(dest) = move_path
            && let Some(key) = to_abs_path(cwd, dest)
        {
            keys.push(key);
        }
    }
    keys
}
```

### Patch Grammar (tool_apply_patch.lark)

```lark
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF
```

## 关键代码路径与文件引用

### 当前文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `ApplyPatchHandler::handle` | 146-258 | 主处理入口 |
| `file_paths_for_action` | 46-64 | 提取 patch 涉及路径 |
| `to_abs_path` | 66-68 | 路径绝对化 |
| `write_permissions_for_paths` | 70-93 | 生成写权限配置 |
| `effective_patch_permissions` | 95-125 | 计算有效权限 |
| `intercept_apply_patch` | 262-356 | 拦截 shell patch |
| `create_apply_patch_freeform_tool` | 360-370 | 生成 freeform 工具规格 |
| `create_apply_patch_json_tool` | 373-462 | 生成 JSON 工具规格 |

### 外部依赖

| 模块/文件 | 用途 |
|-----------|------|
| `codex_apply_patch` | Patch 解析和验证 |
| `apply_patch::apply_patch` | 直接应用 patch |
| `ApplyPatchRuntime` | 沙箱中执行 patch |
| `ToolOrchestrator` | 工具执行编排 |
| `ToolEmitter` | 事件发射 |
| `effective_file_system_sandbox_policy` | 沙箱策略计算 |
| `merge_permission_profiles` | 权限合并 |

## 依赖与外部交互

### 与 Sandboxing 系统集成

```rust
// 计算文件系统沙箱策略
let file_system_sandbox_policy = effective_file_system_sandbox_policy(
    &turn.file_system_sandbox_policy,
    granted_permissions.as_ref(),
);

// 应用已授予权限
let effective_additional_permissions = apply_granted_turn_permissions(
    session,
    SandboxPermissions::UseDefault,
    write_permissions_for_paths(&file_paths),
).await;
```

### 与事件系统集成

```rust
// 开始 patch 事件
let emitter = ToolEmitter::apply_patch(changes.clone(), apply.auto_approved);
let event_ctx = ToolEventCtx::new(session, turn, &call_id, Some(&tracker));
emitter.begin(event_ctx).await;

// 结束 patch 事件
let content = emitter.finish(event_ctx, out).await?;
```

### 与权限系统集成

```rust
// 生成写权限配置
fn write_permissions_for_paths(file_paths: &[AbsolutePathBuf]) -> Option<PermissionProfile> {
    let write_paths = file_paths
        .iter()
        .map(|path| path.parent().unwrap_or_else(|| path.clone()).into_path_buf())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .map(AbsolutePathBuf::from_absolute_path)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;

    Some(PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec![]),
            write: Some(write_paths),
        }),
        ..Default::default()
    })
}
```

## 风险、边界与改进建议

### 已知风险

1. **路径遍历风险**
   - Patch 中可能包含 `../` 等相对路径
   - 已通过 `AbsolutePathBuf::resolve_path_against_base` 处理
   - 建议：添加更严格的路径验证

2. **权限提升风险**
   - Patch 可能尝试写入敏感目录
   - 依赖沙箱策略进行限制
   - 建议：添加路径白名单机制

3. **并发冲突**
   - 多 patch 同时修改同一文件可能产生冲突
   - 当前依赖外部序列化
   - 建议：添加文件锁机制

### 边界情况

1. **空 Patch**
   - `maybe_parse_apply_patch_verified` 返回 `NotApplyPatch`
   - Handler 返回错误给模型

2. **语法错误**
   - `CorrectnessError` - 返回具体错误信息
   - `ShellParseError` - 静默处理（可能不是 patch）

3. **大文件处理**
   - 通过 `ApplyPatchRuntime` 在沙箱中处理
   - 支持超时控制

### 改进建议

1. **性能优化**
   - 批量 patch 合并处理
   - 增量 diff 计算

2. **可观测性**
   - Patch 冲突检测和报告
   - 变更影响范围分析

3. **安全性**
   - 敏感文件检测（如 `.env`, `id_rsa` 等）
   - 变更内容安全扫描

4. **用户体验**
   - Patch 预览功能
   - 冲突自动解决建议

5. **测试覆盖**
   - 当前测试仅 28 行，覆盖有限
   - 建议添加：
     - 复杂 patch 场景测试
     - 权限边界测试
     - 错误恢复测试
