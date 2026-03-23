# exec.rs 深度研究文档

## 场景与职责

`exec.rs` 是 Codex 核心测试套件中专门测试 **macOS Seatbelt 沙箱执行** 的集成测试文件。该文件仅针对 macOS 平台（`#![cfg(target_os = "macos")]`），验证以下核心能力：

1. **命令执行正确性**：确保基本命令能够正常执行并返回预期输出
2. **输出截断机制**：验证大输出场景下的行数和字节数截断逻辑
3. **沙箱隔离性**：确认沙箱策略能够有效阻止未授权的文件系统操作
4. **错误处理**：验证命令不存在等错误场景的妥善处理

该测试文件是 Codex 执行层安全模型的基础验证，确保在启用 macOS Seatbelt 沙箱时代码执行既可用又安全。

## 功能点目的

### 1. 基本命令执行验证
- **目的**：验证简单命令（如 `echo`）在沙箱中正常执行
- **验证点**：
  - 退出码为 0
  - stdout 输出正确
  - stderr 为空

### 2. 输出截断验证
- **目的**：确保大输出不会导致内存问题
- **测试场景**：
  - 行数截断：300 行输出
  - 字节截断：每行 1000 字节，共 15 行（约 15KB）

### 3. 错误场景处理
- **目的**：验证命令不存在时的行为
- **预期**：返回退出码 127，但不视为沙箱错误

### 4. 沙箱隔离验证
- **目的**：确认只读沙箱策略阻止写操作
- **测试**：尝试在沙箱内创建文件应失败

## 具体技术实现

### 沙箱类型定义

```rust
// codex-rs/core/src/exec.rs
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SandboxType {
    None,
    MacosSeatbelt,      // 本测试使用
    LinuxSeccomp,       // Linux 平台
    WindowsRestrictedToken, // Windows 平台
}
```

### 执行参数结构

```rust
pub struct ExecParams {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub expiration: ExecExpiration,
    pub env: HashMap<String, String>,
    pub network: Option<NetworkProxy>,
    pub sandbox_permissions: SandboxPermissions,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
    pub justification: Option<String>,
    pub arg0: Option<String>,
}

pub enum ExecExpiration {
    Timeout(Duration),
    DefaultTimeout,  // 10 秒
    Cancellation(CancellationToken),
}
```

### 核心执行流程

```rust
pub async fn process_exec_tool_call(
    params: ExecParams,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_cwd: &Path,
    codex_linux_sandbox_exe: &Option<PathBuf>,
    use_legacy_landlock: bool,
    stdout_stream: Option<StdoutStream>,
) -> Result<ExecToolCallOutput> {
    // 1. 构建执行请求
    let exec_req = build_exec_request(...)?;
    
    // 2. 选择沙箱类型
    let sandbox_type = select_process_exec_tool_sandbox_type(...);
    
    // 3. 根据沙箱类型执行
    match sandbox_type {
        SandboxType::MacosSeatbelt => {
            // 使用 sandbox-exec 执行
        }
        SandboxType::LinuxSeccomp => { ... }
        SandboxType::None => { ... }
    }
}
```

### 测试辅助函数

```rust
// 测试中的辅助函数
async fn run_test_cmd(tmp: TempDir, cmd: Vec<&str>) -> Result<ExecToolCallOutput> {
    // 获取平台沙箱类型
    let sandbox_type = get_platform_sandbox(false)?;
    assert_eq!(sandbox_type, SandboxType::MacosSeatbelt);
    
    // 构建执行参数
    let params = ExecParams {
        command: cmd.iter().map(ToString::to_string).collect(),
        cwd: tmp.path().to_path_buf(),
        expiration: 1000.into(),  // 1 秒超时
        env: HashMap::new(),
        network: None,
        sandbox_permissions: SandboxPermissions::UseDefault,
        windows_sandbox_level: WindowsSandboxLevel::Disabled,
        windows_sandbox_private_desktop: false,
        justification: None,
        arg0: None,
    };
    
    // 使用只读沙箱策略
    let policy = SandboxPolicy::new_read_only_policy();
    
    // 执行命令
    process_exec_tool_call(params, &policy, ...).await
}
```

### 沙箱策略

```rust
// SandboxPolicy 定义
pub struct SandboxPolicy {
    pub ask_for_approval: AskForApproval,
    pub file_system: FileSystemSandboxPolicy,
    pub network: NetworkSandboxPolicy,
}

// 只读策略（测试中使用的）
impl SandboxPolicy {
    pub fn new_read_only_policy() -> Self {
        Self {
            ask_for_approval: AskForApproval::Never,
            file_system: FileSystemSandboxPolicy::ReadOnly { ... },
            network: NetworkSandboxPolicy::Disabled,
        }
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/exec.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/exec.rs` - 执行引擎核心
  - `process_exec_tool_call` - 主要执行入口
  - `SandboxType` - 沙箱类型枚举
  - `ExecParams` - 执行参数
  - `ExecExpiration` - 超时控制

- `codex-rs/core/src/sandboxing/` - 沙箱实现
  - `SandboxManager` - 沙箱管理器
  - `CommandSpec` - 命令规范
  - `ExecRequest` - 执行请求

- `codex-rs/core/src/spawn.rs` - 子进程管理
  - `spawn_child_async` - 异步子进程创建
  - `SpawnChildRequest` - 子进程请求

### 协议类型
- `codex-rs/protocol/src/permissions.rs`
  - `FileSystemSandboxPolicy` - 文件系统策略
  - `NetworkSandboxPolicy` - 网络策略

- `codex-rs/protocol/src/protocol.rs`
  - `SandboxPolicy` - 完整沙箱策略
  - `ExecCommandOutput` - 执行输出

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_core::exec` | 执行引擎 |
| `codex_core::sandboxing` | 沙箱管理 |
| `codex_core::spawn` | 子进程创建 |
| `codex_protocol::permissions` | 权限策略类型 |

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::process` | 异步进程管理 |

### 平台特定
- **macOS Seatbelt**: 使用 `/usr/bin/sandbox-exec` 执行沙箱命令
- **环境变量**: `CODEX_SANDBOX=seatbelt` 表示当前在沙箱中运行

### 测试跳过逻辑
```rust
fn skip_test() -> bool {
    // 如果已经在 seatbelt 沙箱中，跳过测试
    if std::env::var(CODEX_SANDBOX_ENV_VAR) == Ok("seatbelt".to_string()) {
        eprintln!("{CODEX_SANDBOX_ENV_VAR} is set to 'seatbelt', skipping test.");
        return true;
    }
    false
}
```

## 风险、边界与改进建议

### 已知风险

1. **平台限制**
   - 仅 macOS 平台运行，Linux/Windows 测试缺失
   - 缓解：其他平台有独立的测试文件

2. **沙箱嵌套问题**
   - 在已有沙箱中无法再次启动沙箱
   - 处理：通过 `skip_test()` 检测并跳过

3. **路径硬编码**
   - 测试中使用 `/user/bin/touch`（注意拼写错误）
   - 风险：非标准系统可能不存在该路径

### 边界情况

1. **超时处理**
   - 测试使用 1 秒超时 (`1000.into()`)
   - 边界：命令执行时间接近超时阈值

2. **输出截断**
   - 行数截断：无上限（测试中验证 300 行完整输出）
   - 字节截断：存在 `EXEC_OUTPUT_MAX_BYTES` 限制（默认 10MB）

3. **环境隔离**
   - 测试使用空环境变量 `HashMap::new()`
   - 边界：依赖特定环境变量的命令可能行为异常

### 改进建议

1. **测试覆盖**
   - 添加并发执行测试（多命令同时执行）
   - 添加长时间运行命令的取消测试
   - 添加网络策略测试（允许/禁止网络访问）

2. **错误处理增强**
   - 区分沙箱错误和命令错误
   - 提供更详细的错误上下文

3. **路径修复**
   ```rust
   // 当前代码（有拼写错误）
   let cmd = vec!["/user/bin/touch", ...];  // 应为 /usr/bin/touch
   
   // 改进：使用 which 命令查找
   let touch_path = which::which("touch")?;
   ```

4. **跨平台统一**
   - 提取通用测试逻辑到平台无关模块
   - 使用条件编译仅区分平台特定部分

5. **性能基准**
   - 添加沙箱启动时间基准测试
   - 监控大输出场景下的内存使用
