# cli_stream.rs 深入研究文档

## 场景与职责

`cli_stream.rs` 是 Codex CLI 的端到端集成测试文件，专注于测试 **CLI 命令行接口的流式响应功能**。该测试文件通过启动真实的 Codex 二进制程序，模拟用户与 Codex CLI 的完整交互流程，验证从命令行输入到 SSE（Server-Sent Events）流式响应输出的端到端功能。

### 核心职责

1. **CLI 流式响应测试**：验证 `codex exec` 命令能够正确处理用户输入，并通过流式 SSE 响应返回 AI 生成的内容
2. **配置覆盖测试**：验证 CLI 参数（`-c`）和环境变量能够正确覆盖配置文件中的设置
3. **模型指令文件测试**：验证 `--model-instructions-file` 参数能够正确加载自定义系统提示词
4. **Profile 配置测试**：验证 `--profile` 参数能够正确加载指定配置段落的模型指令文件
5. **会话管理测试**：验证会话创建、持久化和恢复功能（`integration_creates_and_checks_session_file`）
6. **Git 信息收集测试**：验证 Codex 能够正确收集当前 Git 仓库的上下文信息（commit hash、branch、remote URL）

### 业务背景

Codex CLI 是 OpenAI Codex 的命令行界面，允许用户：
- 通过自然语言与 AI 交互，执行代码编辑、文件操作等任务
- 使用 `--model-instructions-file` 自定义 AI 的系统提示词
- 使用 Profile 功能管理不同场景的配置
- 自动收集 Git 上下文信息，帮助 AI 理解代码库状态

---

## 功能点目的

### 1. 基础流式响应测试

| 测试函数 | 目的 |
|---------|------|
| `responses_mode_stream_cli` | 验证 CLI 能够通过 Mock 服务器流式接收并显示 AI 响应 |
| `responses_api_stream_cli` | 验证 CLI 能够从本地 SSE fixture 文件读取响应（离线测试） |

### 2. 配置覆盖与兼容性

| 测试函数 | 目的 |
|---------|------|
| `responses_mode_stream_cli_supports_openai_base_url_env_fallback` | 验证 `OPENAI_BASE_URL` 环境变量作为废弃的 fallback 仍然可用 |
| `responses_mode_stream_cli_supports_openai_base_url_config_override` | 验证 `openai_base_url` 配置项能够覆盖内置 OpenAI provider 的请求地址 |

### 3. 模型指令文件

| 测试函数 | 目的 |
|---------|------|
| `exec_cli_applies_model_instructions_file` | 验证 `-c model_instructions_file=...` 参数能够正确加载自定义指令文件 |
| `exec_cli_profile_applies_model_instructions_file` | 验证 `--profile` 参数能够正确应用 profile-scoped 的模型指令文件配置 |

### 4. 会话管理

| 测试函数 | 目的 |
|---------|------|
| `integration_creates_and_checks_session_file` | 端到端验证：创建会话 → 写入 rollout 文件 → 验证文件结构 → 恢复会话 → 验证追加写入 |

### 5. Git 信息收集

| 测试函数 | 目的 |
|---------|------|
| `integration_git_info_unit_test` | 验证 Git 信息收集功能：初始化仓库 → 创建提交 → 创建分支 → 添加 remote → 验证收集的 GitInfo |

---

## 具体技术实现

### 1. 测试架构概览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         cli_stream.rs 测试架构                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐    │
│  │   测试代码    │────▶│  Codex CLI   │────▶│   Mock HTTP Server   │    │
│  │              │     │   二进制      │     │   (wiremock)         │    │
│  └──────────────┘     └──────────────┘     └──────────────────────┘    │
│        │                      │                       │                 │
│        │                      │                       │                 │
│        ▼                      ▼                       ▼                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐    │
│  │ assert_cmd   │     │  TempDir     │     │   SSE Stream         │    │
│  │ (Command)    │     │  (CODEX_HOME)│     │   (mock responses)   │    │
│  └──────────────┘     └──────────────┘     └──────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2. 关键数据结构

```rust
// Git 信息结构（codex_protocol::protocol::GitInfo）
pub struct GitInfo {
    pub commit_hash: Option<String>,      // Git commit SHA (40字符)
    pub branch: Option<String>,           // 当前分支名
    pub repository_url: Option<String>,   // 远程仓库 URL
}

// 会话元数据结构（SessionMeta）
// 存储在 sessions/YYYY/MM/DD/<uuid>.jsonl 文件中
{
    "type": "session_meta",
    "payload": {
        "id": "<session-id>",
        "timestamp": "2026-03-23T09:27:11Z",
        "git_info": { ... },
        ...
    }
}

// 响应条目结构（ResponseItem）
{
    "type": "response_item",
    "payload": {
        "type": "message",
        "role": "assistant",
        "content": [...]
    }
}
```

### 3. CLI 执行流程

```rust
// 典型的 CLI 测试执行流程
async fn responses_mode_stream_cli() {
    // 1. 启动 Mock 服务器
    let server = MockServer::start().await;
    
    // 2. 构造 SSE 响应
    let sse = responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_assistant_message("msg-1", "hi"),
        responses::ev_completed("resp-1"),
    ]);
    let resp_mock = responses::mount_sse_once(&server, sse).await;
    
    // 3. 准备临时 CODEX_HOME
    let home = TempDir::new().unwrap();
    
    // 4. 构造 provider 覆盖配置
    let provider_override = format!(
        "model_providers.mock={{ name = \"mock\", base_url = \"{}/v1\", env_key = \"PATH\", wire_api = \"responses\" }}",
        server.uri()
    );
    
    // 5. 执行 CLI 命令
    let bin = codex_utils_cargo_bin::cargo_bin("codex").unwrap();
    let mut cmd = AssertCommand::new(bin);
    cmd.arg("exec")
        .arg("--skip-git-repo-check")  // 跳过 Git 检查
        .arg("-c").arg(&provider_override)  // 覆盖 provider 配置
        .arg("-c").arg("model_provider=\"mock\"")
        .arg("-C").arg(&repo_root)      // 设置工作目录
        .arg("hello?");                 // 用户输入
    cmd.env("CODEX_HOME", home.path())
        .env("OPENAI_API_KEY", "dummy");
    
    // 6. 验证输出
    let output = cmd.output().unwrap();
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("hi"));
    
    // 7. 验证请求
    let request = resp_mock.single_request();
    assert_eq!(request.path(), "/v1/responses");
}
```

### 4. 会话文件结构

```
CODEX_HOME/
├── sessions/
│   └── 2026/
│       └── 03/
│           └── 23/
│               └── <uuid>.jsonl          # 会话记录文件
│
# 会话文件格式（JSON Lines）
# Line 1: SessionMeta
{"type":"session_meta","payload":{"id":"...","timestamp":"...",...}}

# Line 2+: ResponseItem / Event
{"type":"response_item","payload":{...}}
{"type":"response_item","payload":{...}}
...
```

### 5. 测试辅助函数

```rust
// 获取仓库根目录
fn repo_root() -> std::path::PathBuf {
    codex_utils_cargo_bin::repo_root().expect("failed to resolve repo root")
}

// 获取 SSE fixture 文件路径
fn cli_responses_fixture() -> std::path::PathBuf {
    find_resource!("tests/cli_responses_fixture.sse").expect("failed to resolve fixture path")
}

// fixture 文件内容示例（SSE 格式）
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture hello"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

### 6. Git 信息收集流程

```rust
// Git 信息收集流程（integration_git_info_unit_test）
async fn integration_git_info_unit_test() {
    // 1. 创建临时目录作为 Git 仓库
    let temp_dir = TempDir::new().unwrap();
    let git_repo = temp_dir.path().to_path_buf();
    
    // 2. 初始化 Git 仓库
    git init
    git config user.name "Integration Test"
    git config user.email "test@example.com"
    
    // 3. 创建文件并提交
    write("test.txt", "integration test content")
    git add .
    git commit -m "Integration test commit"
    
    // 4. 创建分支
    git checkout -b "integration-test-branch"
    
    // 5. 添加远程
    git remote add origin "https://github.com/example/integration-test.git"
    
    // 6. 调用 Git 信息收集
    let git_info = codex_core::git_info::collect_git_info(&git_repo).await;
    
    // 7. 验证结果
    assert!(git_info.commit_hash.is_some());
    assert_eq!(git_info.branch, Some("integration-test-branch".to_string()));
    assert!(git_info.repository_url.is_some());
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/cli/src/main.rs` | CLI 入口点，命令行参数解析 |
| `codex-rs/cli/src/exec.rs` | `exec` 子命令实现 |
| `codex-rs/core/src/codex.rs` | Core Codex 逻辑，会话管理 |
| `codex-rs/core/src/client.rs` | ModelClient，处理 API 请求和 SSE 流 |
| `codex-rs/core/src/git_info.rs` | Git 信息收集实现 |
| `codex-rs/core/src/config.rs` | 配置加载和覆盖逻辑 |

### 测试相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/suite/cli_stream.rs` | 本研究文档对应的测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试公共库，提供 `skip_if_no_network!` 等宏 |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应辅助函数（`responses::sse`、`responses::mount_sse_once` 等） |
| `codex-rs/core/tests/cli_responses_fixture.sse` | 本地 SSE fixture 文件，用于离线测试 |

### 关键代码片段

#### Mock 响应辅助函数（tests/common/responses.rs）

```rust
// 构建 SSE 流响应体
pub fn sse(events: Vec<Value>) -> String {
    let mut out = String::new();
    for ev in events {
        let kind = ev.get("type").and_then(|v| v.as_str()).unwrap();
        writeln!(&mut out, "event: {kind}").unwrap();
        if !ev.as_object().map(|o| o.len() == 1).unwrap_or(false) {
            write!(&mut out, "data: {ev}\n\n").unwrap();
        } else {
            out.push('\n');
        }
    }
    out
}

// SSE 事件构造器
pub fn ev_response_created(id: &str) -> Value {
    serde_json::json!({
        "type": "response.created",
        "response": { "id": id }
    })
}

pub fn ev_assistant_message(id: &str, text: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "message",
            "role": "assistant",
            "id": id,
            "content": [{"type": "output_text", "text": text}]
        }
    })
}

pub fn ev_completed(id: &str) -> Value {
    serde_json::json!({
        "type": "response.completed",
        "response": {
            "id": id,
            "usage": {"input_tokens":0,"output_tokens":0,"total_tokens":0}
        }
    })
}

// 挂载 SSE Mock 响应
pub async fn mount_sse_once(server: &MockServer, body: String) -> ResponseMock {
    let (mock, response_mock) = base_mock();
    mock.respond_with(sse_response(body))
        .up_to_n_times(1)
        .mount(server)
        .await;
    response_mock
}
```

#### 文件等待辅助函数（tests/common/lib.rs）

```rust
pub mod fs_wait {
    // 异步等待路径存在
    pub async fn wait_for_path_exists(
        path: impl Into<PathBuf>,
        timeout: Duration,
    ) -> Result<PathBuf> {
        // 使用 notify crate 监听文件系统事件
        // 超时后返回错误
    }
    
    // 异步等待匹配文件出现
    pub async fn wait_for_matching_file(
        root: impl Into<PathBuf>,
        timeout: Duration,
        predicate: impl FnMut(&Path) -> bool + Send + 'static,
    ) -> Result<PathBuf> {
        // 扫描目录 + 监听文件系统事件
    }
}
```

#### Git 信息收集（core/src/git_info.rs）

```rust
pub async fn collect_git_info(repo_path: &Path) -> Option<GitInfo> {
    // 1. 检查是否是 Git 仓库
    // 2. 获取当前 commit hash: git rev-parse HEAD
    // 3. 获取当前分支: git branch --show-current
    // 4. 获取远程 URL: git remote get-url origin
    // 5. 返回 GitInfo 结构
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `assert_cmd` | 执行 CLI 命令并断言输出 |
| `wiremock` | Mock HTTP 服务器 |
| `tempfile::TempDir` | 创建临时 CODEX_HOME 目录 |
| `tokio` | 异步运行时（`#[tokio::test]`） |
| `uuid` | 生成唯一标识符用于测试标记 |
| `notify` | 文件系统事件监听（fs_wait 模块） |

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `codex_utils_cargo_bin` | 定位编译后的 Codex 二进制文件 |
| `codex_core::git_info` | Git 信息收集 |
| `core_test_support::*` | 测试辅助函数和宏 |
| `codex_protocol::protocol::GitInfo` | Git 信息数据结构 |

### 外部服务交互

```
测试中的 Mock 服务器
    │
    ├── POST /v1/responses
    │   └── 返回 SSE 流（response.created → output_item.done → response.completed）
    │
    └── 实际生产环境
        └── https://api.openai.com/v1/responses
```

---

## 风险、边界与改进建议

### 当前风险点

1. **测试执行时间**
   - 使用 `#[tokio::test(flavor = "multi_thread", worker_threads = 2)]` 启动多线程运行时
   - CLI 执行涉及进程创建，测试时间较长（每个测试 30 秒超时）
   - **缓解措施**：使用 `--skip-git-repo-check` 跳过不必要的 Git 检查

2. **路径依赖**
   - 测试依赖 `codex_utils_cargo_bin::repo_root()` 定位仓库根目录
   - 在不同构建环境（Bazel、Cargo）中可能表现不一致
   - **缓解措施**：使用 `find_resource!` 宏处理资源路径

3. **环境隔离**
   - 测试使用 `TempDir` 作为 `CODEX_HOME`，但 CLI 可能读取其他环境变量
   - 某些配置可能从用户主目录的 `~/.codex/config.toml` 继承
   - **缓解措施**：显式设置所有相关环境变量，使用 `-c` 参数覆盖配置

4. **Flaky Test 风险**
   - `integration_creates_and_checks_session_file` 使用文件系统事件监听
   - 在高负载或慢 IO 环境下可能超时
   - **缓解措施**：使用 `wait_for_matching_file` 带超时重试

### 边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| CLI 二进制未编译 | `cargo_bin("codex")` 返回错误，测试失败 |
| Mock 服务器端口冲突 | `MockServer::start()` 自动分配可用端口 |
| 会话目录创建延迟 | `fs_wait::wait_for_path_exists` 带 5 秒超时 |
| Git 仓库不存在 | `--skip-git-repo-check` 跳过检查，或 `collect_git_info` 返回 None |
| 配置文件解析错误 | CLI 返回非零退出码，测试断言失败 |

### 改进建议

1. **测试速度优化**
   - 考虑使用 `std::process::Command` 直接执行而非 `assert_cmd`，减少依赖
   - 对于纯配置测试，考虑使用单元测试替代集成测试
   - 使用 `CARGO_TARGET_TMPDIR` 共享编译产物

2. **测试覆盖增强**
   - 添加测试：验证 WebSocket 模式下的流式响应
   - 添加测试：验证配置加载优先级（CLI 参数 > 环境变量 > 配置文件）
   - 添加测试：验证错误处理（网络错误、API 错误码）

3. **代码结构优化**
   - `cli_stream.rs` 中测试函数较长，建议提取公共的 CLI 执行辅助函数
   - 建议创建 `CliTestContext` 结构统一管理临时目录、Mock 服务器、CLI 命令构造

4. **可观测性增强**
   - 当前使用 `println!` 输出调试信息，建议改用 `tracing`
   - 添加测试执行时间的监控，及时发现性能退化

5. **跨平台兼容性**
   - 当前测试在 Windows 上可能失败（路径分隔符、shell 命令）
   - 建议使用 `std::path::PathBuf` 处理路径，避免硬编码 `/`
   - 对于 Git 测试，确保使用 `git` 命令而非依赖特定 shell

### 相关配置项

```toml
# config.toml 中相关配置
model_provider = "openai"  # 或自定义 provider

[model_providers.mock]
name = "mock"
base_url = "http://localhost:1234/v1"
env_key = "PATH"  # 用于获取 API key 的环境变量
wire_api = "responses"  # 或 "chat.completions"

# Profile 配置
[profiles.default]
model_instructions_file = "/path/to/instructions.md"

# 环境变量
OPENAI_API_KEY           # API Key
OPENAI_BASE_URL          # 废弃的 base URL 配置（fallback）
CODEX_HOME               # Codex 配置和数据目录
CODEX_RS_SSE_FIXTURE     # 测试用：SSE fixture 文件路径
```

### 测试执行建议

```bash
# 运行单个测试
cargo test -p codex-core responses_mode_stream_cli -- --nocapture

# 运行所有 cli_stream 测试
cargo test -p codex-core --test suite cli_stream -- --nocapture

# 带网络跳过的测试（在沙箱环境中）
# 测试会自动检测 CODEX_SANDBOX_NETWORK_DISABLED 并跳过
```
