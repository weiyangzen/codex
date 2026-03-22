# Memories Pipeline (Core) - 研究文档

## 场景与职责

`codex-rs/core/src/memories/` 模块实现了 Codex 的启动记忆管道（Startup Memory Pipeline），这是一个两阶段的异步后台系统，用于从历史会话中提取结构化记忆并整合到文件系统工件中。

### 核心职责

1. **Phase 1 (Rollout Extraction)**: 从最近的合格 rollouts 中提取结构化记忆
2. **Phase 2 (Global Consolidation)**: 将 stage-1 输出整合到文件系统记忆工件中
3. **记忆生命周期管理**: 包括记忆存储、引用追踪、使用统计和过期清理

### 触发条件

记忆管道仅在以下所有条件满足时触发：
- 会话不是临时的（non-ephemeral）
- 记忆功能已启用（`MemoryTool` feature flag）
- 会话不是子代理会话
- 状态数据库可用

## 功能点目的

### 1. Phase 1: Rollout Extraction

**目的**: 将原始会话 rollouts 转换为结构化的记忆记录

**关键功能**:
- 从状态数据库中声明符合条件的 rollout 作业（claim）
- 过滤 rollout 内容，仅保留与记忆相关的响应项
- 使用 LLM（默认 `gpt-5.1-codex-mini`）并行处理多个 rollouts
- 生成结构化输出：`raw_memory`、`rollout_summary`、`rollout_slug`
- 从生成的记忆字段中编辑敏感信息（secrets redaction）
- 将成功的输出存储回状态数据库作为 stage-1 输出

**作业结果分类**:
- `succeeded`: 成功生成记忆
- `succeeded_no_output`: 有效运行但未生成有用内容
- `failed`: 失败（带重试退避/租约处理）

### 2. Phase 2: Global Consolidation

**目的**: 将 stage-1 输出整合到文件系统记忆工件中

**关键功能**:
- 声明单个全局 phase-2 作业锁（确保只有一个整合进程运行）
- 从状态数据库加载有限的 stage-1 输出集合
- 计算完成水印（watermark）
- 同步本地记忆工件：`raw_memories.md`、`rollout_summaries/`
- 清理不再保留的陈旧 rollout 摘要
- 生成整合提示并启动内部整合子代理
- 监控代理状态并在运行时心跳全局作业租约

### 3. 记忆文件布局

```
$CODEX_HOME/memories/
├── raw_memories.md          # 合并的原始记忆（最新优先）
├── MEMORY.md                # 可搜索的记忆注册表
├── memory_summary.md        # 用户画像和偏好摘要
├── rollout_summaries/       # 每个保留 rollout 的摘要文件
│   └── {timestamp}-{hash}-{slug}.md
└── skills/                  # 可重用技能包
    └── {skill-name}/
        ├── SKILL.md
        ├── scripts/
        ├── templates/
        └── examples/
```

## 具体技术实现

### 模块结构

```
codex-rs/core/src/memories/
├── mod.rs              # 模块入口，常量定义，路径辅助函数
├── README.md           # 架构文档
├── start.rs            # 启动入口点，条件检查
├── phase1.rs           # Phase 1 实现（rollout 提取）
├── phase1_tests.rs     # Phase 1 单元测试
├── phase2.rs           # Phase 2 实现（全局整合）
├── storage.rs          # 文件系统工件管理
├── storage_tests.rs    # 存储单元测试
├── prompts.rs          # 提示模板构建
├── prompts_tests.rs    # 提示单元测试
├── citations.rs        # 记忆引用解析
├── citations_tests.rs  # 引用解析测试
├── control.rs          # 记忆根目录清理控制
├── usage.rs            # 记忆使用统计
└── tests.rs            # 集成测试
```

### Phase 1 关键流程

```rust
// phase1.rs 核心流程
pub async fn run(session: &Arc<Session>, config: &Config) {
    // 1. 声明启动作业
    let claimed_candidates = claim_startup_jobs(session, &config.memories).await?;
    
    // 2. 构建请求上下文（模型信息、遥测等）
    let stage_one_context = build_request_context(session, config).await;
    
    // 3. 并行运行提取作业（并发限制：8）
    let outcomes = run_jobs(session, claimed_candidates, stage_one_context).await;
    
    // 4. 聚合统计并发出指标
    let counts = aggregate_stats(outcomes);
    emit_metrics(session, &counts);
}
```

**作业执行细节** (`job::run`):
1. 加载 rollout 项目 (`RolloutRecorder::load_rollout_items`)
2. 序列化过滤后的响应项（移除开发者消息、AGENTS.md 指令等）
3. 构建提示（系统提示 + 用户输入）
4. 流式调用模型 API
5. 解析 JSON 输出并编辑 secrets
6. 根据结果标记作业状态

### Phase 2 关键流程

```rust
// phase2.rs 核心流程
pub async fn run(session: &Arc<Session>, config: Arc<Config>) {
    // 1. 声明全局作业
    let claim = job::claim(session, db).await?;
    
    // 2. 获取代理配置
    let agent_config = agent::get_config(config.clone())?;
    
    // 3. 查询记忆选择
    let selection = db.get_phase2_input_selection(max_raw_memories, max_unused_days).await?;
    
    // 4. 同步文件系统工件
    sync_rollout_summaries_from_memories(&root, &artifact_memories, ...).await?;
    rebuild_raw_memories_file_from_memories(&root, &artifact_memories, ...).await?;
    
    // 5. 生成提示并生成子代理
    let prompt = agent::get_prompt(config, &selection);
    let thread_id = session.services.agent_control.spawn_agent(...).await?;
    
    // 6. 处理代理生命周期
    agent::handle(session, claim, new_watermark, raw_memories, thread_id, timer);
}
```

### 存储实现

**文件名生成算法** (`storage.rs`):

```rust
pub fn rollout_summary_file_stem_from_parts(
    thread_id: ThreadId,
    source_updated_at: DateTime<Utc>,
    rollout_slug: Option<&str>,
) -> String {
    // 1. 从 UUID 提取时间戳（如果可用）
    // 2. 生成 4 字符短哈希（基于 UUID 或 source_updated_at）
    // 3. 格式：{timestamp}-{short_hash}[-{sanitized_slug}]
    // 4. slug 清理：小写、替换非字母数字为下划线、截断至 60 字符
}
```

### 提示模板

使用 Askama 模板引擎，模板位于 `codex-rs/core/templates/memories/`:

1. **stage_one_system.md**: Phase 1 系统提示（569 行详细指令）
2. **stage_one_input.md**: Phase 1 用户输入模板
3. **consolidation.md**: Phase 2 整合提示（835 行详细指令）
4. **read_path.md**: 记忆工具开发者指令模板

### 引用解析

```rust
// citations.rs
pub fn parse_memory_citation(citations: Vec<String>) -> Option<MemoryCitation> {
    // 解析 <citation_entries> 和 <rollout_ids>/<thread_ids> 块
    // 返回 MemoryCitation { entries, rollout_ids }
}
```

## 关键代码路径与文件引用

### 启动入口

```
codex::codex::Session::start_memories_startup_task
  └─> memories::start::start_memories_startup_task (start.rs:14)
      ├─> phase1::prune (phase1.rs:126)
      ├─> phase1::run (phase1.rs:86)
      └─> phase2::run (phase2.rs:43)
```

### Phase 1 代码路径

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 作业声明 | phase1.rs | `claim_startup_jobs` (180) |
| 请求构建 | phase1.rs | `build_request_context` (222) |
| 并行执行 | phase1.rs | `run_jobs` (241) |
| 单个作业 | phase1.rs | `job::run` (260) |
| 采样 | phase1.rs | `job::sample` (313) |
| 结果处理 | phase1.rs | `job::result::*` (392) |
| 序列化 | phase1.rs | `serialize_filtered_rollout_response_items` (467) |
| 统计聚合 | phase1.rs | `aggregate_stats` (524) |
| 指标发出 | phase1.rs | `emit_metrics` (554) |

### Phase 2 代码路径

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 作业声明 | phase2.rs | `job::claim` (182) |
| 代理配置 | phase2.rs | `agent::get_config` (265) |
| 提示生成 | phase2.rs | `agent::get_prompt` (312) |
| 代理处理 | phase2.rs | `agent::handle` (325) |
| 代理循环 | phase2.rs | `agent::loop_agent` (394) |
| 水印计算 | phase2.rs | `get_watermark` (446) |

### 存储代码路径

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 重建 raw_memories | storage.rs | `rebuild_raw_memories_file_from_memories` (13) |
| 同步 rollout 摘要 | storage.rs | `sync_rollout_summaries_from_memories` (23) |
| 清理 rollout 摘要 | storage.rs | `prune_rollout_summaries` (98) |
| 写入单个摘要 | storage.rs | `write_rollout_summary_for_thread` (128) |
| 文件名生成 | storage.rs | `rollout_summary_file_stem_from_parts` (179) |

### 提示构建代码路径

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 整合提示 | prompts.rs | `build_consolidation_prompt` (38) |
| 渲染选择 | prompts.rs | `render_phase2_input_selection` (56) |
| Stage 1 输入 | prompts.rs | `build_stage_one_input_message` (127) |
| 开发者指令 | prompts.rs | `build_memory_tool_developer_instructions` (158) |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::Session` | 会话上下文、服务访问 |
| `crate::config::Config` | 配置参数（模型、内存限制等） |
| `crate::features::Feature` | 功能标志检查（`MemoryTool`） |
| `crate::rollout::RolloutRecorder` | Rollout 加载和序列化 |
| `crate::truncate` | 文本截断（token 限制） |
| `crate::agent::AgentControl` | 子代理生成和监控 |
| `codex_state::StateRuntime` | 数据库操作（作业声明、状态更新） |
| `codex_protocol` | 类型定义（ThreadId、ResponseItem 等） |
| `codex_secrets` | Secrets 编辑 |
| `codex_otel` | 遥测和指标 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio::fs` | 异步文件系统操作 |
| `sqlx` | SQLite 数据库交互 |
| `askama` | 模板渲染 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `chrono` | 时间戳处理 |
| `uuid` | UUID 生成和解析 |
| `tracing` | 日志记录 |
| `futures` | 流处理 |

### 数据库表

| 表 | 用途 |
|----|------|
| `threads` | 线程元数据 |
| `stage1_outputs` | Stage-1 记忆输出 |
| `jobs` | 作业状态（stage-1 和 phase-2） |

### 作业类型常量

```rust
// codex-rs/state/src/runtime/memories.rs
const JOB_KIND_MEMORY_STAGE1: &str = "memory_stage1";
const JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL: &str = "memory_consolidate_global";
const MEMORY_CONSOLIDATION_JOB_KEY: &str = "global";
```

## 风险、边界与改进建议

### 已知风险

1. **并发竞争**:
   - Phase 2 的 `loop_agent` 中存在潜在的微小竞争条件（TODO 注释）
   - 多个并发 Phase 1 作业通过数据库租约协调，但依赖时钟同步

2. **资源限制**:
   - Phase 1 默认 rollout token 限制：150,000 tokens
   - Phase 1 上下文窗口使用：70% 的有效窗口
   - 默认并发限制：8 个并行作业

3. **数据一致性**:
   - 文件系统工件和数据库状态可能暂时不一致（异步同步）
   - 水印机制防止倒退，但可能延迟新数据的处理

4. **安全性**:
   - `clear_memory_root_contents` 拒绝符号链接根目录（防止意外删除）
   - Secrets 编辑依赖 `codex_secrets::redact_secrets`，可能有遗漏

### 边界条件

1. **空记忆处理**:
   - 当没有 stage-1 输出时，Phase 2 仍会清理陈旧工件并标记成功
   - 空整合会删除 `MEMORY.md`、`memory_summary.md` 和 `skills/` 目录

2. **重试机制**:
   - 默认重试剩余次数：3 次
   - 默认重试延迟：3,600 秒
   - 租约过期：3,600 秒（Phase 1 和 Phase 2）

3. **保留策略**:
   - 默认最大未使用天数：30 天
   - 默认最大 rollout 年龄：30 天
   - 默认最小 rollout 空闲时间：1 小时

### 改进建议

1. **可观测性**:
   - 添加更多细粒度的 span 和事件用于分布式追踪
   - 考虑添加记忆质量指标（不仅仅是数量）

2. **性能优化**:
   - Phase 1 的 `serialize_filtered_rollout_response_items` 可能在大 rollouts 上内存密集
   - 考虑流式处理或分块处理大文件

3. **错误处理**:
   - 某些错误路径仅记录警告而不传播，可能掩盖问题
   - 考虑添加结构化错误类型而非字符串原因

4. **配置灵活性**:
   - 许多常量是硬编码的（如 `THREAD_SCAN_LIMIT = 5_000`）
   - 考虑将这些暴露为配置选项

5. **测试覆盖**:
   - Phase 2 的代理生命周期测试主要依赖模拟
   - 考虑添加更多端到端集成测试

6. **文档**:
   - 模板文件（`stage_one_system.md`、`consolidation.md`）包含大量指令
   - 考虑添加版本控制或校验和以检测模板漂移
