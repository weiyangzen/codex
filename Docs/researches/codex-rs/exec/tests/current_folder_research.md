# 研究报告: codex-rs/exec/tests

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/exec/tests` 是 `codex-exec` CLI 工具的集成测试套件目录。`codex-exec` 是 Codex 项目的核心命令行执行工具，提供非交互式的 AI 辅助编程能力。

### 核心职责

1. **集成测试执行**: 验证 `codex-exec` 端到端功能，包括 CLI 参数解析、配置加载、会话管理、沙箱执行等
2. **事件处理器测试**: 测试 JSONL 输出模式下的协议事件转换逻辑
3. **沙箱安全测试**: 验证 Linux (Landlock) 和 macOS (Seatbelt) 沙箱策略的正确实施
4. **会话恢复测试**: 测试 `--resume` 功能的多种场景
5. **MCP 服务器集成测试**: 验证 MCP (Model Context Protocol) 服务器的初始化和错误处理

### 测试架构

```
codex-rs/exec/tests/
├── all.rs                          # 测试入口，聚合所有测试模块
├── event_processor_with_json_output.rs  # JSONL 事件处理器单元测试
├── fixtures/                       # 测试固件数据
│   ├── apply_patch_freeform_final.txt   # apply_patch 期望输出
│   └── cli_responses_fixture.sse        # SSE 响应流固件
└── suite/                          # 集成测试套件
    ├── mod.rs                      # 套件模块声明
    ├── add_dir.rs                  # --add-dir 参数测试
    ├── apply_patch.rs              # apply_patch 工具测试
    ├── auth_env.rs                 # 环境变量认证测试
    ├── ephemeral.rs                # 临时会话模式测试
    ├── mcp_required_exit.rs        # MCP 服务器必需退出测试
    ├── originator.rs               # Originator 头部测试
    ├── output_schema.rs            # JSON Schema 输出测试
    ├── resume.rs                   # 会话恢复功能测试
    ├── sandbox.rs                  # 沙箱执行测试
    └── server_error_exit.rs        # 服务器错误退出测试
```

---

## 功能点目的

### 1. 事件处理器测试 (`event_processor_with_json_output.rs`)

**目的**: 验证 `EventProcessorWithJsonOutput` 将内部协议事件转换为标准 JSONL 输出格式的正确性。

**测试覆盖**:
- 会话配置事件 (`SessionConfigured`) → `thread.started`
- 任务启动 (`TurnStarted`) → `turn.started`
- 网络搜索 (`WebSearchBegin/End`) → `item.started/completed`
- 计划更新 (`PlanUpdate`) → TodoList 状态流转
- MCP 工具调用 (`McpToolCallBegin/End`) → 完整生命周期
- 协作代理 (`CollabAgentSpawnBegin/End`) → 多代理状态管理
- 命令执行 (`ExecCommandBegin/End`) → 输出捕获和退出码
- 补丁应用 (`PatchApplyBegin/End`) → 文件变更追踪
- 错误处理 (`Error/Warning/StreamError`) → 错误事件转换

### 2. CLI 参数测试 (`add_dir.rs`)

**目的**: 验证 `--add-dir` 参数允许添加额外的可写目录到沙箱。

**关键测试**:
- 单/多 `--add-dir` 参数接受性
- 与 `--sandbox workspace-write` 的集成

### 3. apply_patch 工具测试 (`apply_patch.rs`)

**目的**: 验证 `codex-exec` 作为独立 CLI 工具执行 patch 应用的能力。

**测试场景**:
- 独立 `apply_patch` 子命令执行
- 通过 SSE 流触发的 apply_patch 工具调用
- Freeform 格式的 patch 解析

### 4. 认证环境测试 (`auth_env.rs`)

**目的**: 验证 `CODEX_API_KEY` 环境变量的正确传递和使用。

**测试点**:
- API Key 通过环境变量注入
- Authorization Header 的正确构造 (`Bearer dummy`)

### 5. 临时会话测试 (`ephemeral.rs`)

**目的**: 验证 `--ephemeral` 模式下会话文件不被持久化。

**测试逻辑**:
- 默认模式: 会话持久化到 `~/.codex/sessions/*.jsonl`
- Ephemeral 模式: 会话文件计数为 0

### 6. MCP 服务器测试 (`mcp_required_exit.rs`)

**目的**: 验证必需 MCP 服务器初始化失败时的非零退出码行为。

**测试配置**:
```toml
[mcp_servers.required_broken]
command = "codex-definitely-not-a-real-binary"
required = true
```

### 7. Originator 头部测试 (`originator.rs`)

**目的**: 验证 `Originator` HTTP 头部的正确发送。

**测试场景**:
- 默认 `codex_exec` originator
- 通过 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 环境变量覆盖

### 8. JSON Schema 输出测试 (`output_schema.rs`)

**目的**: 验证 `--output-schema` 参数将 JSON Schema 正确注入请求。

**验证点**:
- Schema 文件读取和解析
- 请求体 `text.format` 字段的结构化输出格式

### 9. 会话恢复测试 (`resume.rs`)

**目的**: 全面测试 `resume` 子命令的各种场景。

**测试覆盖**:
- `resume --last`: 恢复最近会话
- `resume <session_id>`: 按 ID 恢复
- `resume --last --all`: 跨目录恢复
- 全局标志在子命令后的解析
- 配置覆盖的持久化
- 图像附件在恢复时的处理

### 10. 沙箱执行测试 (`sandbox.rs`)

**目的**: 验证多平台沙箱执行环境的正确性。

**测试场景**:
- Python 多进程锁在沙箱中的工作
- Python `getpwuid` 在沙箱中的可用性
- 命令 CWD 与策略 CWD 的区分
- Unix socketpair 通信权限

### 11. 服务器错误退出测试 (`server_error_exit.rs`)

**目的**: 验证服务器返回错误时 CLI 的非零退出码。

---

## 具体技术实现

### 事件转换架构

```rust
// 核心事件处理流程
protocol::Event → EventProcessorWithJsonOutput::collect_thread_events() → Vec<ThreadEvent> → JSONL

// 事件 ID 生成
item_{n}  // 原子自增序列
```

**关键数据结构**:

```rust
// 运行中命令追踪
struct RunningCommand {
    command: String,           // 格式化的命令字符串
    item_id: String,           // 关联的 ThreadItem ID
    aggregated_output: String, // 聚合输出
}

// 运行中 MCP 工具调用
struct RunningMcpToolCall {
    server: String,
    tool: String,
    item_id: String,
    arguments: JsonValue,
}

// 运行中协作工具调用
struct RunningCollabToolCall {
    tool: CollabTool,  // SpawnAgent | SendInput | Wait | CloseAgent
    item_id: String,
}
```

### 测试固件系统

**SSE 响应固件** (`cli_responses_fixture.sse`):
```
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture hello"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

**环境变量固件加载**:
```rust
env("CODEX_RS_SSE_FIXTURE", &fixture)
env("OPENAI_BASE_URL", "http://unused.local")
```

### Mock 服务器架构

使用 `wiremock` 库构建模拟 OpenAI API 服务器:

```rust
// 启动 Mock 服务器
let server = responses::start_mock_server().await;

// 构造 SSE 响应流
let body = responses::sse(vec![
    responses::ev_response_created("response_1"),
    responses::ev_assistant_message("response_1", "Hello"),
    responses::ev_completed("response_1"),
]);

// 挂载响应
responses::mount_sse_once(&server, body).await;
```

### 沙箱测试实现

**平台抽象**:
```rust
#[cfg(target_os = "macos")]
async fn spawn_command_under_sandbox(...) -> io::Result<Child> {
    use codex_core::seatbelt::spawn_command_under_seatbelt;
    // ...
}

#[cfg(target_os = "linux")]
async fn spawn_command_under_sandbox(...) -> io::Result<Child> {
    use codex_core::landlock::spawn_command_under_linux_sandbox;
    // ...
}
```

**自执行测试模式**:
```rust
const IN_SANDBOX_ENV_VAR: &str = "IN_SANDBOX";

pub async fn run_code_under_sandbox<F, Fut>(...) -> io::Result<Option<ExitStatus>>
where
    F: FnOnce() -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    if std::env::var(IN_SANDBOX_ENV_VAR).is_err() {
        // 父进程: 启动沙箱子进程
        spawn_command_under_sandbox(...).await
    } else {
        // 子进程: 执行测试体
        child_body().await;
        Ok(None)
    }
}
```

---

## 关键代码路径与文件引用

### 测试入口

| 文件 | 职责 |
|------|------|
| `all.rs` | 测试二进制入口，声明 `suite` 模块和 `event_processor_with_json_output` |
| `suite/mod.rs` | 套件模块聚合声明 |

### 单元测试

| 文件 | 测试目标 | 测试方法 |
|------|----------|----------|
| `event_processor_with_json_output.rs` | `EventProcessorWithJsonOutput` | 直接单元测试，构造协议事件输入，验证 JSONL 输出 |

### 集成测试

| 文件 | 测试场景 | 关键依赖 |
|------|----------|----------|
| `suite/add_dir.rs` | `--add-dir` 参数 | `test_codex_exec()`, `wiremock` |
| `suite/apply_patch.rs` | Patch 应用 | `codex_apply_patch`, `assert_cmd` |
| `suite/auth_env.rs` | API Key 认证 | `CODEX_API_KEY_ENV_VAR` |
| `suite/ephemeral.rs` | 临时会话 | `walkdir`, `CODEX_RS_SSE_FIXTURE` |
| `suite/mcp_required_exit.rs` | MCP 必需错误 | 配置写入 + Mock 服务器 |
| `suite/originator.rs` | Originator 头部 | `header()` Matcher |
| `suite/output_schema.rs` | JSON Schema | 文件 IO + 请求体验证 |
| `suite/resume.rs` | 会话恢复 | 多轮 CLI 执行 + 文件扫描 |
| `suite/sandbox.rs` | 沙箱执行 | 平台特定 spawn + 自执行 |
| `suite/server_error_exit.rs` | 错误退出码 | `response.failed` 事件 |

### 被测源码

| 被测文件 | 路径 | 功能 |
|----------|------|------|
| `lib.rs` | `codex-rs/exec/src/` | 主运行时逻辑，`run_main()`, `run_exec_session()` |
| `cli.rs` | `codex-rs/exec/src/` | CLI 参数定义，`Cli`, `Command`, `ResumeArgs` |
| `event_processor_with_jsonl_output.rs` | `codex-rs/exec/src/` | JSONL 事件处理器 |
| `exec_events.rs` | `codex-rs/exec/src/` | 输出事件类型定义 |
| `event_processor.rs` | `codex-rs/exec/src/` | 事件处理器 trait |

### 测试支持库

| 文件 | 路径 | 功能 |
|------|------|------|
| `test_codex_exec.rs` | `codex-rs/core/tests/common/` | `TestCodexExecBuilder`, CLI 命令构造 |
| `responses.rs` | `codex-rs/core/tests/common/` | Mock 服务器，SSE 事件构造 |
| `lib.rs` | `codex-rs/core/tests/common/` | 共享测试工具，配置加载 |

---

## 依赖与外部交互

### 直接依赖 (Cargo)

```toml
[dev-dependencies]
anyhow = "..."
assert_cmd = "..."        # CLI 断言测试
codex_apply_patch = "..." # Patch 应用
codex_core = "..."
codex_protocol = "..."
codex_utils_cargo_bin = "..."
core_test_support = "..." # 内部测试支持库
predicates = "..."        # 断言谓词
pretty_assertions = "..." # 美化断言输出
tempfile = "..."          # 临时目录
walkdir = "..."           # 目录遍历
wiremock = "..."          # HTTP Mock 服务器
```

### 外部系统交互

| 系统 | 交互方式 | 测试处理 |
|------|----------|----------|
| OpenAI API | HTTP SSE 流 | `wiremock` Mock 服务器 |
| 文件系统 | 临时目录操作 | `tempfile::TempDir` |
| 沙箱 (macOS) | Seatbelt | 条件编译 + 能力探测 |
| 沙箱 (Linux) | Landlock | 条件编译 + 执行测试 |
| MCP 服务器 | 进程启动 | 配置无效命令模拟失败 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 测试隔离的 Codex 配置目录 |
| `CODEX_API_KEY` | API 认证 |
| `CODEX_RS_SSE_FIXTURE` | SSE 固件文件路径 |
| `OPENAI_BASE_URL` | Mock 服务器地址 |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | Originator 覆盖 |
| `IN_SANDBOX` | 沙箱自执行检测 |
| `CODEX_SANDBOX` | 沙箱类型检测 (seatbelt) |

---

## 风险、边界与改进建议

### 当前风险

1. **平台条件编译复杂性**
   - `#![cfg(not(target_os = "windows"))]` 和 `#![cfg(unix)]` 导致 Windows 测试覆盖缺失
   - 沙箱测试在 Linux 需要 Landlock 支持，可能跳过

2. **测试执行时间**
   - `resume.rs` 测试使用 `std::thread::sleep(std::time::Duration::from_millis(1100))` 等待秒级时间戳更新
   - 多轮 CLI 执行导致测试缓慢

3. **固件维护**
   - SSE 固件硬编码在 `.sse` 文件中，协议变更需同步更新

4. **沙箱测试脆弱性**
   - `linux_sandbox_test_env()` 依赖 `/usr/bin/true` 可用性
   - Python 测试依赖系统 Python3 安装

### 边界情况

1. **事件 ID 生成**: 使用 `AtomicU64` 保证线程安全，但测试假设单线程顺序执行
2. **命令字符串化**: `shlex::try_join` 失败时回退到简单空格连接
3. **WebSearch 查询**: Begin 事件时查询未知，End 事件时才填充

### 改进建议

1. **增加 Windows 测试覆盖**
   ```rust
   // 当前: 完全跳过 Windows
   #![cfg(not(target_os = "windows"))]
   
   // 建议: 对非沙箱功能启用 Windows 测试
   ```

2. **优化 resume 测试时间**
   ```rust
   // 当前: 硬编码 sleep
   std::thread::sleep(std::time::Duration::from_millis(1100));
   
   // 建议: 使用文件系统 touch 或模拟时间
   ```

3. **增加并发测试**
   - 当前测试多为单线程
   - 建议增加 `running_commands` 等并发结构的并发访问测试

4. **改进错误消息断言**
   ```rust
   // 当前: 部分匹配
   .stderr(contains("required MCP servers failed to initialize"));
   
   // 建议: 精确匹配或使用快照测试 (insta)
   ```

5. **统一固件管理**
   - 将 SSE 固件从 `.sse` 文件迁移到 Rust 代码或生成脚本
   - 便于类型检查和重构时自动更新

6. **增加性能基准测试**
   - 事件处理器转换性能
   - 大规模输出流处理性能

---

## 附录: 测试执行命令

```bash
# 运行所有 exec 测试
cargo test -p codex-exec

# 运行特定测试
cargo test -p codex-exec event_processor_with_json_output
cargo test -p codex-exec accepts_add_dir_flag
cargo test -p codex-exec exec_resume_last_appends_to_existing_file

# 运行带输出
cargo test -p codex-exec -- --nocapture
```

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/exec/tests 目录及其直接依赖*
