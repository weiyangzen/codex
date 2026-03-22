# Windows Sandbox Setup Test Research Document

## 1. 场景与职责

### 1.1 文件定位
- **目标文件**: `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
- **文件类型**: 集成测试文件（Rust Integration Test）
- **所属模块**: `app-server` 的 v2 API 测试套件

### 1.2 核心职责
该测试文件负责验证 **Windows Sandbox 设置功能**的 API 行为，具体包括：

1. **验证 `windowsSandbox/setupStart` RPC 方法**的基本功能 - 启动 Windows Sandbox 设置流程
2. **验证设置完成通知** (`windowsSandbox/setupCompleted`) 的正确发送
3. **验证参数校验逻辑** - 特别是 `cwd` 参数必须是绝对路径的约束

### 1.3 业务背景
Windows Sandbox 是 Codex 在 Windows 平台上提供的**代码执行沙箱环境**，用于安全地执行 AI 生成的代码。该功能支持两种模式：
- **Elevated（提升权限模式）**: 使用更高权限运行沙箱
- **Unelevated（非提升权限模式）**: 使用受限令牌运行沙箱（传统模式）

此测试文件确保 app-server 能够正确处理客户端发起的沙箱设置请求，并在设置完成后异步通知客户端结果。

---

## 2. 功能点目的

### 2.1 测试覆盖的功能点

| 测试函数 | 功能点 | 目的 |
|---------|--------|------|
| `windows_sandbox_setup_start_emits_completion_notification` | 正常流程测试 | 验证发送 `setupStart` 请求后，能收到 `started: true` 响应，并最终收到 `setupCompleted` 通知 |
| `windows_sandbox_setup_start_rejects_relative_cwd` | 参数校验测试 | 验证当传入相对路径作为 `cwd` 时，服务器返回 `-32600` (Invalid request) 错误 |

### 2.2 协议方法说明

#### `windowsSandbox/setupStart` (Client → Server)
- **作用**: 启动 Windows Sandbox 的初始化/设置流程
- **参数** (`WindowsSandboxSetupStartParams`):
  - `mode`: 设置模式，可选 `elevated` 或 `unelevated`
  - `cwd`: 可选的工作目录（**必须是绝对路径**）
- **响应** (`WindowsSandboxSetupStartResponse`):
  - `started`: 布尔值，表示是否成功启动设置流程

#### `windowsSandbox/setupCompleted` (Server → Client)
- **作用**: 服务器在设置流程完成后发送的通知
- **参数** (`WindowsSandboxSetupCompletedNotification`):
  - `mode`: 完成的设置模式
  - `success`: 是否成功
  - `error`: 可选的错误信息

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 协议类型定义（v2.rs）

```rust
// 设置模式枚举
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}

// 请求参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartParams {
    pub mode: WindowsSandboxSetupMode,
    #[ts(optional = nullable)]
    pub cwd: Option<AbsolutePathBuf>,  // 必须使用绝对路径
}

// 响应数据
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartResponse {
    pub started: bool,
}

// 完成通知
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupCompletedNotification {
    pub mode: WindowsSandboxSetupMode,
    pub success: bool,
    pub error: Option<String>,
}
```

#### 3.1.2 核心模块类型（codex_core::windows_sandbox）

```rust
// 内部使用的设置模式
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}

// 设置请求结构
pub struct WindowsSandboxSetupRequest {
    pub mode: WindowsSandboxSetupMode,
    pub policy: SandboxPolicy,
    pub policy_cwd: PathBuf,
    pub command_cwd: PathBuf,
    pub env_map: HashMap<String, String>,
    pub codex_home: PathBuf,
    pub active_profile: Option<String>,
}
```

### 3.2 关键流程

#### 3.2.1 测试流程（测试文件）

**测试 1: 正常流程**
```
1. 创建 Mock Responses Server（模拟模型服务器）
2. 创建临时 CODEX_HOME 目录
3. 写入测试用的 config.toml
4. 启动 MCP 进程（codex-app-server）
5. 发送 initialize 请求完成握手
6. 发送 windowsSandbox/setupStart 请求（mode: Unelevated, cwd: None）
7. 验证收到 started: true 响应
8. 等待并验证收到 windowsSandbox/setupCompleted 通知
9. 验证通知中的 mode 与请求一致
```

**测试 2: 参数校验**
```
1. 创建临时 CODEX_HOME 目录
2. 启动 MCP 进程
3. 发送 initialize 请求
4. 发送原始 JSON-RPC 请求，cwd 使用相对路径 "relative-root"
5. 验证收到错误响应，错误码为 -32600 (Invalid request)
6. 验证错误消息包含 "Invalid request"
```

#### 3.2.2 服务端处理流程（codex_message_processor.rs）

```rust
async fn windows_sandbox_setup_start(
    &mut self,
    request_id: ConnectionRequestId,
    params: WindowsSandboxSetupStartParams,
) {
    // 1. 立即返回 started: true 响应
    self.outgoing
        .send_response(request_id.clone(), WindowsSandboxSetupStartResponse { started: true })
        .await;

    // 2. 转换模式
    let mode = match params.mode {
        WindowsSandboxSetupMode::Elevated => CoreWindowsSandboxSetupMode::Elevated,
        WindowsSandboxSetupMode::Unelevated => CoreWindowsSandboxSetupMode::Unelevated,
    };

    // 3. 获取配置和参数
    let config = Arc::clone(&self.config);
    let command_cwd = params.cwd.map(PathBuf::from).unwrap_or_else(|| config.cwd.clone());
    
    // 4. 在后台任务中执行设置
    tokio::spawn(async move {
        // 4.1 根据 cwd 派生配置
        let derived_config = derive_config_for_cwd(...).await;
        
        // 4.2 创建设置请求并执行
        let setup_request = WindowsSandboxSetupRequest {
            mode, policy, policy_cwd, command_cwd, env_map, codex_home, active_profile
        };
        let setup_result = codex_core::windows_sandbox::run_windows_sandbox_setup(setup_request).await;
        
        // 4.3 发送完成通知
        let notification = WindowsSandboxSetupCompletedNotification {
            mode: ..., success: setup_result.is_ok(), error: ...
        };
        outgoing.send_server_notification_to_connections(...).await;
    });
}
```

#### 3.2.3 核心设置流程（codex_core::windows_sandbox）

```rust
pub async fn run_windows_sandbox_setup(request: WindowsSandboxSetupRequest) -> anyhow::Result<()> {
    let start = Instant::now();
    let mode = request.mode;
    
    // 执行设置并持久化结果
    let result = run_windows_sandbox_setup_and_persist(request).await;
    
    // 发送指标（成功/失败）
    match result {
        Ok(()) => emit_success_metrics(mode, ...),
        Err(err) => emit_failure_metrics(mode, ..., &err),
    }
}

async fn run_windows_sandbox_setup_and_persist(request: WindowsSandboxSetupRequest) -> anyhow::Result<()> {
    // 在阻塞线程池中执行
    let setup_result = tokio::task::spawn_blocking(move || {
        match mode {
            WindowsSandboxSetupMode::Elevated => {
                if !sandbox_setup_is_complete(codex_home) {
                    run_elevated_setup(policy, policy_cwd, command_cwd, env_map, codex_home)?;
                }
            }
            WindowsSandboxSetupMode::Unelevated => {
                run_legacy_setup_preflight(policy, policy_cwd, command_cwd, env_map, codex_home)?;
            }
        }
        Ok(())
    }).await?;
    
    // 持久化设置结果到配置
    ConfigEditsBuilder::new(codex_home)
        .set_windows_sandbox_mode(mode_tag)
        .clear_legacy_windows_sandbox_keys()
        .apply()
        .await
}
```

### 3.3 协议定义位置

- **ClientRequest 枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs:425`
  ```rust
  WindowsSandboxSetupStart => "windowsSandbox/setupStart" {
      params: v2::WindowsSandboxSetupStartParams,
      response: v2::WindowsSandboxSetupStartResponse,
  }
  ```

- **ServerNotification 枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs:934`
  ```rust
  WindowsSandboxSetupCompleted => "windowsSandbox/setupCompleted" (v2::WindowsSandboxSetupCompletedNotification)
  ```

---

## 4. 关键代码路径与文件引用

### 4.1 测试相关文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs` | **目标测试文件**，包含两个测试用例 |
| `codex-rs/app-server/tests/suite/v2/mod.rs` | v2 测试模块入口，声明 windows_sandbox_setup 子模块 |
| `codex-rs/app-server/tests/suite/mod.rs` | 测试套件入口 |
| `codex-rs/app-server/tests/all.rs` | 集成测试二进制入口 |
| `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程管理工具，提供 `send_windows_sandbox_setup_start_request` 方法 |
| `codex-rs/app-server/tests/common/config.rs` | 测试配置生成工具，`write_mock_responses_config_toml` |
| `codex-rs/app-server/tests/common/lib.rs` | 测试公共库，导出 `to_response` 等工具函数 |

### 4.2 协议定义文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4977-5008` | Windows Sandbox 相关类型的 Rust 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest/ServerNotification 枚举定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupStartParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupStartResponse.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupCompletedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WindowsSandboxSetup*.ts` | TypeScript 类型定义 |

### 4.3 服务端实现文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:7104-7173` | `windows_sandbox_setup_start` 方法实现 |
| `codex-rs/app-server/src/codex_message_processor.rs:811-814` | 请求路由处理（ClientRequest::WindowsSandboxSetupStart） |
| `codex-rs/core/src/windows_sandbox.rs` | 核心 Windows Sandbox 逻辑，包括设置执行和持久化 |

### 4.4 依赖的 Crate

| Crate | 作用 |
|-------|------|
| `codex-app-server-protocol` | 协议类型定义（WindowsSandboxSetupStartParams 等） |
| `codex-core` | 核心 Windows Sandbox 实现（windows_sandbox 模块） |
| `app_test_support` | 测试支持库（McpProcess、配置生成等） |
| `tempfile` | 临时目录创建 |
| `tokio` | 异步运行时和超时控制 |
| `pretty_assertions` | 断言增强 |

---

## 5. 依赖与外部交互

### 5.1 测试环境依赖

```rust
// 测试使用的常量
const DEFAULT_READ_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
```

**依赖的测试基础设施**:
1. **Mock Responses Server**: 模拟模型服务器，用于初始化测试环境
2. **TempDir**: 临时 CODEX_HOME 目录，隔离测试环境
3. **McpProcess**: 管理 codex-app-server 子进程的生命周期

### 5.2 服务端外部依赖

1. **Windows 平台特定实现**:
   - `codex_windows_sandbox` crate（仅在 Windows 上实际执行）
   - 非 Windows 平台返回 `false` 或错误

2. **配置系统**:
   - `ConfigEditsBuilder`: 用于持久化沙箱设置结果到 config.toml

3. **指标收集**:
   - `codex_otel::metrics`: 发送设置成功/失败指标

### 5.3 协议版本兼容性

- 该 API 属于 **v2 协议**
- 使用 camelCase 命名规范
- 导出 TypeScript 类型到 `v2/` 目录
- 生成 JSON Schema 用于验证

---

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 平台限制
- **非 Windows 平台行为**: 在非 Windows 平台上，`sandbox_setup_is_complete` 始终返回 `false`，`run_elevated_setup` 和 `run_legacy_setup_preflight` 返回错误
- **测试覆盖**: 当前测试在非 Windows 平台上可能无法真正验证沙箱功能，只是验证 API 层面的行为

#### 6.1.2 测试局限性
1. **Mock 依赖**: 测试使用 Mock 模型服务器，不涉及真实的模型调用
2. **超时风险**: 使用 10 秒超时等待通知，在慢速机器上可能不稳定
3. **并发安全**: 测试未验证并发设置请求的处理

#### 6.1.3 参数校验边界
- 测试仅验证了 `cwd` 的相对路径拒绝，未测试：
  - 空路径处理
  - 非法字符路径
  - 超长路径
  - 不存在的绝对路径

### 6.2 改进建议

#### 6.2.1 测试增强
1. **增加错误场景测试**:
   ```rust
   // 建议添加：验证非法 mode 值的处理
   // 建议添加：验证超长 cwd 的处理
   // 建议添加：验证特殊字符路径的处理
   ```

2. **增加并发测试**:
   ```rust
   // 验证同时发起多个 setupStart 请求的行为
   ```

3. **平台特定测试**:
   ```rust
   #[cfg(windows)]
   mod windows_specific_tests {
       // 在真实 Windows 沙箱环境下的测试
   }
   ```

#### 6.2.2 代码改进
1. **更详细的错误码**: 当前使用通用的 `-32600` (Invalid request)，建议增加更具体的错误码
2. **进度通知**: 对于耗长的设置流程，建议增加进度通知而非仅完成通知
3. **取消机制**: 当前没有提供取消正在进行的设置流程的机制

#### 6.2.3 文档改进
1. 在协议文档中更详细地说明：
   - `cwd` 参数的具体用途和约束
   - 两种模式（Elevated/Unelevated）的具体区别
   - 设置流程的预期耗时

### 6.3 监控与可观测性

当前实现已包含基础指标：
- `codex.windows_sandbox.setup_duration_ms`（成功/失败）
- `codex.windows_sandbox.setup_success`
- `codex.windows_sandbox.setup_failure`
- `codex.windows_sandbox.elevated_setup_failure`
- `codex.windows_sandbox.legacy_setup_preflight_failed`

建议增加：
- 按 Windows 版本分类的指标
- 设置取消率指标
- 设置重试次数分布

---

## 7. 总结

`windows_sandbox_setup.rs` 是 Codex app-server 中验证 Windows Sandbox 设置 API 的关键测试文件。它通过两个测试用例覆盖了：

1. **正常流程**: 验证 RPC 请求-响应-通知的完整流程
2. **参数校验**: 验证 `cwd` 必须是绝对路径的约束

该测试依赖于完善的测试基础设施（McpProcess、Mock Server、临时配置），并与核心 Windows Sandbox 实现（`codex_core::windows_sandbox`）紧密集成。虽然测试在 API 层面提供了良好的覆盖，但在平台特定行为和边界条件方面仍有改进空间。
