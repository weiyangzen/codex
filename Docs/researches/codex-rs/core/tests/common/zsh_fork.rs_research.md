# zsh_fork.rs 深度研究文档

## 文件位置
`/home/sansha/Github/codex/codex-rs/core/tests/common/zsh_fork.rs`

---

## 1. 场景与职责

### 1.1 核心定位

`zsh_fork.rs` 是 Codex 核心测试框架中的 **Zsh Fork 测试基础设施模块**，专门用于支持基于 `shell_zsh_fork` 特性的集成测试。该模块提供了一套完整的测试辅助工具，使得测试用例能够在启用 Zsh Fork 执行后端的环境中运行。

### 1.2 业务场景

| 场景 | 描述 |
|------|------|
| **技能脚本执行测试** | 测试带有权限声明的技能脚本在 Zsh Fork 后端下的执行行为 |
| **沙箱策略验证** | 验证 WorkspaceWrite 等沙箱策略在 Zsh Fork 模式下是否正确生效 |
| **执行审批流程测试** | 测试命令执行前的用户审批流程，包括权限提升请求 |
| **子命令拦截测试** | 验证复杂 shell 命令中子命令的独立审批机制 |

### 1.3 架构角色

```
┌─────────────────────────────────────────────────────────────────┐
│                      测试用例 (Test Case)                        │
│                   如: skill_approval.rs                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 使用
┌───────────────────────────▼─────────────────────────────────────┐
│                    zsh_fork.rs (本模块)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ZshForkRuntime│  │build_zsh_   │  │restrictive_workspace_   │  │
│  │   结构体     │  │fork_test()  │  │write_policy()           │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 配置
┌───────────────────────────▼─────────────────────────────────────┐
│                    TestCodex (测试运行时)                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 调用
┌───────────────────────────▼─────────────────────────────────────┐
│              Zsh Fork 后端 (codex_shell_escalation)              │
│         unix_escalation.rs / zsh_fork_backend.rs                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 主要功能

| 功能 | 目的 | 对应函数/结构体 |
|------|------|-----------------|
| **运行时环境封装** | 封装 Zsh Fork 测试所需的二进制路径配置 | `ZshForkRuntime` |
| **测试实例构建** | 创建配置好 Zsh Fork 后端的 TestCodex 实例 | `build_zsh_fork_test()` |
| **沙箱策略工厂** | 提供限制性 WorkspaceWrite 策略用于测试 | `restrictive_workspace_write_policy()` |
| **运行时检测** | 检测当前环境是否支持 Zsh Fork 测试 | `zsh_fork_runtime()` |
| **EXEC_WRAPPER 检测** | 验证 zsh 是否支持 execve 拦截 | `supports_exec_wrapper_intercept()` |

### 2.2 功能特性详解

#### 2.2.1 ZshForkRuntime 结构体

```rust
#[derive(Clone)]
pub struct ZshForkRuntime {
    zsh_path: PathBuf,                    //  patched zsh 可执行文件路径
    main_execve_wrapper_exe: PathBuf,     // codex-execve-wrapper 二进制路径
}
```

该结构体封装了 Zsh Fork 功能所需的两个核心二进制文件：
- **zsh_path**: 经过 patched 的 zsh 可执行文件，支持 `EXEC_WRAPPER` 环境变量拦截
- **main_execve_wrapper_exe**: `codex-execve-wrapper` 二进制，负责 execve 调用的拦截和转发

#### 2.2.2 配置应用逻辑

`apply_to_config()` 方法将 Zsh Fork 配置应用到 `Config` 对象：

```rust
fn apply_to_config(&self, config: &mut Config, ...) {
    // 1. 启用 ShellTool 特性
    config.features.enable(Feature::ShellTool);
    
    // 2. 启用 ShellZshFork 特性（关键）
    config.features.enable(Feature::ShellZshFork);
    
    // 3. 配置 zsh 路径
    config.zsh_path = Some(self.zsh_path.clone());
    
    // 4. 配置 execve wrapper 路径
    config.main_execve_wrapper_exe = Some(self.main_execve_wrapper_exe.clone());
    
    // 5. 禁用登录 shell（测试环境通常不需要）
    config.permissions.allow_login_shell = false;
    
    // 6. 设置审批和沙箱策略
    config.permissions.approval_policy = Constrained::allow_any(approval_policy);
    config.permissions.sandbox_policy = Constrained::allow_any(sandbox_policy);
}
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 测试环境初始化流程

```
测试用例调用 zsh_fork_runtime()
         │
         ▼
    调用 find_test_zsh_path()
         │
         ├──► 检查 codex-rs/app-server/tests/suite/zsh 是否存在
         │
         └──► 使用 dotslash fetch 获取 zsh 实际路径
         │
         ▼
    检查 supports_exec_wrapper_intercept()
         │
         ├──► 运行测试命令: zsh -fc /usr/bin/true EXEC_WRAPPER=/usr/bin/false
         │
         └──► 预期失败（wrapper 返回非零退出码）
         │
         ▼
    解析 codex-execve-wrapper 二进制路径
         │
         └──► 使用 codex_utils_cargo_bin::cargo_bin()
         │
         ▼
    返回 Some(ZshForkRuntime) 或 None（如果不支持）
```

#### 3.1.2 测试实例构建流程

```rust
pub async fn build_zsh_fork_test<F>(
    server: &wiremock::MockServer,
    runtime: ZshForkRuntime,
    approval_policy: AskForApproval,
    sandbox_policy: SandboxPolicy,
    pre_build_hook: F,  // 预构建钩子（如创建技能脚本）
) -> Result<TestCodex>
where
    F: FnOnce(&Path) + Send + 'static,
{
    let mut builder = test_codex()
        .with_pre_build_hook(pre_build_hook)  // 执行预构建操作
        .with_config(move |config| {
            runtime.apply_to_config(config, approval_policy, sandbox_policy);
        });
    builder.build(server).await
}
```

### 3.2 数据结构

#### 3.2.1 核心数据结构关系

```rust
// 本模块定义
pub struct ZshForkRuntime {
    zsh_path: PathBuf,
    main_execve_wrapper_exe: PathBuf,
}

// 依赖的外部类型
pub struct Config {
    pub features: Features,                    // 特性开关集合
    pub zsh_path: Option<PathBuf>,            // Zsh Fork: zsh 路径
    pub main_execve_wrapper_exe: Option<PathBuf>,  // Zsh Fork: wrapper 路径
    pub permissions: Permissions,              // 权限配置
}

pub enum Feature {
    ShellTool,        // 基础 shell 工具
    ShellZshFork,     // Zsh Fork 后端（UnderDevelopment 阶段）
    // ...
}

pub enum SandboxPolicy {
    DangerFullAccess,
    WorkspaceWrite { ... },
    ReadOnly,
    // ...
}

pub enum AskForApproval {
    Never,
    OnRequest,
    UnlessTrusted,
    Granular(...),
}
```

### 3.3 协议与命令

#### 3.3.1 EXEC_WRAPPER 检测机制

```rust
fn supports_exec_wrapper_intercept(zsh_path: &Path) -> bool {
    let status = std::process::Command::new(zsh_path)
        .arg("-fc")                           // 快速执行命令
        .arg("/usr/bin/true")                 // 无害的测试命令
        .env("EXEC_WRAPPER", "/usr/bin/false") // 设置 wrapper 为 false
        .status();
    
    match status {
        // 如果成功，说明 wrapper 没有被调用（不支持拦截）
        // 如果失败，说明 wrapper 被调用了（支持拦截）
        Ok(status) => !status.success(),
        Err(_) => false,
    }
}
```

**原理**: 当 zsh 支持 `EXEC_WRAPPER` 时，任何 `exec()` 调用都会被拦截并转给 wrapper。由于 `/usr/bin/false` 总是返回非零，命令会失败。

#### 3.3.2 DotSlash 资源获取

```rust
fn find_test_zsh_path() -> Result<Option<PathBuf>> {
    let repo_root = codex_utils_cargo_bin::repo_root()?;
    // 使用共享的 DotSlash 文件
    let dotslash_zsh = repo_root.join("codex-rs/app-server/tests/suite/zsh");
    
    // 通过 dotslash 命令获取实际路径
    match crate::fetch_dotslash_file(&dotslash_zsh, /*dotslash_cache*/ None) {
        Ok(path) => Ok(Some(path)),
        Err(error) => {
            eprintln!("skipping zsh-fork test: failed to fetch zsh via dotslash: {error:#}");
            Ok(None)
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本文件内部结构

```
zsh_fork.rs (124 lines)
├── 导入依赖 (lines 1-13)
│   ├── codex_core::config::{Config, Constrained}
│   ├── codex_core::features::Feature
│   └── codex_protocol::protocol::{AskForApproval, SandboxPolicy}
│
├── ZshForkRuntime 结构体定义 (lines 14-41)
│   ├── 字段: zsh_path, main_execve_wrapper_exe
│   └── 方法: apply_to_config()
│
├── restrictive_workspace_write_policy() (lines 43-51)
│   └── 返回限制性的 WorkspaceWrite 沙箱策略
│
├── zsh_fork_runtime() (lines 53-74)
│   └── 检测环境并构建 ZshForkRuntime
│
├── build_zsh_fork_test() (lines 76-92)
│   └── 异步构建配置好的 TestCodex 实例
│
├── find_test_zsh_path() (lines 94-112)
│   └── 通过 DotSlash 获取测试用 zsh 路径
│
└── supports_exec_wrapper_intercept() (lines 114-124)
    └── 检测 zsh 是否支持 EXEC_WRAPPER 拦截
```

### 4.2 上游调用方（谁在使用）

| 调用方文件 | 使用方式 | 测试目的 |
|------------|----------|----------|
| `core/tests/suite/skill_approval.rs` | `use core_test_support::zsh_fork::{build_zsh_fork_test, zsh_fork_runtime, restrictive_workspace_write_policy}` | 技能脚本执行审批测试 |
| `core/tests/suite/approvals.rs` | 同上 | 通用执行审批流程测试 |
| `app-server/tests/suite/v2/turn_start_zsh_fork.rs` | 内联复制了相关函数 | App Server V2 API 的 Zsh Fork 测试 |

### 4.3 下游依赖（被调用方）

| 依赖模块 | 功能 | 路径 |
|----------|------|------|
| `test_codex.rs` | TestCodex 构建器 | `core/tests/common/test_codex.rs` |
| `lib.rs` | fetch_dotslash_file 工具函数 | `core/tests/common/lib.rs` |
| `codex_utils_cargo_bin` | cargo_bin(), repo_root() | 外部 crate |
| `codex_core::config` | Config, Constrained | `core/src/config/mod.rs` |
| `codex_core::features` | Feature enum | `core/src/features.rs` |
| `codex_protocol::protocol` | AskForApproval, SandboxPolicy | protocol crate |

### 4.4 相关核心实现文件

| 文件 | 职责 | 与本文件关系 |
|------|------|--------------|
| `core/src/tools/runtimes/shell/zsh_fork_backend.rs` | Zsh Fork 后端入口 | 本模块配置的目标后端 |
| `core/src/tools/runtimes/shell/unix_escalation.rs` | Unix 权限提升实现 | Zsh Fork 核心执行逻辑 |
| `shell-escalation/src/unix/mod.rs` | Shell 权限提升协议 | 底层 escalation 实现 |
| `shell-escalation/src/bin/main_execve_wrapper.rs` | execve wrapper 二进制 | 本模块配置的 wrapper |
| `core/src/features.rs` | Feature 枚举定义 | ShellZshFork 特性定义 |
| `core/src/tools/spec.rs` | ZshForkConfig 定义 | 配置结构体定义 |

---

## 5. 依赖与外部交互

### 5.1 外部二进制依赖

| 二进制 | 来源 | 用途 |
|--------|------|------|
| `codex-execve-wrapper` | 本项目构建 | execve 系统调用拦截器 |
| `zsh` (patched) | DotSlash 分发 | 支持 EXEC_WRAPPER 的 shell |
| `dotslash` | 系统/用户安装 | 获取 patched zsh |

### 5.2 环境变量交互

| 环境变量 | 设置方 | 用途 |
|----------|--------|------|
| `EXEC_WRAPPER` | escalation server | 指示 zsh 使用 wrapper 拦截 exec |
| `CODEX_ESCALATE_SOCKET` | EscalateServer | escalation 通信 socket |
| `DOTSLASH_CACHE` | 可选配置 | DotSlash 缓存目录 |

### 5.3 特性开关依赖

```rust
// 必须同时启用的特性
Feature::ShellTool      // 基础 shell 功能
Feature::ShellZshFork   // Zsh Fork 后端（UnderDevelopment 阶段）
```

### 5.4 平台限制

```rust
// Zsh Fork 仅在 Unix 平台可用
#[cfg(unix)]
mod imp { ... }

#[cfg(not(unix))]
mod imp {
    // 非 Unix 平台返回 Ok(None) 回退到默认实现
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **环境依赖** | 需要 patched zsh 和 dotslash 工具 | 优雅跳过测试（返回 Ok(None)） |
| **平台限制** | 仅 Unix 平台支持 | 条件编译隔离 |
| **测试不稳定** | Linux CI 偶尔出现额外请求 | 使用 unchecked mock server |
| **ARM 架构问题** | Linux sandbox arg0 测试在 ARM 上失败 | 条件编译排除 |

### 6.2 边界条件

#### 6.2.1 检测边界

```rust
// 当以下任一条件不满足时，测试会被跳过：
1. dotslash 文件不存在
2. dotslash fetch 失败
3. zsh 不支持 EXEC_WRAPPER
4. codex-execve-wrapper 二进制找不到
```

#### 6.2.2 配置边界

```rust
// unified_exec_shell_mode 选择逻辑（from spec.rs）
if cfg!(unix)
    && shell_command_backend == ShellCommandBackendConfig::ZshFork
    && matches!(user_shell.shell_type, ShellType::Zsh)
    && shell_zsh_path.is_some()
    && main_execve_wrapper_exe.is_some()
{
    UnifiedExecShellMode::ZshFork(...)
} else {
    UnifiedExecShellMode::Direct  // 回退到直接执行
}
```

### 6.3 改进建议

#### 6.3.1 短期改进

1. **错误信息增强**
   ```rust
   // 当前
   eprintln!("skipping {test_name}: zsh does not support EXEC_WRAPPER intercepts");
   
   // 建议：增加诊断信息
   eprintln!("skipping {test_name}: zsh ({}) does not support EXEC_WRAPPER intercepts. "
             "Expected command to fail when EXEC_WRAPPER=/usr/bin/false, but got exit code 0",
             zsh_path.display());
   ```

2. **缓存机制**
   ```rust
   // 当前每次测试都检测
   // 建议：使用 once_cell 缓存检测结果
   static ZSH_FORK_AVAILABLE: OnceCell<bool> = OnceCell::new();
   ```

#### 6.3.2 中期改进

1. **统一测试基础设施**
   - `app-server/tests/suite/v2/turn_start_zsh_fork.rs` 复制了 `find_test_zsh_path()` 和 `supports_exec_wrapper_intercept()`
   - 建议：将这些函数提升到更高级别的共享库中

2. **并行测试支持**
   - 当前测试使用共享的 zsh DotSlash 文件
   - 考虑支持并行获取和缓存

#### 6.3.3 长期演进

1. **特性稳定化**
   ```rust
   // 当前状态
   FeatureSpec {
       id: Feature::ShellZshFork,
       key: "shell_zsh_fork",
       stage: Stage::UnderDevelopment,  // 待稳定
       default_enabled: false,
   }
   ```
   - 随着测试覆盖完善，考虑提升到 Experimental 或 Stable 阶段

2. **跨平台支持**
   - 评估 Windows 下的类似机制（如 Detours 或 AppContainer）
   - 或明确文档化仅 Unix 支持的限制

### 6.4 测试覆盖建议

| 测试场景 | 当前覆盖 | 建议补充 |
|----------|----------|----------|
| 基础命令执行 | ✅ | - |
| 技能脚本执行 | ✅ | 增加更多权限组合 |
| 子命令审批 | ✅ | 增加嵌套层级测试 |
| 超时处理 | ⚠️ | 增加长时间运行测试 |
| 并发执行 | ❌ | 增加并行命令测试 |
| 错误恢复 | ⚠️ | 增加 wrapper 崩溃测试 |

---

## 7. 附录

### 7.1 相关代码片段

#### 7.1.1 典型的 Zsh Fork 测试用例结构

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn shell_zsh_fork_some_test() -> Result<()> {
    skip_if_no_network!(Ok(()));

    // 1. 获取运行时（可能返回 None 跳过测试）
    let Some(runtime) = zsh_fork_runtime("test name")? else {
        return Ok(());
    };

    // 2. 构建测试实例
    let server = start_mock_server().await;
    let test = build_zsh_fork_test(
        &server,
        runtime,
        AskForApproval::OnRequest,
        SandboxPolicy::new_workspace_write_policy(),
        |home| {
            // 3. 预构建钩子：创建测试文件、技能脚本等
            setup_test_data(home);
        },
    ).await?;

    // 4. 执行测试逻辑
    // ...
}
```

#### 7.1.2 restrictive_workspace_write_policy 实现

```rust
pub fn restrictive_workspace_write_policy() -> SandboxPolicy {
    SandboxPolicy::WorkspaceWrite {
        writable_roots: Vec::new(),           // 空列表 = 仅工作区可写
        read_only_access: Default::default(),
        network_access: false,                // 禁用网络
        exclude_tmpdir_env_var: true,         // 排除 TMPDIR
        exclude_slash_tmp: true,              // 排除 /tmp
    }
}
```

### 7.2 参考文档

- [shell-escalation/README.md](/home/sansha/Github/codex/codex-rs/shell-escalation/README.md) - escalation 协议文档
- [AGENTS.md](/home/sansha/Github/codex/AGENTS.md) - 项目级开发指南
- [features.rs](/home/sansha/Github/codex/codex-rs/core/src/features.rs) - 特性开关定义

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/core/tests/common/zsh_fork.rs (124 lines)*
