# setup_main_win.rs 研究文档

## 场景与职责

`setup_main_win.rs` 是 Codex Windows Sandbox 的**特权设置助手主程序**，作为独立的可执行文件 (`codex-windows-sandbox-setup.exe`) 运行。该文件负责在提升权限（Administrator）下执行沙箱环境的初始化配置，包括用户创建、ACL（访问控制列表）设置、防火墙规则配置等敏感操作。

该模块是**双模式设计**：
1. **Full 模式**：完整的沙箱设置流程（创建用户、配置防火墙、设置 ACL 等）
2. **ReadAclsOnly 模式**：仅刷新读取权限 ACL 的轻量级模式，用于后台辅助进程

## 功能点目的

### 1. 沙箱用户与组管理
- 创建专用沙箱用户组 `CodexSandboxUsers`
- 创建两个沙箱用户账户：`CodexSandboxOffline`（离线模式）和 `CodexSandboxOnline`（在线模式）
- 使用 DPAPI 加密存储用户密码

### 2. 文件系统 ACL 配置
- **读取权限**：为沙箱用户组授予对指定读取根目录的读取/执行权限
- **写入权限**：为沙箱用户组和 Capability SID 授予对写入根目录的完整访问权限
- **沙箱目录锁定**：保护 `.sandbox`、`.sandbox-bin`、`.sandbox-secrets` 目录，防止沙箱内进程篡改

### 3. 防火墙规则配置
- 为离线用户创建出站阻断规则（调用 `firewall::ensure_offline_outbound_block`）
- 阻止离线沙箱用户的所有网络出站连接

### 4. 工作区保护
- 使用工作区特定的 Capability SID 保护当前工作区的 `.codex` 和 `.agents` 目录
- 防止沙箱内进程篡改工作区元数据

### 5. 并发控制
- 使用命名互斥量（Mutex）防止多个 Read ACL 辅助进程同时运行
- 支持后台异步刷新读取权限

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Clone, Deserialize, Serialize)]
struct Payload {
    version: u32,                    // 设置协议版本（当前为 5）
    offline_username: String,        // 离线沙箱用户名
    online_username: String,         // 在线沙箱用户名
    codex_home: PathBuf,             // Codex 主目录
    command_cwd: PathBuf,            // 命令执行工作目录
    read_roots: Vec<PathBuf>,        // 需要读取权限的根目录列表
    write_roots: Vec<PathBuf>,       // 需要写入权限的根目录列表
    real_user: String,               // 实际用户（用于保留权限）
    mode: SetupMode,                 // 运行模式
    refresh_only: bool,              // 是否仅刷新模式
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(rename_all = "kebab-case")]
enum SetupMode {
    #[default]
    Full,            // 完整设置模式
    ReadAclsOnly,    // 仅刷新读取 ACL 模式
}

struct ReadAclSubjects<'a> {
    sandbox_group_psid: *mut c_void,     // 沙箱用户组 SID
    rx_psids: &'a [*mut c_void],         // 内置读取主体 SID 列表
}
```

### 关键流程

#### 主入口流程 (`main` -> `real_main`)

1. **参数解析**：从命令行接收 Base64 编码的 JSON payload
2. **版本校验**：验证 payload 版本与 `SETUP_VERSION` 匹配
3. **日志初始化**：在 `.sandbox/setup.log` 创建日志文件
4. **模式分发**：根据 `mode` 字段调用 `run_setup`
5. **错误处理**：捕获并结构化记录错误到 `setup_error.json`

#### Full 设置流程 (`run_setup_full`)

```
1. 如果不是 refresh_only:
   - 调用 provision_sandbox_users() 创建沙箱用户
   - 调用 hide_newly_created_users() 隐藏用户配置文件

2. 解析离线用户 SID 和沙箱用户组 SID

3. 加载或创建 Capability SID（调用 load_or_create_cap_sids）
   - 通用 workspace SID
   - 工作区特定的 SID（基于 CWD）

4. 配置防火墙规则（如果不是 refresh_only）

5. 如果需要读取根目录且没有正在运行的 Read ACL 辅助进程:
   - 生成 ReadAclsOnly 模式的 payload
   - 派生新的辅助进程（异步执行）

6. 并行处理写入权限 ACL（使用 scoped threads）:
   - 检查每个写入根目录的当前权限状态
   - 为沙箱用户组和 Capability SID 授予写入权限
   - 使用 mpsc channel 收集结果

7. 锁定沙箱目录:
   - .sandbox-bin: 沙箱组读取/执行，真实用户完全控制
   - .sandbox: 沙箱组完全控制（refresh_only 时跳过）
   - .sandbox-secrets: 沙箱组拒绝访问（保护敏感数据）

8. 保护工作区元数据目录:
   - 对 .codex 和 .agents 添加拒绝写入 ACE

9. 清理资源并返回结果
```

#### Read ACL Only 流程 (`run_read_acl_only`)

```
1. 获取 Read ACL 互斥量（防止并发执行）
2. 解析沙箱用户组 SID 和内置主体 SID（Users, Authenticated Users, Everyone）
3. 遍历 read_roots:
   - 检查内置主体是否已有读取权限
   - 检查沙箱用户组是否已有读取权限
   - 如缺失，授予 FILE_GENERIC_READ | FILE_GENERIC_EXECUTE
4. 释放资源并返回
```

### Windows API 使用

| 功能 | API 函数 |
|------|----------|
| SID 转换 | `ConvertStringSidToSidW`, `ConvertSidToStringSidW` |
| ACL 操作 | `SetEntriesInAclW`, `SetNamedSecurityInfoW`, `GetNamedSecurityInfoW` |
| 权限检查 | `path_mask_allows`（自定义封装） |
| 进程创建 | `Command::spawn`（标准库） |
| 内存管理 | `LocalFree`（释放 SID 和 ACL） |

### 安全常量

```rust
const DENY_ACCESS: i32 = 3;  // ACCESS_DENIED_ACE_TYPE
// 文件权限掩码
const FILE_GENERIC_READ: u32 = 0x80000000;
const FILE_GENERIC_WRITE: u32 = 0x40000000;
const FILE_GENERIC_EXECUTE: u32 = 0x20000000;
const DELETE: u32 = 0x00010000;
const FILE_DELETE_CHILD: u32 = 0x00000040;
// 继承标志
const OBJECT_INHERIT_ACE: u32 = 0x1;
const CONTAINER_INHERIT_ACE: u32 = 0x2;
```

## 关键代码路径与文件引用

### 本文件内部函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `main` | 343-362 | 入口点，错误兜底处理 |
| `real_main` | 364-437 | 参数解析、日志初始化、错误报告 |
| `run_setup` | 439-444 | 模式分发 |
| `run_read_acl_only` | 446-503 | 仅刷新读取 ACL |
| `run_setup_full` | 505-882 | 完整设置流程 |
| `apply_read_acls` | 136-207 | 应用读取权限 ACL |
| `lock_sandbox_dir` | 244-341 | 锁定沙箱目录权限 |
| `spawn_read_acl_helper` | 113-129 | 派生 Read ACL 辅助进程 |

### 调用的外部模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `sandbox_users` | `provision_sandbox_users` | 创建沙箱用户和组 |
| `sandbox_users` | `resolve_sandbox_users_group_sid` | 获取沙箱组 SID |
| `sandbox_users` | `resolve_sid`, `sid_bytes_to_psid` | SID 解析转换 |
| `read_acl_mutex` | `acquire_read_acl_mutex` | 获取互斥量 |
| `read_acl_mutex` | `read_acl_mutex_exists` | 检查互斥量存在 |
| `firewall` | `ensure_offline_outbound_block` | 配置防火墙规则 |
| `codex_windows_sandbox` | `load_or_create_cap_sids` | 加载 Capability SID |
| `codex_windows_sandbox` | `workspace_cap_sid_for_cwd` | 获取工作区 SID |
| `codex_windows_sandbox` | `path_mask_allows` | 检查路径权限 |
| `codex_windows_sandbox` | `ensure_allow_mask_aces_with_inheritance` | 添加允许 ACE |
| `codex_windows_sandbox` | `ensure_allow_write_aces` | 添加写入允许 ACE |
| `codex_windows_sandbox` | `protect_workspace_codex_dir` | 保护 .codex 目录 |
| `codex_windows_sandbox` | `protect_workspace_agents_dir` | 保护 .agents 目录 |
| `codex_windows_sandbox` | `hide_newly_created_users` | 隐藏用户配置文件 |
| `codex_windows_sandbox` | `write_setup_error_report` | 写入错误报告 |

## 依赖与外部交互

### 输入依赖

1. **命令行参数**：Base64 编码的 JSON payload（`ElevationPayload` 结构）
2. **环境变量**：
   - `CODEX_HOME`：用于错误日志的兜底写入位置
   - `USERNAME`：识别真实用户以保留权限
3. **文件系统**：
   - 读取根目录必须存在（不存在则跳过）
   - `.sandbox/setup.log` 日志文件
   - `cap_sid` Capability SID 存储文件

### 输出产物

1. **日志文件**：`.sandbox/setup.log` - 结构化时间戳日志
2. **错误报告**：`.sandbox/setup_error.json` - 结构化错误信息
3. **Windows 用户**：`CodexSandboxOffline`, `CodexSandboxOnline`
4. **Windows 组**：`CodexSandboxUsers`
5. **ACL 修改**：文件系统目录的访问控制列表
6. **防火墙规则**：`codex_sandbox_offline_block_outbound`

### 调用方

- `setup_main.rs`：可执行文件入口，直接调用此模块
- `setup_orchestrator.rs`：通过 `run_setup_exe` 或 `run_setup_refresh` 间接调用

## 风险、边界与改进建议

### 安全风险

1. **内存安全**：大量使用 `unsafe` 代码块操作 Windows 原始指针（PSID、ACL、HANDLE）
   - 风险：SID/ACL 内存泄漏或悬挂指针
   - 缓解：使用 `LocalFree` 释放，但需确保所有路径都执行

2. **权限提升**：以 Administrator 运行，任何漏洞都可能导致系统级危害
   - 风险：payload 注入、路径遍历
   - 缓解：版本校验、路径规范化（通过 `canonicalize_path`）

3. **并发安全**：
   - Read ACL 辅助进程的互斥量机制可能存在竞态条件
   - 建议：使用更健壮的进程间同步机制

### 边界情况

1. **路径不存在**：读取/写入根目录不存在时跳过（记录日志）
2. **ACL 检查失败**：继续处理其他目录，收集错误后统一报告
3. **UAC 取消**：用户取消 UAC 提示时返回特定错误码 `OrchestratorHelperLaunchCanceled`
4. **版本不匹配**：拒绝处理旧版本 payload，强制升级

### 改进建议

1. **错误处理优化**：
   - 当前错误处理分散在多处，建议统一错误上下文收集
   - 考虑使用 `thiserror` 替代部分 `anyhow` 以提高类型安全

2. **性能优化**：
   - 写入 ACL 的并行处理已使用 scoped threads，可考虑使用线程池减少创建开销
   - 大量小文件的 ACL 操作可能成为瓶颈

3. **可观测性**：
   - 增加结构化日志（JSON 格式）便于机器解析
   - 添加性能指标收集（ACL 操作耗时、失败率）

4. **安全加固**：
   - 对 payload 添加数字签名验证
   - 限制可接受的读取/写入根目录白名单
   - 添加操作审计日志（Windows Event Log）

5. **代码结构**：
   - 文件较长（882 行），建议拆分为子模块：
     - `acl_operations.rs`：ACL 相关操作
     - `user_provisioning.rs`：用户创建逻辑
     - `workspace_protection.rs`：工作区保护逻辑
