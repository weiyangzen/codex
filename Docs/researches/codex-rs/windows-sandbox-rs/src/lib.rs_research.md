# lib.rs 深度研究文档

## 场景与职责

`lib.rs` 是 `codex-windows-sandbox` crate 的**模块根和公共接口定义文件**，负责：

1. **模块组织**：使用条件编译组织 Windows 特有的实现模块
2. **公共 API 导出**：统一导出沙箱功能给外部使用者
3. **跨平台兼容**：为非 Windows 平台提供桩（stub）实现
4. **核心实现聚合**：整合沙箱执行的核心逻辑

## 功能点目的

### 1. 模块声明宏 (`windows_modules!`)
```rust
macro_rules! windows_modules {
    ($($name:ident),+ $(,)?) => {
        $(#[cfg(target_os = "windows")] mod $name;)+
    };
}
```
- 简化 Windows 特有模块的条件编译声明
- 包含 20+ 个模块：acl, allow, audit, cap, desktop, dpapi, env 等

### 2. 特殊路径模块
```rust
#[cfg(target_os = "windows")]
#[path = "conpty/mod.rs"]
mod conpty;

#[cfg(target_os = "windows")]
#[path = "elevated/ipc_framed.rs"]
pub mod ipc_framed;

#[cfg(target_os = "windows")]
#[path = "setup_orchestrator.rs"]
mod setup;
```
- `conpty`：Windows ConPTY（控制台伪终端）支持
- `ipc_framed`：进程间通信帧协议
- `setup`：设置流程编排（通过路径重映射）

### 3. 公共 API 导出

#### ACL 相关
```rust
pub use acl::add_deny_write_ace;
pub use acl::allow_null_device;
pub use acl::ensure_allow_mask_aces;
pub use acl::path_mask_allows;
```

#### 令牌和权限
```rust
pub use token::convert_string_sid_to_sid;
pub use token::create_readonly_token_with_cap_from;
pub use token::create_workspace_write_token_with_caps_from;
```

#### 沙箱执行
```rust
pub use windows_impl::run_windows_sandbox_capture;
pub use windows_impl::run_windows_sandbox_legacy_preflight;
pub use windows_impl::CaptureResult;
```

### 4. 核心实现 (`windows_impl` 模块)

#### `CaptureResult` 结构
```rust
pub struct CaptureResult {
    pub exit_code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub timed_out: bool,
}
```

#### `run_windows_sandbox_capture` - 主沙箱执行函数
```rust
#[allow(clippy::too_many_arguments)]
pub fn run_windows_sandbox_capture(
    policy_json_or_preset: &str,
    sandbox_policy_cwd: &Path,
    codex_home: &Path,
    command: Vec<String>,
    cwd: &Path,
    mut env_map: HashMap<String, String>,
    timeout_ms: Option<u64>,
    use_private_desktop: bool,
) -> Result<CaptureResult>
```

**执行流程**：
1. 解析沙箱策略
2. 应用网络阻断（如需要）
3. 规范化环境变量（空设备、分页器）
4. 确保 codex_home 存在
5. 加载或创建能力 SID
6. 根据策略创建受限令牌：
   - `ReadOnly`：只读令牌 + 只读能力 SID
   - `WorkspaceWrite`：工作区写令牌 + 工作区能力 SID
7. 计算允许/拒绝路径
8. 应用 ACL（允许/拒绝访问控制项）
9. 设置标准输入输出管道
10. 创建用户进程
11. 读取输出并等待完成
12. 清理 ACL（如非持久化）

#### `run_windows_sandbox_legacy_preflight` - 预检/预配置
```rust
pub fn run_windows_sandbox_legacy_preflight(
    sandbox_policy: &SandboxPolicy,
    sandbox_policy_cwd: &Path,
    codex_home: &Path,
    cwd: &Path,
    env_map: &HashMap<String, String>,
) -> Result<()>
```
- 仅用于 `WorkspaceWrite` 策略
- 提前应用 ACL，减少命令启动延迟

### 5. 非 Windows 平台桩实现 (`stub` 模块)

```rust
#[cfg(not(target_os = "windows"))]
mod stub {
    pub fn run_windows_sandbox_capture(...) -> Result<CaptureResult> {
        bail!("Windows sandbox is only available on Windows")
    }
    // ... 其他桩函数
}
```

## 具体技术实现

### 网络阻断决策
```rust
fn should_apply_network_block(policy: &SandboxPolicy) -> bool {
    !policy.has_full_network_access()
}
```

### 标准 IO 管道设置
```rust
unsafe fn setup_stdio_pipes() -> io::Result<PipeHandles>
```
- 创建 stdin/stdout/stderr 三对匿名管道
- 设置管道句柄为可继承
- 返回 `((in_r, in_w), (out_r, out_w), (err_r, err_w))`

### 进程创建与监控

```rust
let spawn_res = unsafe {
    create_process_as_user(
        h_token,
        &command,
        cwd,
        &env_map,
        logs_base_dir,
        Some((in_r, out_w, err_w)),
        use_private_desktop,
    )
};
```

**监控流程**：
1. 关闭父进程不需要的管道端
2. 创建读取线程收集 stdout/stderr
3. 使用 `WaitForSingleObject` 等待进程完成或超时
4. 如超时，调用 `TerminateProcess` 终止进程
5. 收集退出码和输出

### ACL 守卫模式
```rust
let mut guards: Vec<(PathBuf, *mut c_void)> = Vec::new();
// ... 添加 ACL，将 (path, sid) 加入 guards ...

// 清理（如非持久化）
if !persist_aces {
    unsafe {
        for (p, sid) in guards {
            revoke_ace(&p, sid);
        }
    }
}
```

## 关键代码路径与文件引用

### 模块依赖图
```
lib.rs (windows_impl)
├── acl.rs          - ACL 操作
├── allow.rs        - 允许/拒绝路径计算
├── cap.rs          - 能力 SID 管理
├── desktop.rs      - 桌面创建
├── env.rs          - 环境变量处理
├── policy.rs       - 策略解析
├── process.rs      - 进程创建
├── token.rs        - 令牌操作
├── workspace_acl.rs - 工作区 ACL
└── setup_orchestrator.rs - 设置流程
```

### 核心调用链
```
run_windows_sandbox_capture
├── parse_policy
├── should_apply_network_block
├── normalize_null_device_env
├── ensure_non_interactive_pager
├── load_or_create_cap_sids
├── create_readonly_token_with_cap / create_workspace_write_token_with_caps_from
├── compute_allow_paths
├── add_allow_ace / add_deny_write_ace
├── setup_stdio_pipes
├── create_process_as_user
├── WaitForSingleObject / TerminateProcess
└── revoke_ace (cleanup)
```

### 导出的公共 API

| API | 类型 | 用途 |
|-----|------|------|
| `run_windows_sandbox_capture` | 函数 | 主沙箱执行入口 |
| `run_windows_sandbox_legacy_preflight` | 函数 | 预检 ACL 配置 |
| `CaptureResult` | 结构体 | 执行结果 |
| `SandboxPolicy` | 类型 | 策略定义 |
| `add_deny_write_ace` | 函数 | ACL 操作 |
| `create_readonly_token_with_cap_from` | 函数 | 令牌创建 |
| `dpapi_protect/unprotect` | 函数 | 数据保护 |

## 依赖与外部交互

### 外部 Crate
- `anyhow`：错误处理
- `windows-sys`：Windows API 绑定
- `serde_json`：策略解析
- `codex_protocol`：协议类型（SandboxPolicy）

### Windows API 使用
- `CreatePipe` / `SetHandleInformation`：管道管理
- `CreateProcessAsUserW`：用户进程创建
- `WaitForSingleObject` / `GetExitCodeProcess` / `TerminateProcess`：进程管理
- `CloseHandle`：句柄清理

### 环境依赖
- `codex_home`：沙箱配置根目录
- `cwd`：命令工作目录
- `env_map`：环境变量映射

## 风险、边界与改进建议

### 已知风险

1. **句柄泄漏**
   - 问题：管道和进程句柄需要仔细管理
   - 缓解：使用 RAII 模式和显式 `CloseHandle` 调用
   - 风险点：错误路径上的句柄清理

2. **令牌权限**
   - 问题：受限令牌可能无法访问必要资源
   - 缓解：通过 ACL 显式授予访问权限
   - 边界：某些系统资源可能无法访问

3. **超时处理**
   - 问题：超时后强制终止可能导致数据丢失
   - 缓解：返回 `timed_out` 标志，调用方处理
   - 退出码：超时使用 `128 + 64 = 192`

### 边界条件

1. **策略限制**：
   - `DangerFullAccess` 和 `ExternalSandbox` 不被支持
   - `Restricted` 读访问需要提权后端

2. **路径处理**：
   - 不存在的路径在 ACL 应用时被跳过
   - 规范化路径用于比较

3. **令牌类型**：
   - `ReadOnly`：单能力 SID
   - `WorkspaceWrite`：双能力 SID（通用 + 工作区特定）

### 改进建议

1. **异步执行**
   - 当前：同步阻塞执行
   - 建议：考虑 `async` 支持，提高并发性能

2. **资源限制**
   - 当前：仅支持超时限制
   - 建议：添加 CPU/内存限制支持

3. **更细粒度的策略**
   - 当前：预设策略模式
   - 建议：支持更细粒度的权限配置

4. **错误恢复**
   - 当前：错误直接返回
   - 建议：添加重试机制和降级策略

5. **性能优化**
   - ACL 应用可能较慢
   - 考虑缓存和增量更新

### 测试覆盖

模块包含以下单元测试：
- `applies_network_block_when_access_is_disabled`：网络阻断逻辑
- `skips_network_block_when_access_is_allowed`：网络允许逻辑
- `applies_network_block_for_read_only`：只读策略网络处理

### 平台兼容性

| 平台 | 支持状态 | 说明 |
|------|----------|------|
| Windows | 完全支持 | 完整实现 |
| Linux/macOS | 桩实现 | 返回错误 |

### 安全考虑

1. **令牌限制**
   - 使用 `CreateRestrictedToken` 创建受限令牌
   - 标志：`DISABLE_MAX_PRIVILEGE | LUA_TOKEN | WRITE_RESTRICTED`

2. **ACL 清理**
   - 非持久化 ACE 在命令执行后撤销
   - 使用守卫模式确保清理执行

3. **桌面隔离**
   - 支持私有桌面选项（`use_private_desktop`）
   - 防止 UI 攻击和窗口注入
