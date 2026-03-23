# agent_jobs.rs 深度研究文档

## 场景与职责

`agent_jobs.rs` 实现了 Codex 的**批量 Agent 任务处理系统**，用于支持 `spawn_agents_on_csv` 工具。该工具允许用户上传一个 CSV 文件，其中每一行代表一个独立的任务项，系统会为每一行并发启动一个子 Agent 来处理任务，并将结果汇总输出到新的 CSV 文件中。

**核心使用场景：**
1. **批量代码审查** - 对多个文件或模块进行并行审查
2. **批量数据处理** - 处理大量结构化数据，每行一个处理单元
3. **批量生成任务** - 如为每个 CSV 行生成对应的文档、测试或代码
4. **大规模并行分析** - 利用多 Agent 并发能力加速处理

## 功能点目的

### 1. CSV 批量任务管理
- 解析输入 CSV 文件，将每行转换为独立的 Agent 任务项
- 支持自定义 ID 列，用于标识和追踪任务项
- 自动处理重复 ID，生成唯一标识符
- 支持模板化指令，使用 `{column}` 占位符填充行数据

### 2. 并发 Agent 执行
- 支持配置最大并发数（默认 16，最大 64）
- 动态调度待处理任务到可用 Agent 槽位
- 支持任务超时控制（默认 30 分钟）
- 深度限制检查，防止无限递归 spawn

### 3. 任务生命周期管理
- 任务状态追踪：Pending → Running → Completed/Failed
- 支持任务取消和优雅关闭
- 失败任务自动重试机制
- 运行时任务恢复（处理崩溃重启场景）

### 4. 结果收集与导出
- 实时进度报告（每秒或状态变化时）
- 自动导出结果到 CSV 文件
- 支持输出 Schema 定义
- 失败项错误摘要收集

### 5. 结果上报机制
- 子 Agent 通过 `report_agent_job_result` 工具上报结果
- 支持提前终止任务（`stop=true`）
- 结果验证和存储到状态数据库

## 具体技术实现

### 关键数据结构

```rust
// 主 Handler 结构
pub struct BatchJobHandler;

// spawn_agents_on_csv 参数
struct SpawnAgentsOnCsvArgs {
    csv_path: String,              // 输入 CSV 路径
    instruction: String,           // 任务指令模板
    id_column: Option<String>,     // 可选 ID 列名
    output_csv_path: Option<String>, // 可选输出路径
    output_schema: Option<Value>,  // 可选输出 Schema
    max_concurrency: Option<usize>, // 最大并发数
    max_workers: Option<usize>,    // 兼容旧参数
    max_runtime_seconds: Option<u64>, // 单任务超时
}

// 结果上报参数
struct ReportAgentJobResultArgs {
    job_id: String,
    item_id: String,
    result: Value,                 // JSON 结果对象
    stop: Option<bool>,            // 是否终止整个任务
}

// 任务执行选项
struct JobRunnerOptions {
    max_concurrency: usize,
    spawn_config: Config,          // 子 Agent 配置
}

// 活跃任务项追踪
struct ActiveJobItem {
    item_id: String,
    started_at: Instant,
    status_rx: Option<Receiver<AgentStatus>>, // 状态订阅
}

// 进度报告发射器
struct JobProgressEmitter {
    started_at: Instant,
    last_emit_at: Instant,
    last_processed: usize,
    last_failed: usize,
}
```

### 核心常量

```rust
const DEFAULT_AGENT_JOB_CONCURRENCY: usize = 16;
const MAX_AGENT_JOB_CONCURRENCY: usize = 64;
const STATUS_POLL_INTERVAL: Duration = Duration::from_millis(250);
const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_secs(1);
const DEFAULT_AGENT_JOB_ITEM_TIMEOUT: Duration = Duration::from_secs(60 * 30); // 30分钟
```

### 关键流程

#### 1. 任务创建流程 (`spawn_agents_on_csv::handle`)

```
1. 解析参数并验证 instruction 非空
2. 读取并解析 CSV 文件
3. 验证表头唯一性
4. 解析 ID 列索引（如指定）
5. 遍历 CSV 行：
   - 验证行列数匹配
   - 提取 source_id（来自 ID 列或行号）
   - 处理重复 ID，生成唯一 item_id
   - 构建 row_json 对象
   - 创建 AgentJobItemCreateParams
6. 生成 job_id 和默认输出路径
7. 创建 AgentJob（写入状态数据库）
8. 构建 runner options（检查深度限制）
9. 标记任务为 Running
10. 运行主循环 run_agent_job_loop
11. 导出 CSV 结果
12. 返回 SpawnAgentsOnCsvResult
```

#### 2. 主执行循环 (`run_agent_job_loop`)

```
1. 恢复正在运行的任务（recover_running_items）
2. 发送初始进度报告
3. 主循环：
   a. 检查取消请求
   b. 如有空槽，启动新 Agent（最多到 max_concurrency）
   c. 清理超时任务（reap_stale_active_items）
   d. 查找已完成 Agent（find_finished_threads）
   e. 如没有变化，等待状态变更（wait_for_status_change）
   f. 处理已完成项（finalize_finished_item）
   g. 发送进度更新
4. 最终 CSV 导出
5. 标记任务完成或取消
```

#### 3. 子 Agent 启动流程

```rust
// 构建工作提示词
let prompt = build_worker_prompt(&job, &item)?;
let items = vec![UserInput::Text { text: prompt, text_elements: Vec::new() }];

// 通过 agent_control 启动子 Agent
let thread_id = session
    .services
    .agent_control
    .spawn_agent(options.spawn_config.clone(), items, Some(SessionSource::SubAgent(...)))
    .await?;

// 标记任务项为 Running
let assigned = db
    .mark_agent_job_item_running_with_thread(job_id, item.item_id.as_str(), thread_id.to_string().as_str())
    .await?;
```

#### 4. 工作提示词模板 (`build_worker_prompt`)

```
You are processing one item for a generic agent job.
Job ID: {job_id}
Item ID: {item_id}

Task instruction:
{instruction}  // 模板已填充行数据

Input row (JSON):
{row_json}

Expected result schema (JSON Schema or {}):
{output_schema}

You MUST call the `report_agent_job_result` tool exactly once with:
1. `job_id` = "{job_id}"
2. `item_id` = "{item_id}"
3. `result` = a JSON object that contains your analysis result for this row.

If you need to stop the job early, include `stop` = true in the tool call.

After the tool call succeeds, stop.
```

#### 5. 结果上报流程 (`report_agent_job_result::handle`)

```
1. 解析参数，验证 result 是 JSON 对象
2. 获取状态数据库
3. 调用 db.report_agent_job_item_result() 记录结果
4. 如 accepted 且 stop=true，标记任务取消
5. 返回 ReportAgentJobResultToolResult { accepted }
```

### CSV 处理函数

#### `parse_csv` - CSV 解析
```rust
fn parse_csv(content: &str) -> Result<(Vec<String>, Vec<Vec<String>>), String> {
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(true)
        .flexible(true)
        .from_reader(content.as_bytes());
    // 处理 BOM，解析表头和行数据
}
```

#### `render_job_csv` - 结果导出
```rust
fn render_job_csv(
    headers: &[String],
    items: &[codex_state::AgentJobItem],
) -> Result<String, FunctionCallError> {
    // 扩展表头：原始列 + job_id, item_id, row_index, source_id, 
    //           status, attempt_count, last_error, result_json, reported_at, completed_at
    // 遍历 items，将 row_json 展开为 CSV 行
}
```

#### `render_instruction_template` - 指令模板渲染
```rust
fn render_instruction_template(instruction: &str, row_json: &Value) -> String {
    // 使用 {{ 和 }} 作为字面量转义
    // 将 {column} 替换为对应行值
}
```

## 关键代码路径与文件引用

### 当前文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `BatchJobHandler::handle` | 193-219 | 工具分发入口 |
| `spawn_agents_on_csv::handle` | 229-467 | 主任务创建逻辑 |
| `report_agent_job_result::handle` | 473-514 | 结果上报处理 |
| `run_agent_job_loop` | 569-792 | 任务执行主循环 |
| `recover_running_items` | 811-889 | 恢复运行中任务 |
| `reap_stale_active_items` | 935-963 | 清理超时任务 |
| `finalize_finished_item` | 965-997 | 完成任务项处理 |
| `build_worker_prompt` | 999-1030 | 构建子 Agent 提示词 |
| `render_instruction_template` | 1032-1055 | 模板渲染 |
| `parse_csv` | 1103-1123 | CSV 解析 |
| `render_job_csv` | 1125-1199 | CSV 结果导出 |

### 外部依赖

| 模块/文件 | 用途 |
|-----------|------|
| `codex_state::StateRuntime` | 状态数据库存储任务和进度 |
| `Session::services.agent_control` | 子 Agent 生命周期管理 |
| `multi_agents::build_agent_spawn_config` | 构建子 Agent 配置 |
| `agent::exceeds_thread_spawn_depth_limit` | 深度限制检查 |
| `agent::status::is_final` | Agent 状态判断 |

## 依赖与外部交互

### 数据库交互 (codex_state)

```rust
// 创建任务
db.create_agent_job(&AgentJobCreateParams { ... }, items).await

// 获取任务
db.get_agent_job(job_id).await

// 标记状态
db.mark_agent_job_running(job_id).await
db.mark_agent_job_completed(job_id).await
db.mark_agent_job_failed(job_id, error).await
db.mark_agent_job_cancelled(job_id, message).await

// 任务项操作
db.list_agent_job_items(job_id, status, limit).await
db.mark_agent_job_item_running_with_thread(job_id, item_id, thread_id).await
db.mark_agent_job_item_completed(job_id, item_id).await
db.mark_agent_job_item_failed(job_id, item_id, error).await
db.mark_agent_job_item_pending(job_id, item_id, error).await
db.report_agent_job_item_result(job_id, item_id, thread_id, result).await

// 进度查询
db.get_agent_job_progress(job_id).await
db.is_agent_job_cancelled(job_id).await
```

### Agent Control 服务交互

```rust
// 启动子 Agent
session.services.agent_control.spawn_agent(config, items, source).await

// 订阅状态变化
session.services.agent_control.subscribe_status(thread_id).await

// 获取当前状态
session.services.agent_control.get_status(thread_id).await

// 关闭 Agent
session.services.agent_control.shutdown_agent(thread_id).await
```

### 事件通知

```rust
// 后台事件通知
session.notify_background_event(turn, message).await

// Agent Job 进度事件格式：
// "agent_job_progress:{serialized AgentJobProgressUpdate}"
```

## 风险、边界与改进建议

### 已知风险

1. **资源耗尽风险**
   - 大量 CSV 行（如 10万+）可能导致内存压力
   - 所有任务项在启动前全部加载到内存
   - 建议：实现流式处理或分页加载

2. **递归深度风险**
   - 子 Agent 可能再次调用 spawn_agents_on_csv
   - 已通过 `agent_max_depth` 和 `exceeds_thread_spawn_depth_limit` 限制
   - 建议：更清晰的递归层级可视化

3. **数据库状态不一致**
   - 进程崩溃后恢复可能遗漏部分状态
   - `recover_running_items` 处理部分场景
   - 建议：更完善的幂等性设计

4. **超时处理粒度**
   - 仅支持单任务超时，不支持整体任务超时
   - 建议：添加 job-level 超时控制

### 边界情况

1. **CSV 格式边界**
   - BOM 头处理（UTF-8 BOM 被自动去除）
   - 空行自动跳过
   - 行列不匹配时返回详细错误

2. **ID 冲突处理**
   - 自动添加后缀生成唯一 ID（`base_id-2`, `base_id-3`...）

3. **并发槽位竞争**
   - AgentLimitReached 时任务回退到 Pending
   - 下次循环重试

### 改进建议

1. **性能优化**
   - 实现任务流式加载，减少内存占用
   - 支持动态调整并发度
   - 添加背压机制

2. **可观测性**
   - 添加更详细的指标（队列深度、等待时间等）
   - 支持结构化日志输出
   - 添加任务追踪 ID

3. **功能增强**
   - 支持任务优先级
   - 支持批量结果上报（减少 RPC 次数）
   - 支持任务依赖关系

4. **错误处理**
   - 更细粒度的错误分类
   - 支持可配置的重试策略
   - 添加死信队列

5. **测试覆盖**
   - 当前测试较少（仅 agent_jobs_tests.rs 62 行）
   - 建议添加集成测试：
     - 大规模 CSV 处理
     - 并发限制验证
     - 超时场景
     - 取消场景
     - 恢复场景
