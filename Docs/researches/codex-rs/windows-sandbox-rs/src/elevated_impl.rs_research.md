# elevated_impl.rs 研究文档

## 场景与职责

`elevated_impl.rs` 实现 Windows 沙箱的**提升执行路径**（Elevated Path）。当主进程以管理员权限运行时，使用此路径启动沙箱子进程。与受限令牌路径（Restricted Token Path）不同，提升路径使用完整的用户令牌，但通过命名管道 IPC 与命令运行器（command-runner）通信。

该模块在以下场景中使用：
- 主进程以管理员权限运行时的沙箱执行
- 需要完整令牌但隔离执行环境的场景
- 通过命名管道与沙箱子进程通信

## 功能点目的

### 1. 沙箱捕获执行（提升路径）
- **`run_windows_sandbox_capture`**: 主入口函数
- 解析策略、准备环境、创建命名管道
- 使用 `CreateProcessWithLogonW` 以沙箱用户身份启动命令运行器
- 通过 IPC 协议与运行器通信

### 2. 命名管道管理
- **`pipe_name`**: 生成唯一管道名称
- **`create_named_pipe`**: 创建具有安全 DACL 的命名管道
- **`connect_pipe`**: 等待客户端连接

### 3. 环境准备
- **`inject_git_safe_directory`**: 注入 Git 安全目录配置
- 解决沙箱用户访问主用户拥有的 Git 仓库的权限问题
- **`find_git_root`**: 查找 Git 工作区根目录（支持 gitfile）

### 4. 辅助程序解析
- **`find_runner_exe`**: 解析命令运行器可执行文件路径
- **`ensure_codex_home_exists`**: 确保 Codex 主目录存在

### 5. Git 仓库支持
- 检测 `.git` 目录或 gitfile
- 自动配置 `GIT_CONFIG_KEY_*` / `GIT_CONFIG_VALUE_*` 环境变量

## 具体技术实现

### 关键数据结构

```rust
// 命名管道访问标志
const PIPE_ACCESS_INBOUND: u32 = 0x0000_0001;
const PIPE_ACCESS_OUTBOUND: u32 = 0x0000_0002;

// IPC 消息类型（来自 ipc_framed.rs）
pub struct CaptureResult {
    pub exit_code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub timed_out: bool,
}
```

### 执行流程

```
run_windows_sandbox_capture(policy_json, sandbox_policy_cwd, codex_home, command, cwd, env_map, timeout_ms, use_private_desktop)
  └─> parse_policy(policy_json) -> SandboxPolicy
  └─> normalize_null_device_env(&mut env_map)
  └─> ensure_non_interactive_pager(&mut env_map)
  └─> inherit_path_env(&mut env_map)
  └─> inject_git_safe_directory(&mut env_map, cwd, None)
  └─> ensure_codex_home_exists(sandbox_base)?
  └─> log_start(&command, logs_base_dir)
  └─> require_logon_sandbox_creds(policy, sandbox_policy_cwd, cwd, &env_map, codex_home)?
  │     └─> 获取沙箱用户凭据（或触发设置）
  └─> resolve_sid(&sandbox_creds.username) -> sandbox_sid
  └─> string_from_sid_bytes(&sandbox_sid) -> sandbox_sid_string
  └─> 拒绝 DangerFullAccess 和 ExternalSandbox 策略
  └─> load_or_create_cap_sids(codex_home)? -> caps
  └─> 根据策略确定 psid_to_use 和 cap_sids:
  │     ReadOnly -> caps.readonly
  │     WorkspaceWrite -> caps.workspace + workspace_cap_sid_for_cwd
  └─> unsafe { allow_null_device(psid_to_use) }
  └─> 创建命名管道:
  │     pipe_in_name = "\\.\\pipe\\codex-runner-{随机}-in"
  │     pipe_out_name = "\\.\\pipe\\codex-runner-{随机}-out"
  │     h_pipe_in = create_named_pipe(&pipe_in_name, PIPE_ACCESS_OUTBOUND, &sandbox_sid)
  │     h_pipe_out = create_named_pipe(&pipe_out_name, PIPE_ACCESS_INBOUND, &sandbox_sid)
  └─> 构建运行器命令行:
  │     "codex-command-runner.exe --pipe-in={in} --pipe-out={out}"
  └─> CreateProcessWithLogonW(
        sandbox_creds.username,
        ".",  // 域
        sandbox_creds.password,
        LOGON_WITH_PROFILE,
        runner_exe,
        cmdline,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
        null,  // 继承父进程环境
        cwd,
        &si,
        &mut pi
      )
  └─> connect_pipe(h_pipe_in)?
  └─> connect_pipe(h_pipe_out)?
  └─> 构建 SpawnRequest 消息并发送
  └─> 等待 SpawnReady 响应
  └─> 循环读取输出消息直到 Exit
  └─> 清理: CloseHandle, log_success/log_failure
  └─> 返回 CaptureResult
```

### 命名管道安全

```rust
fn create_named_pipe(name: &str, access: u32, sandbox_sid: &str) -> io::Result<HANDLE> {
    // SDDL: D:(A;;GA;;;{sandbox_sid})
    // D: - DACL
    // A - 允许
    // GA - 通用所有权限
    let sddl = to_wide(format!("D:(A;;GA;;;{sandbox_sid})"));
    ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.as_ptr(), ...)
    // ... 创建管道
}
```

管道 DACL 仅允许特定沙箱 SID 访问，防止其他进程拦截通信。

### Git 安全目录注入

```rust
fn inject_git_safe_directory(env_map: &mut HashMap<String, String>, cwd: &Path, ...) {
    if let Some(git_root) = find_git_root(cwd) {
        let cfg_count = env_map.get("GIT_CONFIG_COUNT").parse().unwrap_or(0);
        env_map.insert(format!("GIT_CONFIG_KEY_{cfg_count}"), "safe.directory");
        env_map.insert(format!("GIT_CONFIG_VALUE_{cfg_count}"), git_path);
        env_map.insert("GIT_CONFIG_COUNT".to_string(), (cfg_count + 1).to_string());
    }
}
```

Git 2.35+ 引入了目录所有权检查，此功能允许沙箱用户访问主用户拥有的仓库。

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `lib.rs` | `run_windows_sandbox_capture_elevated` | 提升路径入口 |

### 被调用模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `acl.rs` | `allow_null_device` | 授予 NULL 设备访问 |
| `allow.rs` | `compute_allow_paths`, `AllowDenyPaths` | 路径权限计算 |
| `cap.rs` | `load_or_create_cap_sids`, `workspace_cap_sid_for_cwd` | Capability SID |
| `env.rs` | `ensure_non_interactive_pager`, `inherit_path_env`, `normalize_null_device_env` | 环境准备 |
| `helper_materialization.rs` | `resolve_helper_for_launch`, `HelperExecutable` | 运行器解析 |
| `identity.rs` | `require_logon_sandbox_creds` | 凭据获取 |
| `ipc_framed.rs` | `read_frame`, `write_frame`, `decode_bytes`, `FramedMessage`, `Message` | IPC 通信 |
| `logging.rs` | `log_start`, `log_success`, `log_failure`, `log_note` | 日志记录 |
| `policy.rs` | `parse_policy`, `SandboxPolicy` | 策略解析 |
| `token.rs` | `convert_string_sid_to_sid` | SID 转换 |
| `winutil.rs` | `quote_windows_arg`, `resolve_sid`, `string_from_sid_bytes`, `to_wide` | 工具函数 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/elevated_impl.rs
  ├─> 依赖: acl.rs, allow.rs, cap.rs, env.rs, helper_materialization.rs
  ├─> 依赖: identity.rs, ipc_framed.rs, logging.rs, policy.rs, token.rs, winutil.rs
  ├─> 被 lib.rs 公开导出: run_windows_sandbox_capture_elevated
  └─> Windows API: CreateProcessWithLogonW, CreateNamedPipeW, etc.
```

## 依赖与外部交互

### 内部依赖
- **`acl.rs`**: NULL 设备权限
- **`allow.rs`**: 路径权限计算
- **`cap.rs`**: Capability SID 管理
- **`env.rs`**: 环境变量准备
- **`helper_materialization.rs`**: 辅助程序解析
- **`identity.rs`**: 沙箱凭据获取
- **`ipc_framed.rs`**: IPC 协议
- **`logging.rs`**: 日志记录
- **`policy.rs`**: 策略解析
- **`token.rs`**: SID 转换
- **`winutil.rs`**: Windows 工具函数

### 外部依赖
- **windows-sys**: Windows API 绑定
  - `Win32::System::Threading`: 进程创建
  - `Win32::System::Pipes`: 命名管道
  - `Win32::Security`: 安全描述符
- **anyhow**: 错误处理
- **rand**: 随机数生成（管道名称）
- **base64**: IPC 编码（通过 ipc_framed.rs）

### Windows API 使用

| API | 用途 |
|-----|------|
| `CreateProcessWithLogonW` | 以指定用户身份创建进程 |
| `CreateNamedPipeW` | 创建命名管道 |
| `ConnectNamedPipe` | 等待客户端连接 |
| `ConvertStringSecurityDescriptorToSecurityDescriptorW` | SDDL 转安全描述符 |
| `SetErrorMode` | 抑制错误弹窗 |
| `CloseHandle` | 关闭句柄 |

### 环境交互
- 读取/修改环境变量映射
- 文件系统操作（创建目录、解析路径）
- 命名管道 IPC

## 风险、边界与改进建议

### 安全风险

1. **凭据处理**
   - `sandbox_creds.password` 以明文形式传递
   - 在内存中存在时间较长（整个函数执行期间）
   - 建议：使用 `Zeroizing<String>` 或类似机制

2. **命名管道安全**
   - 管道名称包含随机数，但理论上可被猜测
   - 如果攻击者在连接前创建同名管道，可能导致劫持
   - 建议：使用更安全的 IPC 机制或增加认证

3. **CreateProcessWithLogonW 风险**
   - 需要明文密码
   - 密码在内存中可能被转储
   - 替代方案：使用令牌创建（但需要更多权限）

4. **环境变量注入**
   - `inject_git_safe_directory` 修改环境变量
   - 如果 Git 根目录检测错误，可能注入恶意路径

### 边界条件

| 边界 | 处理 |
|------|------|
| 策略不支持 | 返回错误（DangerFullAccess/ExternalSandbox） |
| 管道创建失败 | 清理并返回错误 |
| 连接超时 | 依赖 Windows 默认超时 |
| 运行器启动失败 | 记录详细错误并返回 |
| IPC 消息错误 | 返回错误并清理 |
| 非 Windows | 存根实现返回错误 |

### 改进建议

1. **密码保护**
   ```rust
   // 当前: String 存储密码
   // 建议: 使用 zeroize 保护
   use zeroize::Zeroizing;
   pub struct SandboxCreds {
       pub username: String,
       pub password: Zeroizing<String>,
   }
   ```

2. **管道安全增强**
   ```rust
   // 当前: 仅依赖随机名称
   // 建议: 连接后交换随机 nonce 验证身份
   ```

3. **超时控制**
   ```rust
   // 当前: 无显式超时
   // 建议: 为管道操作和进程等待添加超时
   ```

4. **错误信息脱敏**
   ```rust
   // 当前: 日志包含完整命令行
   // 建议: 过滤敏感信息（密码、令牌等）
   ```

5. **资源泄漏防护**
   - 当前使用多个 `if let Err` 块清理资源
   - 建议：使用 RAII 包装器（如 `scopeguard` crate）

6. **异步支持**
   - 当前使用阻塞 I/O 和线程
   - 建议：考虑使用 tokio 异步运行时

### 测试分析

现有测试：

| 测试 | 覆盖场景 |
|------|----------|
| `applies_network_block_when_access_is_disabled` | 网络策略验证 |
| `skips_network_block_when_access_is_allowed` | 网络策略验证 |
| `applies_network_block_for_read_only` | 只读策略网络验证 |

测试覆盖不足，建议补充：
- 管道创建和连接测试
- IPC 协议往返测试
- Git 根目录检测测试
- 错误处理路径测试
- 资源清理验证

### 与受限路径的对比

| 特性 | 提升路径 (elevated_impl.rs) | 受限路径 (lib.rs windows_impl) |
|------|---------------------------|------------------------------|
| 令牌类型 | 完整用户令牌 | 受限令牌 + Capability SID |
| IPC 机制 | 命名管道 | 匿名管道 |
| 进程创建 | CreateProcessWithLogonW | CreateProcessAsUserW |
| 适用场景 | 主进程提升运行 | 主进程非提升运行 |
| 复杂度 | 高（需要运行器） | 中 |
| 安全性 | 依赖用户隔离 | 额外令牌限制 |
