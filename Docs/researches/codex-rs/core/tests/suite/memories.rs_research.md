# memories.rs 研究文档

## 场景与职责

`memories.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **记忆系统（Memory System）** 的两阶段流水线功能。记忆系统负责从对话历史中提取、整合和持久化重要信息，使 Codex 能够在跨会话时保持上下文连续性。

### 核心职责
1. **验证 Phase 2 启动输入跟踪**：跟踪新增和移除的 Phase 1 输入
2. **验证 Web 搜索污染检测**：检测并处理被 Web 搜索污染的记忆
3. **测试记忆持久化**：验证原始记忆和汇总摘要正确写入文件系统
4. **验证数据库状态管理**：验证 SQLite 数据库中的记忆状态转换

---

## 功能点目的

### 1. Phase 2 启动输入跟踪测试 (`memories_startup_phase2_tracks_added_and_removed_inputs_across_runs`)
- **目的**：验证 Phase 2 启动时正确跟踪输入变化
- **测试流程**：
  1. 初始化数据库并创建 Thread A 的 Stage 1 输出
  2. 启动 Codex，验证 Phase 2 提示包含 Thread A 作为新增输入
  3. 等待 Phase 2 成功，验证文件系统写入
  4. 关闭 Codex，创建 Thread B 的 Stage 1 输出
  5. 重新启动 Codex，验证 Phase 2 提示包含 Thread B 作为新增、Thread A 作为移除

- **关键验证点**：
  - 提示文本包含 `selected inputs this run`、`newly added`、`removed` 统计
  - 原始记忆写入 `memories/raw_memories.md`
  - 汇总摘要写入 `memories/rollout_summaries/`
  - 数据库状态正确更新

### 2. Web 搜索污染测试 (`web_search_pollution_moves_selected_thread_into_removed_phase2_inputs`)
- **目的**：验证当会话使用 Web 搜索时，相关记忆被标记为污染并从选择中移除
- **测试流程**：
  1. 创建初始会话并生成 Stage 1 输出
  2. 关闭 Codex，模拟会话使用 Web 搜索
  3. 重新启动 Codex，验证初始选择包含该会话
  4. 提交 Web 搜索查询
  5. 验证会话被标记为 `polluted` 记忆模式
  6. 验证会话从 Phase 2 选择中移除

- **关键验证点**：
  - `memory_mode` 字段变为 `"polluted"`
  - `Phase2InputSelection` 中会话进入 `removed` 列表
  - `selected` 和 `retained_thread_ids` 为空

---

## 具体技术实现

### 关键数据结构

#### Phase2InputSelection

```rust
pub struct Phase2InputSelection {
    pub selected: Vec<Stage1Output>,
    pub retained_thread_ids: Vec<ThreadId>,
    pub removed: Vec<Stage1Output>,
}
```

#### Stage1Output

```rust
pub struct Stage1Output {
    pub thread_id: ThreadId,
    pub source_updated_at: i64,
    pub raw_memory: String,
    pub rollout_summary: String,
    pub rollout_slug: Option<String>,
    // ...
}
```

### 测试基础设施

#### 数据库初始化

```rust
async fn init_state_db(home: &Arc<TempDir>) -> Result<Arc<codex_state::StateRuntime>> {
    let db = codex_state::StateRuntime::init(
        home.path().to_path_buf(),
        "test-provider".into()
    ).await?;
    db.mark_backfill_complete(None).await?;
    Ok(db)
}
```

#### Stage 1 输出种子数据

```rust
async fn seed_stage1_output(
    db: &codex_state::StateRuntime,
    codex_home: &Path,
    updated_at: chrono::DateTime<Utc>,
    raw_memory: &str,
    rollout_summary: &str,
    rollout_slug: &str,
) -> Result<ThreadId> {
    let thread_id = ThreadId::new();
    let metadata = codex_state::ThreadMetadataBuilder::new(
        thread_id,
        codex_home.join(format!("rollout-{thread_id}.jsonl")),
        updated_at,
        SessionSource::Cli,
    )
    .with_cwd(codex_home.join(format!("workspace-{rollout_slug}")))
    .with_git_branch(format!("branch-{rollout_slug}"))
    .build("test-provider");
    
    db.upsert_thread(&metadata).await?;
    
    // 创建 Stage 1 作业并标记成功
    let claim = db.try_claim_stage1_job(thread_id, owner, updated_at.timestamp(), 3_600, 64).await?;
    db.mark_stage1_job_succeeded(
        thread_id,
        &ownership_token,
        updated_at.timestamp(),
        raw_memory,
        rollout_summary,
        Some(rollout_slug),
    ).await?;
    
    Ok(thread_id)
}
```

#### Phase 2 提示文本提取

```rust
fn phase2_prompt_text(request: &ResponsesRequest) -> String {
    request
        .message_input_texts("user")
        .into_iter()
        .find(|text| text.contains("Current selected Phase 1 inputs:"))
        .expect("phase2 prompt text")
}
```

#### Phase 2 成功等待

```rust
async fn wait_for_phase2_success(
    db: &codex_state::StateRuntime,
    expected_thread_id: ThreadId,
) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let selection = db.get_phase2_input_selection(1, 30).await?;
        if selection.selected.len() == 1
            && selection.selected[0].thread_id == expected_thread_id
            && selection.retained_thread_ids == vec![expected_thread_id]
            && selection.removed.is_empty()
        {
            return Ok(());
        }
        assert!(Instant::now() < deadline, "timed out");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}
```

### 配置设置

```rust
let mut builder = test_codex().with_home(home.clone()).with_config(|config| {
    config.features.enable(Feature::Sqlite).expect("...");
    config.features.enable(Feature::MemoryTool).expect("...");
    config.memories.max_raw_memories_for_consolidation = 1;
    config.memories.no_memories_if_mcp_or_web_search = true;
});
```

### 污染检测配置

```rust
config.memories.no_memories_if_mcp_or_web_search = true;
```

当此配置启用时，使用 Web 搜索的会话会被标记为污染。

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/memories.rs` (479 行)

### 记忆系统实现
- **`codex-rs/core/src/memories/`**：记忆系统核心实现
- **`codex-rs/core/src/memories/phase2.rs`**：Phase 2 流水线
- **`codex-rs/core/src/memories/prompts.rs`**：Phase 2 提示生成

### 状态数据库
- **`codex-rs/state/src/lib.rs`**：StateRuntime 定义
- **`codex-rs/state/src/runtime/memories.rs`**：记忆相关数据库操作
- **`codex-rs/state/src/model/memories.rs`**：记忆数据模型

### 协议定义
- **`codex-rs/protocol/src/protocol.rs`**：
  - `EventMsg::TurnComplete`
  - `Op::UserTurn`

### 测试支持库
- **`codex-rs/core/tests/common/responses.rs`**：
  - `mount_sse_sequence`：顺序响应 Mock
  - `ev_response_created`、`ev_assistant_message`、`ev_completed`：事件构造
- **`codex-rs/core/tests/common/test_codex.rs`**：
  - `TestCodex` 结构体
  - `session_configured.rollout_path`

---

## 依赖与外部交互

### 外部依赖
1. **wiremock**：HTTP Mock 服务器
2. **tokio**：异步运行时
3. **sqlx**：SQLite 数据库访问
4. **chrono**：日期时间处理
5. **tempfile**：临时目录管理

### 内部依赖
1. **codex_core**：核心库（Config、Features、ThreadManager）
2. **codex_protocol**：协议类型（ThreadId、SessionSource）
3. **codex_state**：状态数据库（StateRuntime、Phase2InputSelection）
4. **core_test_support**：测试支持库

### 文件系统交互
- 创建 `memories/raw_memories.md`
- 创建 `memories/rollout_summaries/{thread_id}.md`
- 读取和写入 SQLite 数据库

---

## 风险、边界与改进建议

### 已知风险

1. **时序敏感性**：
   - 使用轮询等待数据库状态更新
   - 10 秒超时可能导致不稳定测试

2. **数据库状态依赖**：
   - 测试间共享数据库状态
   - 需要仔细的清理和设置

3. **复杂设置**：
   - 测试需要大量前置设置（数据库、文件、Mock）
   - 维护成本较高

### 边界情况

1. **并发会话**：
   - 当前测试未覆盖多会话并发修改记忆
   - 建议增加并发测试

2. **记忆冲突**：
   - 多个会话修改相同记忆的场景
   - 建议增加冲突解决测试

3. **大记忆内容**：
   - 当前测试使用小记忆内容
   - 建议增加大内容性能测试

4. **数据库损坏**：
   - 当前测试未覆盖数据库损坏恢复
   - 建议增加容错测试

### 改进建议

1. **增加测试覆盖**：
   - 测试记忆合并冲突解决
   - 测试记忆删除场景
   - 测试记忆版本迁移
   - 测试数据库备份和恢复

2. **性能优化**：
   - 大量记忆的加载性能
   - 频繁更新的写入性能

3. **可靠性改进**：
   - 增加事务重试机制
   - 增加状态一致性检查

4. **监控和调试**：
   - 增加记忆系统指标
   - 提供记忆状态查询工具

5. **文档改进**：
   - 提供记忆系统架构图
   - 说明 Phase 1 和 Phase 2 的详细流程
   - 提供故障排除指南

### 相关测试

- **`codex-rs/core/tests/suite/sqlite_state.rs`**：SQLite 状态数据库测试
