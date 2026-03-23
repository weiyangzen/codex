# resume.rs 深度研究文档

## 场景与职责

`resume.rs` 是 `codex-exec` CLI 工具最复杂的集成测试模块，专门验证 `resume` 子命令的完整功能。该子命令允许用户恢复之前的会话，继续对话或添加新的提示。

**核心场景**：
- 用户需要继续之前的对话会话
- 通过 `--last` 恢复最近的会话
- 通过会话 ID 恢复特定会话
- 支持在恢复时附加图片和新的提示

## 功能点目的

### 1. 最近会话恢复 (`exec_resume_last_appends_to_existing_file`)
验证 `--last` 参数能够正确找到并恢复最近的会话文件。

### 2. JSON 模式提示位置 (`exec_resume_last_accepts_prompt_after_flag_in_json_mode`)
验证在 `--json` 模式下，提示可以放在 `--last` 标志之后。

### 3. CWD 过滤和 `--all` 标志 (`exec_resume_last_respects_cwd_filter_and_all_flag`)
验证 `--last` 默认按当前工作目录过滤，而 `--all` 可以禁用过滤。

### 4. 全局标志传递 (`exec_resume_accepts_global_flags_after_subcommand`)
验证全局标志（如 `--json`、`--model`）可以在子命令后使用。

### 5. 按 ID 恢复 (`exec_resume_by_id_appends_to_existing_file`)
验证通过会话 ID 恢复特定会话的功能。

### 6. 配置覆盖保持 (`exec_resume_preserves_cli_configuration_overrides`)
验证恢复会话时 CLI 配置覆盖（如 `--model`、`--sandbox`）仍然有效。

### 7. 图片附件 (`exec_resume_accepts_images_after_subcommand`)
验证恢复会话时可以附加图片。

## 具体技术实现

### 会话文件结构

**文件位置**: `~/.codex/sessions/<uuid>.jsonl`

**格式**（JSON Lines）：
```jsonl
{"type":"session_meta","payload":{"id":"uuid","..."}}
{"type":"response_item","payload":{"type":"message","role":"user","..."}}
{"type":"response_item","payload":{"type":"message","role":"assistant","..."}}
```

### 关键辅助函数

#### 查找包含标记的会话文件
```rust
fn find_session_file_containing_marker(
    sessions_dir: &std::path::Path,
    marker: &str,
) -> Option<std::path::PathBuf> {
    // 遍历 sessions 目录
    // 查找包含特定标记的 .jsonl 文件
    // 解析每行的 JSON，检查 message.content
}
```

#### 提取会话 ID
```rust
fn extract_conversation_id(path: &std::path::Path) -> String {
    // 读取文件第一行（session_meta）
    // 提取 payload.id 字段
}
```

#### 统计用户图片数量
```rust
fn last_user_image_count(path: &std::path::Path) -> usize {
    // 遍历所有行
    // 查找 role=user 的 message
    // 统计 content 中 type=input_image 的条目
}
```

### CLI 参数解析

**`codex-rs/exec/src/cli.rs:117-215`**:
```rust
#[derive(Debug, clap::Subcommand)]
pub enum Command {
    Resume(ResumeArgs),
    ...
}

#[derive(Debug)]
pub struct ResumeArgs {
    pub session_id: Option<String>,  // 会话 ID 或名称
    pub last: bool,                  // --last 标志
    pub all: bool,                   // --all 标志
    pub images: Vec<PathBuf>,        // --image 附件
    pub prompt: Option<String>,      // 恢复后的提示
}
```

### 恢复路径解析

**`codex-rs/exec/src/lib.rs:1404-1444`**:
```rust
async fn resolve_resume_path(
    config: &Config,
    args: &crate::cli::ResumeArgs,
) -> anyhow::Result<Option<PathBuf>> {
    if args.last {
        // 使用 RolloutRecorder 查找最新会话
        RolloutRecorder::find_latest_thread_path(
            config,
            /*page_size*/ 1,
            /*cursor*/ None,
            ThreadSortKey::UpdatedAt,
            &[],
            Some(default_provider_filter.as_slice()),
            &config.model_provider_id,
            filter_cwd,
        ).await
    } else if let Some(id_str) = args.session_id.as_deref() {
        // 按 UUID 或名称查找
        if Uuid::parse_str(id_str).is_ok() {
            find_thread_path_by_id_str(&config.codex_home, id_str).await
        } else {
            find_thread_path_by_name_str(&config.codex_home, id_str).await
        }
    } else {
        Ok(None)
    }
}
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **CLI 参数定义**: `codex-rs/exec/src/cli.rs:117-215`
   - `ResumeArgs` 结构体定义
   - 从 `ResumeArgsRaw` 转换处理 `--last` 特殊情况

2. **恢复逻辑**: `codex-rs/exec/src/lib.rs:545-592`
   - 处理 `Command::Resume` 分支
   - 调用 `resolve_resume_path` 解析会话路径
   - 发送 `ThreadResume` 或 `ThreadStart` 请求

3. **会话查找**: `codex-rs/core/src/rollout_recorder.rs`
   - `find_latest_thread_path` 实现
   - 支持按时间、CWD、provider 过滤

4. **会话 ID 查找**: `codex-rs/core/src/lib.rs`
   - `find_thread_path_by_id_str` - 按 UUID 查找
   - `find_thread_path_by_name_str` - 按名称查找

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境 |
| `find_resource!` | `codex_utils_cargo_bin` | 定位 fixture |
| `WalkDir` | `walkdir` crate | 目录遍历 |
| `Uuid` | `uuid` crate | 生成唯一标记 |

### 测试数据

**图片数据**（内联 PNG）：
```rust
let image_bytes: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, ... // PNG 文件头
];
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `uuid` | 生成唯一测试标记 |
| `walkdir` | 目录遍历 |
| `tempfile` | 临时目录 |
| `pretty_assertions` | 更好的断言输出 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_RS_SSE_FIXTURE` | SSE fixture 文件路径 |
| `OPENAI_BASE_URL` | 指向无效地址，强制使用 fixture |

### 时序处理

测试中处理 `updated_at` 的秒级精度限制：
```rust
// `updated_at` is second-granularity
std::thread::sleep(std::time::Duration::from_millis(1100));
```

## 风险、边界与改进建议

### 当前风险

1. **时序敏感**: 依赖 `updated_at` 时间戳，使用 sleep  workaround
2. **Fixture 依赖**: 使用固定 SSE 响应
3. **文件系统依赖**: 依赖特定的文件命名和组织结构

### 边界情况

1. **并发恢复**: 多个进程同时恢复同一会话
2. **会话损坏**: 会话文件格式损坏的处理
3. **磁盘满**: 恢复时磁盘空间不足
4. **权限变更**: 会话文件权限变更
5. **跨设备恢复**: 会话在不同设备间的恢复

### 改进建议

1. **消除 sleep**: 使用更可靠的时序控制机制
   ```rust
   // 使用 mock 时钟或文件系统事件
   ```

2. **增加错误场景**:
   ```rust
   #[test]
   fn exec_resume_fails_with_invalid_session_id() { ... }
   
   #[test]
   fn exec_resume_handles_corrupted_session_file() { ... }
   ```

3. **并发测试**: 验证多线程/多进程恢复行为

4. **性能测试**: 大会话的恢复性能

5. **迁移测试**: 不同版本间的会话兼容性

### 相关文件

- `codex-rs/exec/src/cli.rs` - Resume 参数定义
- `codex-rs/exec/src/lib.rs` - Resume 逻辑实现
- `codex-rs/core/src/rollout_recorder.rs` - 会话记录和查找
- `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse` - 测试 fixture

### 会话管理架构

```
┌─────────────────┐
│   codex-exec    │
│  (resume 命令)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ resolve_resume  │
│   _path()       │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌──────────┐
│ --last │ │ session  │
│ 查找   │ │  ID 查找 │
└────┬───┘ └────┬─────┘
     │          │
     ▼          ▼
┌─────────────────────┐
│ RolloutRecorder     │
│ find_latest_thread  │
│ _path()             │
└─────────────────────┘
```
