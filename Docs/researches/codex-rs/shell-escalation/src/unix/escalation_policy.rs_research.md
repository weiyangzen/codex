# escalation_policy.rs 研究文档

## 场景与职责

`escalation_policy.rs` 是 Unix 平台 shell 权限提升机制的**策略接口定义**，定义了服务器用于决策的 trait 契约。它将权限提升的决策逻辑与核心服务器实现解耦，允许不同的调用者根据自身的安全需求和业务逻辑实现自定义策略。

核心职责：
1. 定义 `EscalationPolicy` trait，规范权限提升决策接口
2. 提供策略实现的类型约束（`Send + Sync` 确保线程安全）
3. 作为服务器与具体策略实现之间的桥梁

## 功能点目的

### EscalationPolicy Trait

```rust
/// Decides what action to take in response to an execve request from a client.
#[async_trait::async_trait]
pub trait EscalationPolicy: Send + Sync {
    async fn determine_action(
        &self,
        file: &AbsolutePathBuf,
        argv: &[String],
        workdir: &AbsolutePathBuf,
    ) -> anyhow::Result<EscalationDecision>;
}
```

**设计意图**：
- **异步接口**：使用 `async_trait` 支持异步决策（可能需要查询外部服务、用户确认等）
- **线程安全**：`Send + Sync` 约束确保策略可以在多线程环境中共享
- **对象安全**：trait 方法使用 `&self` 和引用参数，支持动态分发

**参数说明**：
- `file`：要执行的程序路径（已解析为绝对路径）
- `argv`：参数列表（包含 argv[0]）
- `workdir`：工作目录（绝对路径）

**返回值**：
- `EscalationDecision`：决策结果（Run、Escalate、Deny）

## 具体技术实现

### 类型约束分析

```rust
pub trait EscalationPolicy: Send + Sync
```

- `Send`：允许将策略对象转移到其他线程
- `Sync`：允许在多个线程间共享策略对象的引用

这些约束是必要的，因为：
1. `EscalateServer` 使用 `Arc<dyn EscalationPolicy>` 存储策略
2. `escalate_task` 在 tokio 运行时中 spawn 任务，需要跨线程共享策略

### 参数类型选择

| 参数 | 类型 | 原因 |
|------|------|------|
| `file` | `&AbsolutePathBuf` | 确保是绝对路径，避免相对路径解析问题 |
| `argv` | `&[String]` | 参数列表，包含 argv[0] |
| `workdir` | `&AbsolutePathBuf` | 工作目录，用于解析相对路径（虽然 file 已经是绝对路径）|

### 返回值设计

```rust
anyhow::Result<EscalationDecision>
```

- 使用 `anyhow::Result` 允许策略实现者灵活地返回各种错误
- `EscalationDecision` 定义在 `escalate_protocol.rs` 中，包含三种决策：
  - `Run`：在客户端本地执行
  - `Escalate(EscalationExecution)`：提升权限到服务器执行
  - `Deny { reason }`：拒绝执行

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 1 | `use codex_utils_absolute_path::AbsolutePathBuf;` | 绝对路径类型 |
| 3 | `use crate::unix::escalate_protocol::EscalationDecision;` | 决策枚举 |
| 5-14 | `EscalationPolicy` trait 定义 | 核心接口 |

### 依赖文件

- `codex-rs/utils/absolute-path/src/lib.rs`：`AbsolutePathBuf` 定义
- `escalate_protocol.rs`：`EscalationDecision` 定义

### 被依赖文件

| 文件 | 用途 |
|------|------|
| `escalate_server.rs` | `EscalateServer` 存储 `Arc<dyn EscalationPolicy>`，在 `handle_escalate_session_with_policy` 中调用 `determine_action()` |
| `mod.rs` | 重新导出 `EscalationPolicy` |
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` | 实现 `CoreShellActionProvider` 作为策略 |

### 实现者

| 实现 | 位置 | 用途 |
|------|------|------|
| `CoreShellActionProvider` | `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs:309-751` | 核心策略实现，集成 execpolicy、技能、审批流程 |
| `DeterministicEscalationPolicy` | `escalate_server.rs` (测试) | 测试用，返回固定决策 |
| `AssertingEscalationPolicy` | `escalate_server.rs` (测试) | 测试用，验证期望参数 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `async-trait` | async trait 支持 |
| `anyhow` | 错误处理 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径类型 |
| `crate::unix::escalate_protocol::EscalationDecision` | 决策结果类型 |

### 调用流程

```
EscalateServer::exec()
    └── EscalateServer::start_session()
            └── escalate_task() [spawned]
                    └── handle_escalate_session_with_policy()
                            └── policy.determine_action(file, argv, workdir)
                                    └── [具体策略实现，如 CoreShellActionProvider]
```

## 风险、边界与改进建议

### 已知风险

1. **trait 简单性**：当前 trait 只有一个方法，虽然简单但可能限制某些高级功能：
   - 无法传递额外的上下文信息（如用户 ID、会话状态）
   - 无法支持策略的初始化/清理生命周期

2. **错误处理统一**：使用 `anyhow::Result` 虽然灵活，但调用者难以区分不同类型的错误（策略错误 vs 系统错误）

### 边界情况

1. **策略实现责任**：trait 本身不保证策略的确定性，同一个 (file, argv, workdir) 在不同时间调用可能返回不同结果（例如基于时间、用户状态的策略）

2. **异步执行**：策略在异步上下文中执行，需要注意：
   - 避免阻塞操作（应使用异步 IO）
   - 考虑超时（调用者可以通过 `tokio::time::timeout` 包装）

3. **路径解析**：虽然 `file` 已经是绝对路径，但策略实现者可能仍需要 `workdir` 来解析其他相对路径（如配置文件）

### 改进建议

1. **添加上下文参数**：
   ```rust
   async fn determine_action(
       &self,
       file: &AbsolutePathBuf,
       argv: &[String],
       workdir: &AbsolutePathBuf,
       context: &EscalationContext,  // 新增
   ) -> anyhow::Result<EscalationDecision>;
   ```
   
   `EscalationContext` 可以包含：
   - 会话 ID
   - 用户 ID
   - 请求时间
   - 历史决策记录

2. **生命周期钩子**：
   ```rust
   async fn on_session_start(&self, session_id: &str) -> anyhow::Result<()>;
   async fn on_session_end(&self, session_id: &str);
   ```

3. **批量决策**：对于需要查询外部服务的策略，支持批量决策接口：
   ```rust
   async fn determine_actions(
       &self,
       requests: &[EscalationRequest],
   ) -> anyhow::Result<Vec<EscalationDecision>>;
   ```

4. **错误类型细化**：
   ```rust
   pub enum EscalationPolicyError {
       Internal(anyhow::Error),
       InvalidRequest(String),
       ServiceUnavailable,
   }
   ```

5. **缓存支持**：添加缓存提示接口，允许策略实现者指示结果是否可以缓存：
   ```rust
   fn cache_ttl(&self, decision: &EscalationDecision) -> Option<Duration>;
   ```

### 测试覆盖

本文件本身没有测试，但 `escalate_server.rs` 中的测试模块包含多个策略实现：

- `DeterministicEscalationPolicy`：返回固定决策，用于测试各种执行路径
- `AssertingEscalationPolicy`：验证传入的参数是否符合预期

这些测试实现验证了 trait 的可用性和正确性。

### 核心实现分析

`CoreShellActionProvider`（在 `unix_escalation.rs` 中）是主要的策略实现，其决策逻辑包括：

1. **会话审批缓存**：检查 `execve_session_approvals` 中是否有预审批
2. **技能匹配**：检查命令是否属于某个 skill 的 scripts 目录
3. **Execpolicy 评估**：使用 `codex_execpolicy` crate 评估策略规则
4. **用户确认**：对于需要 Prompt 的决策，请求用户审批
5. **权限转换**：将内部决策转换为 `EscalationExecution` 变体

这个实现展示了 `EscalationPolicy` trait 的典型使用方式，也说明了 trait 设计的合理性——足够简单以支持各种实现，又足够丰富以支持复杂的决策逻辑。
