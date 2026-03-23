# ephemeral.rs 深度研究文档

## 场景与职责

`ephemeral.rs` 是 `codex-exec` CLI 工具的会话持久化测试模块，专门验证 `--ephemeral` 参数的功能。该参数控制是否在磁盘上持久化保存会话（rollout）文件。

**核心场景**：
- 用户执行一次性任务，不需要保留会话历史
- CI/CD 环境中避免产生临时文件
- 隐私敏感场景，不保留对话记录

## 功能点目的

### 1. 默认持久化测试 (`persists_rollout_file_by_default`)

验证在不使用 `--ephemeral` 参数时，会话文件会被正确保存到 `CODEX_HOME/sessions/` 目录。

### 2. 临时模式测试 (`does_not_persist_rollout_file_in_ephemeral_mode`)

验证使用 `--ephemeral` 参数时，不会创建会话文件。

## 具体技术实现

### 会话文件结构

**存储位置**: `~/.codex/sessions/<uuid>.jsonl`

**文件格式**（JSON Lines）：
```jsonl
{"type":"session_meta","payload":{"id":"uuid","..."}}
{"type":"response_item","payload":{"type":"message","..."}}
...
```

### 测试流程

#### 默认持久化测试
```
创建 TestCodexExec 环境
  ↓
加载 SSE fixture 文件
  ↓
执行 codex-exec 命令（无 --ephemeral）
  ├─ CODEX_RS_SSE_FIXTURE=<fixture_path>
  ├─ OPENAI_BASE_URL=http://unused.local
  ├─ --skip-git-repo-check
  └─ "default persistence behavior"
  ↓
验证退出码为 0
  ↓
统计 sessions 目录中的 .jsonl 文件数量
  ↓
断言数量为 1
```

#### 临时模式测试
```
创建 TestCodexExec 环境
  ↓
加载 SSE fixture 文件
  ↓
执行 codex-exec 命令（带 --ephemeral）
  ├─ --ephemeral
  └─ ...其他参数同上
  ↓
验证退出码为 0
  ↓
统计 sessions 目录中的 .jsonl 文件数量
  ↓
断言数量为 0
```

### 辅助函数

```rust
fn session_rollout_count(home_path: &std::path::Path) -> usize {
    let sessions_dir = home_path.join("sessions");
    if !sessions_dir.exists() {
        return 0;
    }
    WalkDir::new(sessions_dir)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| entry.file_name().to_string_lossy().ends_with(".jsonl"))
        .count()
}
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **CLI 参数定义**: `codex-rs/exec/src/cli.rs:74-76`
   ```rust
   /// Run without persisting session files to disk.
   #[arg(long = "ephemeral", global = true, default_value_t = false)]
   pub ephemeral: bool,
   ```

2. **配置覆盖**: `codex-rs/exec/src/lib.rs:359`
   ```rust
   ephemeral: ephemeral.then_some(true),
   ```

3. **会话记录器**: `codex-rs/core/src/rollout_recorder.rs`
   - 根据 `ephemeral` 配置决定是否写入文件
   - 处理文件滚动和压缩

4. **Thread 启动参数**: `codex-rs/exec/src/lib.rs:928`
   ```rust
   ThreadStartParams {
       ephemeral: Some(config.ephemeral),
       ...
   }
   ```

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `find_resource!` | `codex_utils_cargo_bin` | 定位 fixture 文件 |
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境 |
| `WalkDir` | `walkdir` crate | 目录遍历 |

### Fixture 文件

**`codex-rs/exec/tests/fixtures/cli_responses_fixture.sse`**:
```
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{...}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `walkdir` | 目录遍历和文件计数 |
| `tempfile` | 临时目录创建 |
| `assert_cmd` | CLI 测试断言 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_RS_SSE_FIXTURE` | 指定 SSE fixture 文件路径 |
| `OPENAI_BASE_URL` | 指向无效地址，强制使用 fixture |

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

## 风险、边界与改进建议

### 当前风险

1. **Fixture 依赖**: 使用固定 SSE 响应，不测试真实场景
2. **简单计数**: 仅验证文件存在性，不验证内容正确性
3. **时序问题**: 未测试并发场景下的文件写入

### 边界情况

1. **磁盘满**: 未测试磁盘空间不足时的行为
2. **权限问题**: 未测试无写权限目录的处理
3. **会话恢复**: 未测试 ephemeral 模式下的会话恢复行为
4. **大会话**: 未测试大量对话时的内存使用

### 改进建议

1. **内容验证**: 验证会话文件内容格式正确
   ```rust
   let content = std::fs::read_to_string(&session_file)?;
   assert!(content.contains("session_meta"));
   ```

2. **错误场景**: 测试磁盘满、权限不足等错误

3. **性能测试**: 大量消息时的写入性能

4. **清理测试**: 验证进程退出时的资源清理

5. **配置组合**: 测试 `--ephemeral` 与其他参数的组合

### 相关文件

- `codex-rs/core/src/rollout_recorder.rs` - 会话记录实现
- `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse` - 测试 fixture
