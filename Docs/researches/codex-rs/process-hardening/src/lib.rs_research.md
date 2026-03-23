# codex-rs/process-hardening/src/lib.rs 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-process-hardening` 是 Codex 项目中的**进程安全加固 crate**，其核心目标是在程序启动早期（pre-main 阶段）执行一系列安全加固措施，防止敏感信息（如 API 密钥）被恶意提取或进程被非法调试。

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **API 密钥保护** | `responses-api-proxy` 等处理敏感凭证的组件需要防止内存被 dump |
| **反调试保护** | 阻止调试器通过 `ptrace` 附加到进程 |
| **动态链接器劫持防护** | 清除 `LD_PRELOAD`/`DYLD_*` 等环境变量，防止库注入攻击 |
| **Core Dump 防护** | 禁用 core dump 防止进程内存被写入磁盘 |

### 1.3 调用方分析

当前主要的调用方是 `codex-responses-api-proxy`：

```rust
// codex-rs/responses-api-proxy/src/main.rs
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
}
```

通过 `ctor` crate 的 `#[ctor::ctor]` 属性，确保 `pre_main_hardening()` 在 `main()` 函数之前自动执行，实现**零侵入**的安全加固。

---

## 2. 功能点目的

### 2.1 功能总览

| 功能 | Linux/Android | macOS | FreeBSD/OpenBSD | Windows |
|------|--------------|-------|-----------------|---------|
| **禁用 ptrace/调试** | ✅ `prctl(PR_SET_DUMPABLE, 0)` | ✅ `ptrace(PT_DENY_ATTACH)` | ❌ 未实现 | ❌ TODO |
| **禁用 Core Dump** | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | ❌ TODO |
| **清除 LD_* 环境变量** | ✅ 清除所有 `LD_` 前缀变量 | N/A | ✅ 清除所有 `LD_` 前缀变量 | N/A |
| **清除 DYLD_* 环境变量** | N/A | ✅ 清除所有 `DYLD_` 前缀变量 | N/A | N/A |

### 2.2 各功能详细目的

#### 2.2.1 禁用 ptrace / 进程防调试

- **Linux/Android**: 使用 `prctl(PR_SET_DUMPABLE, 0)` 将进程标记为 non-dumpable
  - 阻止 `ptrace` 附加（除非父进程或具有 `CAP_SYS_PTRACE` 能力）
  - 阻止生成 core dump
  - 阻止 `/proc/[pid]/mem` 等敏感文件被非特权用户读取

- **macOS**: 使用 `ptrace(PT_DENY_ATTACH, 0, NULL, 0)`
  - 显式拒绝调试器附加
  - 这是 macOS 特有的反调试机制

#### 2.2.2 禁用 Core Dump

通过 `setrlimit(RLIMIT_CORE, 0)` 将 core file size limit 设置为 0：
- 作为 "defense in depth"（纵深防御）措施
- 即使 `PR_SET_DUMPABLE` 被绕过，也能阻止 core dump 生成

#### 2.2.3 清除危险环境变量

| 平台 | 环境变量前缀 | 风险 |
|------|-------------|------|
| Linux/Android/FreeBSD/OpenBSD | `LD_` | `LD_PRELOAD` 可用于注入恶意共享库 |
| macOS | `DYLD_` | `DYLD_INSERT_LIBRARIES` 可用于库注入 |

注释中特别提到：
> "Official Codex releases are MUSL-linked, which means that variables such as LD_PRELOAD are ignored anyway, but just to be sure, clear them here."

说明这是**额外的安全层**，即使 MUSL 链接已经提供了一定保护。

---

## 3. 具体技术实现

### 3.1 核心函数

#### `pre_main_hardening()` - 入口函数

```rust
pub fn pre_main_hardening() {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    pre_main_hardening_linux();

    #[cfg(target_os = "macos")]
    pre_main_hardening_macos();

    #[cfg(any(target_os = "freebsd", target_os = "openbsd"))]
    pre_main_hardening_bsd();

    #[cfg(windows)]
    pre_main_hardening_windows();
}
```

使用条件编译 (`#[cfg]`) 实现跨平台支持。

#### `pre_main_hardening_linux()` - Linux/Android 实现

```rust
pub(crate) fn pre_main_hardening_linux() {
    // 1. 禁用 ptrace attach / 标记进程 non-dumpable
    let ret_code = unsafe { libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0) };
    if ret_code != 0 {
        eprintln!("ERROR: prctl(PR_SET_DUMPABLE, 0) failed: {}", ...);
        std::process::exit(PRCTL_FAILED_EXIT_CODE);
    }

    // 2. 设置 core file size limit 为 0
    set_core_file_size_limit_to_zero();

    // 3. 清除 LD_* 环境变量
    let ld_keys = env_keys_with_prefix(std::env::vars_os(), b"LD_");
    for key in ld_keys {
        unsafe { std::env::remove_var(key); }
    }
}
```

#### `pre_main_hardening_macos()` - macOS 实现

```rust
pub(crate) fn pre_main_hardening_macos() {
    // 1. 使用 ptrace 阻止调试器附加
    let ret_code = unsafe { libc::ptrace(libc::PT_DENY_ATTACH, 0, std::ptr::null_mut(), 0) };
    if ret_code == -1 {
        eprintln!("ERROR: ptrace(PT_DENY_ATTACH) failed: {}", ...);
        std::process::exit(PTRACE_DENY_ATTACH_FAILED_EXIT_CODE);
    }

    // 2. 禁用 core dump
    set_core_file_size_limit_to_zero();

    // 3. 清除 DYLD_* 环境变量
    let dyld_keys = env_keys_with_prefix(std::env::vars_os(), b"DYLD_");
    for key in dyld_keys {
        unsafe { std::env::remove_var(key); }
    }
}
```

#### `pre_main_hardening_bsd()` - BSD 实现

```rust
pub(crate) fn pre_main_hardening_bsd() {
    // FreeBSD/OpenBSD: 仅实现 core dump 禁用和 LD_* 清除
    set_core_file_size_limit_to_zero();

    let ld_keys = env_keys_with_prefix(std::env::vars_os(), b"LD_");
    for key in ld_keys {
        unsafe { std::env::remove_var(key); }
    }
}
```

#### `set_core_file_size_limit_to_zero()` - 跨平台 core dump 禁用

```rust
#[cfg(unix)]
fn set_core_file_size_limit_to_zero() {
    let rlim = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };

    let ret_code = unsafe { libc::setrlimit(libc::RLIMIT_CORE, &rlim) };
    if ret_code != 0 {
        eprintln!("ERROR: setrlimit(RLIMIT_CORE) failed: {}", ...);
        std::process::exit(SET_RLIMIT_CORE_FAILED_EXIT_CODE);
    }
}
```

### 3.2 辅助函数

#### `env_keys_with_prefix()` - 环境变量过滤

```rust
#[cfg(unix)]
fn env_keys_with_prefix<I>(vars: I, prefix: &[u8]) -> Vec<OsString>
where
    I: IntoIterator<Item = (OsString, OsString)>,
{
    vars.into_iter()
        .filter_map(|(key, _)| {
            key.as_os_str()
                .as_bytes()
                .starts_with(prefix)
                .then_some(key)
        })
        .collect()
}
```

**关键设计点**：
- 使用字节级比较（而非字符串比较），支持非 UTF-8 环境变量名
- 返回匹配的 key 列表，避免在迭代过程中修改环境变量（可能导致迭代器失效）

### 3.3 错误处理与退出码

| 常量 | 值 | 含义 |
|------|-----|------|
| `PRCTL_FAILED_EXIT_CODE` | 5 | `prctl(PR_SET_DUMPABLE, 0)` 失败 |
| `PTRACE_DENY_ATTACH_FAILED_EXIT_CODE` | 6 | `ptrace(PT_DENY_ATTACH)` 失败 |
| `SET_RLIMIT_CORE_FAILED_EXIT_CODE` | 7 | `setrlimit(RLIMIT_CORE)` 失败 |

**设计原则**：Fail-secure（故障安全）
- 任何加固措施失败时，立即打印错误信息并退出进程
- 不继续运行可能处于不安全状态的程序

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/process-hardening/
├── Cargo.toml          # 包配置，依赖 libc
├── BUILD.bazel         # Bazel 构建配置
├── README.md           # 简要文档
└── src/
    └── lib.rs          # 全部实现（190 行）
```

### 4.2 关键代码路径

```
pre_main_hardening()
├── Linux/Android
│   └── pre_main_hardening_linux()
│       ├── libc::prctl(PR_SET_DUMPABLE, 0)      [src/lib.rs:46]
│       ├── set_core_file_size_limit_to_zero()   [src/lib.rs:56]
│       │   └── libc::setrlimit(RLIMIT_CORE, 0)  [src/lib.rs:115]
│       └── env_keys_with_prefix(b"LD_")         [src/lib.rs:60]
│           └── std::env::remove_var()           [src/lib.rs:64]
├── macOS
│   └── pre_main_hardening_macos()
│       ├── libc::ptrace(PT_DENY_ATTACH)         [src/lib.rs:85]
│       ├── set_core_file_size_limit_to_zero()   [src/lib.rs:95]
│       └── env_keys_with_prefix(b"DYLD_")       [src/lib.rs:99]
├── BSD
│   └── pre_main_hardening_bsd()
│       ├── set_core_file_size_limit_to_zero()   [src/lib.rs:72]
│       └── env_keys_with_prefix(b"LD_")         [src/lib.rs:74]
└── Windows
    └── pre_main_hardening_windows()             [src/lib.rs:126]
        └── TODO
```

### 4.3 外部调用点

| 调用方 | 文件 | 调用方式 |
|--------|------|----------|
| responses-api-proxy | `codex-rs/responses-api-proxy/src/main.rs:6` | `#[ctor::ctor]` 自动调用 |

---

## 5. 依赖与外部交互

### 5.1 依赖分析

```toml
[dependencies]
libc = { workspace = true }
```

**唯一生产依赖**：`libc` crate，用于调用底层系统调用。

### 5.2 系统调用清单

| 系统调用/函数 | 平台 | 用途 |
|--------------|------|------|
| `prctl(PR_SET_DUMPABLE, 0)` | Linux/Android | 禁用 ptrace 和 core dump |
| `ptrace(PT_DENY_ATTACH, ...)` | macOS | 拒绝调试器附加 |
| `setrlimit(RLIMIT_CORE, ...)` | Unix-like | 设置 core file size limit |
| `std::env::remove_var()` | 跨平台 | 清除环境变量 |

### 5.3 与 Linux Sandbox 的关系

在 `codex-rs/linux-sandbox/src/landlock.rs` 中也有对 `ptrace` 的防护：

```rust
deny_syscall(&mut rules, libc::SYS_ptrace);
```

这说明：
- `process-hardening` 是**进程自身**的加固
- `linux-sandbox` 是**子进程**的加固（通过 seccomp/landlock）
- 两者形成**纵深防御**体系

---

## 6. 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 Windows 平台未实现

```rust
#[cfg(windows)]
pub(crate) fn pre_main_hardening_windows() {
    // TODO(mbolin): Perform the appropriate configuration for Windows.
}
```

**风险**：Windows 平台完全缺乏加固措施。

#### 6.1.2 BSD 平台 ptrace 防护缺失

FreeBSD/OpenBSD 目前只实现了 core dump 禁用和环境变量清除，缺少 ptrace 防护。

#### 6.1.3 无法防御特权攻击

- `prctl(PR_SET_DUMPABLE, 0)` 可以被具有 `CAP_SYS_PTRACE` 能力的进程绕过
- root 用户仍然可以 attach 调试器

#### 6.1.4 环境变量清除时机

环境变量清除发生在运行时，如果攻击者在程序启动前就已经注入恶意库，清除操作无法撤销已经发生的攻击。

### 6.2 改进建议

#### 6.2.1 Windows 平台实现

建议实现以下措施：
- 使用 `SetProcessMitigationPolicy` 启用 `ProcessDisableNonSystemFontsMitigation` 等策略
- 使用 `DebugActiveProcessStop` 或相关机制阻止调试器附加
- 清除 `PATH` 环境变量中的可疑路径

#### 6.2.2 增强 BSD 支持

FreeBSD 支持 `PT_DENY_ATTACH`（与 macOS 类似），可以添加：

```rust
#[cfg(any(target_os = "freebsd", target_os = "openbsd"))]
pub(crate) fn pre_main_hardening_bsd() {
    // 添加 ptrace 防护
    #[cfg(target_os = "freebsd")]
    {
        let ret_code = unsafe { libc::ptrace(libc::PT_DENY_ATTACH, 0, std::ptr::null_mut(), 0) };
        if ret_code == -1 {
            eprintln!("ERROR: ptrace(PT_DENY_ATTACH) failed: {}", ...);
            std::process::exit(PTRACE_DENY_ATTACH_FAILED_EXIT_CODE);
        }
    }
    // ...
}
```

#### 6.2.3 增加加固状态报告

建议添加一个函数返回当前加固状态，便于日志记录和调试：

```rust
pub struct HardeningStatus {
    pub ptrace_disabled: bool,
    pub core_dump_disabled: bool,
    pub ld_vars_cleared: Vec<String>,
    pub dyld_vars_cleared: Vec<String>,
}

pub fn get_hardening_status() -> HardeningStatus { ... }
```

#### 6.2.4 增加集成测试

当前只有单元测试（`env_keys_with_prefix` 的测试），建议添加：
- 安全属性测试（验证 ptrace 确实被禁用）
- 跨平台 CI 测试

#### 6.2.5 考虑添加 seccomp 支持

对于 Linux，可以考虑使用 `seccomp` 进行更细粒度的系统调用过滤，作为 `prctl` 的补充。

### 6.3 安全审计建议

1. **定期审查** `libc` crate 的版本更新，确保系统调用封装没有安全漏洞
2. **监控** 新的内核安全特性（如 Linux 的 `PR_SET_NO_NEW_PRIVS`），评估是否值得添加
3. **评估** 是否需要添加内存加密（如使用 `mlock` 保护敏感数据），这在 `responses-api-proxy` 中已有部分实现

---

## 7. 总结

`codex-process-hardening` 是一个**简洁但关键**的安全组件，通过约 190 行代码实现了跨平台的进程加固。其核心设计原则包括：

1. **Fail-secure**：任何加固失败都立即终止进程
2. **Defense in depth**：多层防护（如同时禁用 ptrace 和 core dump）
3. **零侵入**：通过 `ctor` 实现 pre-main 自动执行
4. **跨平台**：使用条件编译支持多平台

主要改进空间在于 Windows 平台的完整实现和 BSD 平台的 ptrace 防护增强。
