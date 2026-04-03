# turn_start_zsh_fork.rs 研究文档

## 场景与职责

`turn_start_zsh_fork.rs` 是 Codex App Server V2 API 的集成测试文件，专注于测试 **Zsh Fork 模式下的 Shell 命令执行** 功能。这是 Codex 的高级执行模式，使用 Zsh 作为命令执行的中介，提供更精细的命令控制和沙盒隔离。

### 核心测试场景

1. **基本 Zsh Fork 执行**：验证通过 Zsh fork 执行命令的基本流程
2. **审批拒绝（Decline）**：验证用户对命令审批选择拒绝时的行为
3. **审批取消（Cancel）**：验证用户对命令审批选择取消时的行为
4. **子命令审批拒绝**：验证复杂命令中子命令被拒绝时的级联行为

### 平台限制

```rust
#![cfg(not(windows))]
```

该测试文件在非 Windows 平台运行，因为依赖 Unix 特定的 Zsh shell 和进程控制机制。

---

## 功能点目的

### Zsh Fork 功能

Zsh Fork 是 Codex 的命令执行增强模式：

- **命令拦截**：通过 Zsh 的 `EXEC_WRAPPER` 机制拦截所有命令执行
- **细粒度控制**：支持对复合命令中的每个子命令单独审批
- **状态保持**：Zsh 进程保持运行，维护 shell 状态（环境变量、目录等）
- **安全隔离**：通过 Zsh 的配置实现额外的安全层

### Feature Flags

测试涉及以下功能标志：

```rust
Feature::ShellZshFork    // 启用 Zsh fork 模式
Feature::UnifiedExec     // 统一执行模式（测试中禁用）
Feature::ShellSnapshot   // Shell 快照（测试中禁用）
```

### 关键业务规则

1. Zsh fork 模式下，命令通过 Zsh 进程执行而非直接 exec
2. 支持 `UnlessTrusted` 审批策略，对不信任命令请求用户确认
3. 子命令可以独立审批，拒绝子命令会标记父命令为 declined
4. 审批决策支持：Accept（接受）、Decline（拒绝）、Cancel（取消）

---

## 具体技术实现

### 测试基础设施

#### Zsh 路径查找

```rust
fn find_test_zsh_path() -> Result<Option<PathBuf>>
```

**逻辑**:
1. 查找仓库根目录下的 DotSlash 文件：`codex-rs/app-server/tests/suite/zsh`
2. 使用 `core_test_support::fetch_dotslash_file` 获取实际 Zsh 可执行文件路径
3. 如果 DotSlash 获取失败，返回 `None`（测试跳过）

#### EXEC_WRAPPER 支持检测

```rust
fn supports_exec_wrapper_intercept(zsh_path: &Path) -> bool
```

**逻辑**:
1. 运行 `zsh -fc /usr/bin/true` 并设置 `EXEC_WRAPPER=/usr/bin/false`
2. 如果命令失败（返回非零退出码），说明支持 EXEC_WRAPPER 拦截
3. 用于跳过不支持该特性的 Zsh 构建

#### 测试配置生成

```rust
fn create_config_toml(
    codex_home: &Path,
    server_uri: &str,
    approval_policy: &str,
    feature_flags: &BTreeMap<Feature, bool>,
    zsh_path: &Path,
) -> std::io::Result<()>
```

**生成的配置**:
```toml
model = "mock-model"
approval_policy = "never|untrusted"
sandbox_mode = "read-only"
zsh_path = "/path/to/zsh"

[features]
shell_zsh_fork = true
unified_exec = false
shell_snapshot = false
remote_models = false

[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "..."
wire_api = "responses"
```

#### MCP 进程创建

```rust
async fn create_zsh_test_mcp_process(codex_home: &Path, zdotdir: &Path) -> Result<McpProcess>
```

设置 `ZDOTDIR` 环境变量，确保 Zsh 使用测试工作目录作为配置目录。

### 测试用例 1: 基本 Zsh Fork 执行

```rust
async fn turn_start_shell_zsh_fork_executes_command_v2() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录（codex_home, workspace）
2. 创建中断释放标记文件路径
3. 查找 Zsh 可执行文件（跳过如果未找到）
4. 配置 Mock Server 返回等待中断的命令
   └── 命令: while [ ! -f 'release_marker' ]; do sleep 0.01; done
5. 创建启用 Zsh fork 的配置
6. 启动 MCP 进程（设置 ZDOTDIR）
7. 创建线程
8. 启动回合，触发命令执行
9. 等待 item/started 通知（CommandExecution 类型）
10. 验证命令执行项属性：
    - id: "call-zsh-fork"
    - status: InProgress
    - command: 包含 zsh 路径和 /bin/sh -c
    - cwd: workspace
11. 调用 interrupt_turn_and_wait_for_aborted 清理
```

**关键验证点**:
- 命令通过 Zsh 启动（验证 command 字段包含 zsh 路径）
- 状态正确报告为 `InProgress`
- 工作目录正确设置

### 测试用例 2: 审批拒绝（Decline）

```rust
async fn turn_start_shell_zsh_fork_exec_approval_decline_v2() -> Result<()>
```

**测试流程**:
```
1. 配置 approval_policy = "untrusted"
2. Mock Server 返回 python3 -c "print(42)" 命令
3. 启动回合
4. 等待 CommandExecutionRequestApproval 请求
5. 验证请求参数（item_id, thread_id）
6. 发送拒绝响应（decision: Decline）
7. 等待 item/completed 通知
8. 验证命令执行项：
   - status: Declined
   - exit_code: None
   - aggregated_output: None
9. 验证回合完成
```

### 测试用例 3: 审批取消（Cancel）

```rust
async fn turn_start_shell_zsh_fork_exec_approval_cancel_v2() -> Result<()>
```

**与 Decline 测试的区别**:
- 发送 `decision: Cancel` 而非 `Decline`
- 验证回合状态为 `Interrupted`（Cancel 会中断整个回合）

### 测试用例 4: 子命令审批拒绝

```rust
async fn turn_start_shell_zsh_fork_subcommand_decline_marks_parent_declined_v2() -> Result<()>
```

**复杂场景测试**:

```
命令: /bin/rm first.txt && /bin/rm second.txt
```

**测试流程**:
```
1. 创建工作目录和测试文件（first.txt, second.txt）
2. 检查 Zsh 支持 EXEC_WRAPPER 拦截
3. 配置 Mock Server 返回复合命令
4. 启动回合，使用 UnlessTrusted 审批策略
5. 循环处理审批请求：
   - 识别父命令（包含 zsh 路径和完整命令）
   - 识别子命令（只包含一个 rm 命令）
   - 第一个子命令：Accept
   - 第二个子命令：Cancel（模拟拒绝）
6. 验证父命令标记为 Declined
7. 验证子命令有独立的 approval_id
8. 验证回合最终状态（Interrupted 或 Completed）
```

**子命令识别逻辑**:
```rust
let is_target_subcommand =
    (has_first_file != has_second_file)  // 只包含一个目标文件
    && (has_rm_action || mentions_rm_binary);  // 是 rm 命令

let is_parent_approval = 
    approval_command.contains(&zsh_path.display().to_string())  // 包含 zsh 路径
    && (approval_command.contains(&shell_command)  // 包含完整命令
        || (has_first_file && has_second_file)  // 或包含所有文件
        || approval_command.contains(&parent_shell_hint));  // 包含 && 提示
```

---

## 关键代码路径与文件引用

### 测试文件
- **位置**: `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs`
- **行数**: 828 行
- **平台限制**: `#[cfg(not(windows))]`

### Zsh DotSlash 文件
- **位置**: `codex-rs/app-server/tests/suite/zsh`
- **用途**: 通过 DotSlash 分发测试专用的 Zsh 可执行文件

### 协议定义
- **位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **相关类型**:
  - `CommandAction` (行 1436-1458)
  - `CommandExecutionStatus` (行 1459-1470)
  - `CommandExecutionApprovalDecision` (行 1471-1480)

### 功能标志定义
- **位置**: `codex-rs/core/src/features.rs`
- **相关**: `Feature::ShellZshFork`, `Feature::UnifiedExec`, `Feature::ShellSnapshot`

### 测试支持库
- **位置**: `codex-rs/app-server/tests/common/mcp_process.rs`
- **方法**: `interrupt_turn_and_wait_for_aborted`

### 核心实现
- **位置**: `codex-rs/exec/src/` (命令执行实现)
- **相关**: Zsh fork 执行器、命令拦截逻辑

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 测试超时控制 |
| `core_test_support::skip_if_no_network` | 网络检查（DotSlash 需要） |
| `core_test_support::fetch_dotslash_file` | 获取 Zsh 可执行文件 |

### 内部模块依赖

```
turn_start_zsh_fork.rs
├── app_test_support::McpProcess
├── app_test_support::create_mock_responses_server_sequence
├── app_test_support::create_shell_command_sse_response
├── app_test_support::to_response
├── codex_app_server_protocol::CommandAction
├── codex_app_server_protocol::CommandExecutionApprovalDecision
├── codex_app_server_protocol::CommandExecutionRequestApprovalResponse
├── codex_app_server_protocol::CommandExecutionStatus
├── codex_app_server_protocol::ItemCompletedNotification
├── codex_app_server_protocol::ItemStartedNotification
├── codex_app_server_protocol::ServerRequest
├── codex_app_server_protocol::ThreadItem
├── codex_core::features::FEATURES
├── codex_core::features::Feature
├── core_test_support::responses
├── core_test_support::skip_if_no_network
└── codex_utils_cargo_bin::repo_root
```

### 网络依赖

测试使用 `skip_if_no_network!` 宏检查网络可用性：
- DotSlash 首次获取 Zsh 可执行文件需要网络
- 后续运行使用缓存的工件

---

## 风险、边界与改进建议

### 潜在风险

1. **DotSlash 依赖**
   - 首次运行需要网络下载 Zsh 可执行文件
   - 如果 DotSlash 服务不可用，测试会跳过
   - **缓解**: 已在 CI 环境预配置，本地开发需确保网络

2. **Zsh 版本差异**
   - 不同 Zsh 版本对 EXEC_WRAPPER 的支持可能不同
   - 测试使用 `supports_exec_wrapper_intercept` 检测，但可能不完整
   - **缓解**: 使用固定的 DotSlash 分发版本

3. **竞态条件**
   - 子命令审批测试中，命令完成和通知的顺序可能不稳定
   - 测试使用 `timeout` 和 `match` 处理多种完成路径
   - **缓解**: 增加重试逻辑和多种完成路径处理

4. **平台限制**
   - 测试不在 Windows 运行，Windows Zsh 支持未覆盖
   - **缓解**: 文档说明 Windows 使用替代执行模式

### 边界情况

1. **Zsh 启动失败**: 测试未覆盖 Zsh 可执行文件损坏的情况
2. **环境变量污染**: 测试依赖 ZDOTDIR 隔离，但可能有遗漏
3. **大输出处理**: 测试未覆盖命令产生大量输出的场景
4. **信号处理**: 测试未覆盖 Zsh 进程信号处理的边界情况

### 改进建议

1. **增加错误场景测试**
   ```rust
   // 建议添加：Zsh 可执行文件不存在
   async fn zsh_fork_with_missing_executable_returns_error() -> Result<()>
   
   // 建议添加：Zsh 配置错误
   async fn zsh_fork_with_invalid_zdotdir_handles_gracefully() -> Result<()>
   ```

2. **增加性能测试**
   ```rust
   // 建议添加：大量子命令审批性能
   async fn zsh_fork_many_subcommands_performance() -> Result<()>
   ```

3. **增强稳定性**
   - 使用更可靠的子命令检测机制
   - 增加审批请求的超时处理

4. **Windows 支持探索**
   - 研究 Windows 下的替代实现（如 WSL、Git Bash）
   - 或明确文档说明 Windows 不支持 Zsh fork 模式

### 相关测试文件

- `turn_start.rs`: 标准回合启动测试
- `turn_interrupt.rs`: 回合中断测试
- `command_exec.rs`: 命令执行测试

### 测试跳过条件

测试在以下情况会跳过：
1. 无网络连接（`skip_if_no_network!`）
2. Zsh DotSlash 文件不存在
3. DotSlash 获取失败
4. Zsh 不支持 EXEC_WRAPPER 拦截

这种设计确保测试在不适用的环境优雅跳过，而非失败。
