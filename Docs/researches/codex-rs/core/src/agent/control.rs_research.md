# control.rs 研究文档

## 场景与职责

`control.rs` 是 Codex 多代理系统的核心控制平面，负责管理子代理（sub-agent）的生命周期。它提供了以下核心能力：

1. **代理创建与销毁**：创建新的子代理线程、从 rollout 文件恢复代理、关闭代理
2. **代理通信**：向代理发送用户输入、中断代理执行、查询代理状态
3. **父子代理协调**：支持 fork 父代理的历史记录、继承父代理的 shell 快照和执行策略
4. **状态监控**：订阅代理状态变更、获取 token 使用量、格式化子代理上下文

`AgentControl` 结构体是每个用户会话共享的句柄，确保所有子代理在同一个会话中共享相同的 Guards（限制控制）。

## 功能点目的

### 1. 代理生命周期管理
- **spawn_agent**: 创建新代理并发送初始提示
- **spawn_agent_with_options**: 支持 fork 模式的代理创建
- **resume_agent_from_rollout**: 从 rollout 文件恢复代理状态
- **shutdown_agent**: 关闭代理并释放资源

### 2. 代理通信
- **send_input**: 向代理发送丰富的用户输入（文本、图片等）
- **interrupt_agent**: 中断当前正在执行的任务
- **get_status**: 获取代理当前状态
- **subscribe_status**: 订阅状态变更通知

### 3. 父子代理协调
- **fork 模式**: 子代理继承父代理的对话历史
- **shell 快照继承**: 子代理继承父代理的 shell 环境状态
- **执行策略继承**: 子代理继承父代理的执行策略配置
- **完成通知**: 子代理完成后自动通知父代理

### 4. 昵称管理
- 为每个子代理分配独特的历史人物昵称
- 支持角色特定的昵称候选列表
- 处理昵称池耗尽时的序数后缀扩展

## 具体技术实现

### 核心数据结构

```rust
/// 控制平面句柄，每个会话共享一个实例
#[derive(Clone, Default)]
pub(crate) struct AgentControl {
    /// 弱引用指向全局线程管理器，避免循环引用
    manager: Weak<ThreadManagerState>,
    /// 共享的 Guards，用于限制多代理能力
    state: Arc<Guards>,
}

/// 创建代理的选项
#[derive(Clone, Debug, Default)]
pub(crate) struct SpawnAgentOptions {
    /// 如果设置，fork 父代理的历史记录
    pub(crate) fork_parent_spawn_call_id: Option<String>,
}
```

### 关键流程

#### 1. 代理创建流程 (`spawn_agent_with_options`)

```
1. 升级 Weak<ThreadManagerState> 到 Arc
2. 通过 Guards 预留 spawn 槽位（检查 max_threads 限制）
3. 获取继承的 shell 快照和执行策略
4. 为子代理分配昵称（从角色配置或默认列表）
5. 根据 session_source 类型：
   - ThreadSpawn: 创建子代理，支持 fork 模式
   - 其他: 创建独立代理
6. 提交预留槽位（注册线程 ID）
7. 通知线程创建事件
8. 发送初始输入
9. 启动完成监听器（如果是子代理）
```

#### 2. Fork 模式实现

Fork 模式允许子代理继承父代理的完整对话历史：

```rust
if let Some(call_id) = options.fork_parent_spawn_call_id.as_ref() {
    // 1. 确保父代理的 rollout 已持久化
    parent_thread.codex.session.ensure_rollout_materialized().await;
    parent_thread.codex.session.flush_rollout().await;
    
    // 2. 从 rollout 文件加载历史
    let mut forked_rollout_items = RolloutRecorder::get_rollout_history(&rollout_path)
        .await?
        .get_rollout_items();
    
    // 3. 添加 fork 通知消息作为 FunctionCallOutput
    let mut output = FunctionCallOutputPayload::from_text(
        FORKED_SPAWN_AGENT_OUTPUT_MESSAGE.to_string(),
    );
    output.success = Some(true);
    forked_rollout_items.push(RolloutItem::ResponseItem(
        ResponseItem::FunctionCallOutput { call_id: call_id.clone(), output },
    ));
    
    // 4. 使用 Forked 初始历史创建线程
    let initial_history = InitialHistory::Forked(forked_rollout_items);
    state.fork_thread_with_source(...).await?
}
```

#### 3. 代理恢复流程 (`resume_agent_from_rollout`)

```
1. 升级 ThreadManagerState
2. 预留 spawn 槽位
3. 从 SQLite 数据库恢复昵称和角色信息
4. 重新预留相同的昵称（如果可用）
5. 获取继承的 shell 快照和执行策略
6. 查找 rollout 文件路径
7. 调用 resume_thread_from_rollout_with_source 恢复线程
8. 提交预留槽位
9. 通知线程创建
10. 启动完成监听器
```

#### 4. 完成监听器 (`maybe_start_completion_watcher`)

这是一个后台任务，监控子代理的执行状态并在完成后通知父代理：

```rust
fn maybe_start_completion_watcher(&self, child_thread_id: ThreadId, session_source: Option<SessionSource>) {
    // 只对 ThreadSpawn 类型的子代理启用
    let Some(SessionSource::SubAgent(SubAgentSource::ThreadSpawn { parent_thread_id, .. })) = session_source else { return };
    
    tokio::spawn(async move {
        // 订阅状态变更
        let status = match control.subscribe_status(child_thread_id).await {
            Ok(mut status_rx) => {
                let mut status = status_rx.borrow().clone();
                while !is_final(&status) {
                    if status_rx.changed().await.is_err() { break }
                    status = status_rx.borrow().clone();
                }
                status
            }
            Err(_) => control.get_status(child_thread_id).await,
        };
        
        // 向父代理注入完成通知消息
        if is_final(&status) {
            parent_thread.inject_user_message_without_turn(
                format_subagent_notification_message(&child_thread_id.to_string(), &status)
            ).await;
        }
    });
}
```

### 昵称分配算法

```rust
fn agent_nickname_candidates(config: &Config, role_name: Option<&str>) -> Vec<String> {
    let role_name = role_name.unwrap_or(DEFAULT_ROLE_NAME);
    // 优先使用角色配置的昵称候选
    if let Some(candidates) = resolve_role_config(config, role_name)
        .and_then(|role| role.nickname_candidates.clone()) {
        return candidates;
    }
    // 回退到默认历史名人列表
    default_agent_nickname_list().into_iter().map(ToOwned::to_owned).collect()
}
```

## 关键代码路径与文件引用

### 主要结构体和函数

| 名称 | 位置 | 说明 |
|------|------|------|
| `AgentControl` | 第 69-76 行 | 主控制结构体 |
| `SpawnAgentOptions` | 第 33-36 行 | 创建代理的选项 |
| `spawn_agent` | 第 88-96 行 | 创建代理的简化接口 |
| `spawn_agent_with_options` | 第 98-225 行 | 完整的代理创建逻辑 |
| `resume_agent_from_rollout` | 第 228-304 行 | 从 rollout 恢复代理 |
| `send_input` | 第 307-327 行 | 发送用户输入 |
| `interrupt_agent` | 第 330-333 行 | 中断代理 |
| `shutdown_agent` | 第 336-342 行 | 关闭代理 |
| `get_status` | 第 345-354 行 | 获取代理状态 |
| `subscribe_status` | 第 387-394 行 | 订阅状态变更 |
| `maybe_start_completion_watcher` | 第 444-488 行 | 启动完成监听器 |

### 常量定义

| 名称 | 位置 | 说明 |
|------|------|------|
| `AGENT_NAMES` | 第 30 行 | 嵌入的昵称列表文件 |
| `FORKED_SPAWN_AGENT_OUTPUT_MESSAGE` | 第 31 行 | Fork 时的系统消息 |

### 依赖文件

- `agent_names.txt`: 默认昵称列表
- `guards.rs`: `Guards` 和 `SpawnReservation`，用于限制管理
- `role.rs`: 角色配置解析
- `status.rs`: 状态转换逻辑
- `thread_manager.rs`: `ThreadManagerState`，线程管理

## 依赖与外部交互

### 内部模块依赖

```rust
use crate::agent::AgentStatus;
use crate::agent::guards::Guards;
use crate::agent::role::DEFAULT_ROLE_NAME;
use crate::agent::role::resolve_role_config;
use crate::agent::status::is_final;
use crate::codex_thread::ThreadConfigSnapshot;
use crate::error::CodexErr;
use crate::error::Result as CodexResult;
use crate::find_thread_path_by_id_str;
use crate::rollout::RolloutRecorder;
use crate::session_prefix::format_subagent_context_line;
use crate::session_prefix::format_subagent_notification_message;
use crate::shell_snapshot::ShellSnapshot;
use crate::state_db;
use crate::thread_manager::ThreadManagerState;
```

### 外部 crate 依赖

```rust
use codex_protocol::ThreadId;
use codex_protocol::models::FunctionCallOutputPayload;
use codex_protocol::models::ResponseItem;
use codex_protocol::protocol::InitialHistory;
use codex_protocol::protocol::Op;
use codex_protocol::protocol::RolloutItem;
use codex_protocol::protocol::SessionSource;
use codex_protocol::protocol::SubAgentSource;
use codex_protocol::protocol::TokenUsage;
use codex_protocol::user_input::UserInput;
use std::sync::Arc;
use std::sync::Weak;
use tokio::sync::watch;
```

### 与 ThreadManagerState 的交互

| 方法 | 用途 |
|------|------|
| `spawn_new_thread_with_source` | 创建新线程 |
| `fork_thread_with_source` | Fork 父线程历史 |
| `resume_thread_from_rollout_with_source` | 从 rollout 恢复 |
| `get_thread` | 获取线程句柄 |
| `remove_thread` | 移除线程 |
| `list_thread_ids` | 列出所有线程 ID |
| `notify_thread_created` | 通知线程创建 |
| `send_op` | 发送操作到线程 |

## 风险、边界与改进建议

### 当前风险

1. **Weak 引用升级失败**：
   - 如果 `ThreadManagerState` 被提前释放，`upgrade()` 会失败
   - 当前处理是返回错误，但某些场景下可能导致代理创建失败

2. **Fork 模式的 rollout 依赖**：
   - Fork 需要父代理的 rollout 文件已持久化
   - 如果 `ensure_rollout_materialized()` 失败，fork 会失败

3. **状态不一致风险**：
   - `release_spawned_thread` 和 `remove_thread` 是分开调用的
   - 如果中间发生 panic 或取消，可能导致资源泄漏

4. **完成监听器的生命周期**：
   - 使用 `tokio::spawn` 启动后台任务，没有明确的取消机制
   - 如果父代理提前关闭，监听器可能尝试访问已释放的资源

### 边界情况

1. **最大线程限制**：
   - `agent_max_threads` 为 `None` 时，不限制线程数
   - 为 `Some(n)` 时，通过原子操作和 CAS 循环确保线程安全

2. **昵称分配**：
   - 如果角色配置的昵称列表为空，会尝试使用默认列表
   - 如果所有昵称都被使用，会添加序数后缀（如 "the 2nd"）

3. **Shell 快照和执行策略继承**：
   - 只对 `ThreadSpawn` 类型的子代理启用
   - 执行策略继承需要 `child_uses_parent_exec_policy()` 返回 true

4. **错误处理**：
   - `send_input` 遇到 `InternalAgentDied` 时会自动清理线程
   - 其他错误会向上传播

### 改进建议

1. **增强错误恢复**：
   - 添加重试机制处理临时的 rollout 读取失败
   - 在 `shutdown_agent` 中确保即使 `send_op` 失败也清理资源

2. **完善取消机制**：
   - 为完成监听器添加 `AbortHandle`，在父代理关闭时取消
   - 使用 `tokio_util::sync::CancellationToken` 管理后台任务生命周期

3. **优化昵称分配**：
   - 添加昵称预留超时机制，防止僵尸昵称长期占用
   - 支持动态加载新的昵称列表

4. **增强可观测性**：
   - 添加更多 tracing 日志，特别是 fork 和恢复流程
   - 导出指标：代理创建/关闭计数、平均存活时间等

5. **代码重构**：
   - `spawn_agent_with_options` 函数较长（约 130 行），可以拆分为多个辅助函数
   - 提取 fork 逻辑到单独的模块

6. **测试增强**：
   - 添加并发创建代理的压力测试
   - 测试 rollout 文件损坏时的恢复行为
   - 测试网络分区场景下的状态同步
