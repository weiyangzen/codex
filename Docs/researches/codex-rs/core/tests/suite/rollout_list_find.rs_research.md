# rollout_list_find.rs 研究文档

## 场景与职责

`rollout_list_find.rs` 是 Codex Core 的测试文件，专注于验证 **会话（Thread）持久化数据的查找和发现功能**。在 Codex 架构中，每次会话会产生一个 rollout 文件（JSONL 格式），存储在 `~/.codex/sessions/YYYY/MM/DD/` 目录下。本测试确保系统能够可靠地：

- 通过会话 ID 查找对应的 rollout 文件
- 通过会话名称查找对应的 rollout 文件
- 处理归档会话（`archived_sessions` 目录）
- 正确处理 `.gitignore` 等边界情况

## 功能点目的

### 1. 按 ID 查找会话 (`find_locates_rollout_file_by_id`)
验证通过 UUID 查找会话文件的基本功能：
- 创建模拟 rollout 文件
- 使用 `find_thread_path_by_id_str()` 查找
- 验证返回正确的文件路径

### 2. GitIgnore 处理 (`find_handles_gitignore_covering_codex_home_directory`)
测试当 `.codex` 目录被 `.gitignore` 覆盖时的查找能力：
- 在父目录创建 `.gitignore` 包含 `.codex/**`
- 验证仍能正确找到会话文件

### 3. SQLite 优先 (`find_prefers_sqlite_path_by_id`)
验证当 SQLite 数据库中存在路径记录时，优先使用数据库中的路径：
- 创建文件系统 rollout 文件
- 在 SQLite 中插入不同的路径记录
- 验证返回 SQLite 中的路径

### 4. 数据库无匹配回退 (`find_falls_back_to_filesystem_when_sqlite_has_no_match`)
测试当 SQLite 中没有匹配记录时，回退到文件系统搜索：
- 在 SQLite 中插入不相关的会话记录
- 验证仍能正确找到目标会话文件

### 5. 细粒度 GitIgnore (`find_ignores_granular_gitignore_rules`)
验证细粒度的 `.gitignore` 规则（如 `*.jsonl`）不影响查找：
- 在 `sessions/` 子目录创建 `.gitignore`
- 验证查找功能不受影响

### 6. 真实 Recorder 集成 (`find_locates_rollout_file_written_by_recorder`)
测试与真实 `RolloutRecorder` 的集成：
- 使用 `RolloutRecorder` 创建会话记录
- 通过 `find_thread_path_by_name_str()` 查找
- 验证文件内容包含正确的会话 ID

### 7. 归档会话查找 (`find_archived_locates_rollout_file_by_id`)
验证对归档会话的查找能力：
- 在 `archived_sessions` 目录创建 rollout 文件
- 使用 `find_archived_thread_path_by_id_str()` 查找

## 具体技术实现

### 关键数据结构

```rust
// 会话查找函数（来自 codex_core::rollout::list）
pub async fn find_thread_path_by_id_str(
    codex_home: &Path,
    id: &str,
) -> io::Result<Option<PathBuf>>

pub async fn find_archived_thread_path_by_id_str(
    codex_home: &Path,
    id: &str,
) -> io::Result<Option<PathBuf>>

pub async fn find_thread_path_by_name_str(
    codex_home: &Path,
    name: &str,
) -> io::Result<Option<PathBuf>>
```

### Rollout 文件格式

```jsonl
// rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
{"timestamp": "2024-01-01T00:00:00.000Z", "type": "session_meta", "payload": {"id": "...", ...}}
{"timestamp": "...", "type": "user_event", "payload": {...}}
// ... 更多事件
```

### 查找流程

```
find_thread_path_by_id_str()
  ├─ 尝试 SQLite 查找 (StateRuntime)
  │    └─ 查询 state_db 中的 thread 记录
  ├─ 回退到文件系统搜索
  │    └─ 遍历 sessions/YYYY/MM/DD/ 目录结构
  │         └─ 解析文件名中的 UUID
  │              └─ 匹配目标 ID
  └─ 返回找到的路径
```

### 测试辅助函数

```rust
// 创建最小化 rollout 文件
fn write_minimal_rollout_with_id(codex_home: &Path, id: Uuid) -> PathBuf {
    // 路径: sessions/2024/01/01/rollout-2024-01-01T00-00-00-{id}.jsonl
    // 包含 session_meta 行以便查找
}

// 更新 SQLite 元数据
async fn upsert_thread_metadata(codex_home: &Path, thread_id: ThreadId, rollout_path: PathBuf) {
    // 使用 StateRuntime 和 ThreadMetadataBuilder
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::rollout::list` | 会话查找实现 |
| `codex_core::rollout::recorder::RolloutRecorder` | 真实会话记录器 |
| `codex_core::find_thread_path_by_id_str` | 被测函数 |
| `codex_state::StateRuntime` | SQLite 状态管理 |
| `codex_protocol::ThreadId` | 会话 ID 类型 |

### 目录结构

```
~/.codex/
├── sessions/
│   └── YYYY/
│       └── MM/
│           └── DD/
│               └── rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
├── archived_sessions/
│   └── ... (相同结构)
└── state.db  (SQLite 数据库)
```

## 风险、边界与改进建议

### 当前风险

1. **文件系统依赖**：测试依赖临时目录和文件系统操作，可能受磁盘性能影响
2. **时间敏感性**：rollout 文件名包含时间戳，测试中需要固定时间
3. **并发冲突**：多个测试同时操作 `TempDir` 时可能产生冲突（已通过唯一 UUID 缓解）

### 边界情况

1. **空目录**：`sessions` 目录不存在时的处理
2. **无效 UUID**：文件名中包含无法解析为 UUID 的部分
3. **权限问题**：无法读取目录或文件时的错误处理
4. **符号链接**：未测试对符号链接的处理

### 改进建议

1. **性能优化**：
   - 添加基于 `notify` 的实时索引，减少文件系统遍历
   - 缓存最近访问的会话路径

2. **测试扩展**：
   - 添加大量文件（>10000）的性能测试
   - 测试并发写入和读取的场景
   - 添加对损坏 rollout 文件的容错测试

3. **功能增强**：
   - 支持模糊搜索会话名称
   - 添加按时间范围过滤的查找
   - 支持跨 `sessions` 和 `archived_sessions` 的统一搜索

4. **代码重构**：
   - 将文件系统遍历逻辑抽象为可插拔的存储后端
   - 统一 SQLite 和文件系统查找的接口

### 相关文件引用

- `codex-rs/core/src/rollout/list.rs` - 会话列表和查找实现
- `codex-rs/core/src/rollout/recorder.rs` - Rollout 记录器
- `codex-rs/core/src/rollout/session_index.rs` - 会话索引管理
- `codex-rs/core/src/state/mod.rs` - SQLite 状态管理
- `codex-rs/core/src/state/service.rs` - StateRuntime 实现
