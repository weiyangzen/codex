# agent_jobs.rs 研究文档

## 场景与职责

`agent_jobs.rs` 是 Codex Core 的集成测试文件，专注于测试**批量 Agent 任务（Agent Jobs）**功能。该功能允许用户通过 CSV 文件批量创建子 Agent 任务，并行处理大量独立工作项。

核心测试场景包括：
1. CSV 批量任务创建与执行 (`spawn_agents_on_csv`)
2. 任务结果报告与验证 (`report_agent_job_result`)
3. 任务去重（重复 item_id 处理）
4. 任务取消与停止机制
5. 线程安全验证（防止跨线程错误报告结果）

## 功能点目的

### 1. 批量任务创建 (`spawn_agents_on_csv`)
- 从 CSV 文件读取工作项列表
- 为每个工作项创建子 Agent 并行处理
- 支持自定义指令模板（使用 `{column}` 占位符替换）
- 支持并发控制（`max_concurrency`）

### 2. 任务结果报告 (`report_agent_job_result`)
- 子 Agent 通过工具调用报告处理结果
- 结果被持久化到 SQLite 状态数据库
- 支持任务级取消（通过 `stop: true` 参数）

### 3. 任务生命周期管理
- **Pending**: 等待分配子 Agent
- **Running**: 子 Agent 正在处理
- **Completed**: 成功完成
- **Failed**: 处理失败
- **Cancelled**: 被取消

### 4. 输出导出
- 任务完成后自动导出结果到 CSV
- 保留原始输入列并追加结果列

## 具体技术实现

### 关键流程

```
spawn_agents_on_csv(csv_path, instruction, output_csv_path)
    ↓
解析 CSV，提取 headers 和 rows
    ↓
为每行生成唯一 item_id（去重处理）
    ↓
创建 AgentJob 和 AgentJobItem 记录
    ↓
启动 JobRunner 循环
    ↓
while 有待处理项且未取消:
    - 检查活跃项状态
    - 启动新 worker（不超过并发限制）
    - 回收完成的 worker
    ↓
导出结果到 CSV
```

### 核心数据结构

**SpawnAgentsOnCsvArgs**:
```rust
struct SpawnAgentsOnCsvArgs {
    csv_path: String,
    instruction: String,
    id_column: Option<String>,  // 指定作为 item_id 的列
    output_csv_path: Option<String>,
    output_schema: Option<Value>,
    max_concurrency: Option<usize>,
    max_workers: Option<usize>,
    max_runtime_seconds: Option<u64>,
}
```

**ReportAgentJobResultArgs**:
```rust
struct ReportAgentJobResultArgs {
    job_id: String,
    item_id: String,
    result: Value,
    stop: Option<bool>,  // 设置为 true 取消整个任务
}
```

**AgentJobProgressUpdate**:
```rust
struct AgentJobProgressUpdate {
    job_id: String,
    total_items: usize,
    pending_items: usize,
    running_items: usize,
    completed_items: usize,
    failed_items: usize,
    eta_seconds: Option<u64>,
}
```

### 并发控制参数

```rust
const DEFAULT_AGENT_JOB_CONCURRENCY: usize = 16;
const MAX_AGENT_JOB_CONCURRENCY: usize = 64;
const STATUS_POLL_INTERVAL: Duration = Duration::from_millis(250);
const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_secs(1);
const DEFAULT_AGENT_JOB_ITEM_TIMEOUT: Duration = Duration::from_secs(60 * 30); // 30分钟
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/agent_jobs.rs` - 本测试文件

### 被测试的核心代码
- `codex-rs/core/src/tools/handlers/agent_jobs.rs` - Agent Jobs 工具处理器
- `codex-rs/core/src/agent/control.rs` - Agent 控制平面（spawn/shutdown）
- `codex-rs/core/src/agent/status.rs` - Agent 状态管理

### 状态数据库
- `codex-rs/state/src/lib.rs` - SQLite 状态数据库接口
- AgentJob 相关方法：
  - `create_agent_job()` - 创建任务
  - `mark_agent_job_running()` - 标记运行中
  - `mark_agent_job_completed()` - 标记完成
  - `mark_agent_job_failed()` - 标记失败
  - `report_agent_job_item_result()` - 报告结果

### 测试支持代码
- `codex-rs/core/tests/common/responses.rs` - Mock 响应服务器
- `codex-rs/core/tests/common/test_codex.rs` - 测试构建器

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化 |
| `regex_lite` | CSV 解析辅助 |

### Mock 响应器
测试实现了两个自定义 `Respond` trait：

**AgentJobsResponder**:
- 首次请求：返回 `spawn_agents_on_csv` 函数调用
- 后续请求：根据请求内容识别 worker 请求，返回 `report_agent_job_result` 调用

**StopAfterFirstResponder**:
- 第一个 worker 返回 `stop: true`，触发任务取消
- 验证后续工作项不再被处理

### 核心 crate 依赖
- `codex_core::features::Feature` - 功能开关（`SpawnCsv`, `Sqlite`）
- `codex_state` - 状态数据库类型

## 风险、边界与改进建议

### 当前风险点

1. **Mock 响应器的脆弱性**
   - `extract_job_and_item()` 使用正则表达式解析请求文本
   - 如果提示词模板改变，测试可能失败
   ```rust
   let job_id = Regex::new(r"Job ID:\s*([^\n]+)")
       .ok()?
       .captures(&combined)
       .and_then(|caps| caps.get(1))
       .map(|m| m.as_str().trim().to_string())?;
   ```

2. **并发测试的非确定性**
   - `spawn_agents_on_csv_stop_halts_future_items` 测试依赖 worker 按顺序启动
   - 在高度并发的环境中，两个 worker 可能同时启动

3. **CSV 解析简化**
   - `parse_simple_csv_line()` 使用简单字符串分割，不支持引号内的逗号
   - 测试数据需要避免复杂 CSV 格式

### 边界情况

1. **空 CSV 文件**
   - 测试未覆盖空 CSV 或只有 header 的情况

2. **极大 CSV 文件**
   - 未测试内存限制下的流式处理

3. **Worker 崩溃恢复**
   - 测试未覆盖子 Agent 异常退出的恢复场景

4. **深度嵌套**
   - 未测试 Agent Job 中再 spawn Agent Job 的深度限制

### 改进建议

1. **增强 Mock 稳定性**
   - 使用结构化数据（如 JSON）传递 job_id/item_id，而非正则解析
   - 或者使用固定的测试提示词模板

2. **增加边界测试**
   ```rust
   // 建议添加：
   #[tokio::test]
   async fn spawn_agents_on_csv_empty_file() { ... }
   
   #[tokio::test]
   async fn spawn_agents_on_csv_all_items_fail() { ... }
   
   #[tokio::test]
   async fn spawn_agents_on_csv_worker_timeout() { ... }
   ```

3. **并发控制验证**
   - 添加测试验证并发限制确实生效
   - 使用原子计数器跟踪同时运行的 worker 数量

4. **性能基准**
   - 添加基准测试验证大批量任务的处理性能
   - 监控内存使用不随 item 数量线性增长

5. **错误处理改进**
   - 当前测试主要验证成功路径
   - 建议增加对磁盘满、权限错误等 IO 错误的测试

6. **状态一致性**
   - 添加测试验证任务中断后数据库状态的一致性
   - 验证部分完成的 job 可以正确恢复
