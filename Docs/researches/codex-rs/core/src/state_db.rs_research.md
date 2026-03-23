# state_db.rs 研究文档

## 场景与职责

`state_db.rs` 是 Codex Core 模块中负责 SQLite 状态数据库交互的核心封装层。它作为 `codex_state` crate 的 facade（门面），为上层业务逻辑提供统一的状态持久化接口。

**主要职责：**
1. **状态运行时初始化** - 初始化 SQLite 状态数据库，处理数据回填（backfill）
2. **线程元数据管理** - 提供线程列表查询、线程ID查询、rollout 路径查找等功能
3. **动态工具持久化** - 管理每个线程的动态工具规范（DynamicToolSpec）
4. **数据一致性修复** - 提供 read-repair 机制修复数据库与文件系统的不一致
5. **游标分页支持** - 实现基于游标的分页查询，支持 CreatedAt 和 UpdatedAt 排序

## 功能点目的

### 1. 状态运行时初始化 (`init`)

在 Core 启动时初始化 SQLite 状态运行时。如果检测到回填未完成，会在后台异步启动回填任务。

```rust
pub(crate) async fn init(config: &Config) -> Option<StateDbHandle>
```

**关键流程：**
1. 使用 `codex_state::StateRuntime::init()` 初始化运行时
2. 检查回填状态 `get_backfill_state()`
3. 如果状态不是 Complete，spawn 异步任务执行 `metadata::backfill_sessions`

### 2. 数据库访问控制 (`get_state_db`, `open_if_present`)

提供条件式数据库访问，仅在数据库文件存在且回填完成时返回句柄。

- `get_state_db`: 检查 `state.db` 文件存在性，回填完成后返回句柄
- `open_if_present`: 用于 SQLite 迁移阶段的一致性检查，无特性门控

### 3. 线程列表查询 (`list_thread_ids_db`, `list_threads_db`)

提供基于 SQLite 的线程查询，避免全量 rollout 目录扫描。

**参数说明：**
- `page_size`: 分页大小
- `cursor`: 游标锚点，支持分页续查
- `sort_key`: 排序键（CreatedAt/UpdatedAt）
- `allowed_sources`: 会话来源过滤
- `model_providers`: 模型提供者过滤
- `archived_only`: 仅返回已归档线程

**游标格式：** `YYYY-MM-DDTHH-MM-SS|<uuid>`

### 4. 动态工具管理 (`get_dynamic_tools`, `persist_dynamic_tools`)

管理每个线程的动态工具规范，支持 MCP（Model Context Protocol）工具的持久化。

### 5. Rollout 数据协调 (`reconcile_rollout`)

将 rollout 文件中的数据协调到 SQLite，支持增量更新。

**协调流程：**
1. 如果有 builder 或 items，直接调用 `apply_rollout_items`
2. 否则从 rollout 文件提取元数据
3. 处理归档状态覆盖
4. 更新内存模式
5. 持久化动态工具

### 6. Read-Repair 机制 (`read_repair_rollout_path`)

当文件系统回退成功但数据库记录缺失或路径不一致时，修复数据库记录。

**双路径策略：**
- **Fast Path**: 更新现有元数据行的 rollout_path
- **Slow Path**: 从 rollout 内容重建元数据并协调入库

## 具体技术实现

### 关键数据结构

```rust
/// Core-facing handle to the SQLite-backed state runtime.
pub type StateDbHandle = Arc<codex_state::StateRuntime>;
```

### 游标与锚点转换

```rust
fn cursor_to_anchor(cursor: Option<&Cursor>) -> Option<codex_state::Anchor>
```

支持两种时间戳格式：
1. 文件名格式：`%Y-%m-%dT%H-%M-%S`
2. RFC3339 格式

### 路径规范化

```rust
pub(crate) fn normalize_cwd_for_state_db(cwd: &Path) -> PathBuf
```

使用 `path_utils::normalize_for_path_comparison` 确保路径一致性。

### 错误处理策略

所有数据库操作均采用**优雅降级**策略：
- 错误时记录警告日志
- 返回 `None` 让调用方回退到文件系统扫描
- 不阻塞主业务流程

## 关键代码路径与文件引用

### 核心依赖

| 依赖模块 | 路径 | 用途 |
|---------|------|------|
| `codex_state` | 外部 crate | SQLite 状态运行时 |
| `path_utils` | `src/path_utils.rs` | 路径规范化 |
| `rollout::metadata` | `src/rollout/metadata.rs` | 元数据提取与回填 |
| `rollout::list` | `src/rollout/list.rs` | 游标解析与 rollout 列表 |

### 调用关系

**被调用方（上游）：**
- `crate::codex` - 会话管理
- `crate::thread_manager` - 线程生命周期管理
- `crate::rollout::list` - 线程列表查询

**调用方（下游）：**
- `codex_state::StateRuntime` - 底层数据库操作
- `crate::rollout::metadata::backfill_sessions` - 数据回填

### 关键函数调用链

```
init()
  ├── StateRuntime::init()
  ├── get_backfill_state()
  └── tokio::spawn(metadata::backfill_sessions())

list_threads_db()
  ├── cursor_to_anchor()
  ├── ctx.list_threads()
  └── tokio::fs::try_exists() [验证 rollout_path]

reconcile_rollout()
  ├── apply_rollout_items()
  └── metadata::extract_metadata_from_rollout()

read_repair_rollout_path()
  ├── ctx.get_thread() [Fast Path]
  ├── ctx.upsert_thread()
  └── reconcile_rollout() [Slow Path]
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_state` | SQLite 状态运行时 |
| `codex_protocol` | ThreadId, RolloutItem, SessionSource 等协议类型 |
| `chrono` | 时间戳处理 |
| `uuid` | UUID 解析 |
| `serde_json` | JSON 序列化 |
| `tracing` | 日志记录 |

### 环境依赖

- `config.sqlite_home` - SQLite 数据库目录
- `config.codex_home` - Codex 主目录
- `config.model_provider_id` - 默认模型提供者

### 异步运行时

依赖 `tokio` 异步运行时：
- 文件系统操作使用 `tokio::fs`
- 后台回填任务使用 `tokio::spawn`

## 风险、边界与改进建议

### 已知风险

1. **回填竞争条件**
   - 多个进程同时启动可能触发并发回填
   - 缓解：使用 `try_claim_backfill` 租赁机制

2. **路径不一致**
   - 数据库中的 rollout_path 可能与实际文件系统不一致
   - 缓解：`list_threads_db` 中验证路径存在性，自动删除失效记录

3. **游标格式兼容性**
   - 时间戳格式变更可能导致游标解析失败
   - 缓解：支持多种格式解析（文件名格式 + RFC3339）

### 边界情况

1. **空数据库**
   - `get_state_db` 在数据库不存在时返回 `None`
   - 调用方需回退到文件系统扫描

2. **回填中断**
   - 进程崩溃可能导致回填状态停留在 Running
   - 租赁过期机制（900秒）允许重新认领

3. **WSL 路径**
   - `normalize_cwd_for_state_db` 处理 WSL 大小写不敏感路径

### 改进建议

1. **监控增强**
   - 添加回填进度指标（已处理/剩余文件数）
   - 添加数据库查询延迟直方图

2. **错误分类**
   - 当前所有错误统一为警告日志
   - 建议区分可恢复错误和需要人工介入的错误

3. **缓存层**
   - 考虑在热点查询路径添加内存缓存
   - 特别是 `find_rollout_path_by_id` 频繁调用

4. **测试覆盖**
   - 当前测试仅覆盖 `cursor_to_anchor`
   - 建议添加集成测试：回填流程、read-repair、并发场景

### 测试文件

- `src/state_db_tests.rs` - 单元测试（游标解析）
