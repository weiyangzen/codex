# Research: codex-rs/exec/tests/suite

## 场景与职责

`codex-rs/exec/tests/suite` 是 `codex-exec` crate 的集成测试套件目录。该目录包含对 `codex-exec` CLI 工具的全面集成测试，验证其作为非交互式 Codex 代理的核心功能。

**核心职责：**
1. 验证 `codex-exec` CLI 的命令行参数解析与处理
2. 测试会话管理（创建、恢复、持久化）
3. 验证沙箱策略执行（macOS Seatbelt / Linux Landlock）
4. 测试与 OpenAI Responses API 的集成
5. 验证工具调用（特别是 `apply_patch` 工具）
6. 测试认证、环境变量和配置覆盖
7. 验证错误处理和退出码行为

**测试架构定位：**
- 位于 `codex-rs/exec/tests/` 目录下，遵循 Rust 集成测试惯例
- 使用 `mod.rs` 聚合所有测试模块
- 依赖 `core_test_support` 提供共享的测试基础设施
- 使用 `wiremock` 模拟 OpenAI API 服务器
- 使用 `assert_cmd` 进行 CLI 断言测试

---

## 功能点目的

### 1. `mod.rs` - 测试模块聚合器
- 简单的模块声明文件，聚合所有测试子模块
- 被 `../all.rs` 引用作为集成测试入口

### 2. `add_dir.rs` - 额外目录参数测试
- **目的**: 验证 `--add-dir` 标志的功能
- **测试场景**:
  - 接受单个 `--add-dir` 标志
  - 接受多个 `--add-dir` 标志（多目录写入权限）
- **关键断言**: CLI 成功执行并返回退出码 0

### 3. `apply_patch.rs` - 补丁应用工具测试
- **目的**: 验证 `apply_patch` 工具的多种调用方式
- **测试场景**:
  - 独立 CLI 模式：`codex-exec apply-patch <patch>`
  - 工具调用模式：通过 mock SSE 流触发 `apply_patch` 函数调用
  - Freeform 补丁格式（自定义工具调用）
- **关键验证**: 文件内容按预期修改，支持添加、更新文件操作

### 4. `auth_env.rs` - 认证环境变量测试
- **目的**: 验证 `CODEX_API_KEY` 环境变量的使用
- **测试场景**: 确保 CLI 正确读取并使用 API key 发送 `Authorization: Bearer` 头
- **依赖**: `core_test_support::responses` 提供的 mock 服务器

### 5. `ephemeral.rs` - 临时模式测试
- **目的**: 验证 `--ephemeral` 标志的会话持久化行为
- **测试场景**:
  - 默认模式：会话数据持久化到磁盘（`~/.codex/sessions/*.jsonl`）
  - 临时模式：不创建会话文件
- **实现细节**: 扫描 `sessions` 目录计数 `.jsonl` 文件

### 6. `mcp_required_exit.rs` - MCP 服务器错误处理
- **目的**: 验证必需 MCP 服务器初始化失败时的错误处理
- **测试场景**: 配置一个 `required = true` 的无效 MCP 服务器
- **关键断言**: 进程以退出码 1 退出，stderr 包含特定错误信息

### 7. `originator.rs` - Originator 头测试
- **目的**: 验证 `Originator` HTTP 头的发送
- **测试场景**:
  - 默认发送 `codex_exec` 作为 originator
  - 支持 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 环境变量覆盖
- **实现**: 使用 `wiremock::matchers::header` 验证请求头

### 8. `output_schema.rs` - 输出模式测试
- **目的**: 验证 `--output-schema` 参数将 JSON Schema 传递给 API
- **测试场景**: 提供 schema 文件，验证请求体中的 `text.format` 字段
- **关键验证**: 请求包含 `json_schema` 类型的格式定义

### 9. `resume.rs` - 会话恢复功能测试
- **目的**: 全面测试会话恢复（resume）功能
- **测试场景**（共 7 个测试用例）：
  - `exec_resume_last_appends_to_existing_file`: `--last` 恢复最近会话
  - `exec_resume_last_accepts_prompt_after_flag_in_json_mode`: JSON 模式下 prompt 位置灵活性
  - `exec_resume_last_respects_cwd_filter_and_all_flag`: CWD 过滤和 `--all` 标志
  - `exec_resume_accepts_global_flags_after_subcommand`: 子命令后接受全局标志
  - `exec_resume_by_id_appends_to_existing_file`: 通过 session ID 恢复
  - `exec_resume_preserves_cli_configuration_overrides`: 保留 CLI 配置覆盖
  - `exec_resume_accepts_images_after_subcommand`: 恢复时附加图片
- **关键技术**: 使用 UUID marker 追踪会话文件，验证内容追加

### 10. `sandbox.rs` - 沙箱功能测试
- **目的**: 验证 macOS Seatbelt 和 Linux Landlock 沙箱
- **测试场景**:
  - Python 多进程锁在沙箱内工作
  - Python `getpwuid` 在沙箱内工作
  - 区分命令 CWD 和策略 CWD 的权限控制
  - Unix socketpair 通信允许
- **平台特定代码**: `#[cfg(target_os = "macos")]` / `#[cfg(target_os = "linux")]`
- **关键技术**: `run_code_under_sandbox` 辅助函数实现自我执行测试

### 11. `server_error_exit.rs` - 服务器错误处理
- **目的**: 验证服务器返回错误时的退出码行为
- **测试场景**: Mock `response.failed` 事件
- **关键断言**: 进程以退出码 1 退出（非零）

---

## 具体技术实现

### 测试基础设施依赖

#### 1. `core_test_support` 提供的关键组件

**`test_codex_exec::TestCodexExecBuilder`**:
```rust
pub struct TestCodexExecBuilder {
    home: TempDir,  // 隔离的 CODEX_HOME
    cwd: TempDir,   // 隔离的工作目录
}
```

**`responses` 模块**:
- `start_mock_server()`: 启动 wiremock 服务器
- `mount_sse_once()`: 挂载单次 SSE 响应
- `mount_sse_sequence()`: 挂载顺序 SSE 响应序列
- `sse()`: 构建 SSE 事件流
- 事件构造器：`ev_response_created`, `ev_completed`, `ev_assistant_message`, `ev_apply_patch_function_call` 等

#### 2. Mock SSE 事件流构建

```rust
let body = responses::sse(vec![
    responses::ev_response_created("response_1"),
    responses::ev_assistant_message("response_1", "Task completed"),
    responses::ev_completed("response_1"),
]);
responses::mount_sse_once(&server, body).await;
```

#### 3. CLI 命令构建模式

```rust
test.cmd_with_server(&server)
    .arg("--skip-git-repo-check")
    .arg("--sandbox")
    .arg("workspace-write")
    .arg("test prompt")
    .assert()
    .code(0);
```

### 关键数据结构和协议

#### 1. SSE 事件格式（OpenAI Responses API）

```
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{...}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

#### 2. Session 文件格式（JSONL）

```json
{"type":"session_meta","payload":{"id":"uuid","..."}}
{"type":"response_item","payload":{"type":"message","role":"user","..."}}
```

#### 3. Apply Patch 格式

```
*** Begin Patch
*** Add File: test.md
+Hello world
*** End Patch
```

### 平台特定实现

#### macOS Seatbelt
```rust
#[cfg(target_os = "macos")]
async fn spawn_command_under_sandbox(...) -> io::Result<Child> {
    use codex_core::seatbelt::spawn_command_under_seatbelt;
    spawn_command_under_seatbelt(...).await
}
```

#### Linux Landlock
```rust
#[cfg(target_os = "linux")]
async fn spawn_command_under_sandbox(...) -> io::Result<Child> {
    use codex_core::landlock::spawn_command_under_linux_sandbox;
    let codex_linux_sandbox_exe = codex_utils_cargo_bin::cargo_bin("codex-exec")?;
    spawn_command_under_linux_sandbox(codex_linux_sandbox_exe, ...).await
}
```

---

## 关键代码路径与文件引用

### 被测试的主要源文件

| 测试文件 | 被测试的源文件 | 功能 |
|---------|--------------|------|
| `add_dir.rs` | `codex-rs/exec/src/cli.rs` | `--add-dir` 参数定义 |
| `apply_patch.rs` | `codex-rs/exec/src/lib.rs`, `codex-rs/apply-patch/src/` | 补丁应用逻辑 |
| `auth_env.rs` | `codex-rs/core/src/auth.rs` | API key 环境变量 |
| `ephemeral.rs` | `codex-rs/exec/src/lib.rs` | 会话持久化控制 |
| `mcp_required_exit.rs` | `codex-rs/core/src/mcp/` | MCP 服务器初始化 |
| `originator.rs` | `codex-rs/core/src/default_client.rs` | Originator 头发送 |
| `output_schema.rs` | `codex-rs/exec/src/cli.rs` | `--output-schema` 参数 |
| `resume.rs` | `codex-rs/exec/src/cli.rs`, `codex-rs/core/src/rollout/` | 会话恢复逻辑 |
| `sandbox.rs` | `codex-rs/core/src/seatbelt/`, `codex-rs/core/src/landlock/` | 沙箱实现 |
| `server_error_exit.rs` | `codex-rs/exec/src/event_processor.rs` | 错误处理 |

### 测试辅助文件

- `../fixtures/cli_responses_fixture.sse`: 静态 SSE 响应 fixture
- `../fixtures/apply_patch_freeform_final.txt`: 预期补丁结果

### 测试支持库

- `codex-rs/core/tests/common/lib.rs`: 共享测试基础设施
- `codex-rs/core/tests/common/responses.rs`: Mock 服务器实现
- `codex-rs/core/tests/common/test_codex_exec.rs`: CLI 测试构建器

---

## 依赖与外部交互

### 内部依赖（Workspace crates）

```toml
[dev-dependencies]
core_test_support = { workspace = true }
codex_utils_cargo_bin = { workspace = true }
codex-apply-patch = { workspace = true }
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `assert_cmd` | CLI 命令断言 |
| `wiremock` | HTTP mock 服务器 |
| `tempfile` | 临时目录/文件 |
| `predicates` | 断言谓词 |
| `pretty_assertions` | 美观的断言输出 |
| `uuid` | 生成唯一 marker |
| `walkdir` | 目录遍历 |
| `libc` | Unix 系统调用（沙箱测试） |

### 外部系统交互

1. **Mock OpenAI API Server**: 通过 `wiremock` 在随机端口启动
2. **文件系统**: 创建临时目录作为隔离的 `CODEX_HOME` 和 CWD
3. **环境变量**: 
   - `CODEX_API_KEY`: API 认证
   - `CODEX_HOME`: 隔离配置目录
   - `CODEX_RS_SSE_FIXTURE`: 使用静态 fixture 替代网络请求
   - `OPENAI_BASE_URL`: 指向 mock 服务器

---

## 风险、边界与改进建议

### 当前风险与限制

1. **平台限制**:
   - 多个测试使用 `#![cfg(not(target_os = "windows"))]` 排除 Windows
   - `sandbox.rs` 使用 `#![cfg(unix)]` 仅支持 Unix 系统
   - Linux 沙箱测试需要 Landlock 支持，否则自动跳过

2. **测试隔离**:
   - 使用 `TempDir` 确保文件系统隔离
   - 环境变量修改可能影响并行测试（使用 `serial_test` 或进程隔离）

3. **时间敏感测试**:
   - `resume.rs` 中使用 `std::thread::sleep(std::time::Duration::from_millis(1100))` 确保 `updated_at` 时间戳差异
   - 可能导致测试运行缓慢

### 边界情况

1. **Session 恢复边界**:
   - `--last` 与 `--all` 标志的 CWD 过滤逻辑复杂
   - Session ID 与 prompt 的位置解析（clap 限制）

2. **沙箱边界**:
   - 命令 CWD 与沙箱策略 CWD 的区分
   - `/dev/shm` 在 Linux 上的特殊处理（Python 多进程）

3. **网络依赖**:
   - `skip_if_no_network!` 宏处理沙箱网络禁用情况
   - `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量检查

### 改进建议

1. **测试性能优化**:
   - 替换固定睡眠时间为条件等待或时间 mocking
   - 使用 `tokio::time::pause()` 进行异步时间控制

2. **覆盖率提升**:
   - 添加 Windows 平台的等效测试（使用 Windows 沙箱 API）
   - 增加更多错误场景测试（网络超时、无效响应格式）

3. **可维护性**:
   - 将 `find_session_file_containing_marker` 等辅助函数提取到共享库
   - 使用 builder 模式简化复杂的 CLI 参数组合测试

4. **文档**:
   - 为每个测试添加更详细的失败场景说明
   - 记录测试所需的系统依赖（Python3、bash 等）

### 相关配置与脚本

- **Build 配置**: `codex-rs/exec/Cargo.toml` 定义测试依赖
- **CI 集成**: `.github/workflows/` 中运行 `cargo test -p codex-exec`
- **研究清单**: `Docs/researches/blueprint_checklist.md` 第 268 行标记研究状态

---

*Research completed: 2026-03-21*
*Target: codex-rs/exec/tests/suite (DIR)*
