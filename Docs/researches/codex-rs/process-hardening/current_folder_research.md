# codex-rs/process-hardening 深度研究文档

## 1. 场景与职责

### 1.1 定位

`codex-process-hardening` 是一个 Rust 安全加固 crate，专注于在进程启动早期（pre-main）执行一系列进程级安全强化措施。它是 Codex 项目安全架构的基础组件，用于保护敏感服务（如 `responses-api-proxy`）免受进程注入、内存转储和动态链接器劫持等攻击。

### 1.2 核心职责

- **进程防调试**：阻止调试器通过 ptrace 附加到进程
- **核心转储禁用**：防止敏感数据通过 core dump 泄露到磁盘
- **环境变量清理**：移除可能被利用的动态链接器环境变量（LD_PRELOAD, DYLD_* 等）
- **跨平台支持**：覆盖 Linux、Android、macOS、FreeBSD、OpenBSD 和 Windows

### 1.3 使用场景

当前主要被 `codex-responses-api-proxy` 使用，该服务作为 OpenAI API 的本地代理，需要保护内存中的 API 密钥不被提取：

```rust
// responses-api-proxy/src/main.rs
#[ctor::ctor]
fn pre_main() {
    codex_process_hardening::pre_main_hardening();
}
```

通过 `#[ctor::ctor]` 属性，确保在 `main()` 函数执行前完成所有加固措施。

---

## 2. 功能点目的

### 2.1 功能矩阵

| 功能 | Linux/Android | macOS | FreeBSD/OpenBSD | Windows | 目的 |
|------|---------------|-------|-----------------|---------|------|
| ptrace 禁用 | ✅ `prctl(PR_SET_DUMPABLE, 0)` | ✅ `ptrace(PT_DENY_ATTACH)` | ❌ | TODO | 防止调试器附加 |
| Core dump 禁用 | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | ✅ `setrlimit(RLIMIT_CORE, 0)` | TODO | 防止内存转储泄露 |
| LD_* 清理 | ✅ 移除所有 `LD_` 前缀变量 | ❌ | ✅ 移除所有 `LD_` 前缀变量 | N/A | 防止动态链接器劫持 |
| DYLD_* 清理 | ❌ | ✅ 移除所有 `DYLD_` 前缀变量 | ❌ | N/A | 防止 macOS 动态链接器劫持 |

### 2.2 各功能详细说明

#### 2.2.1 ptrace 防护（Linux/Android）

使用 Linux 特有的 `prctl(PR_SET_DUMPABLE, 0)` 系统调用：
- 标记进程为不可转储（non-dumpable）
- 自动阻止非特权进程通过 `/proc/<pid>/mem` 访问进程内存
- 阻止 `ptrace` 附加（除非父进程或具有 `CAP_SYS_PTRACE`）

#### 2.2.2 ptrace 防护（macOS）

使用 `ptrace(PT_DENY_ATTACH, 0, NULL, 0)`：
- macOS 特有的反调试机制
- 阻止任何调试器（包括 Xcode、lldb）附加
- 尝试附加的调试器会收到 `EPERM` 错误

#### 2.2.3 Core Dump 禁用（全 Unix 平台）

使用 `setrlimit(RLIMIT_CORE, 0)`：
- 将核心文件大小限制设为 0
- 即使进程崩溃，也不会生成 core dump 文件
- 防止内存中的敏感数据（如 API 密钥）泄露到磁盘

#### 2.2.4 环境变量清理

**Linux/FreeBSD/OpenBSD**：
- 扫描并移除所有以 `LD_` 开头的环境变量
- 包括 `LD_PRELOAD`（预加载恶意共享库）、`LD_LIBRARY_PATH`（劫持库搜索路径）等

**macOS**：
- 扫描并移除所有以 `DYLD_` 开头的环境变量
- 包括 `DYLD_INSERT_LIBRARIES`（macOS 版 LD_PRELOAD）、`DYLD_LIBRARY_PATH` 等

**注意**：官方 Codex 发布版本使用 MUSL 静态链接，LD_PRELOAD 本就无效，但清理提供额外防御层。

---

## 3. 具体技术实现

### 3.1 关键流程

```
pre_main_hardening()
├── 平台检测（编译期条件编译）
│   ├── Linux/Android → pre_main_hardening_linux()
│   ├── macOS → pre_main_hardening_macos()
│   ├── FreeBSD/OpenBSD → pre_main_hardening_bsd()
│   └── Windows → pre_main_hardening_windows() (TODO)
│
├── Linux/Android 流程:
│   ├── prctl(PR_SET_DUMPABLE, 0)
│   ├── setrlimit(RLIMIT_CORE, 0)
│   └── 清理 LD_* 环境变量
│
├── macOS 流程:
│   ├── ptrace(PT_DENY_ATTACH)
│   ├── setrlimit(RLIMIT_CORE, 0)
│   └── 清理 DYLD_* 环境变量
│
└── BSD 流程:
    ├── setrlimit(RLIMIT_CORE, 0)
    └── 清理 LD_* 环境变量
```

### 3.2 数据结构

#### 3.2.1 退出码常量

```rust
// Linux/Android
const PRCTL_FAILED_EXIT_CODE: i32 = 5;           // prctl 失败

// macOS
const PTRACE_DENY_ATTACH_FAILED_EXIT_CODE: i32 = 6;  // ptrace 失败

// 全 Unix 平台
const SET_RLIMIT_CORE_FAILED_EXIT_CODE: i32 = 7;     // setrlimit 失败
```

#### 3.2.2 环境变量处理

使用 `OsString` 而非 `String` 处理环境变量：
- 支持非 UTF-8 编码的环境变量名/值
- 避免 panic 在处理二进制数据时

### 3.3 关键系统调用

| 系统调用 | 平台 | 功能 | 失败处理 |
|---------|------|------|---------|
| `prctl(PR_SET_DUMPABLE, 0)` | Linux/Android | 禁用进程转储 | 打印错误，exit(5) |
| `ptrace(PT_DENY_ATTACH)` | macOS | 拒绝调试器附加 | 打印错误，exit(6) |
| `setrlimit(RLIMIT_CORE, &rlim)` | Unix | 设置 core 文件限制为 0 | 打印错误，exit(7) |

### 3.4 环境变量清理算法

```rust
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

特点：
- 使用字节级前缀匹配，避免 UTF-8 解码
- 返回匹配的键列表，供后续 `std::env::remove_var()` 使用
- 使用 `unsafe` 调用 `remove_var()`（Rust 文档标记为 unsafe，因为可能导致多线程问题）

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

### 4.2 核心代码路径

| 文件 | 行号 | 功能 |
|------|------|------|
| `src/lib.rs` | 12-25 | `pre_main_hardening()` - 入口函数，平台分发 |
| `src/lib.rs` | 44-67 | `pre_main_hardening_linux()` - Linux 加固 |
| `src/lib.rs` | 69-80 | `pre_main_hardening_bsd()` - BSD 加固 |
| `src/lib.rs` | 82-106 | `pre_main_hardening_macos()` - macOS 加固 |
| `src/lib.rs` | 108-123 | `set_core_file_size_limit_to_zero()` - 通用 core dump 禁用 |
| `src/lib.rs` | 125-128 | `pre_main_hardening_windows()` - Windows 占位 |
| `src/lib.rs` | 130-143 | `env_keys_with_prefix()` - 环境变量扫描 |

### 4.3 调用方引用

**主调用方**：`codex-responses-api-proxy`
- 文件：`codex-rs/responses-api-proxy/src/main.rs` (第 4-7 行)
- 使用 `#[ctor::ctor]` 确保 pre-main 执行

**依赖声明**：
- `codex-rs/responses-api-proxy/Cargo.toml` 第 21 行：`codex-process-hardening = { workspace = true }`
- `codex-rs/Cargo.toml` 第 40 行：workspace member
- `codex-rs/Cargo.toml` 第 124 行：workspace dependency

---

## 5. 依赖与外部交互

### 5.1 依赖关系

```
codex-process-hardening
├── libc (workspace dependency)
└── pretty_assertions (dev-dependency, tests only)
```

### 5.2 外部系统交互

| 交互对象 | 交互方式 | 说明 |
|---------|---------|------|
| Linux Kernel | `prctl` 系统调用 | 进程控制操作 |
| Unix Kernel | `setrlimit` 系统调用 | 资源限制设置 |
| macOS Kernel | `ptrace` 系统调用 | 进程跟踪控制 |
| 进程环境 | `std::env::vars_os()` / `remove_var()` | 环境变量读写 |

### 5.3 条件编译配置

```rust
#[cfg(unix)]           // Unix 通用代码
#[cfg(windows)]        // Windows 代码
#[cfg(target_os = "linux")]      // Linux 特有
#[cfg(target_os = "android")]    // Android 特有
#[cfg(target_os = "macos")]      // macOS 特有
#[cfg(target_os = "freebsd")]    // FreeBSD 特有
#[cfg(target_os = "openbsd")]    // OpenBSD 特有
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 Windows 支持缺失

**风险等级**：中

当前 `pre_main_hardening_windows()` 为空实现（TODO）：
```rust
#[cfg(windows)]
pub(crate) fn pre_main_hardening_windows() {
    // TODO(mbolin): Perform the appropriate configuration for Windows.
}
```

影响：Windows 平台无法获得同等安全保护。

#### 6.1.2 不安全代码使用

**风险等级**：低

使用 `unsafe` 调用 `std::env::remove_var()`：
- Rust 标准库将此函数标记为 unsafe，因为多线程环境下修改环境变量可能导致未定义行为
- 当前使用场景（pre-main 单线程）相对安全，但依赖调用时机

#### 6.1.3 退出码硬编码

**风险等级**：低

失败时直接调用 `std::process::exit()` 终止进程，使用特定退出码（5, 6, 7）。这可能与调用方的退出码约定冲突。

### 6.2 边界条件

| 边界条件 | 当前行为 | 评估 |
|---------|---------|------|
| 非 UTF-8 环境变量 | 正确处理（使用 OsString） | ✅ 良好 |
| 无权限调用 prctl/ptrace | 打印错误并 exit(5/6) | ✅ 安全优先 |
| 环境变量不存在 | 正常遍历，无匹配则跳过 | ✅ 安全 |
| 重复调用加固 | 幂等（多次调用无害） | ✅ 安全 |
| 沙箱/容器环境 | 可能因权限失败 | ⚠️ 需测试 |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **实现 Windows 支持**
   ```rust
   // 建议实现：
   // - SetProcessDEPPolicy() / SetDllCharacteristics() - 启用 DEP
   // - SetErrorMode(SEM_NOGPFAULTERRORBOX) - 禁用错误弹窗
   // - 清理可能影响 DLL 加载的环境变量
   ```

2. **添加日志/追踪支持**
   当前仅打印到 stderr，建议集成 `tracing` 以便与上层应用日志系统统一。

3. **提供非终止失败选项**
   某些场景（如开发环境、容器）可能希望加固失败时继续运行而非退出：
   ```rust
   pub fn pre_main_hardening_opts(opts: HardeningOptions) { ... }
   ```

#### 6.3.2 中优先级

4. **增加加固状态查询**
   允许调用方验证加固是否成功：
   ```rust
   pub fn verify_hardening() -> HardeningStatus { ... }
   ```

5. **支持更多加固选项**
   - 内存锁定（mlockall）选项
   - seccomp-bpf 过滤器安装（Linux）
   - 文件描述符清理（关闭非标准 FD）

#### 6.3.3 低优先级

6. **文档完善**
   - 添加架构图
   - 详细说明各平台差异
   - 安全审计报告引用

7. **测试覆盖**
   当前仅测试 `env_keys_with_prefix`，建议增加：
   - 集成测试（验证系统调用行为）
   - 平台特定测试
   - 安全属性测试（如验证 ptrace 确实被禁用）

### 6.4 安全审计建议

- 定期审查 libc 绑定安全性
- 验证各平台系统调用行为符合预期
- 评估新出现的绕过技术（如 Linux 的 `PTRACE_SEIZE`）
- 考虑使用 Landlock/SELinux 等更现代的沙箱机制作为补充

---

## 7. 附录

### 7.1 相关文档

- `codex-rs/process-hardening/README.md` - 简要功能说明
- `codex-rs/responses-api-proxy/README.md` - 使用场景说明（第 66-80 行）
- `AGENTS.md` - 项目级开发规范

### 7.2 相关 Issue/PR

- 无公开跟踪 issue

### 7.3 测试执行

```bash
# 运行单元测试
cd codex-rs && cargo test -p codex-process-hardening
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/process-hardening 目录及其直接依赖/调用方*
