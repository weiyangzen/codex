# codex-rs/core/src/codex_tests.rs 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`codex_tests.rs` 是 `codex-core` crate 的核心测试文件，位于 `codex-rs/core/src/` 目录下。该文件包含对 `Codex` 和 `Session` 核心结构的全面单元测试和集成测试，是验证 Codex AI 助手核心功能正确性的关键测试套件。

### 1.2 核心职责

该测试文件覆盖以下核心场景：

1. **会话生命周期管理**：Session 创建、配置、关闭流程
2. **Turn（对话轮次）管理**：用户输入处理、任务生成与执行、中断与恢复
3. **历史记录与 Rollout 重建**：对话历史持久化、恢复、Fork 操作
4. **线程回滚（Thread Rollback）**：多轮对话的回滚与状态恢复
5. **权限与审批流程**：执行策略审批、网络策略审批、权限请求
6. **MCP（Model Context Protocol）工具管理**：工具发现、调用、刷新
7. **实时对话（Realtime Conversation）**：实时模式切换与状态管理
8. **上下文管理**：初始上下文构建、设置更新、环境变更
9. **Token 使用与限流**：Token 计数、限流信息维护
10. **追踪与遥测**：W3C Trace Context、OpenTelemetry 集成

### 1.3 测试架构角色

```
┌─────────────────────────────────────────────────────────────┐
│                    codex_tests.rs                           │
├─────────────────────────────────────────────────────────────┤
│  被测试对象:                                                │
│  • Codex (主接口)                                           │
│  • Session (会话核心)                                       │
│  • SessionConfiguration (会话配置)                          │
│  • TurnContext (轮次上下文)                                 │
│  • SessionTask/SessionTaskContext (任务执行)                │
├─────────────────────────────────────────────────────────────┤
│  依赖模块:                                                  │
│  • codex.rs (主实现)                                        │
│  • state/ (状态管理)                                        │
│  • tasks/ (任务实现)                                        │
│  • tools/ (工具系统)                                        │
│  • rollout/ (持久化)                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 会话启动与配置测试

| 测试函数 | 目的 |
|---------|------|
| `session_new_fails_when_zsh_fork_enabled_without_zsh_path` | 验证当启用 zsh fork 功能但未配置 zsh 路径时，会话创建应失败 |
| `reload_user_config_layer_updates_effective_apps_config` | 验证运行时重新加载用户配置层能正确更新应用配置 |
| `session_configuration_apply_preserves_split_file_system_policy_on_cwd_only_update` | 验证仅更新工作目录时，分割的文件系统沙盒策略应被保留 |
| `session_configuration_apply_rederives_legacy_file_system_policy_on_cwd_update` | 验证工作目录变更时，旧版文件系统策略应重新派生 |

### 2.2 Turn 生命周期测试

| 测试函数 | 目的 |
|---------|------|
| `regular_turn_emits_turn_started_without_waiting_for_startup_prewarm` | 验证常规 turn 不会等待启动预热即可发出 TurnStarted 事件 |
| `interrupting_regular_turn_waiting_on_startup_prewarm_emits_turn_aborted` | 验证中断等待启动预热的 turn 会正确发出 TurnAborted 事件 |
| `spawn_task_turn_span_inherits_dispatch_trace_context` | 验证任务 turn span 正确继承调度追踪上下文 |
| `spawn_task_does_not_update_previous_turn_settings_for_non_run_turn_tasks` | 验证非运行 turn 任务不会更新 previous_turn_settings |

### 2.3 历史记录与 Rollout 测试

| 测试函数 | 目的 |
|---------|------|
| `reconstruct_history_matches_live_compactions` | 验证历史重建与实时压缩结果匹配 |
| `reconstruct_history_uses_replacement_history_verbatim` | 验证重建历史时直接使用替换历史 |
| `record_initial_history_reconstructs_resumed_transcript` | 验证记录初始历史时能正确重建恢复的对话记录 |
| `record_initial_history_new_defers_initial_context_until_first_turn` | 验证新会话将初始上下文延迟到第一 turn |
| `record_initial_history_seeds_token_info_from_rollout` | 验证从 rollout 中种子化 token 信息 |
| `recompute_token_usage_uses_session_base_instructions` | 验证使用会话基础指令重新计算 token 使用 |
| `recompute_token_usage_updates_model_context_window` | 验证重新计算时更新模型上下文窗口 |

### 2.4 线程回滚测试

| 测试函数 | 目的 |
|---------|------|
| `thread_rollback_drops_last_turn_from_history` | 验证回滚从历史中删除最后一 turn |
| `thread_rollback_clears_history_when_num_turns_exceeds_existing_turns` | 验证回滚 turns 数超过现有 turns 时清空历史 |
| `thread_rollback_fails_without_persisted_rollout_path` | 验证无持久化 rollout 路径时回滚失败 |
| `thread_rollback_recomputes_previous_turn_settings_and_reference_context_from_replay` | 验证从回放中重新计算 previous_turn_settings 和 reference_context |
| `thread_rollback_restores_cleared_reference_context_item_after_compaction` | 验证压缩后恢复已清除的 reference_context_item |
| `thread_rollback_persists_marker_and_replays_cumulatively` | 验证回滚标记持久化并累积回放 |
| `thread_rollback_fails_when_turn_in_progress` | 验证 turn 进行中时回滚失败 |
| `thread_rollback_fails_when_num_turns_is_zero` | 验证 turns 数为 0 时回滚失败 |

### 2.5 权限与审批测试

| 测试函数 | 目的 |
|---------|------|
| `notify_request_permissions_response_ignores_unmatched_call_id` | 验证不匹配的 call_id 被忽略 |
| `request_permissions_emits_event_when_granular_policy_allows_requests` | 验证细粒度策略允许时发出权限请求事件 |
| `request_permissions_is_auto_denied_when_granular_policy_blocks_tool_requests` | 验证细粒度策略阻止时自动拒绝 |
| `rejects_escalated_permissions_when_policy_not_on_request` | 验证非 on-request 策略时拒绝提升权限 |
| `unified_exec_rejects_escalated_permissions_when_policy_not_on_request` | 验证 unified_exec 同样拒绝提升权限 |

### 2.6 MCP 工具管理测试

| 测试函数 | 目的 |
|---------|------|
| `non_app_mcp_tools_remain_visible_without_search_selection` | 验证无搜索选择时非应用 MCP 工具保持可见 |
| `search_tool_selection_keeps_codex_apps_tools_without_mentions` | 验证搜索工具选择保留 codex_apps 工具 |
| `apps_mentions_add_codex_apps_tools_to_search_selected_set` | 验证应用提及将 codex_apps 工具添加到选择集 |
| `refresh_mcp_servers_is_deferred_until_next_turn` | 验证 MCP 服务器刷新延迟到下一 turn |

### 2.7 实时对话测试

| 测试函数 | 目的 |
|---------|------|
| `build_settings_update_items_emits_realtime_start_when_session_becomes_live` | 验证会话变为实时时发出 realtime_start |
| `build_settings_update_items_emits_realtime_end_when_session_stops_being_live` | 验证会话停止实时时发出 realtime_end |
| `build_settings_update_items_uses_previous_turn_settings_for_realtime_end` | 验证使用 previous_turn_settings 处理 realtime_end |
| `build_initial_context_uses_previous_realtime_state` | 验证初始上下文使用之前的实时状态 |
| `build_initial_context_restates_realtime_start_when_reference_context_is_missing` | 验证 reference_context 缺失时重新声明 realtime_start |

### 2.8 上下文管理测试

| 测试函数 | 目的 |
|---------|------|
| `build_settings_update_items_emits_environment_item_for_network_changes` | 验证网络变更时发出环境项 |
| `build_settings_update_items_emits_environment_item_for_time_changes` | 验证时间变更时发出环境项 |
| `record_context_updates_and_set_reference_context_item_injects_full_context_when_baseline_missing` | 验证基线缺失时注入完整上下文 |
| `record_context_updates_and_set_reference_context_item_reinjects_full_context_after_clear` | 验证清除后重新注入完整上下文 |
| `record_context_updates_and_set_reference_context_item_persists_baseline_without_emitting_diffs` | 验证持久化基线而不发出差异 |

### 2.9 追踪与遥测测试

| 测试函数 | 目的 |
|---------|------|
| `submit_with_id_captures_current_span_trace_context` | 验证 submit_with_id 捕获当前 span 追踪上下文 |
| `new_default_turn_captures_current_span_trace_id` | 验证新默认 turn 捕获当前 span trace_id |
| `submission_dispatch_span_prefers_submission_trace_context` | 验证调度 span 优先使用提交追踪上下文 |
| `submission_dispatch_span_uses_debug_for_realtime_audio` | 验证实时音频使用 debug 级别调度 span |

### 2.10 流解析与消息处理测试

| 测试函数 | 目的 |
|---------|------|
| `assistant_message_stream_parsers_can_be_seeded_from_output_item_added_text` | 验证流解析器可从输出项添加的文本种子化 |
| `assistant_message_stream_parsers_seed_buffered_prefix_stays_out_of_finish_tail` | 验证缓冲前缀不进入 finish tail |
| `assistant_message_stream_parsers_seed_plan_parser_across_added_and_delta_boundaries` | 验证计划解析器跨添加和增量边界 |

### 2.11 限流与 Token 测试

| 测试函数 | 目的 |
|---------|------|
| `set_rate_limits_retains_previous_credits` | 验证设置限流时保留之前的 credits |
| `set_rate_limits_updates_plan_type_when_present` | 验证存在时更新 plan_type |

### 2.12 网络代理测试

| 测试函数 | 目的 |
|---------|------|
| `start_managed_network_proxy_applies_execpolicy_network_rules` | 验证启动托管网络代理时应用 execpolicy 网络规则 |
| `start_managed_network_proxy_ignores_invalid_execpolicy_network_rules` | 验证忽略无效的 execpolicy 网络规则 |
| `validated_network_policy_amendment_host_allows_normalized_match` | 验证归一化主机匹配允许 |
| `validated_network_policy_amendment_host_rejects_mismatch` | 验证主机不匹配时拒绝 |

### 2.13 连接器与提及测试

| 测试函数 | 目的 |
|---------|------|
| `filter_connectors_for_input_skips_duplicate_slug_mentions` | 验证过滤输入中的重复 slug 提及 |
| `filter_connectors_for_input_skips_when_skill_name_conflicts` | 验证技能名称冲突时跳过 |
| `filter_connectors_for_input_skips_disabled_connectors` | 验证跳过后禁用的连接器 |
| `collect_explicit_app_ids_from_skill_items_includes_linked_mentions` | 验证从技能项中收集显式应用 ID |
| `collect_explicit_app_ids_from_skill_items_resolves_unambiguous_plain_mentions` | 验证解析无歧义的纯文本提及 |
| `collect_explicit_app_ids_from_skill_items_skips_plain_mentions_with_skill_conflicts` | 验证技能冲突时跳过纯文本提及 |

### 2.14 关闭与清理测试

| 测试函数 | 目的 |
|---------|------|
| `shutdown_and_wait_allows_multiple_waiters` | 验证关闭等待允许多个等待者 |
| `shutdown_and_wait_waits_when_shutdown_is_already_in_progress` | 验证关闭进行中时等待 |
| `shutdown_and_wait_shuts_down_cached_guardian_subagent` | 验证关闭缓存的 guardian 子代理 |
| `shutdown_and_wait_shuts_down_tracked_ephemeral_guardian_review` | 验证关闭追踪的临时 guardian 审查 |

### 2.15 任务中止与生命周期测试

| 测试函数 | 目的 |
|---------|------|
| `abort_regular_task_emits_turn_aborted_only` | 验证中止常规任务仅发出 TurnAborted |
| `abort_gracefully_emits_turn_aborted_only` | 验证优雅中止仅发出 TurnAborted |
| `abort_review_task_emits_exited_then_aborted_and_records_history` | 验证审查任务中止发出 ExitedReviewMode 然后 TurnAborted |
| `task_finish_emits_turn_item_lifecycle_for_leftover_pending_user_input` | 验证任务完成时为剩余待处理用户输入发出 turn item 生命周期事件 |

### 2.16 Steer Input 测试

| 测试函数 | 目的 |
|---------|------|
| `steer_input_requires_active_turn` | 验证 steer_input 需要活动 turn |
| `steer_input_enforces_expected_turn_id` | 验证强制执行预期的 turn_id |
| `steer_input_returns_active_turn_id` | 验证返回活动 turn_id |
| `prepend_pending_input_keeps_older_tail_ahead_of_newer_input` | 验证前置待处理输入保持旧尾部在新输入之前 |

### 2.17 图像生成测试

| 测试函数 | 目的 |
|---------|------|
| `handle_output_item_done_records_image_save_history_message` | 验证处理输出项完成时记录图像保存历史消息 |
| `handle_output_item_done_skips_image_save_message_when_save_fails` | 验证保存失败时跳过图像保存消息 |
| `build_initial_context_omits_default_image_save_location_with_image_history` | 验证有图像历史时省略默认图像保存位置 |
| `build_initial_context_omits_default_image_save_location_without_image_history` | 验证无图像历史时省略默认图像保存位置 |

### 2.18 基础指令测试

| 测试函数 | 目的 |
|---------|------|
| `get_base_instructions_no_user_content` | 验证获取基础指令不包含用户内容 |

### 2.19 技能与角色测试

| 测试函数 | 目的 |
|---------|------|
| `new_default_turn_uses_config_aware_skills_for_role_overrides` | 验证新默认 turn 使用配置感知技能进行角色覆盖 |

### 2.20 模型切换测试

| 测试函数 | 目的 |
|---------|------|
| `turn_context_with_model_updates_model_fields` | 验证 turn_context 更新模型字段 |
| `build_initial_context_prepends_model_switch_message` | 验证初始上下文前置模型切换消息 |

### 2.21 MCP 结果转换测试

| 测试函数 | 目的 |
|---------|------|
| `prefers_structured_content_when_present` | 验证存在时优先使用结构化内容 |
| `falls_back_to_content_when_structured_is_null` | 验证结构化内容为 null 时回退到 content |
| `success_flag_reflects_is_error_true` | 验证 success 标志反映 is_error=true |
| `success_flag_true_with_no_error_and_content_used` | 验证无错误且使用内容时 success 为 true |

### 2.22 Exec 输出格式化测试

| 测试函数 | 目的 |
|---------|------|
| `includes_timed_out_message` | 验证包含超时消息 |

### 2.23 模型警告测试

| 测试函数 | 目的 |
|---------|------|
| `record_model_warning_appends_user_message` | 验证记录模型警告时追加用户消息 |

### 2.24 致命工具错误测试

| 测试函数 | 目的 |
|---------|------|
| `fatal_tool_error_stops_turn_and_reports_error` | 验证致命工具错误停止 turn 并报告错误 |

### 2.25 Op 类型测试

| 测试函数 | 目的 |
|---------|------|
| `op_kind_distinguishes_turn_ops` | 验证 op_kind 区分 turn 操作 |

### 2.26 独立 Shell 命令测试

| 测试函数 | 目的 |
|---------|------|
| `run_user_shell_command_does_not_set_reference_context_item` | 验证运行用户 shell 命令不设置 reference_context_item |

---

## 3. 具体技术实现

### 3.1 测试基础设施

#### 3.1.1 测试辅助函数

```rust
// 创建测试用 Session 和 TurnContext
pub(crate) async fn make_session_and_context() -> (Session, TurnContext)

// 创建带事件接收器的 Session 和 TurnContext
pub(crate) async fn make_session_and_context_with_rx() -> (
    Arc<Session>,
    Arc<TurnContext>,
    async_channel::Receiver<Event>,
)

// 创建带动态工具的 Session 和 TurnContext
pub(crate) async fn make_session_and_context_with_dynamic_tools_and_rx(
    dynamic_tools: Vec<DynamicToolSpec>,
) -> (Arc<Session>, Arc<TurnContext>, async_channel::Receiver<Event>)

// 构建测试配置
async fn build_test_config(codex_home: &Path) -> Config

// 创建会话配置
pub(crate) async fn make_session_configuration_for_tests() -> SessionConfiguration

// 创建测试工具运行时
fn test_tool_runtime(session: Arc<Session>, turn_context: Arc<TurnContext>) -> ToolCallRuntime

// 创建测试模型客户端会话
fn test_model_client_session() -> crate::client::ModelClientSession

// 创建连接器
fn make_connector(id: &str, name: &str) -> AppInfo

// 创建 MCP 工具
fn make_mcp_tool(
    server_name: &str,
    tool_name: &str,
    connector_id: Option<&str>,
    connector_name: Option<&str>,
) -> ToolInfo
```

#### 3.1.2 测试等待辅助函数

```rust
// 等待 ThreadRolledBack 事件
async fn wait_for_thread_rolled_back(
    rx: &async_channel::Receiver<Event>,
) -> crate::protocol::ThreadRolledBackEvent

// 等待 ThreadRollbackFailed 错误事件
async fn wait_for_thread_rollback_failed(rx: &async_channel::Receiver<Event>) -> ErrorEvent

// 附加 rollout 记录器
async fn attach_rollout_recorder(session: &Arc<Session>) -> PathBuf
```

#### 3.1.3 测试数据构造辅助函数

```rust
// 创建用户消息
fn user_message(text: &str) -> ResponseItem

// 创建助手消息
fn assistant_message(text: &str) -> ResponseItem

// 创建技能消息
fn skill_message(text: &str) -> ResponseItem

// 创建文本块
fn text_block(s: &str) -> serde_json::Value

// 从输出中提取文本工具输出
fn expect_text_tool_output(output: &FunctionToolOutput) -> String

// 从开发者输入文本中提取
fn developer_input_texts(items: &[ResponseItem]) -> Vec<&str>

// 创建示例 rollout
async fn sample_rollout(
    session: &Session,
    _turn_context: &TurnContext,
) -> (Vec<RolloutItem>, Vec<ResponseItem>)
```

### 3.2 核心数据结构

#### 3.2.1 测试用例结构

```rust
struct InstructionsTestCase {
    slug: &'static str,
    expects_apply_patch_instructions: bool,
}
```

#### 3.2.2 永不结束的任务（用于测试中止）

```rust
#[derive(Clone, Copy)]
struct NeverEndingTask {
    kind: TaskKind,
    listen_to_cancellation_token: bool,
}

#[async_trait::async_trait]
impl SessionTask for NeverEndingTask {
    fn kind(&self) -> TaskKind { ... }
    fn span_name(&self) -> &'static str { ... }
    async fn run(...) -> Option<String> { ... }
}
```

### 3.3 关键测试模式

#### 3.3.1 事件驱动测试模式

```rust
// 典型的事件断言模式
let evt = tokio::time::timeout(std::time::Duration::from_secs(2), rx.recv())
    .await
    .expect("timeout waiting for event")
    .expect("event");
    
match evt.msg {
    EventMsg::TurnAborted(e) => assert_eq!(TurnAbortReason::Interrupted, e.reason),
    other => panic!("unexpected event: {other:?}"),
}
```

#### 3.3.2 状态验证模式

```rust
// 历史记录验证
let history = session.clone_history().await;
assert_eq!(expected, history.raw_items());

// Token 信息验证
let actual = session.state.lock().await.token_info();
assert_eq!(actual, Some(info2));
```

#### 3.3.3 Rollout 验证模式

```rust
// 读取 rollout 历史并验证
let InitialHistory::Resumed(resumed) = RolloutRecorder::get_rollout_history(&rollout_path)
    .await
    .expect("read rollout history")
else {
    panic!("expected resumed rollout history");
};
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心被测试文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/codex.rs` | Codex 和 Session 的主实现 |
| `codex-rs/core/src/state/session.rs` | SessionState 实现 |
| `codex-rs/core/src/state/turn.rs` | ActiveTurn 和 RunningTask 实现 |
| `codex-rs/core/src/tasks/mod.rs` | SessionTask trait 和任务管理 |
| `codex-rs/core/src/context_manager/mod.rs` | 上下文管理 |
| `codex-rs/core/src/rollout/recorder.rs` | RolloutRecorder 实现 |

### 4.2 依赖协议文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/protocol/mod.rs` | Event、EventMsg、Op 等协议类型 |
| `codex-rs/protocol/src/models.rs` | ResponseItem、ContentItem 等模型类型 |
| `codex-rs/protocol/src/request_permissions.rs` | 权限请求相关类型 |

### 4.3 关键代码路径

#### 4.3.1 Session 创建路径

```
Codex::spawn -> Codex::spawn_internal -> Session::new
```

#### 4.3.2 Turn 执行路径

```
Session::spawn_task -> SessionTask::run -> Session::on_task_finished
```

#### 4.3.3 历史记录重建路径

```
Session::record_initial_history -> Session::apply_rollout_reconstruction 
  -> Session::reconstruct_history_from_rollout -> Session::replace_history
```

#### 4.3.4 线程回滚路径

```
handlers::thread_rollback -> RolloutRecorder::get_rollout_history 
  -> Session::replace_history -> Session::set_previous_turn_settings
```

#### 4.3.5 上下文更新路径

```
Session::record_context_updates_and_set_reference_context_item
  -> Session::build_initial_context / Session::build_settings_update_items
  -> Session::record_conversation_items
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖模块

```
codex_tests.rs
├── codex.rs (被测试对象)
├── state/ (SessionState, ActiveTurn)
├── tasks/ (SessionTask, RegularTask, ReviewTask, etc.)
├── tools/ (ToolRouter, ToolCallRuntime)
├── rollout/ (RolloutRecorder)
├── context_manager/ (ContextManager)
├── config/ (Config, SessionConfiguration)
├── models_manager/ (ModelsManager)
├── mcp_connection_manager/ (McpConnectionManager)
├── skills/ (SkillsManager)
├── plugins/ (PluginsManager)
└── guardian/ (GuardianReviewSessionManager)
```

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | 协议类型（Event、ResponseItem、Op 等） |
| `codex_app_server_protocol` | 应用服务器协议 |
| `codex_execpolicy` | 执行策略 |
| `codex_network_proxy` | 网络代理 |
| `codex_otel` | OpenTelemetry 追踪 |
| `codex_rmcp_client` | MCP 客户端 |
| `tokio` | 异步运行时 |
| `async_channel` | 异步通道 |
| `tokio_util` | 异步工具 |
| `serde_json` | JSON 序列化 |
| `tempfile` | 临时文件 |
| `pretty_assertions` | 美观的断言输出 |

### 5.3 测试专用依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::tempdir()` | 创建临时目录用于测试配置 |
| `tokio::time::timeout` | 测试超时控制 |
| `async_channel::unbounded` | 测试事件接收 |
| `Arc<Session>` | 共享会话所有权 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试时序风险

- **风险**: 部分测试依赖 `tokio::time::timeout` 和事件顺序，在慢速 CI 环境可能 flaky
- **缓解**: 使用较长的超时（通常 2-5 秒），使用 `test_log::test` 记录详细日志

#### 6.1.2 并发测试风险

- **风险**: `#[tokio::test(flavor = "multi_thread")]` 测试可能因并发执行产生竞争条件
- **缓解**: 每个测试使用独立的临时目录和会话 ID

#### 6.1.3 平台差异风险

- **风险**: 部分测试使用平台特定命令（如 `cmd.exe` vs `/bin/sh`）
- **缓解**: 使用 `cfg!(windows)` 条件编译区分平台

### 6.2 边界条件

#### 6.2.1 历史记录边界

- 空历史记录处理
- 压缩后历史记录重建
- 大量 turns（>1000）的回滚性能

#### 6.2.2 Token 计数边界

- 超大上下文窗口（>200K tokens）
- Token 计数溢出处理
- 负 token 计数（缓存输入计算）

#### 6.2.3 权限边界

- 细粒度权限策略的所有组合
- 权限请求超时处理
- 并发权限请求

### 6.3 改进建议

#### 6.3.1 测试覆盖率

1. **增加故障注入测试**: 当前测试主要覆盖正常路径，建议增加网络故障、磁盘满等异常场景
2. **增加性能基准测试**: 对历史重建、rollout 读写等关键路径增加性能测试
3. **增加模糊测试**: 对输入解析、JSON 序列化等增加模糊测试

#### 6.3.2 测试组织

1. **模块化测试**: 考虑将测试按功能拆分为多个文件（如 `codex_tests_turn.rs`、`codex_tests_rollback.rs`）
2. **测试 fixtures**: 提取通用的测试数据构造为 fixtures
3. **参数化测试**: 使用 `test_case` crate 减少重复测试代码

#### 6.3.3 测试可维护性

1. **文档化测试意图**: 为复杂测试增加更多注释说明测试意图
2. **统一错误消息**: 标准化 panic 和 assert 的错误消息格式
3. **减少测试耦合**: 部分测试依赖具体实现细节，建议增加抽象层

#### 6.3.4 特定改进点

| 区域 | 建议 |
|------|------|
| Thread Rollback | 增加并发回滚测试 |
| MCP 工具 | 增加 MCP 服务器故障恢复测试 |
| Realtime | 增加网络抖动下的实时对话测试 |
| Token 计数 | 增加大文件处理的 token 估算精度测试 |
| 权限审批 | 增加审批超时和取消场景测试 |

### 6.4 技术债务

1. **TODO 标记**: 文件中存在 `// todo: use online model info` 等 TODO 标记
2. **测试配置重复**: `make_session_and_context` 和 `make_session_and_context_with_rx` 有大量重复代码
3. **硬编码值**: 部分测试使用硬编码的模型名称（如 "gpt-5.1"），建议参数化

---

## 7. 总结

`codex_tests.rs` 是 `codex-core` crate 的核心测试文件，包含约 130+ 个测试用例，全面覆盖了 Codex 会话管理、Turn 执行、历史记录、权限审批、MCP 工具、实时对话等核心功能。测试采用异步 Tokio 运行时，使用事件驱动和状态验证相结合的方式进行断言。

该测试文件对于保障 Codex AI 助手的稳定性和正确性至关重要，任何对核心功能的修改都应确保相关测试通过，并在必要时添加新的测试用例。
