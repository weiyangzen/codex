# codex-rs/process-hardening/src 深度研究文档

## 1. 场景与职责

### 1.1 定位

`codex-rs/process-hardening/src` 目录包含 `codex-process-hardening` crate 的单一源文件实现 `lib.rs`。这是一个专门用于进程级安全加固的底层系统组件，设计目标是在 Rust 程序进入 `main()` 函数之前执行关键的安全强化措施。

该目录的核心设计哲学是：**最小攻击面、最大平台覆盖、零运行时依赖**（除 `libc` 外）。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **Pre-Main 安全初始化** | 通过 `#[ctor::ctor]` 机制在程序启动早期执行加固 |
| **反调试保护** | 阻止调试器通过 `ptrace` 附加到进程 |
| **内存转储防护** | 禁用 core dump 防止敏感数据泄露到磁盘 |
| **动态链接器防护** | 清理 `LD_*` / `DYLD_*` 环境变量防止库注入 |
| **跨平台抽象** | 统一接口封装 Linux、macOS、BSD 和 Windows 的差异 |

### 1.3 使用场景

当前主要服务于 `codex-responses-api-proxy` 服务，该服务作为 OpenAI API 的本地安全代理，需要在内存中安全地保存 API 密钥：

```rust
// codex-rs/responses-api-proxy/src/main.rs
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
}
```

通过构造函数属性宏确保加固代码在 `main()` 之前执行，这是安全关键代码的典型模式。

---

## 2. 功能点目的

### 2.1 功能矩阵（平台对比）

| 功能 | Linux/Android | macOS | FreeBSD/OpenBSD | Windows | 安全目标 |
|------|---------------|-------|-----------------|---------|----------|
| **ptrace 禁用** | ✅ `prctl(PR_SET_DUMPABLE, 0)` | ✅ `ptrace(PT_DENY_ATTACH)` | ❌ 未实现 | ❌ TODO | 防止调试器附加、内存读取 |
| **Core dump 禁用** | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | ❌ TODO | 防止崩溃时内存泄露 |
| **LD_* 清理** | ✅ 移除所有 `LD_` 前缀变量 | ❌ N/A | ✅ 移除所有 `LD_` 前缀变量 | N/A | 防止动态链接器劫持 |
| **DYLD_* 清理** | ❌ N/A | ✅ 移除所有 `DYLD_` 前缀变量 | ❌ N/A | N/A | 防止 macOS 动态链接器劫持 |

### 2.2 各功能详细说明

#### 2.2.1 Linux/Android ptrace 防护

**实现**：`prctl(PR_SET_DUMPABLE, 0, 0, 0, 0)`

**安全机制**：
- 设置进程的 `dumpable` 标志为 0
- 阻止非特权进程通过 `/proc/<pid>/mem` 读取进程内存
- 阻止 `ptrace` 附加（除非父进程或具有 `CAP_SYS_PTRACE` 能力）
- 防止 `gdb`、`strace` 等调试工具附加

**失败处理**：打印错误到 stderr，以退出码 5 终止进程

#### 2.2.2 macOS ptrace 防护

**实现**：`ptrace(PT_DENY_ATTACH, 0, std::ptr::null_mut(), 0)`

**安全机制**：
- macOS 特有的反调试机制
- 阻止任何调试器（包括 Xcode、lldb）附加
- 尝试附加的调试器会收到 `EPERM` (Operation not permitted) 错误
- 这是 macOS 平台标准的反调试技术

**失败处理**：打印错误到 stderr，以退出码 6 终止进程

#### 2.2.3 Core Dump 禁用（全 Unix 平台）

**实现**：`setrlimit(RLIMIT_CORE, &rlim)` 其中 `rlim_cur = rlim_max = 0`

**安全机制**：
- 将核心文件大小软限制和硬限制都设为 0
- 即使进程崩溃（如段错误），也不会生成 core dump 文件
- 防止内存中的敏感数据（如 API 密钥、用户凭证）泄露到磁盘
- 符合安全审计和合规要求

**失败处理**：打印错误到 stderr，以退出码 7 终止进程

#### 2.2.4 环境变量清理

**Linux/FreeBSD/OpenBSD**：
- 扫描并移除所有以 `LD_` 开头的环境变量
- 包括 `LD_PRELOAD`（预加载恶意共享库）
- `LD_LIBRARY_PATH`（劫持库搜索路径）
- `LD_AUDIT`（共享库审计劫持）等

**macOS**：
- 扫描并移除所有以 `DYLD_` 开头的环境变量
- 包括 `DYLD_INSERT_LIBRARIES`（macOS 版 LD_PRELOAD）
- `DYLD_LIBRARY_PATH`、`DYLD_FRAMEWORK_PATH` 等

**实现细节**：
- 使用 `OsString` 字节级处理，支持非 UTF-8 环境变量
- 使用 `unsafe { std::env::remove_var() }` 移除变量
- 官方 Codex 发布版本使用 MUSL 静态链接，LD_PRELOAD 本就无效，但清理提供额外防御层（防御纵深）

---

## 3. 具体技术实现

### 3.1 关键流程

```
pre_main_hardening()  [入口函数，src/lib.rs:12-25]
│
├── 平台检测（编译期条件编译）
│   ├── #[cfg(any(target_os = "linux", target_os = "android"))]
│   │   └── pre_main_hardening_linux()
│   ├── #[cfg(target_os = "macos")]
│   │   └── pre_main_hardening_macos()
│   ├── #[cfg(any(target_os = "freebsd", target_os = "openbsd"))]
│   │   └── pre_main_hardening_bsd()
│   └── #[cfg(windows)]
│       └── pre_main_hardening_windows() [TODO]
│
├── Linux/Android 流程 [src/lib.rs:44-67]:
│   ├── prctl(PR_SET_DUMPABLE, 0)      // 禁用进程转储
│   ├── setrlimit(RLIMIT_CORE, 0)      // 禁用 core dump
│   └── 遍历清理所有 LD_* 环境变量
│
├── macOS 流程 [src/lib.rs:82-106]:
│   ├── ptrace(PT_DENY_ATTACH)         // 拒绝调试器附加
│   ├── setrlimit(RLIMIT_CORE, 0)      // 禁用 core dump
│   └── 遍历清理所有 DYLD_* 环境变量
│
└── BSD 流程 [src/lib.rs:69-80]:
    ├── setrlimit(RLIMIT_CORE, 0)      // 禁用 core dump
    └── 遍历清理所有 LD_* 环境变量
```

### 3.2 数据结构

#### 3.2.1 退出码常量定义

```rust
// src/lib.rs:28-41

#[cfg(any(target_os = "linux", target_os = "android"))]
const PRCTL_FAILED_EXIT_CODE: i32 = 5;           // prctl 失败

#[cfg(target_os = "macos")]
const PTRACE_DENY_ATTACH_FAILED_EXIT_CODE: i32 = 6;  // ptrace 失败

#[cfg(any(
    target_os = "linux",
    target_os = "android",
    target_os = "macos",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
const SET_RLIMIT_CORE_FAILED_EXIT_CODE: i32 = 7;     // setrlimit 失败
```

退出码设计遵循 "fail secure" 原则：任何加固失败都导致进程立即终止，避免在不安全状态下继续运行。

#### 3.2.2 环境变量处理数据结构

使用 `OsString` 而非 `String` 处理环境变量：
- `OsString` 可以包含任意字节序列，不限于有效的 UTF-8
- 避免在处理非 UTF-8 环境变量名/值时 panic
- 符合 Unix 环境变量的实际语义（字节序列而非字符串）

### 3.3 关键系统调用与 API

| 系统调用/API | 平台 | 功能 | 失败处理 | 代码位置 |
|-------------|------|------|---------|----------|
| `libc::prctl(PR_SET_DUMPABLE, 0, 0, 0, 0)` | Linux/Android | 禁用进程转储 | eprintln + exit(5) | src/lib.rs:46-52 |
| `libc::ptrace(PT_DENY_ATTACH, 0, ptr::null_mut(), 0)` | macOS | 拒绝调试器附加 | eprintln + exit(6) | src/lib.rs:85-91 |
| `libc::setrlimit(RLIMIT_CORE, &rlim)` | Unix | 设置 core 限制为 0 | eprintln + exit(7) | src/lib.rs:115-121 |
| `std::env::vars_os()` | 跨平台 | 获取所有环境变量 | - | src/lib.rs:60,74,99 |
| `std::env::remove_var()` | 跨平台 | 移除环境变量 | - | src/lib.rs:63-66 等 |

### 3.4 环境变量清理算法实现

```rust
// src/lib.rs:131-143

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

**算法特点**：
1. **字节级前缀匹配**：使用 `as_bytes()` 直接比较字节序列，避免 UTF-8 解码开销和潜在 panic
2. **惰性求值**：使用 `filter_map` 和 `then_some` 组合，只收集匹配的键
3. **前缀匹配**：匹配所有以指定前缀开头的变量，而非精确匹配
4. **OsString 返回**：保留原始字节序列，确保后续 `remove_var` 调用正确

**使用示例**：
```rust
// Linux: 清理所有 LD_* 变量
let ld_keys = env_keys_with_prefix(std::env::vars_os(), b"LD_");
for key in ld_keys {
    unsafe { std::env::remove_var(key); }
}

// macOS: 清理所有 DYLD_* 变量
let dyld_keys = env_keys_with_prefix(std::env::vars_os(), b"DYLD_");
for key in dyld_keys {
    unsafe { std::env::remove_var(key); }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/process-hardening/
├── Cargo.toml          # 包配置，依赖 libc
├── BUILD.bazel         # Bazel 构建配置（使用 codex_rust_crate 宏）
├── README.md           # 简要功能说明
└── src/
    └── lib.rs          # 全部实现（190 行，含测试）
```

### 4.2 核心代码路径详解

| 文件 | 行号范围 | 功能描述 |
|------|----------|----------|
| `src/lib.rs` | 1-6 | 平台条件导入：`OsString`、`OsStrExt` |
| `src/lib.rs` | 7-25 | `pre_main_hardening()` - 公开 API 入口，平台分发 |
| `src/lib.rs` | 27-41 | 退出码常量定义（条件编译） |
| `src/lib.rs` | 44-67 | `pre_main_hardening_linux()` - Linux/Android 加固 |
| `src/lib.rs` | 69-80 | `pre_main_hardening_bsd()` - FreeBSD/OpenBSD 加固 |
| `src/lib.rs` | 82-106 | `pre_main_hardening_macos()` - macOS 加固 |
| `src/lib.rs` | 108-123 | `set_core_file_size_limit_to_zero()` - Unix 通用 core dump 禁用 |
| `src/lib.rs` | 125-128 | `pre_main_hardening_windows()` - Windows 占位（TODO） |
| `src/lib.rs` | 130-143 | `env_keys_with_prefix()` - 环境变量扫描工具函数 |
| `src/lib.rs` | 145-190 | 单元测试模块（`#[cfg(all(test, unix))]`） |

### 4.3 公开 API

```rust
/// 入口函数：执行所有平台相关的进程加固措施
/// 
/// 设计为在 pre-main 阶段调用（通过 #[ctor::ctor]）
/// 失败时会打印错误信息并调用 std::process::exit() 终止进程
pub fn pre_main_hardening()
```

**使用契约**：
- 必须在单线程环境下调用（pre-main 阶段满足此条件）
- 调用后进程将被加固，调试器无法附加，core dump 被禁用
- 失败时进程立即终止，不会返回错误

### 4.4 调用方引用

**主调用方**：`codex-responses-api-proxy`

```rust
// codex-rs/responses-api-proxy/src/main.rs:4-7
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
}
```

**依赖链**：
- `codex-rs/responses-api-proxy/Cargo.toml:21`: `codex-process-hardening = { workspace = true }`
- `codex-rs/Cargo.toml:40`: workspace member `"process-hardening"`
- `codex-rs/Cargo.toml:124`: workspace dependency `codex-process-hardening = { path = "process-hardening" }`

---

## 5. 依赖与外部交互

### 5.1 依赖关系图

```
codex-process-hardening
├── libc = "0.2.182" (workspace dependency)
│   ├── prctl (Linux)
│   ├── ptrace (macOS)
│   ├── setrlimit (Unix)
│   └── RLIMIT_CORE, PR_SET_DUMPABLE, PT_DENY_ATTACH 等常量
└── pretty_assertions (dev-dependency, tests only)
```

### 5.2 外部系统交互

| 交互对象 | 交互方式 | 说明 | 安全影响 |
|---------|---------|------|----------|
| Linux Kernel | `prctl` 系统调用 | 进程控制操作 | 修改进程 dumpable 标志 |
| Unix Kernel | `setrlimit` 系统调用 | 资源限制设置 | 修改进程资源限制 |
| macOS Kernel | `ptrace` 系统调用 | 进程跟踪控制 | 设置反调试标志 |
| 进程环境 | `std::env::vars_os()` / `remove_var()` | 环境变量读写 | 修改进程环境 |

### 5.3 条件编译配置矩阵

```rust
// 模块级条件编译
#[cfg(unix)]           // Unix 通用代码（Linux, macOS, BSD）
#[cfg(windows)]        // Windows 代码

// 平台特定代码
#[cfg(any(target_os = "linux", target_os = "android"))]
#[cfg(target_os = "macos")]
#[cfg(any(target_os = "freebsd", target_os = "openbsd"))]

// 测试条件编译
#[cfg(all(test, unix))]  // 仅 Unix 平台测试
```

### 5.4 与 `ctor` crate 的集成

`ctor` crate 提供了 `#[ctor::ctor]` 属性宏，允许定义在 `main()` 之前执行的构造函数：

```rust
// codex-rs/Cargo.toml:183
ctor = "0.6.3"

// 使用示例（responses-api-proxy/src/main.rs）
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
}
```

**工作原理**：
- `ctor` 利用平台特定的机制（如 Linux 的 `.init_array` 段、macOS 的 `__mod_init_func` 段）
- 在运行时库初始化阶段执行标记的函数
- 确保在 `main()` 之前完成所有加固

---

## 6. 风险、边界与改进建议

### 6.1 当前风险分析

#### 6.1.1 Windows 支持缺失

**风险等级**：中

```rust
// src/lib.rs:125-128
#[cfg(windows)]
pub(crate) fn pre_main_hardening_windows() {
    // TODO(mbolin): Perform the appropriate configuration for Windows.
}
```

**影响**：Windows 平台无法获得同等安全保护，存在以下攻击面：
- 调试器附加（如 WinDbg、Visual Studio）
- 内存转储（WER、用户模式转储）
- DLL 注入（通过 `SetWindowsHookEx`、`CreateRemoteThread` 等）

**建议实现**：
```rust
// Windows 加固建议
#[cfg(windows)]
pub(crate) fn pre_main_hardening_windows() {
    // 1. 禁用 Windows Error Reporting (WER) 转储
    // SetErrorMode(SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)
    
    // 2. 启用数据执行保护 (DEP)
    // SetProcessDEPPolicy(PROCESS_DEP_ENABLE)
    
    // 3. 禁用调试权限
    // AdjustTokenPrivileges 移除 SeDebugPrivilege
    
    // 4. 清理环境变量
    // 移除可能影响 DLL 加载的变量（如 `PATH` 中的可疑路径）
}
```

#### 6.1.2 不安全代码使用

**风险等级**：低

```rust
// src/lib.rs:63-66, 76-78, 102-104
unsafe {
    std::env::remove_var(key);
}
```

**风险说明**：
- Rust 标准库将 `remove_var` 标记为 `unsafe`，因为多线程环境下修改环境变量可能导致未定义行为
- 当前使用场景（pre-main 单线程）相对安全
- 依赖调用时机（必须在任何其他线程启动前执行）

**缓解措施**：
- 文档明确说明必须在 pre-main 阶段调用
- 使用 `#[ctor::ctor]` 确保在运行时库初始化阶段执行

#### 6.1.3 退出码硬编码

**风险等级**：低

失败时直接调用 `std::process::exit()` 终止进程，使用特定退出码（5, 6, 7）。这可能与调用方的退出码约定冲突。

**当前退出码定义**：
| 退出码 | 场景 | 说明 |
|--------|------|------|
| 5 | `prctl(PR_SET_DUMPABLE, 0)` 失败 | Linux/Android |
| 6 | `ptrace(PT_DENY_ATTACH)` 失败 | macOS |
| 7 | `setrlimit(RLIMIT_CORE, 0)` 失败 | Unix 通用 |

### 6.2 边界条件分析

| 边界条件 | 当前行为 | 评估 |
|---------|---------|------|
| 非 UTF-8 环境变量 | ✅ 正确处理（使用 OsString 字节级操作） | 良好 |
| 无权限调用 prctl/ptrace | ✅ 打印错误并 exit(5/6) | 安全优先，符合 fail-secure 原则 |
| 环境变量不存在 | ✅ 正常遍历，无匹配则跳过 | 安全 |
| 重复调用加固 | ✅ 幂等（多次调用无害） | 安全 |
| 沙箱/容器环境 | ⚠️ 可能因权限失败 | 需测试验证 |
| 静态链接 (MUSL) | ✅ LD_PRELOAD 本就无效，清理提供纵深防御 | 良好 |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **实现 Windows 支持**
   - 启用 DEP（数据执行保护）
   - 禁用 WER（Windows Error Reporting）转储
   - 移除调试权限
   - 清理环境变量

2. **添加日志/追踪支持**
   当前仅打印到 stderr，建议集成 `tracing` crate：
   ```rust
   // 建议添加（可选特性）
   #[cfg(feature = "tracing")]
   tracing::info!("Process hardening applied successfully");
   ```

3. **提供非终止失败选项**
   某些场景（如开发环境、容器）可能希望加固失败时继续运行：
   ```rust
   pub struct HardeningOptions {
       pub fail_on_error: bool,  // 默认 true
       pub log_level: LogLevel,
   }
   
   pub fn pre_main_hardening_opts(opts: HardeningOptions) -> Result<(), HardeningError> {
       // 返回 Result 而非直接 exit
   }
   ```

#### 6.3.2 中优先级

4. **增加加固状态查询**
   ```rust
   pub struct HardeningStatus {
       pub ptrace_disabled: bool,
       pub core_dump_disabled: bool,
       pub env_vars_cleaned: Vec<String>,
   }
   
   pub fn verify_hardening() -> HardeningStatus {
       // 查询当前进程状态
   }
   ```

5. **支持更多加固选项**
   - 内存锁定（`mlockall`）选项，防止敏感数据换出到磁盘
   - seccomp-bpf 过滤器安装（Linux），限制可用系统调用
   - 文件描述符清理（关闭非标准 FD，防止 FD 泄露）
   - ASLR 熵值检查

6. **添加 BSD ptrace 支持**
   FreeBSD/OpenBSD 支持 `PT_DENY_ATTACH` 或类似的反调试机制，可以扩展实现。

#### 6.3.3 低优先级

7. **文档完善**
   - 添加架构图
   - 详细说明各平台差异
   - 安全审计报告引用
   - 威胁模型文档

8. **测试覆盖增强**
   当前仅测试 `env_keys_with_prefix`，建议增加：
   - 集成测试（验证系统调用行为）
   - 平台特定测试（在 CI 中运行）
   - 安全属性测试（如验证 ptrace 确实被禁用）
   - 模糊测试（非 UTF-8 环境变量处理）

### 6.4 安全审计建议

1. **定期审查 libc 绑定安全性**
   - 验证 `libc` crate 的 FFI 绑定正确性
   - 跟进 `libc` 版本更新

2. **验证各平台系统调用行为**
   - 测试 `prctl(PR_SET_DUMPABLE, 0)` 确实阻止 ptrace
   - 测试 `setrlimit(RLIMIT_CORE, 0)` 确实阻止 core dump
   - 测试 `ptrace(PT_DENY_ATTACH)` 确实阻止调试器附加

3. **评估新出现的绕过技术**
   - Linux 的 `PTRACE_SEIZE` / `PTRACE_ATTACH` 差异
   - 容器/命名空间环境下的行为差异
   - eBPF 等新技术对安全模型的影响

4. **考虑补充沙箱机制**
   - Landlock（Linux）用于文件系统沙箱
   - SELinux/AppArmor 策略
   - seccomp-bpf 系统调用过滤

---

## 7. 附录

### 7.1 测试代码分析

```rust
// src/lib.rs:145-190
#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::ffi::OsStr;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::ffi::OsStringExt;

    #[test]
    fn env_keys_with_prefix_handles_non_utf8_entries() {
        // 测试非 UTF-8 环境变量处理
        // RÖDBURK (包含 ISO-8859-1 编码的 Ö)
        let non_utf8_key1 = OsStr::from_bytes(b"R\xD6DBURK").to_os_string();
        let non_utf8_key2 = OsString::from_vec(vec![b'L', b'D', b'_', 0xF0]);
        let non_utf8_value = OsString::from_vec(vec![0xF0, 0x9F, 0x92, 0xA9]);

        let keys = env_keys_with_prefix(
            vec![
                (non_utf8_key1, non_utf8_value.clone()),
                (non_utf8_key2.clone(), non_utf8_value),
            ],
            b"LD_",
        );
        assert_eq!(
            keys,
            vec![non_utf8_key2],
            "non-UTF-8 env entries with LD_ prefix should be retained"
        );
    }

    #[test]
    fn env_keys_with_prefix_filters_only_matching_keys() {
        // 测试前缀匹配过滤
        let ld_test_var = OsStr::from_bytes(b"LD_TEST");
        let vars = vec![
            (OsString::from("PATH"), OsString::from("/usr/bin")),
            (ld_test_var.to_os_string(), OsString::from("1")),
            (OsString::from("DYLD_FOO"), OsString::from("bar")),
        ];

        let keys = env_keys_with_prefix(vars, b"LD_");
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0].as_os_str(), ld_test_var);
    }
}
```

**测试覆盖分析**：
- ✅ 非 UTF-8 环境变量处理
- ✅ 前缀匹配逻辑
- ❌ 未测试系统调用行为（需要特权，难以在单元测试中覆盖）
- ❌ 未测试平台特定代码路径

### 7.2 相关文档引用

| 文档 | 路径 | 内容 |
|------|------|------|
| README | `codex-rs/process-hardening/README.md` | 简要功能说明 |
| 使用场景 | `codex-rs/responses-api-proxy/README.md:66-80` | 安全代理使用说明 |
| 项目规范 | `AGENTS.md` | 项目级开发规范 |
| 父目录研究 | `Docs/researches/codex-rs/process-hardening/current_folder_research.md` | 父目录研究文档 |

### 7.3 测试执行命令

```bash
# 运行单元测试
cd codex-rs && cargo test -p codex-process-hardening

# 运行并查看输出
cd codex-rs && cargo test -p codex-process-hardening -- --nocapture
```

### 7.4 代码统计

```
Language: Rust
File: codex-rs/process-hardening/src/lib.rs
Lines: 190
Code: ~120 lines (excluding comments and tests)
Tests: ~45 lines (2 test functions)
```

---

*文档生成时间：2026-03-22*  
*研究范围：codex-rs/process-hardening/src 目录*  
*模型：k2p5*
