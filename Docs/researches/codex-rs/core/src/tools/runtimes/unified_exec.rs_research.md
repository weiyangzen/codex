# unified_exec.rs 深入研究

## 场景与职责

`unified_exec.rs` 实现了 Codex 的 **Unified Exec 运行时**（`UnifiedExecRuntime`），是下一代命令执行基础设施，支持长时间运行的进程、PTY（伪终端）交互和更灵活的执行模型。与传统的 `ShellRuntime` 相比，它提供了更强大的进程生命周期管理能力。

**核心职责：**
1. **统一执行管理**：通过 `UnifiedExecProcessManager` 管理进程生命周期
2. **PTY 支持**：支持交互式终端会话（TTY 模式）
3. **审批集成**：与标准审批流程集成
4. **网络审批**：支持延迟网络审批（Deferred Network Approval）
5. **ZshFork 集成**：支持实验性的 ZshFork 后端

**架构定位：**
- 位于工具运行时层（`tools/runtimes/`）
- 被 `UnifiedExecHandler`（`handlers/unified_exec.rs`）调用
- 通过 `UnifiedExecProcessManager` 管理进程
- 支持 `exec_command` 和 `write_stdin` 工具

---

## 功能点目的

### 1. UnifiedExecRequest - 请求数据结构

```rust
pub struct UnifiedExecRequest {
    pub command: Vec<String>,           // 命令行
    pub cwd: PathBuf,                   // 工作目录
    pub env: HashMap<String, String>,   // 环境变量
    pub explicit_env_overrides: HashMap<String, String>, // 显式环境覆盖
    pub network: Option<NetworkProxy>,  // 网络代理
    pub tty: bool,                      // 是否使用 TTY
    pub sandbox_permissions: SandboxPermissions, // 沙箱权限
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    #[cfg(unix)]
    pub additional_permissions_preapproved: bool, // 额外权限是否预批准
    pub justification: Option<String>,  // 执行理由
    pub exec_approval_requirement: ExecApprovalRequirement, // 执行审批要求
}
```

**与 `ShellRequest` 的关键区别：**
- 包含 `tty` 标志支持 PTY 模式
- 无 `timeout_ms`（由 `UnifiedExecProcessManager` 管理超时）
- 设计用于长时间运行的交互式会话

### 2. UnifiedExecApprovalKey - 审批缓存键

```rust
pub struct UnifiedExecApprovalKey {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub tty: bool,                      // 包含 TTY 标志
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
}
```

**设计考虑：**
- `tty` 标志影响执行环境，因此包含在审批键中
- 相同的命令在 TTY 和非 TTY 模式下被视为不同的审批实体

### 3. UnifiedExecRuntime - 运行时实现

**生命周期管理：**
```rust
pub struct UnifiedExecRuntime<'a> {
    manager: &'a UnifiedExecProcessManager,  // 进程管理器引用
    shell_mode: UnifiedExecShellMode,         // Shell 模式配置
}
```

运行时持有对 `UnifiedExecProcessManager` 的引用，用于：
- 分配进程 ID
- 创建执行会话
- 管理进程生命周期

#### `Sandboxable` 实现
```rust
impl Sandboxable for UnifiedExecRuntime<'_> {
    fn sandbox_preference(&self) -> SandboxablePreference { SandboxablePreference::Auto }
    fn escalate_on_failure(&self) -> bool { true }
}
```

#### `Approvable<UnifiedExecRequest>` 实现

**审批流程与 `ShellRuntime` 类似，但：**
- 构建 `GuardianApprovalRequest::ExecCommand`（而非 `Shell`）
- 包含 `tty` 字段

#### `ToolRuntime` 实现

**关键区别：网络审批模式**
```rust
fn network_approval_spec(&self, req: &UnifiedExecRequest, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec> {
    req.network.as_ref()?;
    Some(NetworkApprovalSpec {
        network: req.network.clone(),
        mode: NetworkApprovalMode::Deferred,  // 延迟模式（vs Immediate）
    })
}
```

**延迟网络审批（Deferred）：**
- 网络访问审批延迟到实际需要时
- 适用于长时间运行的进程，可能不需要立即网络访问
- 与 `ShellRuntime` 的立即模式形成对比

### 4. 执行流程

```rust
async fn run(&mut self, req: &UnifiedExecRequest, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx)
    -> Result<UnifiedExecProcess, ToolError>
```

**执行步骤：**

1. **命令准备**（同 `ShellRuntime`）：
   - `maybe_wrap_shell_lc_with_snapshot`
   - PowerShell UTF-8 处理

2. **环境变量设置**：
   ```rust
   let mut env = req.env.clone();
   if let Some(network) = req.network.as_ref() {
       network.apply_to_env(&mut env);
   }
   ```

3. **ZshFork 模式处理**：
   ```rust
   if let UnifiedExecShellMode::ZshFork(zsh_fork_config) = &self.shell_mode {
       match zsh_fork_backend::maybe_prepare_unified_exec(...).await? {
           Some(prepared) => {
               return self.manager.open_session_with_exec_env(
                   &prepared.exec_request,
                   req.tty,
                   prepared.spawn_lifecycle,
               ).await;
           }
           None => { /* 回退 */ }
       }
   }
   ```

4. **标准执行**：
   ```rust
   let spec = build_command_spec(&command, &req.cwd, &env, ExecExpiration::DefaultTimeout, ...)?;
   let exec_env = attempt.env_for(spec, req.network.as_ref())?;
   self.manager.open_session_with_exec_env(&exec_env, req.tty, Box::new(NoopSpawnLifecycle)).await
   ```

---

## 具体技术实现

### ZshFork 集成详解

**准备阶段：**
```rust
match zsh_fork_backend::maybe_prepare_unified_exec(
    req,
    attempt,
    ctx,
    exec_env,
    zsh_fork_config,
).await?
```

**成功路径：**
- 返回 `PreparedUnifiedExec` 包含：
  - `exec_request`: 配置好的执行请求
  - `spawn_lifecycle`: 自定义生命周期回调

**会话创建：**
```rust
self.manager.open_session_with_exec_env(
    &prepared.exec_request,
    req.tty,
    prepared.spawn_lifecycle,
).await
```

**错误处理：**
```rust
.map_err(|err| match err {
    UnifiedExecError::SandboxDenied { output, .. } => {
        ToolError::Codex(CodexErr::Sandbox(SandboxErr::Denied {
            output: Box::new(output),
            network_policy_decision: None,
        }))
    }
    other => ToolError::Rejected(other.to_string()),
})
```

### 与 `UnifiedExecProcessManager` 的交互

**进程 ID 分配**（在 Handler 层）：
```rust
let process_id = manager.allocate_process_id().await;
```

**执行会话创建：**
```rust
manager.exec_command(ExecCommandRequest { ... }, &context).await
```

**关键区别：**
- `ShellRuntime` 返回 `ExecToolCallOutput`（一次性输出）
- `UnifiedExecRuntime` 返回 `UnifiedExecProcess`（持续交互句柄）

### 超时处理

```rust
ExecExpiration::DefaultTimeout  // 使用系统默认超时
```

- 实际超时由 `UnifiedExecProcessManager` 控制
- 支持 `yield_time_ms` 配置（在 Handler 层）

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `unified_exec.rs` | 本文件，Unified Exec 运行时实现 |
| `shell/zsh_fork_backend.rs` | ZshFork 后端实现（共享） |
| `handlers/unified_exec.rs` | Handler 层，解析输入并调用运行时 |
| `unified_exec/process_manager.rs` | 进程管理器实现 |
| `unified_exec/mod.rs` | Unified Exec 模块定义 |

### 调用链

```
[Model] exec_command/write_stdin tool call
    ↓
[UnifiedExecHandler::handle] (handlers/unified_exec.rs:120)
    ↓
[process_id allocation]
    ↓
[UnifiedExecRequest 构建]
    ↓
[ToolOrchestrator::run] (orchestrator.rs:100)
    ↓
[UnifiedExecRuntime::start_approval_async] (unified_exec.rs:109)
    ↓ (if approved)
[UnifiedExecRuntime::run] (unified_exec.rs:189)
    ↓
[maybe_wrap_shell_lc_with_snapshot] (mod.rs:68)
    ↓
[manager.open_session_with_exec_env] (unified_exec/process_manager.rs)
```

### 依赖类型

| 类型 | 来源 |
|------|------|
| `UnifiedExecProcessManager` | `crate::unified_exec` |
| `UnifiedExecProcess` | `crate::unified_exec` |
| `UnifiedExecShellMode` | `crate::tools::spec` |
| `NoopSpawnLifecycle` | `crate::unified_exec` |
| `ExecCommandRequest` | `crate::unified_exec` |

---

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `codex_network_proxy::NetworkProxy` | 网络代理配置 |
| `codex_protocol::models::PermissionProfile` | 权限配置 |
| `futures::future::BoxFuture` | 异步 trait 方法 |

### 内部模块依赖

```rust
use crate::unified_exec::NoopSpawnLifecycle;
use crate::unified_exec::UnifiedExecError;
use crate::unified_exec::UnifiedExecProcess;
use crate::unified_exec::UnifiedExecProcessManager;
```

### 共享组件

与 `shell.rs` 共享：
- `build_command_spec`
- `maybe_wrap_shell_lc_with_snapshot`
- `zsh_fork_backend`
- `prefix_powershell_script_with_utf8`

---

## 风险、边界与改进建议

### 风险点

1. **生命周期管理复杂性**
   - **风险**：`UnifiedExecProcess` 需要显式管理，可能泄漏
   - **现状**：由 `UnifiedExecProcessManager` 管理
   - **建议**：确保所有路径都正确释放资源

2. **ZshFork 与 Unified Exec 的耦合**
   - **风险**：ZshFork 逻辑分散在多个文件中
   - **现状**：通过 `maybe_prepare_unified_exec` 集成
   - **建议**：考虑统一 ZshFork 的 Shell 和 Unified Exec 实现

3. **延迟网络审批的复杂性**
   - **风险**：Deferred 模式增加了状态管理复杂性
   - **现状**：由 `NetworkApprovalSpec` 管理
   - **建议**：添加更多文档和测试覆盖

4. **错误映射不一致**
   - **风险**：`UnifiedExecError` 到 `ToolError` 的映射可能丢失信息
   - **现状**：仅特殊处理 `SandboxDenied`
   - **建议**：审计所有错误路径

### 边界条件

| 边界 | 处理 |
|------|------|
| TTY 模式不可用 | 由 `UnifiedExecProcessManager` 处理 |
| ZshFork 条件不满足 | 回退到标准执行 |
| 进程 ID 耗尽 | 由 `UnifiedExecProcessManager` 处理 |
| 网络未配置 | `network_approval_spec` 返回 `None` |

### 与 `ShellRuntime` 的对比

| 特性 | `ShellRuntime` | `UnifiedExecRuntime` |
|------|----------------|----------------------|
| 输出类型 | `ExecToolCallOutput`（一次性） | `UnifiedExecProcess`（持续） |
| TTY 支持 | 有限 | 原生支持 |
| 网络审批 | Immediate | Deferred |
| 超时控制 | 运行时指定 | Manager 控制 |
| 适用场景 | 简单命令 | 交互式/长时间运行 |

### 改进建议

1. **统一错误处理**
   - 当前：`UnifiedExecError` 和 `ToolError` 转换可能丢失信息
   - 建议：定义更清晰的错误层次结构

2. **ZshFork 稳定化**
   - 当前：ZshFork 是实验性功能
   - 建议：决定是稳定化还是移除，减少维护负担

3. **文档完善**
   - 当前：缺少架构级文档说明何时使用 Unified Exec vs Shell
   - 建议：添加决策指南

4. **测试覆盖**
   - 当前：无专门的运行时测试
   - 建议：添加单元测试，特别是 ZshFork 路径

5. **性能优化**
   - 当前：每次执行都重新构建命令规范
   - 建议：考虑缓存可重用的配置

### 演进方向

`UnifiedExecRuntime` 代表了 Codex 执行架构的演进方向：
- 从一次性命令执行向持续会话管理转变
- 更好的交互式工具支持
- 更灵活的网络和权限管理

长期可能逐步替代 `ShellRuntime` 成为主要执行路径。
