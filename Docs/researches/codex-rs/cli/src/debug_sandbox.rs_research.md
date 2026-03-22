# debug_sandbox.rs 研究文档

## 场景与职责

`debug_sandbox.rs` 是 Codex CLI 中用于调试沙箱功能的核心模块。它提供了在三种不同沙箱技术（Seatbelt、Landlock、Windows Sandbox）下运行命令的能力，主要用于：

1. **开发调试**: 验证沙箱策略配置是否正确
2. **安全测试**: 测试应用在受限环境下的行为
3. **权限验证**: 检查文件系统和网络访问权限
4. **拒绝日志**: macOS 下捕获和显示沙箱拒绝日志

## 功能点目的

### 1. 多平台沙箱支持
- **Seatbelt**: macOS 原生沙箱技术 (`sandbox-exec`)
- **Landlock**: Linux 内核级沙箱 (通过 codex-linux-sandbox 辅助程序)
- **Windows Sandbox**: Windows 受限令牌沙箱

### 2. 调试功能
- `--full-auto` 模式: 提供低摩擦的自动执行环境
- `--log-denials` (macOS): 捕获沙箱拒绝日志
- 配置覆盖: 支持通过 CLI 覆盖配置

### 3. 网络代理管理
- 支持托管网络代理的启动和管理
- 网络沙箱策略集成

## 具体技术实现

### 关键数据结构

```rust
enum SandboxType {
    #[cfg(target_os = "macos")]
    Seatbelt,
    Landlock,
    Windows,
}

// 命令结构体定义在 lib.rs
pub struct SeatbeltCommand {
    pub full_auto: bool,
    pub log_denials: bool,
    pub config_overrides: CliConfigOverrides,
    pub command: Vec<String>,
}

pub struct LandlockCommand {
    pub full_auto: bool,
    pub config_overrides: CliConfigOverrides,
    pub command: Vec<String>,
}
```

### 核心流程

```
run_command_under_sandbox()
    ↓
load_debug_sandbox_config() - 加载配置
    ↓
create_env() - 创建环境变量
    ↓
[Windows] 特殊处理: run_windows_sandbox_capture()
    ↓
[macOS/Linux] spawn_debug_sandbox_child()
    ↓
    ├── Seatbelt: /usr/bin/sandbox-exec + seatbelt 参数
    ├── Landlock: codex-linux-sandbox + landlock 参数
    └── Windows: (已在前面处理)
    ↓
child.wait() → handle_exit_status()
```

### 配置加载逻辑

```rust
async fn load_debug_sandbox_config(
    cli_overrides: Vec<(String, TomlValue)>,
    codex_linux_sandbox_exe: Option<PathBuf>,
    full_auto: bool,
) -> anyhow::Result<Config>
```

配置加载分为两种情况：
1. **权限配置文件模式**: 使用新的 `[permissions]` 配置格式
2. **传统沙箱模式**: 使用 `sandbox_mode` 配置（支持 `--full-auto`）

### 子进程创建

```rust
async fn spawn_debug_sandbox_child(
    program: PathBuf,
    args: Vec<String>,
    arg0: Option<&str>,
    cwd: PathBuf,
    network_sandbox_policy: NetworkSandboxPolicy,
    mut env: HashMap<String, String>,
    apply_env: impl FnOnce(&mut HashMap<String, String>),
) -> std::io::Result<Child>
```

关键特性：
- 继承标准输入输出
- 环境变量清理后重新设置
- 网络禁用标志设置

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs` (556 行)

### 子模块
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs` - macOS 拒绝日志捕获
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs` - 进程树跟踪

### 依赖的核心库
- `codex_core::config` - 配置管理
- `codex_core::landlock` - Linux Landlock 策略生成
- `codex_core::seatbelt` - macOS Seatbelt 策略生成
- `codex_core::spawn` - 环境变量常量
- `codex_core::exec_env` - 执行环境创建

### 调用关系
```
debug_sandbox.rs
    ├── run_command_under_seatbelt()
    ├── run_command_under_landlock()
    ├── run_command_under_windows()
    └── run_command_under_sandbox()
            ├── load_debug_sandbox_config()
            ├── create_env()
            ├── [Windows] run_windows_sandbox_capture()
            └── spawn_debug_sandbox_child()
                    └── TokioCommand
```

## 依赖与外部交互

### 外部系统命令
- `/usr/bin/sandbox-exec`: macOS 沙箱执行
- `codex-linux-sandbox`: Linux 沙箱辅助程序

### 环境变量
- `CODEX_SANDBOX_ENV_VAR`: 标识沙箱类型
- `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR`: 网络禁用标志

### 核心依赖
```rust
use codex_core::config::{Config, ConfigBuilder, ConfigOverrides, NetworkProxyAuditMetadata};
use codex_core::exec_env::create_env;
use codex_core::landlock::create_linux_sandbox_command_args_for_policies;
use codex_core::seatbelt::create_seatbelt_command_args_for_policies_with_extensions;
use codex_protocol::config_types::SandboxMode;
use codex_protocol::permissions::NetworkSandboxPolicy;
```

## 风险、边界与改进建议

### 风险点

1. **平台差异**: 三种沙箱实现差异大，行为可能不一致
2. **权限提升**: Windows 沙箱需要处理 Elevated 模式
3. **进程泄漏**: 子进程需要正确清理
4. **信号处理**: Unix 信号处理需要特殊考虑

### 边界情况

1. **配置冲突**: `--full-auto` 与权限配置文件不兼容
   ```rust
   if config_uses_permission_profiles(&config) && full_auto {
       anyhow::bail!("`codex sandbox --full-auto` is only supported for legacy...");
   }
   ```

2. **网络代理生命周期**: 代理只在子进程生命周期内有效

3. **Windows 特殊处理**: 使用 `spawn_blocking` 因为 Windows 沙箱 API 是同步的

### 测试覆盖

模块包含两个集成测试：
1. `debug_sandbox_honors_active_permission_profiles`: 验证权限配置文件优先级
2. `debug_sandbox_rejects_full_auto_for_permission_profiles`: 验证 `--full-auto` 冲突检测

### 改进建议

1. **统一抽象**: 三种沙箱的抽象层次可以进一步统一
2. **日志增强**: 添加更多调试日志，特别是策略生成过程
3. **错误信息**: 提供更详细的沙箱启动失败原因
4. **策略验证**: 在启动前验证策略配置的有效性
5. **资源限制**: 添加内存/CPU 限制支持
6. **超时控制**: 为沙箱执行添加超时机制
7. **跨平台测试**: 增加 CI 覆盖所有三种沙箱类型

### 安全考虑

1. 环境变量清理确保敏感信息不会泄漏到沙箱内
2. 网络代理提供细粒度的网络访问控制
3. 配置文件权限验证防止恶意配置注入
