# turn_metadata.rs 研究文档

## 场景与职责

`turn_metadata.rs` 是 Codex Core 中负责构建和管理**回合元数据（Turn Metadata）**的模块。其核心职责包括：

1. **收集 Git 仓库信息**：获取当前工作目录的 Git 远程 URL、最新提交哈希、是否有未提交更改等
2. **构建回合元数据头**：将收集的信息序列化为 JSON 格式，作为 HTTP 请求头发送给后端
3. **管理沙盒标签**：记录当前使用的沙盒策略类型
4. **支持异步富化**：通过后台任务异步获取 Git 元数据，避免阻塞主流程

该模块主要用于在每次用户与 AI 交互的"回合"中，向服务器提供上下文信息，帮助服务器更好地理解代码库状态。

## 功能点目的

### 1. 回合元数据结构 (`TurnMetadataBag`)

```rust
#[derive(Clone, Debug, Serialize, Default)]
pub(crate) struct TurnMetadataBag {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    workspaces: BTreeMap<String, TurnMetadataWorkspace>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    sandbox: Option<String>,
}
```

- `turn_id`: 唯一标识当前回合
- `workspaces`: 工作空间映射（路径 -> Git 元数据）
- `sandbox`: 沙盒类型标签（如 "none", "seatbelt", "windows_elevated" 等）

### 2. 工作空间 Git 元数据

```rust
#[derive(Clone, Debug, Serialize, Default)]
struct TurnMetadataWorkspace {
    associated_remote_urls: Option<BTreeMap<String, String>>,  // 远程仓库 URL
    latest_git_commit_hash: Option<String>,                    // HEAD 提交哈希
    has_changes: Option<bool>,                                 // 是否有未提交更改
}
```

### 3. 状态管理 (`TurnMetadataState`)

提供回合级别的状态管理：
- 存储基础元数据（回合 ID、沙盒类型）
- 支持异步 Git 元数据富化
- 提供线程安全的头信息获取

## 具体技术实现

### 关键流程

#### 1. 构建回合元数据头（同步）

```rust
pub async fn build_turn_metadata_header(cwd: &Path, sandbox: Option<&str>) -> Option<String>
```

流程：
1. 获取 Git 仓库根目录
2. 并行执行三个 Git 命令（`tokio::join!`）：
   - `get_head_commit_hash`: 获取 HEAD 提交哈希
   - `get_git_remote_urls_assume_git_repo`: 获取远程 URL
   - `get_has_changes`: 检查是否有未提交更改
3. 如果所有信息都为空且没有沙盒标签，返回 `None`
4. 否则构建 `TurnMetadataBag` 并序列化为 JSON

#### 2. 异步 Git 富化任务

```rust
pub(crate) fn spawn_git_enrichment_task(&self)
```

设计模式：
- 使用 `Arc<RwLock<Option<String>>>` 存储富化后的头信息
- 使用 `Arc<Mutex<Option<JoinHandle<()>>>>` 管理后台任务
- 确保只有一个富化任务在运行（通过 `Mutex` 检查）
- 任务完成后更新 `enriched_header`

#### 3. 获取当前头信息

```rust
pub(crate) fn current_header_value(&self) -> Option<String>
```

优先级：
1. 如果富化完成，返回富化后的头信息
2. 否则返回基础头信息

### 数据结构

| 结构体 | 用途 |
|--------|------|
| `WorkspaceGitMetadata` | 内部 Git 元数据表示（非序列化） |
| `TurnMetadataWorkspace` | 可序列化的工作空间元数据 |
| `TurnMetadataBag` | 完整的回合元数据包 |
| `TurnMetadataState` | 回合级别的状态管理 |

### 协议/格式

- 输出格式：JSON 字符串
- 序列化库：`serde`
- 序列化选项：`skip_serializing_if` 用于省略空值

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `build_turn_metadata_header` | 90-117 | 主入口：构建元数据头 |
| `build_turn_metadata_bag` | 70-88 | 构建元数据包 |
| `TurnMetadataState::new` | 130-156 | 初始化状态 |
| `spawn_git_enrichment_task` | 171-208 | 启动异步富化 |
| `fetch_workspace_git_metadata` | 220-232 | 获取 Git 元数据 |

### 依赖文件

| 文件 | 依赖内容 |
|------|----------|
| `git_info.rs` | `get_git_repo_root`, `get_head_commit_hash`, `get_git_remote_urls_assume_git_repo`, `get_has_changes` |
| `sandbox_tags.rs` | `sandbox_tag` 函数 |
| `codex_protocol::protocol::SandboxPolicy` | 沙盒策略类型 |
| `codex_protocol::config_types::WindowsSandboxLevel` | Windows 沙盒级别 |

### 调用方

- `codex.rs`: 在 `TurnContext` 中创建 `TurnMetadataState`
- 通过 `current_header_value()` 获取头信息添加到 HTTP 请求

## 依赖与外部交互

### 外部系统交互

1. **Git 命令执行**：通过 `git_info.rs` 间接调用 Git 命令
   - 超时控制：5 秒（在 `git_info.rs` 中定义）
   - 并行执行：使用 `tokio::join!`

2. **HTTP 请求头**：序列化后的 JSON 作为请求头发送

### 并发控制

```rust
enriched_header: Arc<RwLock<Option<String>>>,      // 读多写少
enrichment_task: Arc<Mutex<Option<JoinHandle<()>>>>, // 互斥访问
```

- `RwLock`: 允许多个读取者并发访问
- `Mutex`: 确保只有一个富化任务

## 风险、边界与改进建议

### 风险点

1. **Git 命令超时**
   - 风险：大型仓库可能导致 Git 命令超时
   - 缓解：5 秒超时，超时后返回 `None` 不影响主流程

2. **并发安全**
   - `RwLock` 和 `Mutex` 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)`
   - 如果持有锁的线程 panic，锁会被"污染"，但代码选择继续执行

3. **任务取消**
   - `cancel_git_enrichment_task` 调用 `task.abort()`
   - 不会等待任务真正停止，只是发送取消信号

### 边界情况

1. **非 Git 仓库**：所有 Git 相关字段为 `None`，只保留沙盒标签
2. **空仓库**（刚 init 没有 commit）：`latest_git_commit_hash` 为 `None`
3. **重复调用 `spawn_git_enrichment_task`**：通过 `Mutex` 检查确保只启动一个任务

### 改进建议

1. **缓存优化**
   - 当前每次回合都重新获取 Git 信息
   - 可考虑在仓库未改变时复用缓存

2. **错误处理**
   - 当前 Git 错误静默处理（返回 `None`）
   - 可考虑记录警告日志帮助调试

3. **测试覆盖**
   - 测试用例较少，缺少对并发场景的测试
   - 建议添加多线程环境下的测试

4. **性能优化**
   - `tokio::join!` 并行执行三个 Git 命令
   - 但每个命令还是顺序执行，可考虑更细粒度的并行

### 相关测试

测试文件：`turn_metadata_tests.rs`

| 测试 | 说明 |
|------|------|
| `build_turn_metadata_header_includes_has_changes_for_clean_repo` | 验证干净仓库的 `has_changes` 为 `false` |
| `turn_metadata_state_uses_platform_sandbox_tag` | 验证沙盒标签正确生成 |
