# debug_clear_memories.rs 研究文档

## 场景与职责

`debug_clear_memories.rs` 是 Codex CLI 的集成测试文件，负责测试 `codex debug clear-memories` 命令的功能。该命令是一个内部调试工具，用于重置本地记忆状态，为用户提供"干净启动"的体验。

**主要测试场景：**
- 验证 `debug clear-memories` 命令能够正确清除 SQLite 数据库中的记忆相关数据
- 验证命令能够删除本地文件系统中的记忆目录
- 验证命令将线程的 memory_mode 从 'enabled' 更新为 'disabled'

## 功能点目的

### 1. 记忆系统清理

Codex 的记忆系统（Memory System）用于在多次会话之间保持上下文信息。`clear-memories` 命令的目的是：

- **清除 Stage1 输出**：删除 `stage1_outputs` 表中的所有记录
- **清除记忆任务**：删除 `jobs` 表中类型为 `memory_stage1` 和 `memory_consolidate_global` 的任务
- **禁用线程记忆**：将所有线程的 `memory_mode` 从 'enabled' 改为 'disabled'
- **删除记忆文件**：移除 `~/.codex/memories/` 目录及其内容

### 2. 干净启动支持

该功能主要用于：
- 开发调试时重置状态
- 用户想要"忘记"之前的记忆
- 解决记忆数据损坏或不一致的问题

## 具体技术实现

### 测试结构

```rust
#[tokio::test]
async fn debug_clear_memories_resets_state_and_removes_memory_dir() -> Result<()>
```

### 关键流程

1. **初始化测试环境**
   ```rust
   let codex_home = TempDir::new()?;
   let runtime = StateRuntime::init(codex_home.path().to_path_buf(), "test-provider".to_string()).await?;
   ```

2. **准备测试数据**
   - 在 `threads` 表中插入测试线程记录
   - 在 `stage1_outputs` 表中插入记忆输出记录
   - 在 `jobs` 表中插入记忆处理任务
   - 创建 `memories` 目录并写入测试文件

3. **执行被测命令**
   ```rust
   let mut cmd = codex_command(codex_home.path())?;
   cmd.args(["debug", "clear-memories"])
       .assert()
       .success()
       .stdout(contains("Cleared memory state"));
   ```

4. **验证清理结果**
   - 验证 `stage1_outputs` 表为空
   - 验证 `jobs` 表中的记忆任务被删除
   - 验证线程的 `memory_mode` 变为 'disabled'
   - 验证 `memories` 目录被删除

### 核心数据结构

**数据库表结构（由测试推断）：**

```sql
-- threads 表
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT,
    created_at INTEGER,
    updated_at INTEGER,
    source TEXT,
    agent_nickname TEXT,
    agent_role TEXT,
    model_provider TEXT,
    cwd TEXT,
    cli_version TEXT,
    title TEXT,
    sandbox_policy TEXT,
    approval_mode TEXT,
    tokens_used INTEGER,
    first_user_message TEXT,
    archived INTEGER,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT,
    memory_mode TEXT  -- 'enabled', 'disabled', 'polluted'
);

-- stage1_outputs 表
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER,
    raw_memory TEXT,
    rollout_summary TEXT,
    generated_at INTEGER,
    rollout_slug TEXT,
    usage_count INTEGER,
    last_usage INTEGER,
    selected_for_phase2 INTEGER,
    selected_for_phase2_source_updated_at INTEGER
);

-- jobs 表
CREATE TABLE jobs (
    kind TEXT,  -- 'memory_stage1', 'memory_consolidate_global'
    job_key TEXT,
    status TEXT,
    worker_id TEXT,
    ownership_token TEXT,
    started_at INTEGER,
    finished_at INTEGER,
    lease_until INTEGER,
    retry_at INTEGER,
    retry_remaining INTEGER,
    last_error TEXT,
    input_watermark INTEGER,
    last_success_watermark INTEGER
);
```

### 命令实现

被测命令的实现位于 `codex-rs/cli/src/main.rs`：

```rust
async fn run_debug_clear_memories_command(
    root_config_overrides: &CliConfigOverrides,
    interactive: &TuiCli,
) -> anyhow::Result<()> {
    // 加载配置
    let config = Config::load_with_cli_overrides_and_harness_overrides(...).await?;
    
    // 清理状态数据库
    let state_path = state_db_path(config.sqlite_home.as_path());
    if tokio::fs::try_exists(&state_path).await? {
        let state_db = StateRuntime::init(...).await?;
        state_db.reset_memory_data_for_fresh_start().await?;
    }
    
    // 删除记忆目录
    let memory_root = config.codex_home.join("memories");
    tokio::fs::remove_dir_all(&memory_root).await?;
    
    println!("{message}");
    Ok(())
}
```

核心清理逻辑在 `codex-rs/state/src/runtime/memories.rs`：

```rust
pub async fn reset_memory_data_for_fresh_start(&self) -> anyhow::Result<()> {
    self.clear_memory_data_inner(/*disable_existing_threads*/ true).await
}

async fn clear_memory_data_inner(&self, disable_existing_threads: bool) -> anyhow::Result<()> {
    let mut tx = self.pool.begin().await?;
    
    // 删除所有 stage1 输出
    sqlx::query("DELETE FROM stage1_outputs").execute(&mut *tx).await?;
    
    // 删除记忆相关任务
    sqlx::query("DELETE FROM jobs WHERE kind = ? OR kind = ?")
        .bind(JOB_KIND_MEMORY_STAGE1)
        .bind(JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL)
        .execute(&mut *tx).await?;
    
    // 禁用所有线程的记忆功能
    if disable_existing_threads {
        sqlx::query("UPDATE threads SET memory_mode = 'disabled' WHERE memory_mode = 'enabled'")
            .execute(&mut *tx).await?;
    }
    
    tx.commit().await?;
    Ok(())
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/cli/tests/debug_clear_memories.rs` - 本测试文件

### 被测代码
- `codex-rs/cli/src/main.rs`
  - `run_debug_clear_memories_command()` - 命令主入口
  - `DebugSubcommand::ClearMemories` - 子命令定义

### 依赖的 State 模块
- `codex-rs/state/src/runtime/memories.rs`
  - `reset_memory_data_for_fresh_start()` - 重置记忆数据
  - `clear_memory_data_inner()` - 内部清理实现

### 依赖的配置模块
- `codex-rs/state/src/lib.rs`
  - `state_db_path()` - 状态数据库路径
- `codex-rs/state/src/runtime/mod.rs`
  - `StateRuntime::init()` - 运行时初始化

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建隔离的测试环境 |
| `sqlx::SqlitePool` | 直接操作 SQLite 数据库验证结果 |
| `assert_cmd::Command` | 执行 CLI 命令并断言输出 |
| `predicates::str::contains` | 输出内容匹配 |
| `codex_state::StateRuntime` | 初始化状态运行时 |
| `codex_utils_cargo_bin::cargo_bin` | 定位测试用的 codex 二进制文件 |

### 数据库交互

测试直接与 SQLite 数据库交互：
- 使用 `sqlx::query` 插入测试数据
- 使用 `sqlx::query_scalar` 验证清理结果

### 文件系统交互

- 创建临时目录作为 `CODEX_HOME`
- 创建 `memories` 目录和测试文件
- 验证目录删除结果

## 风险、边界与改进建议

### 潜在风险

1. **数据库 Schema 变更**
   - 测试硬编码了 SQL 语句和表结构
   - 如果数据库 Schema 变更，测试可能失败
   - 建议：使用 ORM 或 Schema 验证机制

2. **并发测试问题**
   - 每个测试使用独立的 `TempDir`，无并发冲突
   - 但测试依赖于 `cargo_bin("codex")`，需要确保二进制文件已构建

3. **平台兼容性**
   - 使用标准路径操作，跨平台兼容
   - SQLite 操作在所有支持的平台上一致

### 边界情况

1. **空数据库状态**
   - 测试未覆盖数据库不存在的情况
   - 实现代码中已处理：`try_exists` 检查

2. **大容量数据**
   - 测试使用单条记录，未测试大量数据清理性能

3. **权限问题**
   - 测试未覆盖文件系统权限不足的场景

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议添加：空状态测试
   #[tokio::test]
   async fn debug_clear_memories_handles_empty_state() -> Result<()>
   
   // 建议添加：重复执行测试
   #[tokio::test]
   async fn debug_clear_memories_is_idempotent() -> Result<()>
   ```

2. **性能测试**
   - 添加大量数据清理的性能基准测试

3. **错误处理测试**
   - 测试数据库锁定时的行为
   - 测试文件系统只读时的错误处理

4. **集成测试增强**
   - 验证清理后新记忆能正常生成
   - 验证多线程并发清理的安全性

### 相关配置

- 命令被标记为 `#[clap(hide = true)]`，对用户隐藏
- 仅在内部调试场景使用
- 需要正确设置 `CODEX_HOME` 环境变量
