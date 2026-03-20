# DIR Research: codex-rs/core/src/memories

## 场景与职责

`codex-rs/core/src/memories` 是 Codex 智能体的**记忆子系统**，负责实现跨会话的长期记忆功能。该模块通过两阶段流水线（Phase 1 + Phase 2）自动从历史会话（rollouts）中提取、整理和固化有价值的记忆，帮助未来的智能体：

- 深入理解用户偏好，减少重复指令
- 复用已验证的工作流程和检查清单
- 避免已知的陷阱和失败模式
- 提高解决类似任务的效率

**触发条件**：当根会话启动时，如果满足以下条件则自动触发：
- 会话非临时性（非 ephemeral）
- MemoryTool 功能已启用
- 不是子代理会话
- State DB 可用

## 功能点目的

### 1. Phase 1: Rollout 提取（每线程）

**目的**：从最近的合格 rollouts 中提取结构化记忆。

**合格 rollout 的筛选条件**：
- 来自允许的交互式会话源（INTERACTIVE_SESSION_SOURCES）
- 在配置的年龄窗口内（max_rollout_age_days，默认30天）
- 已空闲足够时间（min_rollout_idle_hours，默认6小时）
- 未被其他正在运行的 Phase 1 worker 占用
- 在启动扫描/声明限制范围内（max_rollouts_per_startup，默认16个）

**输出**：
- `raw_memory`: 详细的原始记忆（Markdown格式）
- `rollout_summary`: 紧凑的摘要行，用于路由和索引
- `rollout_slug`: 可选的短标识符，用于文件名生成

### 2. Phase 2: 全局整合（Consolidation）

**目的**：将 Stage 1 的输出整合到文件系统记忆产物中，并运行专门的整合代理。

**产物**：
- `raw_memories.md`: 合并的原始记忆（最新优先）
- `rollout_summaries/`: 每个保留 rollout 的摘要文件
- `MEMORY.md`: 可检索的记忆手册
- `memory_summary.md`: 用户画像和偏好摘要
- `skills/`: 可复用的技能包

### 3. 记忆使用追踪

**目的**：追踪记忆的使用情况，用于：
- 记录 `usage_count` 和 `last_usage` 时间戳
- 支持基于使用频率的 Phase 2 选择排序
- 清理长期未使用的记忆（max_unused_days，默认30天）

## 具体技术实现

### 关键流程

#### Phase 1 流程 (`phase1.rs`)

```
1. claim_startup_jobs() - 从 State DB 声明启动任务
   - 查询符合条件的线程
   - 使用 lease 机制防止重复处理
   
2. build_request_context() - 构建请求上下文
   - 使用 gpt-5.1-codex-mini 模型（可配置）
   - Low reasoning effort
   
3. run_jobs() - 并行运行提取任务（并发限制：8）
   - 加载 rollout 内容
   - 过滤记忆相关的响应项
   - 调用模型提取记忆
   - 使用 JSON schema 约束输出
   - 敏感信息脱敏（redact_secrets）
   
4. 标记任务结果
   - succeeded: 成功提取记忆
   - succeeded_no_output: 有效运行但无有用输出
   - failed: 失败，进入重试退避
```

#### Phase 2 流程 (`phase2.rs`)

```
1. job::claim() - 声明全局 Phase 2 任务
   - 单例锁确保只有一个整合任务运行
   - 检查 watermark 确定是否需要运行
   
2. agent::get_config() - 构建子代理配置
   - 禁用 Collab 和 MemoryTool（防止递归）
   - 设置 WorkspaceWrite 沙箱策略（仅 codex_home 可写）
   - 使用 gpt-5.3-codex 模型（可配置）
   
3. db.get_phase2_input_selection() - 获取输入选择
   - 按 usage_count 和 last_usage 排序
   - 计算 added/retained/removed 差异
   
4. sync_rollout_summaries_from_memories() - 同步产物
   - 重建 raw_memories.md
   - 更新 rollout_summaries/ 目录
   - 清理过时的产物
   
5. agent::spawn() - 启动整合子代理
   - 注入 consolidation.md 提示词
   - 监控代理状态
   - 定期心跳保活任务租约
   
6. job::succeed/failed() - 标记任务完成
   - 更新 watermark
   - 记录选中的 stage1 输出
```

### 关键数据结构

#### Stage1Output (`codex-state/src/model/memories.rs`)

```rust
pub struct Stage1Output {
    pub thread_id: ThreadId,
    pub rollout_path: PathBuf,
    pub source_updated_at: DateTime<Utc>,
    pub raw_memory: String,
    pub rollout_summary: String,
    pub rollout_slug: Option<String>,
    pub cwd: PathBuf,
    pub git_branch: Option<String>,
    pub generated_at: DateTime<Utc>,
}
```

#### Phase2InputSelection

```rust
pub struct Phase2InputSelection {
    pub selected: Vec<Stage1Output>,      // 当前选中的记忆
    pub previous_selected: Vec<Stage1Output>, // 上次选中的记忆
    pub retained_thread_ids: Vec<ThreadId>,   // 保留的线程ID
    pub removed: Vec<Stage1OutputRef>,    // 移除的记忆引用
}
```

#### 配置项 (`config/types.rs`)

```rust
pub struct MemoriesConfig {
    pub no_memories_if_mcp_or_web_search: bool,
    pub generate_memories: bool,          // 是否生成记忆
    pub use_memories: bool,               // 是否使用记忆
    pub max_raw_memories_for_consolidation: usize, // 默认256
    pub max_unused_days: i64,             // 默认30天
    pub max_rollouts_per_startup: usize,  // 默认16
    pub max_rollout_age_days: i64,        // 默认30天
    pub min_rollout_idle_hours: i64,      // 默认6小时
    pub extract_model: Option<String>,    // Phase 1 模型
    pub consolidation_model: Option<String>, // Phase 2 模型
}
```

### 数据库表结构 (`codex-state/src/runtime/memories.rs`)

#### stage1_outputs 表

```sql
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER,
    raw_memory TEXT,
    rollout_summary TEXT,
    rollout_slug TEXT,
    generated_at INTEGER,
    usage_count INTEGER DEFAULT 0,
    last_usage INTEGER,
    selected_for_phase2 INTEGER DEFAULT 0,
    selected_for_phase2_source_updated_at INTEGER
);
```

#### jobs 表（用于任务调度）

```sql
-- memory_stage1: Phase 1 任务
-- memory_consolidate_global: Phase 2 全局整合任务

字段：kind, job_key, status, worker_id, ownership_token,
      started_at, finished_at, lease_until, retry_at,
      retry_remaining, last_error, input_watermark, last_success_watermark
```

### 提示词模板

#### Phase 1 系统提示 (`templates/memories/stage_one_system.md`)

- **核心任务**：将原始 agent rollouts 转换为有用的原始记忆和 rollout 摘要
- **最小信号门控**：如果无有价值内容，返回空字段
- **高信号记忆类型**：
  1. 稳定的用户操作偏好
  2. 高杠杆程序知识
  3. 可靠的决策触发器
  4. 关于用户环境和工作流程的持久证据
- **任务结果分类**：success/partial/uncertain/fail
- **输出格式**：JSON 对象，包含 rollout_summary、rollout_slug、raw_memory

#### Phase 2 整合提示 (`templates/memories/consolidation.md`)

- **两种模式**：
  - INIT：首次构建 Phase 2 产物
  - INCREMENTAL UPDATE：将新记忆整合到现有产物
- **产物格式**：
  - MEMORY.md：可检索的记忆手册
  - memory_summary.md：用户画像和偏好
  - skills/：可复用技能包
- **增量更新机制**：
  - 使用 diff 识别 added/retained/removed threads
  - 仅删除由 removed threads 支持的内存
  - 保留未删除 threads 的内容

#### 记忆工具开发者指令 (`templates/memories/read_path.md`)

- 指导 Agent 如何使用记忆文件夹
- 快速记忆通道：4-6 步搜索限制
- 引用格式要求：`<oai-mem-citation>` 块

## 关键代码路径与文件引用

### 核心模块文件

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块入口，定义常量、路径函数、指标名称 |
| `start.rs` | 启动任务入口 `start_memories_startup_task()` |
| `phase1.rs` | Phase 1 提取逻辑，包含 job 处理和结果标记 |
| `phase2.rs` | Phase 2 整合逻辑，包含子代理管理和产物同步 |
| `storage.rs` | 文件系统操作：raw_memories.md、rollout_summaries/ 管理 |
| `prompts.rs` | 提示词构建：consolidation、stage_one_input、memory_tool 指令 |
| `citations.rs` | 记忆引用解析：`<citation_entries>` 和 `<rollout_ids>` |
| `usage.rs` | 记忆使用指标追踪 |
| `control.rs` | 内存根目录清理工具 |
| `README.md` | 模块架构文档 |

### 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests.rs` | 集成测试：存储同步、Phase 2 调度、watermark 逻辑 |
| `phase1_tests.rs` | Phase 1 单元测试：序列化、统计聚合 |
| `storage_tests.rs` | 存储单元测试：文件名生成逻辑 |
| `prompts_tests.rs` | 提示词单元测试：输入消息截断 |
| `citations_tests.rs` | 引用解析单元测试 |

### 模板文件

| 文件 | 用途 |
|------|------|
| `templates/memories/stage_one_system.md` | Phase 1 系统提示 |
| `templates/memories/stage_one_input.md` | Phase 1 用户输入模板 |
| `templates/memories/consolidation.md` | Phase 2 整合提示 |
| `templates/memories/read_path.md` | 记忆工具开发者指令 |

### 调用入口

```rust
// codex.rs:1980
codex-rs/core/src/codex.rs:1980
memories::start_memories_startup_task(&sess, Arc::clone(&config), &session_source);

// 条件检查：非 ephemeral、MemoryTool 启用、非子代理、State DB 可用
```

### State DB 接口 (`codex-state/src/runtime/memories.rs`)

| 方法 | 用途 |
|------|------|
| `claim_stage1_jobs_for_startup()` | 声明 Phase 1 启动任务 |
| `try_claim_stage1_job()` | 尝试声明单个 Stage 1 任务 |
| `mark_stage1_job_succeeded()` | 标记 Stage 1 成功并存储输出 |
| `mark_stage1_job_succeeded_no_output()` | 标记 Stage 1 成功但无输出 |
| `mark_stage1_job_failed()` | 标记 Stage 1 失败并设置重试 |
| `try_claim_global_phase2_job()` | 声明全局 Phase 2 任务 |
| `mark_global_phase2_job_succeeded()` | 标记 Phase 2 成功 |
| `mark_global_phase2_job_failed()` | 标记 Phase 2 失败 |
| `get_phase2_input_selection()` | 获取 Phase 2 输入选择（含 diff） |
| `record_stage1_output_usage()` | 记录记忆使用 |
| `prune_stage1_outputs_for_retention()` | 清理过期记忆 |
| `clear_memory_data()` | 清除所有记忆数据 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex-state` | SQLite 数据库操作，任务调度，Stage1Output/Phase2InputSelection 类型 |
| `codex-protocol` | ThreadId、SessionSource、TokenUsage、ResponseItem 等类型 |
| `codex-otel` | SessionTelemetry，指标收集（counter/histogram/timer） |
| `crate::codex::Session` | 会话上下文，模型客户端访问 |
| `crate::config::Config` | 配置读取 |
| `crate::features::Feature` | MemoryTool 功能开关检查 |
| `crate::rollout::RolloutRecorder` | Rollout 内容加载 |
| `crate::agent::AgentControl` | 子代理生命周期管理 |
| `crate::truncate` | 文本截断（按 token 限制） |
| `codex-secrets` | 敏感信息脱敏 (`redact_secrets`) |

### 外部产物

```
~/.codex/memories/
├── raw_memories.md              # 合并的原始记忆
├── MEMORY.md                    # 记忆手册
├── memory_summary.md            # 用户画像摘要
├── rollout_summaries/           # 每 rollout 摘要
│   ├── 2025-02-11T15-35-19-jqmb.md
│   └── ...
└── skills/                      # 技能包
    └── <skill-name>/
        ├── SKILL.md
        ├── scripts/
        ├── templates/
        └── examples/
```

### 指标

| 指标名称 | 类型 | 描述 |
|----------|------|------|
| `codex.memory.phase1` | Counter | Phase 1 任务数（按状态分组） |
| `codex.memory.phase1.e2e_ms` | Timer | Phase 1 端到端延迟 |
| `codex.memory.phase1.output` | Counter | Phase 1 原始记忆输出数 |
| `codex.memory.phase1.token_usage` | Histogram | Phase 1 Token 使用分布 |
| `codex.memory.phase2` | Counter | Phase 2 任务数（按状态分组） |
| `codex.memory.phase2.e2e_ms` | Timer | Phase 2 端到端延迟 |
| `codex.memory.phase2.input` | Counter | Phase 2 输入记忆数 |
| `codex.memory.phase2.token_usage` | Histogram | Phase 2 Token 使用分布 |
| `codex.memories.usage` | Counter | 记忆文件使用次数（按类型） |

## 风险、边界与改进建议

### 已知风险

1. **递归风险**：Phase 2 子代理禁用了 Collab 和 MemoryTool，防止无限递归
2. **数据竞争**：Phase 1 使用 lease 机制（1小时）防止并发冲突；Phase 2 使用全局单例锁
3. **敏感信息泄露**：Phase 1 使用 `redact_secrets` 脱敏，但依赖模型正确识别敏感信息
4. **存储膨胀**：长期运行可能导致 memories 目录膨胀；有 `max_unused_days` 和 `max_raw_memories_for_consolidation` 限制
5. **任务失败**：失败任务进入退避重试（1小时），最多3次重试

### 边界条件

1. **空记忆处理**：当无输入时，Phase 2 仍会清理过时产物并标记成功
2. **Symlink 安全**：`clear_memory_root_contents()` 拒绝处理 symlink 目录，防止误删
3. **模型不可用**：Phase 1/2 模型配置可回退到默认模型
4. **上下文限制**：Phase 1 rollout 内容截断至模型上下文窗口的 70% 的 70%
5. **线程扫描限制**：最多扫描 5000 个线程，声明限制为 max_rollouts_per_startup（默认16）

### 改进建议

1. **可观测性**：
   - 添加记忆质量评估指标（如用户反馈相关性）
   - 添加 Phase 2 产物大小监控

2. **性能优化**：
   - Phase 1 当前顺序处理 rollout 加载，可考虑预取
   - Phase 2 子代理的超时处理可更细粒度

3. **功能增强**：
   - 支持记忆的手动标记（重要/无用）
   - 支持跨设备的记忆同步
   - 支持记忆的版本控制和回滚

4. **安全加固**：
   - 增加敏感信息检测的覆盖率测试
   - 考虑对记忆文件进行加密存储

5. **配置灵活性**：
   - 支持按项目/目录的记忆隔离
   - 支持更细粒度的记忆保留策略

---

*研究文档生成时间：2026-03-21*
*基于代码版本：codex-rs/core/src/memories/*
