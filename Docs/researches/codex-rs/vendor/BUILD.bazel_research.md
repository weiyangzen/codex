# codex-rs/vendor/BUILD.bazel 研究文档

## 场景与职责

`codex-rs/vendor/BUILD.bazel` 是 Codex 项目中负责管理 **Bubblewrap** 沙箱工具源码依赖的 Bazel 构建文件。该文件位于 `codex-rs/vendor/` 目录下，主要职责包括：

1. **源码组织**：将 Bubblewrap 的 C 源代码和头文件组织为 Bazel 的 `filegroup` 目标
2. **构建抽象**：为上层 `linux-sandbox` crate 提供统一的源码引用接口
3. **跨平台支持**：通过 Bazel 的 select 机制支持 Linux 平台的沙箱功能

### 项目上下文

Codex 是一个 AI 编程助手 CLI 工具，需要在 Linux 上提供安全的代码执行环境。Bubblewrap 是一个轻量级的沙箱工具，用于创建隔离的文件系统命名空间。Codex 选择将 Bubblewrap 源码 vendoring（内嵌）到项目中，以确保：

- **构建可复现性**：不依赖系统安装的 bubblewrap
- **功能一致性**：锁定特定版本（0.11.0）的行为
- **Fallback 能力**：当系统 `/usr/bin/bwrap` 不存在时使用内嵌版本

---

## 功能点目的

### 1. 源码分组目标

该 BUILD 文件定义了三个 `filegroup` 目标：

| 目标名 | 类型 | 内容 | 用途 |
|--------|------|------|------|
| `bubblewrap_c_sources` | filegroup | `bubblewrap/*.c` | C 源文件集合 |
| `bubblewrap_headers` | filegroup | `bubblewrap/*.h` | 头文件集合 |
| `bubblewrap_sources` | filegroup | 上述两者的组合 | 完整的源码包 |

### 2. 消费者：linux-sandbox crate

这些 filegroup 的主要消费者是 `codex-rs/linux-sandbox/BUILD.bazel` 中的 `vendored-bwrap-ffi` 目标：

```bazel
cc_library(
    name = "vendored-bwrap-ffi",
    srcs = ["//codex-rs/vendor:bubblewrap_c_sources"],
    hdrs = [
        "config.h",
        "//codex-rs/vendor:bubblewrap_headers",
    ],
    copts = [
        "-D_GNU_SOURCE",
        "-Dmain=bwrap_main",  # 关键：重命名 main 函数
    ],
    deps = ["@libcap//:libcap"],
    ...
)
```

### 3. 关键编译选项

- **`-D_GNU_SOURCE`**：启用 GNU 扩展，支持 Linux 特定的系统调用和特性
- **`-Dmain=bwrap_main`**：将 bubblewrap 的 `main` 函数重命名为 `bwrap_main`，使其可以作为库被调用而非独立程序

---

## 具体技术实现

### 1. 文件结构

```
codex-rs/vendor/
├── BUILD.bazel          # 本文件：定义 filegroup 目标
└── bubblewrap/          # Bubblewrap 0.11.0 源码目录
    ├── bubblewrap.c     # 主程序 (3641 行)
    ├── bind-mount.c     # 绑定挂载实现 (598 行)
    ├── network.c        # 网络命名空间设置 (199 行)
    ├── utils.c          # 工具函数 (1080 行)
    ├── bind-mount.h     # 绑定挂载头文件
    ├── network.h        # 网络功能头文件
    └── utils.h          # 工具函数头文件
```

### 2. Bubblewrap 核心功能

Bubblewrap 是一个用于创建 Linux 沙箱环境的工具，核心功能包括：

#### 2.1 命名空间隔离

```c
// bubblewrap.c: 支持的命名空间类型
static NsInfo ns_infos[] = {
  {"cgroup", &opt_unshare_cgroup, 0},
  {"ipc",    &opt_unshare_ipc,    0},
  {"mnt",    NULL,                0},  // 总是 unshare
  {"net",    &opt_unshare_net,    0},
  {"pid",    &opt_unshare_pid,    0},
  {"uts",    &opt_unshare_uts,    0},
  {NULL,     NULL,                0}
};
```

#### 2.2 文件系统操作类型

```c
// bubblewrap.c: 设置操作类型枚举
typedef enum {
  SETUP_BIND_MOUNT,
  SETUP_RO_BIND_MOUNT,
  SETUP_DEV_BIND_MOUNT,
  SETUP_OVERLAY_MOUNT,
  SETUP_TMP_OVERLAY_MOUNT,
  SETUP_RO_OVERLAY_MOUNT,
  SETUP_MOUNT_PROC,
  SETUP_MOUNT_DEV,
  SETUP_MOUNT_TMPFS,
  ...
} SetupOpType;
```

#### 2.3 关键数据结构

```c
// 设置操作结构体
struct _SetupOp {
  SetupOpType type;
  const char *source;
  const char *dest;
  int         fd;
  SetupOpFlag flags;
  int         perms;
  size_t      size;
  SetupOp    *next;
};

// 特权分离操作（用于 setuid 模式）
typedef struct {
  uint32_t op;
  uint32_t flags;
  uint32_t perms;
  size_t   size_arg;
  uint32_t arg1_offset;
  uint32_t arg2_offset;
} PrivSepOp;
```

### 3. 与 Rust 代码的集成

#### 3.1 FFI 接口

`codex-rs/linux-sandbox/src/vendored_bwrap.rs` 提供了 Rust 到 C 的 FFI 绑定：

```rust
#[cfg(vendored_bwrap_available)]
mod imp {
    use std::ffi::CString;
    use std::os::raw::c_char;

    unsafe extern "C" {
        fn bwrap_main(argc: libc::c_int, argv: *const *const c_char) -> libc::c_int;
    }

    pub(crate) fn exec_vendored_bwrap(argv: Vec<String>, preserved_files: Vec<File>) -> ! {
        let exit_code = run_vendored_bwrap_main(&argv, &preserved_files);
        std::process::exit(exit_code);
    }
}
```

#### 3.2 启动流程

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-linux-sandbox                       │
│                     (Rust 二进制)                            │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  检查 /usr/bin/bwrap 是否存在？ │
        └───────────────┬───────────────┘
                        │
           ┌────────────┴────────────┐
           │ 是                      │ 否
           ▼                         ▼
   ┌──────────────┐         ┌──────────────────┐
   │ 系统 bwrap   │         │ 内嵌 bwrap_main  │
   │ execv 调用   │         │ FFI 调用         │
   └──────────────┘         └──────────────────┘
                        │
                        ▼
           ┌──────────────────────┐
           │ bubblewrap C 代码    │
           │ (本 BUILD 文件管理)  │
           └──────────┬───────────┘
                      │
                      ▼
           ┌──────────────────────┐
           │ 创建命名空间         │
           │ 设置文件系统视图     │
           │ exec 用户命令        │
           └──────────────────────┘
```

### 4. 构建时配置

#### 4.1 Cargo 构建（build.rs）

`codex-rs/linux-sandbox/build.rs` 处理 Cargo 构建场景：

```rust
fn try_build_vendored_bwrap() -> Result<(), String> {
    let src_dir = resolve_bwrap_source_dir(&manifest_dir)?;
    let libcap = pkg_config::Config::new()
        .probe("libcap")
        .map_err(|err| format!("libcap not available via pkg-config: {err}"))?;

    let mut build = cc::Build::new();
    build
        .file(src_dir.join("bubblewrap.c"))
        .file(src_dir.join("bind-mount.c"))
        .file(src_dir.join("network.c"))
        .file(src_dir.join("utils.c"))
        .define("_GNU_SOURCE", None)
        .define("main", Some("bwrap_main"));  // 关键重命名
    
    build.compile("build_time_bwrap");
    println!("cargo:rustc-cfg=vendored_bwrap_available");
    Ok(())
}
```

#### 4.2 Bazel 构建

Bazel 构建通过 `codex-rs/linux-sandbox/BUILD.bazel` 中的 `vendored-bwrap-ffi` cc_library 目标实现，引用本文件定义的 filegroup。

---

## 关键代码路径与文件引用

### 1. 核心源码文件

| 文件 | 行数 | 功能描述 |
|------|------|----------|
| `bubblewrap/bubblewrap.c` | 3641 | 主程序逻辑、命令行解析、命名空间管理、进程监控 |
| `bubblewrap/bind-mount.c` | 598 | 绑定挂载实现，包括只读重挂载、递归挂载处理 |
| `bubblewrap/network.c` | 199 | 网络命名空间设置，loopback 接口配置 |
| `bubblewrap/utils.c` | 1080 | 内存管理、文件操作、字符串处理、系统调用包装 |

### 2. 关键头文件

| 文件 | 功能描述 |
|------|----------|
| `bubblewrap/utils.h` | 通用工具函数声明、内存管理宏、错误处理 |
| `bubblewrap/bind-mount.h` | 绑定挂载 API、挂载选项枚举 |
| `bubblewrap/network.h` | 网络设置函数声明 |

### 3. 调用链关键路径

```
# Rust 侧调用链
codex-rs/linux-sandbox/src/launcher.rs:exec_bwrap()
    ├── 优先尝试 /usr/bin/bwrap (系统版本)
    └── 回退到 codex-rs/linux-sandbox/src/vendored_bwrap.rs:exec_vendored_bwrap()
            └── FFI 调用 bwrap_main()

# C 侧入口
codex-rs/vendor/bubblewrap/bubblewrap.c:bwrap_main()
    ├── 解析命令行参数
    ├── 创建命名空间 (clone/unshare)
    ├── 执行设置操作链 (SetupOp)
    └── exec 目标程序
```

### 4. 配置头文件

`codex-rs/linux-sandbox/config.h` 提供了编译时配置：

```c
#pragma once
#define PACKAGE_STRING "bubblewrap built at codex build-time"
```

这与 Bubblewrap 原版的 `meson.build` 生成的配置不同，Codex 使用简化版本。

---

## 依赖与外部交互

### 1. 外部依赖

| 依赖 | 用途 | 来源 |
|------|------|------|
| libcap | Linux capabilities 支持 | 系统包管理器 (pkg-config) |
| libc | 标准 C 库 | 系统默认 |

### 2. Bazel 工作区依赖

```bazel
# MODULE.bazel 中定义
bazel_dep(name = "rules_cc", version = "...")
bazel_dep(name = "platforms", version = "...")
```

### 3. 消费者依赖

| 消费者 | 依赖方式 | 用途 |
|--------|----------|------|
| `//codex-rs/linux-sandbox:vendored-bwrap-ffi` | `srcs` + `hdrs` | 编译内嵌 bubblewrap |
| `//codex-rs/linux-sandbox:linux-sandbox` | `deps_extra` | Rust crate 依赖 |
| `//codex-rs/core:core` | `extra_binaries` | 测试时调用沙箱 |

### 4. 系统调用依赖

Bubblewrap 依赖以下 Linux 特性：

- **Namespaces**: `CLONE_NEWUSER`, `CLONE_NEWPID`, `CLONE_NEWNET`, `CLONE_NEWIPC`, `CLONE_NEWUTS`, `CLONE_NEWCGROUP`
- **Capabilities**: `CAP_SYS_ADMIN` (用于挂载操作)
- **Seccomp**: `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ...)`
- **特权控制**: `PR_SET_NO_NEW_PRIVS`, `PR_SET_PDEATHSIG`

---

## 风险、边界与改进建议

### 1. 安全风险

#### 1.1 setuid 风险

Bubblewrap 传统上以 setuid 模式运行以获取必要的特权。Codex 使用内嵌版本时：

- **风险**：如果内嵌版本被攻击者替换或篡改，可能导致特权提升
- **缓解**：Codex 使用 `PR_SET_NO_NEW_PRIVS` 限制 setuid 二进制文件的特权提升

#### 1.2 命名空间逃逸

```c
// bubblewrap.c: 安全相关的全局选项
static bool opt_assert_userns_disabled = false;
static bool opt_disable_userns = false;
```

Codex 默认启用 `--unshare-user`，但某些内核配置可能限制用户命名空间。

### 2. 边界情况

#### 2.1 容器环境限制

在 Docker 等容器环境中：
- 可能无法创建新的用户命名空间（`--unshare-user` 失败）
- 可能无法挂载 `/proc`（Codex 已实现 `--no-proc` 回退）

```rust
// linux_run_main.rs: proc 挂载预检
fn preflight_proc_mount_support(...) -> bool {
    // 运行预检命令检测 --proc 是否可用
}
```

#### 2.2 跨平台限制

```rust
// lib.rs
#[cfg(not(target_os = "linux"))]
pub fn run_main() -> ! {
    panic!("codex-linux-sandbox is only supported on Linux");
}
```

### 3. 改进建议

#### 3.1 构建系统优化

| 建议 | 优先级 | 描述 |
|------|--------|------|
| 添加源码校验 | 中 | 添加 bubblewrap 源码的 checksum 验证，防止意外修改 |
| 分离编译单元 | 低 | 将每个 .c 文件编译为单独的 object 文件，提高增量构建效率 |
| 配置生成 | 低 | 使用更完整的 config.h 生成，支持更多编译选项 |

#### 3.2 功能增强

| 建议 | 优先级 | 描述 |
|------|--------|------|
| 版本检测 | 中 | 运行时检测系统 bubblewrap 版本，选择最优实现 |
| 能力降级 | 高 | 当某些命名空间不可用时，优雅降级到 Landlock |
| 日志增强 | 低 | 添加更多调试日志，便于排查沙箱问题 |

#### 3.3 安全加固

| 建议 | 优先级 | 描述 |
|------|--------|------|
| 源码签名 | 中 | 对 vendored 的 bubblewrap 源码进行签名验证 |
| 编译时加固 | 中 | 启用更多编译器安全选项（CFI, stack protector 等） |
| seccomp 审计 | 高 | 定期审计 seccomp 规则，确保最小权限原则 |

### 4. 已知问题

1. **libcap 依赖**：构建时需要系统安装 libcap-dev/libcap-devel 包
2. **交叉编译**：跨架构构建时需要目标架构的 libcap 头文件
3. **测试覆盖**：bubblewrap 本身的 C 代码缺乏单元测试，依赖集成测试

### 5. 维护建议

- **版本升级**：Bubblewrap 当前版本为 0.11.0，建议定期跟进上游安全更新
- **文档同步**：确保 `codex-rs/linux-sandbox/README.md` 与实际行为保持一致
- **CI 覆盖**：在多种 Linux 发行版和容器环境中测试沙箱功能

---

## 附录：相关文件索引

### 构建相关
- `codex-rs/vendor/BUILD.bazel` - 本文件
- `codex-rs/linux-sandbox/BUILD.bazel` - linux-sandbox crate 构建配置
- `codex-rs/linux-sandbox/build.rs` - Cargo 构建脚本

### 源码相关
- `codex-rs/vendor/bubblewrap/*.c` - C 源文件
- `codex-rs/vendor/bubblewrap/*.h` - 头文件
- `codex-rs/vendor/bubblewrap/meson.build` - 上游构建配置（参考用）

### Rust 集成
- `codex-rs/linux-sandbox/src/lib.rs` - crate 入口
- `codex-rs/linux-sandbox/src/vendored_bwrap.rs` - FFI 绑定
- `codex-rs/linux-sandbox/src/launcher.rs` - 启动器逻辑
- `codex-rs/linux-sandbox/src/bwrap.rs` - bubblewrap 参数构建
- `codex-rs/linux-sandbox/src/linux_run_main.rs` - 主运行逻辑

### 文档
- `codex-rs/vendor/bubblewrap/README.md` - Bubblewrap 项目文档
- `codex-rs/linux-sandbox/README.md` - Linux 沙箱使用文档
