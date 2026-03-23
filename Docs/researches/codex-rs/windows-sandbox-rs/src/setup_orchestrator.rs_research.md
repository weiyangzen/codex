# setup_orchestrator.rs 研究文档

## 场景与职责

`setup_orchestrator.rs` 是 Codex Windows Sandbox 的**设置编排器**，负责协调沙箱环境的设置流程。它作为非特权（或已提升特权）进程的一部分运行，决定何时需要提升权限执行设置，并准备传递给特权设置助手（`codex-windows-sandbox-setup.exe`）的参数。

该模块是**特权分离架构**的关键组件：
- **编排器（本模块）**：运行在非特权或中等完整性级别，负责决策和参数准备
- **设置助手（setup_main_win.rs）**：以 Administrator 运行，执行实际的系统修改

## 功能点目的

### 1. 设置流程编排
- 检测当前权限状态（是否已提升）
- 决定是否需要 UAC 提升
- 准备并序列化设置参数（`ElevationPayload`）

### 2. 根目录收集与过滤
- **读取根目录（read_roots）**：沙箱进程需要读取访问的目录列表
- **写入根目录（write_roots）**：沙箱进程需要写入访问的目录列表
- 根据沙箱策略动态计算根目录集合

### 3. ACL 刷新（非特权模式）
- `run_setup_refresh`：在不请求 UAC 提升的情况下刷新 ACL
- 用于策略变更后的权限更新

### 4. 错误报告与诊断
- 解析设置助手的退出代码
- 读取结构化错误报告（`setup_error.json`）
- 提供详细的错误上下文

## 具体技术实现

### 关键数据结构

```rust
pub const SETUP_VERSION: u32 = 5;
pub const OFFLINE_USERNAME: &str = "CodexSandboxOffline";
pub const ONLINE_USERNAME: &str = "CodexSandboxOnline";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SetupMarker {
    pub version: u32,
    pub offline_username: String,
    pub online_username: String,
    #[serde(default)]
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SandboxUserRecord {
    pub username: String,
    /// DPAPI-encrypted password blob, base64 encoded.
    pub password: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SandboxUsersFile {
    pub version: u32,
    pub offline: SandboxUserRecord,
    pub online: SandboxUserRecord,
}

#[derive(Serialize)]
struct ElevationPayload {
    version: u32,
    offline_username: String,
    online_username: String,
    codex_home: PathBuf,
    command_cwd: PathBuf,
    read_roots: Vec<PathBuf>,
    write_roots: Vec<PathBuf>,
    real_user: String,
    refresh_only: bool,
}
```

### 关键流程

#### 完整设置流程 (`run_elevated_setup`)

```
1. 确保 .sandbox 目录存在

2. 构建根目录列表（调用 build_payload_roots）:
   - 收集写入根目录（gather_write_roots 或 override）
   - 过滤敏感路径（filter_sensitive_write_roots）
   - 收集读取根目录（gather_read_roots 或 override）
   - 去重：从读取列表中移除已在写入列表中的路径

3. 构建 ElevationPayload

4. 检测当前权限状态（is_elevated）:
   - 使用 AllocateAndInitializeSid 创建 Administrators SID
   - 使用 CheckTokenMembership 检查当前令牌是否属于 Administrators

5. 执行设置助手（run_setup_exe）:
   - 如果已提升：直接执行（Command::status）
   - 如果未提升：使用 ShellExecuteExW 请求 UAC 提升
```

#### ACL 刷新流程 (`run_setup_refresh`)

```
1. 跳过 DangerFullAccess 和 ExternalSandbox 策略

2. 收集读取和写入根目录

3. 构建 refresh_only=true 的 ElevationPayload

4. 查找设置助手可执行文件（find_setup_exe）

5. 非特权执行（不请求 UAC 提升）

6. 检查退出状态，失败时返回错误
```

#### 根目录收集策略

**读取根目录收集** (`gather_read_roots`):

```rust
pub(crate) fn gather_read_roots(
    command_cwd: &Path,
    policy: &SandboxPolicy,
    codex_home: &Path,
) -> Vec<PathBuf> {
    if policy.has_full_disk_read_access() {
        gather_legacy_full_read_roots(command_cwd, policy, codex_home)
    } else {
        gather_restricted_read_roots(command_cwd, policy, codex_home)
    }
}
```

- **Legacy Full 模式**：包含平台默认目录、用户配置文件（排除敏感目录）、命令 CWD、Helper 目录
- **Restricted 模式**：仅包含策略指定的可读根目录 + Helper 目录 + 可选平台默认

**写入根目录收集** (`gather_write_roots`):

```rust
pub(crate) fn gather_write_roots(
    policy: &SandboxPolicy,
    policy_cwd: &Path,
    command_cwd: &Path,
    env_map: &HashMap<String, String>,
) -> Vec<PathBuf> {
    // 1. 对于 WorkspaceWrite 策略，总是包含 command_cwd
    // 2. 调用 compute_allow_paths 计算允许路径
    // 3. 去重并规范化路径
}
```

#### 敏感路径过滤

```rust
fn filter_sensitive_write_roots(mut roots: Vec<PathBuf>, codex_home: &Path) -> Vec<PathBuf> {
    // 禁止写入以下目录：
    // - CODEX_HOME 本身
    // - CODEX_HOME/.sandbox
    // - CODEX_HOME/.sandbox-bin
    // - CODEX_HOME/.sandbox-secrets
}
```

### Windows API 使用

| 功能 | API 函数 |
|------|----------|
| 权限检查 | `AllocateAndInitializeSid`, `CheckTokenMembership`, `FreeSid` |
| UAC 提升 | `ShellExecuteExW` (with "runas" verb) |
| 进程管理 | `WaitForSingleObject`, `GetExitCodeProcess`, `CloseHandle` |

### 常量定义

```rust
const ERROR_CANCELLED: u32 = 1223;  // 用户取消 UAC 提示
const SECURITY_BUILTIN_DOMAIN_RID: u32 = 0x0000_0020;
const DOMAIN_ALIAS_RID_ADMINS: u32 = 0x0000_0220;

// 用户配置文件排除列表（安全敏感目录）
const USERPROFILE_READ_ROOT_EXCLUSIONS: &[&str] = &[
    ".ssh", ".gnupg", ".aws", ".azure", ".kube", 
    ".docker", ".config", ".npm", ".pki", ".terraform.d",
];

// Windows 平台默认读取根目录
const WINDOWS_PLATFORM_DEFAULT_READ_ROOTS: &[&str] = &[
    r"C:\Windows",
    r"C:\Program Files",
    r"C:\Program Files (x86)",
    r"C:\ProgramData",
];
```

## 关键代码路径与文件引用

### 本文件内部函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `run_elevated_setup` | 576-620 | 主入口，完整设置流程 |
| `run_setup_refresh` | 81-97 | ACL 刷新入口 |
| `run_setup_refresh_with_extra_read_roots` | 99-118 | 带额外读取根的刷新 |
| `run_setup_refresh_inner` | 120-190 | 刷新流程实现 |
| `run_setup_exe` | 465-574 | 执行设置助手 |
| `build_payload_roots` | 622-645 | 构建根目录列表 |
| `gather_read_roots` | 348-358 | 收集读取根目录 |
| `gather_write_roots` | 360-382 | 收集写入根目录 |
| `gather_legacy_full_read_roots` | 303-324 | Legacy 模式读取根 |
| `gather_restricted_read_roots` | 326-346 | Restricted 模式读取根 |
| `filter_sensitive_write_roots` | 647-670 | 过滤敏感写入路径 |
| `is_elevated` | 227-257 | 检查当前是否已提升 |
| `find_setup_exe` | 434-444 | 查找设置助手可执行文件 |
| `report_helper_failure` | 446-463 | 解析设置助手失败 |
| `quote_arg` | 398-432 | Windows 命令行参数转义 |

### 调用的外部模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `allow` | `compute_allow_paths` | 计算允许/拒绝路径 |
| `helper_materialization` | `helper_bin_dir` | 获取 Helper 目录 |
| `path_normalization` | `canonical_path_key` | 路径规范化 |
| `setup_error` | `clear_setup_error_report` | 清除错误报告 |
| `setup_error` | `read_setup_error_report` | 读取错误报告 |
| `winutil` | `to_wide` | 转换为宽字符 |

### 调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `lib.rs` | `run_elevated_setup` | 导出供外部使用 |
| `lib.rs` | `run_setup_refresh` | 导出供外部使用 |
| `identity.rs` | `run_elevated_setup` | 需要设置时调用 |
| `identity.rs` | `run_setup_refresh` | 刷新 ACL 时调用 |
| `tui/src/app.rs` | `run_setup_refresh_with_extra_read_roots` | TUI 应用 |
| `tui_app_server/src/app.rs` | `run_setup_refresh_with_extra_read_roots` | App Server |

## 依赖与外部交互

### 输入依赖

1. **沙箱策略（SandboxPolicy）**：决定读取/写入权限范围
2. **环境变量**：
   - `USERNAME`：识别真实用户
   - `USERPROFILE`：收集用户配置文件目录
3. **文件系统**：
   - `codex-windows-sandbox-setup.exe` 必须存在
   - `.sandbox/setup_error.json` 错误报告文件

### 输出产物

1. **进程执行**：启动 `codex-windows-sandbox-setup.exe`
2. **日志记录**：通过 `log_note` 记录操作日志
3. **错误传播**：将设置助手的错误转换为 `anyhow::Error`

### 与设置助手的交互协议

```
编排器                                    设置助手
   |                                          |
   |-- 1. Base64(JSON(ElevationPayload)) -->|
   |                                          |
   |<-- 2. 退出码 (0=成功, 非0=失败) --------|
   |                                          |
   |-- 3. 如失败，读取 setup_error.json ----|
```

## 风险、边界与改进建议

### 安全风险

1. **参数注入**：`ElevationPayload` 通过命令行传递，可能存在注入风险
   - 缓解：使用 Base64 编码 + JSON 序列化，避免 shell 解析
   - 建议：考虑使用命名管道或文件传递大参数

2. **路径遍历**：收集的根目录可能包含恶意构造的路径
   - 缓解：`canonicalize_path` 规范化路径，`filter_sensitive_write_roots` 过滤敏感路径
   - 建议：添加更严格的路径白名单验证

3. **UAC 绕过**：`run_setup_refresh` 不请求 UAC，依赖设置助手的权限检查
   - 缓解：设置助手内部验证权限是否足够
   - 建议：在编排器层也进行权限预检查

### 边界情况

1. **UAC 禁用**：系统禁用 UAC 时 `ShellExecuteExW` 行为可能不同
2. **路径不存在**：`canonical_existing` 过滤不存在的路径
3. **策略变更**：版本号变更触发完整重新设置
4. **并发执行**：多个进程同时请求设置可能导致竞态

### 改进建议

1. **协议改进**：
   - 使用更安全的 IPC 机制（命名管道）替代命令行参数
   - 添加请求签名防止重放攻击

2. **性能优化**：
   - 缓存根目录计算结果，避免重复遍历文件系统
   - 使用异步 I/O 减少阻塞

3. **可观测性**：
   - 添加详细的遥测指标（设置耗时、失败率、UAC 取消率）
   - 记录策略变更历史

4. **用户体验**：
   - 提供更清晰的 UAC 提示说明（通过 manifest 配置）
   - 支持静默模式（用于自动化场景）

5. **代码结构**：
   - 拆分 `build_payload_roots` 为更小的函数
   - 提取 Windows 平台特定的路径处理逻辑

6. **测试覆盖**：
   - 当前测试主要集中在根目录收集逻辑
   - 建议添加集成测试（使用模拟的设置助手）
