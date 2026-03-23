# sandboxing.rs 深度研究文档

## 场景与职责

`sandboxing.rs` 是 Codex 工具沙箱系统的核心 trait 定义和审批流程实现。主要职责包括：

1. **审批状态管理**：提供审批缓存存储 (`ApprovalStore`)
2. **审批流程抽象**：定义 `Approvable` trait，规范工具审批接口
3. **沙箱偏好控制**：定义 `Sandboxable` trait，控制沙箱使用策略
4. **工具运行时抽象**：定义 `ToolRuntime` trait，整合审批和沙箱
5. **执行要求计算**：根据策略计算执行审批要求
6. **审批缓存优化**：支持会话级别的审批缓存，避免重复询问

该模块是工具沙箱系统的"接口层"，定义了所有工具运行时必须实现的契约。

## 功能点目的

### 1. 审批存储 (ApprovalStore)

```rust
#[derive(Clone, Default, Debug)]
pub(crate) struct ApprovalStore {
    map: HashMap<String, ReviewDecision>,
}
```

- 使用序列化键存储审批决策
- 支持 `ApprovedForSession` 决策的缓存
- 用于 `apply_patch` 等多目标工具的批量审批

### 2. 带缓存的审批 (with_cached_approval)

```rust
pub(crate) async fn with_cached_approval<K, F, Fut>(
    services: &SessionServices,
    tool_name: &str,
    keys: Vec<K>,
    fetch: F,
) -> ReviewDecision
```

- 如果所有键都已批准，跳过询问
- 用户批准会话时，缓存每个键的决策
- 支持多键场景（如 apply_patch 修改多个文件）

### 3. 执行审批要求 (ExecApprovalRequirement)

```rust
pub(crate) enum ExecApprovalRequirement {
    Skip { bypass_sandbox: bool, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    NeedsApproval { reason: Option<String>, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    Forbidden { reason: String },
}
```

- **Skip**: 无需审批，可选择跳过沙箱
- **NeedsApproval**: 需要审批，可附带原因和建议的 execpolicy 修正
- **Forbidden**: 禁止执行

### 4. 沙箱覆盖 (SandboxOverride)

```rust
pub(crate) enum SandboxOverride {
    NoOverride,
    BypassSandboxFirstAttempt,
}
```

- 允许工具请求首次尝试跳过沙箱
- 用于 `RequireEscalated` 权限场景

### 5. 可审批 trait (Approvable)

```rust
pub(crate) trait Approvable<Req> {
    type ApprovalKey: Hash + Eq + Clone + Debug + Serialize;
    fn approval_keys(&self, req: &Req) -> Vec<Self::ApprovalKey>;
    fn sandbox_mode_for_first_attempt(&self, _req: &Req) -> SandboxOverride;
    fn should_bypass_approval(&self, policy: AskForApproval, already_approved: bool) -> bool;
    fn exec_approval_requirement(&self, _req: &Req) -> Option<ExecApprovalRequirement>;
    fn wants_no_sandbox_approval(&self, policy: AskForApproval) -> bool;
    fn start_approval_async<'a>(...) -> BoxFuture<'a, ReviewDecision>;
}
```

### 6. 可沙箱化 trait (Sandboxable)

```rust
pub(crate) trait Sandboxable {
    fn sandbox_preference(&self) -> SandboxablePreference;
    fn escalate_on_failure(&self) -> bool { true }
}
```

### 7. 工具运行时 trait (ToolRuntime)

```rust
pub(crate) trait ToolRuntime<Req, Out>: Approvable<Req> + Sandboxable {
    fn network_approval_spec(&self, _req: &Req, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec>;
    async fn run(&mut self, req: &Req, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) -> Result<Out, ToolError>;
}
```

### 8. 沙箱尝试 (SandboxAttempt)

```rust
pub(crate) struct SandboxAttempt<'a> {
    pub sandbox: crate::exec::SandboxType,
    pub policy: &'a crate::protocol::SandboxPolicy,
    pub file_system_policy: &'a FileSystemSandboxPolicy,
    pub network_policy: NetworkSandboxPolicy,
    pub enforce_managed_network: bool,
    pub(crate) manager: &'a SandboxManager,
    pub(crate) sandbox_cwd: &'a Path,
    pub codex_linux_sandbox_exe: Option<&'a std::path::PathBuf>,
    pub use_legacy_landlock: bool,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
}
```

## 具体技术实现

### 审批缓存流程

```
┌─────────────────────────────────────────────────────────────────┐
│                   with_cached_approval()                         │
├─────────────────────────────────────────────────────────────────┤
│ 1. 空键检查                                                      │
│    └─ keys.is_empty() → 直接调用 fetch()                        │
├─────────────────────────────────────────────────────────────────┤
│ 2. 检查是否全部已批准                                            │
│    └─ 所有 key 都有 ApprovedForSession 决策？                   │
│       ├─ 是 → 返回 ApprovedForSession                           │
│       └─ 否 → 继续                                               │
├─────────────────────────────────────────────────────────────────┤
│ 3. 获取用户决策                                                  │
│    └─ fetch().await                                             │
├─────────────────────────────────────────────────────────────────┤
│ 4. 记录遥测                                                      │
│    └─ counter "codex.approval.requested"                        │
├─────────────────────────────────────────────────────────────────┤
│ 5. 缓存会话批准                                                  │
│    └─ 如果决策是 ApprovedForSession，缓存每个键                 │
└─────────────────────────────────────────────────────────────────┘
```

### 默认执行审批要求计算

```rust
pub(crate) fn default_exec_approval_requirement(
    policy: AskForApproval,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
) -> ExecApprovalRequirement {
    let needs_approval = match policy {
        AskForApproval::Never | AskForApproval::OnFailure => false,
        AskForApproval::OnRequest | AskForApproval::Granular(_) => {
            matches!(file_system_sandbox_policy.kind, FileSystemSandboxKind::Restricted)
        }
        AskForApproval::UnlessTrusted => true,
    };

    if needs_approval && matches!(policy, AskForApproval::Granular(granular_config) if !granular_config.allows_sandbox_approval()) {
        ExecApprovalRequirement::Forbidden { ... }
    } else if needs_approval {
        ExecApprovalRequirement::NeedsApproval { ... }
    } else {
        ExecApprovalRequirement::Skip { ... }
    }
}
```

### 沙箱覆盖决策

```rust
pub(crate) fn sandbox_override_for_first_attempt(
    sandbox_permissions: SandboxPermissions,
    exec_approval_requirement: &ExecApprovalRequirement,
) -> SandboxOverride {
    if sandbox_permissions.requires_escalated_permissions()
        || matches!(exec_approval_requirement, ExecApprovalRequirement::Skip { bypass_sandbox: true, .. })
    {
        SandboxOverride::BypassSandboxFirstAttempt
    } else {
        SandboxOverride::NoOverride
    }
}
```

### 关键代码路径

#### ApprovalStore 实现

```rust
// sandboxing.rs:41-58
impl ApprovalStore {
    pub fn get<K>(&self, key: &K) -> Option<ReviewDecision>
    where
        K: Serialize,
    {
        let s = serde_json::to_string(key).ok()?;
        self.map.get(&s).cloned()
    }

    pub fn put<K>(&mut self, key: K, value: ReviewDecision)
    where
        K: Serialize,
    {
        if let Ok(s) = serde_json::to_string(&key) {
            self.map.insert(s, value);
        }
    }
}
```

#### with_cached_approval 实现

```rust
// sandboxing.rs:66-112
pub(crate) async fn with_cached_approval<K, F, Fut>(...) -> ReviewDecision {
    if keys.is_empty() {
        return fetch().await;
    }

    let already_approved = {
        let store = services.tool_approvals.lock().await;
        keys.iter().all(|key| matches!(store.get(key), Some(ReviewDecision::ApprovedForSession)))
    };

    if already_approved {
        return ReviewDecision::ApprovedForSession;
    }

    let decision = fetch().await;

    services.session_telemetry.counter("codex.approval.requested", ...);

    if matches!(decision, ReviewDecision::ApprovedForSession) {
        let mut store = services.tool_approvals.lock().await;
        for key in keys {
            store.put(key, ReviewDecision::ApprovedForSession);
        }
    }

    decision
}
```

#### Approvable trait 默认实现

```rust
// sandboxing.rs:251-281
fn should_bypass_approval(&self, policy: AskForApproval, already_approved: bool) -> bool {
    if already_approved {
        return true;
    }
    matches!(policy, AskForApproval::Never)
}

fn wants_no_sandbox_approval(&self, policy: AskForApproval) -> bool {
    match policy {
        AskForApproval::OnFailure => true,
        AskForApproval::UnlessTrusted => true,
        AskForApproval::Never => false,
        AskForApproval::OnRequest => false,
        AskForApproval::Granular(granular_config) => granular_config.sandbox_approval,
    }
}
```

### 数据结构详解

#### ApprovalCtx

```rust
pub(crate) struct ApprovalCtx<'a> {
    pub session: &'a Arc<Session>,
    pub turn: &'a Arc<TurnContext>,
    pub call_id: &'a str,
    pub retry_reason: Option<String>,
    pub network_approval_context: Option<NetworkApprovalContext>,
}
```

#### ToolCtx

```rust
pub(crate) struct ToolCtx {
    pub session: Arc<Session>,
    pub turn: Arc<TurnContext>,
    pub call_id: String,
    pub tool_name: String,
}
```

#### ToolError

```rust
pub(crate) enum ToolError {
    Rejected(String),
    Codex(CodexErr),
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::state::SessionServices` | 审批存储和遥测 |
| `crate::sandboxing::{SandboxManager, CommandSpec}` | 沙箱管理 |
| `crate::tools::network_approval::NetworkApprovalSpec` | 网络审批规格 |
| `crate::error::{CodexErr, SandboxErr}` | 错误类型 |

### 外部协议依赖

| 协议类型 | 用途 |
|----------|------|
| `AskForApproval` | 审批策略 |
| `ReviewDecision` | 审批决策 |
| `ExecPolicyAmendment` | 执行策略修正 |
| `NetworkApprovalContext` | 网络审批上下文 |
| `FileSystemSandboxPolicy` | 文件系统沙箱策略 |
| `NetworkSandboxPolicy` | 网络沙箱策略 |

### 调用关系

```
Approvable trait (由具体工具实现)
    ├── approval_keys()              [生成审批键]
    ├── sandbox_mode_for_first_attempt()  [沙箱覆盖决策]
    ├── should_bypass_approval()     [是否跳过审批]
    ├── exec_approval_requirement()  [自定义审批要求]
    ├── wants_no_sandbox_approval()  [是否需要无沙箱审批]
    └── start_approval_async()       [启动审批流程]

Sandboxable trait (由具体工具实现)
    ├── sandbox_preference()         [沙箱偏好]
    └── escalate_on_failure()        [失败时是否升级]

ToolRuntime trait (由具体工具实现)
    ├── network_approval_spec()      [网络审批规格]
    └── run()                        [实际执行]

with_cached_approval() (通用辅助函数)
    ├── ApprovalStore::get()         [查询缓存]
    ├── fetch()                      [获取用户决策]
    └── ApprovalStore::put()         [缓存决策]

default_exec_approval_requirement() (策略计算)
    └── 根据 AskForApproval 和 FileSystemSandboxPolicy 计算

sandbox_override_for_first_attempt() (覆盖决策)
    └── 根据 SandboxPermissions 和 ExecApprovalRequirement 计算
```

## 风险、边界与改进建议

### 已知风险

1. **审批缓存序列化失败**
   ```rust
   serde_json::to_string(key).ok()?  // 失败时静默返回 None
   ```
   - 如果键序列化失败，缓存失效但不会报错
   - 可能导致重复审批询问

2. **多键部分批准**
   - `with_cached_approval` 要求所有键都批准才跳过
   - 如果用户批准部分键，下次仍需询问
   - 这是设计决策，但可能不符合用户预期

3. **Granular 配置复杂性**
   ```rust
   AskForApproval::Granular(granular_config)
   ```
   - 配置组合复杂，容易出错
   - 需要详细的文档和验证

4. **trait 对象安全性**
   - `ToolRuntime` 使用泛型关联类型
   - 不能直接使用 trait object
   - 需要通过 `AnyToolHandler` 间接使用

### 边界情况

1. **空审批键列表**
   - `with_cached_approval` 对空列表直接调用 `fetch()`
   - 不经过缓存逻辑

2. **混合审批决策**
   - 如果缓存中有 `Approved` 而非 `ApprovedForSession`
   - 不视为已批准，会重新询问

3. **并发审批**
   - `ApprovalStore` 使用 `Mutex` 保护
   - 但 `with_cached_approval` 的检查和获取不是原子的
   - 可能导致重复询问

4. **网络审批上下文生命周期**
   - `network_approval_context` 在 `ApprovalCtx` 中是 `Option`
   - 需要确保在需要时正确设置

### 改进建议

1. **审批缓存持久化**
   ```rust
   // 建议：支持跨会话的审批缓存
   struct PersistentApprovalStore {
       memory: HashMap<String, ReviewDecision>,
       disk: Option< sled::Tree >,  // 或其他持久化存储
   }
   ```

2. **原子性改进**
   ```rust
   // 建议：使用原子操作减少重复询问
   async fn with_cached_approval_atomic(...) -> ReviewDecision {
       // 使用 compare-and-swap 模式
   }
   ```

3. **审批决策过期**
   ```rust
   // 建议：支持审批决策过期时间
   struct TimedReviewDecision {
       decision: ReviewDecision,
       expires_at: Option<Instant>,
   }
   ```

4. **更好的错误处理**
   ```rust
   // 建议：序列化失败时记录警告
   pub fn get<K>(&self, key: &K) -> Option<ReviewDecision>
   where
       K: Serialize,
   {
       match serde_json::to_string(key) {
           Ok(s) => self.map.get(&s).cloned(),
           Err(e) => {
               tracing::warn!("Failed to serialize approval key: {}", e);
               None
           }
       }
   }
   ```

5. **trait 简化**
   ```rust
   // 建议：考虑将 ToolRuntime 拆分为更小的 trait
   trait ToolExecutor { ... }
   trait ToolApprover { ... }
   trait ToolSandboxConfigurator { ... }
   ```

6. **配置验证**
   ```rust
   // 建议：在启动时验证 Granular 配置
   impl GranularApprovalConfig {
       fn validate(&self) -> Result<(), ConfigError> { ... }
   }
   ```

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/sandboxing_tests.rs` | 单元测试 |
| `codex-rs/core/src/tools/orchestrator.rs` | 使用这些 trait 编排执行 |
| `codex-rs/core/src/tools/runtimes/*.rs` | 具体工具运行时实现 |
| `codex-rs/core/src/sandboxing/mod.rs` | SandboxManager 实现 |
| `codex-rs/core/src/tools/network_approval.rs` | NetworkApprovalSpec 使用 |
| `codex-rs/core/src/state.rs` | SessionServices 定义 |
