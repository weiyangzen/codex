# landlock.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`landlock.rs` 实现 Linux 沙箱的**内圈安全机制**，负责在当前线程应用进程级沙箱限制。它是 Codex Linux 沙箱架构中的第二道防线，在 bubblewrap 构建的文件系统视图基础上，进一步限制进程能力。

### 1.2 核心职责
- **`PR_SET_NO_NEW_PRIVS`**：启用后阻止进程通过 setuid/setgid 提升权限
- **Seccomp BPF 过滤**：系统调用级别的网络访问控制
- **Landlock LSM**（遗留）：文件系统访问控制（当前默认禁用，作为后备方案）

### 1.3 架构角色

```
┌─────────────────────────────────────────────────────────────┐
│                    Linux Sandbox 架构                        │
├─────────────────────────────────────────────────────────────┤
│  外圈 (bwrap.rs)                                            │
│  ├── mount 命名空间隔离（文件系统视图）                       │
│  ├── PID 命名空间隔离                                        │
│  └── 网络命名空间隔离（可选）                                 │
├─────────────────────────────────────────────────────────────┤
│  内圈 (landlock.rs)                                         │
│  ├── PR_SET_NO_NEW_PRIVS（阻止权限提升）                     │
│  ├── Seccomp（系统调用过滤）                                 │
│  └── Landlock（文件系统访问控制 - 遗留）                      │
└─────────────────────────────────────────────────────────────┘
```

模块注释明确指出："Filesystem restrictions are intentionally handled by bubblewrap. Landlock helpers remain available here as legacy/backup utilities."

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 状态 |
|--------|------|------|
| `apply_sandbox_policy_to_current_thread` | 主入口：应用所有进程级沙箱策略 | 活跃使用 |
| `set_no_new_privs` | 启用 `PR_SET_NO_NEW_PRIVS` | 活跃使用 |
| `install_network_seccomp_filter_on_current_thread` | 安装网络相关的 seccomp 过滤器 | 活跃使用 |
| `install_filesystem_landlock_rules_on_current_thread` | 安装 Landlock 文件系统规则 | 遗留/后备 |

### 2.2 网络 Seccomp 模式

```rust
enum NetworkSeccompMode {
    Restricted,    // 完全网络隔离：阻断所有网络相关 syscall
    ProxyRouted,   // 代理路由模式：仅允许 AF_INET/AF_INET6，禁止 AF_UNIX
}
```

### 2.3 策略应用条件

`PR_SET_NO_NEW_PRIVS` 在以下情况启用：
1. 需要安装网络 seccomp 过滤器时
2. 显式使用遗留 Landlock 文件系统管道且非完全磁盘写入时

## 3. 具体技术实现

### 3.1 核心数据结构

#### NetworkSeccompMode
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum NetworkSeccompMode {
    Restricted,
    ProxyRouted,
}
```

### 3.2 主入口函数

```rust
pub(crate) fn apply_sandbox_policy_to_current_thread(
    sandbox_policy: &SandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    cwd: &Path,
    apply_landlock_fs: bool,        // 是否应用遗留 Landlock
    allow_network_for_proxy: bool,  // 是否为代理允许网络
    proxy_routed_network: bool,     // 是否使用代理路由模式
) -> Result<()>
```

**执行流程**：
1. 确定网络 seccomp 模式
2. 条件性启用 `PR_SET_NO_NEW_PRIVS`
3. 条件性安装网络 seccomp 过滤器
4. 条件性安装 Landlock 文件系统规则

### 3.3 PR_SET_NO_NEW_PRIVS

```rust
fn set_no_new_privs() -> Result<()> {
    let result = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
    if result != 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(())
}
```

**安全意义**：
- 阻止进程执行 setuid/setgid 二进制文件提升权限
- 是 seccomp 过滤器生效的前提条件
- 一旦启用，进程及其子进程无法撤销

### 3.4 Seccomp BPF 过滤器

#### 3.4.1 被拒绝的系统调用（通用）

```rust
deny_syscall(&mut rules, libc::SYS_ptrace);           // 调试/进程注入
deny_syscall(&mut rules, libc::SYS_io_uring_setup);  // io_uring
deny_syscall(&mut rules, libc::SYS_io_uring_enter);
deny_syscall(&mut rules, libc::SYS_io_uring_register);
```

#### 3.4.2 Restricted 模式

完全阻断网络相关系统调用：
```rust
deny_syscall(&mut rules, libc::SYS_connect);
deny_syscall(&mut rules, libc::SYS_accept);
deny_syscall(&mut rules, libc::SYS_accept4);
deny_syscall(&mut rules, libc::SYS_bind);
deny_syscall(&mut rules, libc::SYS_listen);
deny_syscall(&mut rules, libc::SYS_getpeername);
deny_syscall(&mut rules, libc::SYS_getsockname);
deny_syscall(&mut rules, libc::SYS_shutdown);
deny_syscall(&mut rules, libc::SYS_sendto);
deny_syscall(&mut rules, libc::SYS_sendmmsg);
deny_syscall(&mut rules, libc::SYS_recvmmsg);
deny_syscall(&mut rules, libc::SYS_getsockopt);
deny_syscall(&mut rules, libc::SYS_setsockopt);
```

**socket/socketpair 的特殊处理**：
允许 `AF_UNIX`（Unix 域套接字），拒绝其他地址族：
```rust
let unix_only_rule = SeccompRule::new(vec![SeccompCondition::new(
    0, // first argument (domain)
    SeccompCmpArgLen::Dword,
    SeccompCmpOp::Ne,
    libc::AF_UNIX as u64,
)?])?;

rules.insert(libc::SYS_socket, vec![unix_only_rule.clone()]);
rules.insert(libc::SYS_socketpair, vec![unix_only_rule]);
```

**注意**：`recvfrom` 被有意允许，以支持 `cargo clippy` 等使用 socketpair 进行子进程管理的工具。

#### 3.4.3 ProxyRouted 模式

允许 IP 套接字，禁止 Unix 域套接字：
```rust
let deny_non_ip_socket = SeccompRule::new(vec![
    SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET as u64)?,
    SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET6 as u64)?,
])?;
let deny_unix_socketpair = SeccompRule::new(vec![SeccompCondition::new(
    0, SeccompCmpArgLen::Dword, SeccompCmpOp::Eq, libc::AF_UNIX as u64,
)?])?;

rules.insert(libc::SYS_socket, vec![deny_non_ip_socket]);
rules.insert(libc::SYS_socketpair, vec![deny_unix_socketpair]);
```

#### 3.4.4 过滤器构建

```rust
let filter = SeccompFilter::new(
    rules,
    SeccompAction::Allow,                     // 默认允许
    SeccompAction::Errno(libc::EPERM as u32), // 匹配规则时返回 EPERM
    if cfg!(target_arch = "x86_64") {
        TargetArch::x86_64
    } else if cfg!(target_arch = "aarch64") {
        TargetArch::aarch64
    } else {
        unimplemented!("unsupported architecture for seccomp filter");
    },
)?;

let prog: BpfProgram = filter.try_into()?;
apply_filter(&prog)?;
```

### 3.5 Landlock 文件系统控制（遗留）

```rust
fn install_filesystem_landlock_rules_on_current_thread(
    writable_roots: Vec<AbsolutePathBuf>,
) -> Result<()>
```

**策略**：
- 全局只读访问（`/`）
- `/dev/null` 可读写
- 指定的 `writable_roots` 可读写

**限制**：
- 不支持受限只读访问（需要显式列出所有可读路径）
- 作为后备方案保留，默认不使用

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
linux_run_main::run_main
  └── apply_sandbox_policy_to_current_thread (landlock.rs:42)
      ├── network_seccomp_mode (landlock.rs:104)
      ├── set_no_new_privs (landlock.rs:119) [条件性]
      ├── install_network_seccomp_filter_on_current_thread (landlock.rs:168) [条件性]
      │   ├── deny_syscall (ptrace, io_uring)
      │   └── 根据模式添加 socket 规则
      └── install_filesystem_landlock_rules_on_current_thread (landlock.rs:136) [条件性]
```

### 4.2 调用方

| 调用方 | 位置 | 用途 |
|--------|------|------|
| `linux_run_main.rs` | 行 148, 162, 209 | 应用沙箱策略到当前线程 |

### 4.3 测试覆盖

单元测试位于模块底部（行 266-325）：

| 测试函数 | 测试目的 |
|----------|----------|
| `managed_network_enforces_seccomp_even_for_full_network_policy` | 托管网络强制 seccomp |
| `full_network_policy_without_managed_network_skips_seccomp` | 非托管网络跳过 seccomp |
| `restricted_network_policy_always_installs_seccomp` | 受限网络总是安装 seccomp |
| `managed_proxy_routes_use_proxy_routed_seccomp_mode` | 代理路由使用 ProxyRouted 模式 |
| `restricted_network_without_proxy_routing_uses_restricted_mode` | 受限网络使用 Restricted 模式 |
| `full_network_without_managed_proxy_skips_network_seccomp_mode` | 完全网络无代理时跳过 |

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| crate | 用途 | 特性 |
|-------|------|------|
| `landlock` | Landlock LSM 绑定 | 文件系统访问控制 |
| `seccompiler` | Seccomp BPF 编译 | 系统调用过滤 |
| `libc` | Linux 系统调用 | prctl, 常量定义 |

### 5.2 Landlock crate 使用

```rust
use landlock::ABI;
use landlock::Access;
use landlock::AccessFs;
use landlock::CompatLevel;
use landlock::Compatible;
use landlock::Ruleset;
use landlock::RulesetAttr;
use landlock::RulesetCreatedAttr;
```

### 5.3 Seccompiler crate 使用

```rust
use seccompiler::BpfProgram;
use seccompiler::SeccompAction;
use seccompiler::SeccompCmpArgLen;
use seccompiler::SeccompCmpOp;
use seccompiler::SeccompCondition;
use seccompiler::SeccompFilter;
use seccompiler::SeccompRule;
use seccompiler::TargetArch;
use seccompiler::apply_filter;
```

### 5.4 内部依赖

```rust
use codex_core::error::CodexErr;
use codex_core::error::Result;
use codex_core::error::SandboxErr;
use codex_protocol::protocol::NetworkSandboxPolicy;
use codex_protocol::protocol::SandboxPolicy;
use codex_utils_absolute_path::AbsolutePathBuf;
```

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Seccomp 绕过风险
- **风险**：通过已允许的系统调用间接实现网络访问
- **缓解**：`recvfrom` 被允许以支持工具链，但可能暴露攻击面
- **评估**：当前策略在功能性和安全性之间取得平衡

#### 6.1.2 Landlock 兼容性问题
- **风险**：旧内核不支持 Landlock ABI v5
- **缓解**：使用 `CompatLevel::BestEffort` 降级
- **代码**：
```rust
let mut ruleset = Ruleset::default()
    .set_compatibility(CompatLevel::BestEffort)
```

#### 6.1.3 架构支持限制
- **风险**：仅支持 x86_64 和 aarch64
- **代码**：
```rust
if cfg!(target_arch = "x86_64") { TargetArch::x86_64 }
else if cfg!(target_arch = "aarch64") { TargetArch::aarch64 }
else { unimplemented!("unsupported architecture for seccomp filter"); }
```

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 内核不支持 Landlock | 返回 `CodexErr::Sandbox(LandlockRestrict)` |
| 内核不支持 seccomp | 依赖 seccompiler crate 处理错误 |
| `PR_SET_NO_NEW_PRIVS` 失败 | 返回 IO 错误 |
| 非 Linux 平台 | 编译时排除 |

### 6.3 改进建议

#### 6.3.1 架构支持扩展
- **建议**：添加对 riscv64 的支持
- **理由**：RISC-V 在服务器和嵌入式领域日益普及
- **实现**：添加 `TargetArch` 分支

#### 6.3.2 Seccomp 规则优化
- **建议**：考虑使用 seccomp 的 `SECCOMP_FILTER_FLAG_TSYNC` 确保多线程安全
- **理由**：当前实现假设单线程或依赖调用方保证

#### 6.3.3 Landlock 移除评估
- **建议**：评估完全移除 Landlock 代码路径的可行性
- **理由**：注释表明其为"legacy/backup"，且 bubblewrap 已提供文件系统隔离
- **风险**：需要确保所有使用场景都被覆盖

#### 6.3.4 可观测性增强
- **建议**：添加 seccomp 违规日志记录
- **实现**：使用 `SECCOMP_RET_LOG` 动作或审计子系统
- **价值**：便于调试和审计

#### 6.3.5 测试覆盖扩展
- **建议**：添加实际的系统调用拦截测试
- **实现**：使用 `nix` crate 尝试被禁止的调用，验证 EPERM 返回
- **当前**：仅测试模式选择逻辑，未测试实际过滤效果

### 6.4 维护注意事项

1. **seccompiler 版本更新**：关注上游安全公告，及时更新规则
2. **Landlock ABI 演进**：ABI v5 是当前使用版本，关注新版本的兼容性要求
3. **内核版本要求**：Landlock 需要 Linux 5.13+，seccomp 需要 3.5+
4. **与 bubblewrap 的协调**：确保 seccomp 不重复或冲突于 bwrap 的限制
