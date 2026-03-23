# Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 `codex-linux-sandbox` crate 的 Cargo 构建配置文件，定义了 crate 的元数据、编译目标、依赖关系和构建脚本。该 crate 是 Codex CLI 的 Linux 沙箱辅助程序，提供基于 bubblewrap 和 seccomp 的进程隔离功能。

## 功能点目的

### 1. 包元数据

```toml
[package]
name = "codex-linux-sandbox"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- 使用 workspace 级别的版本、edition 和 license 配置，确保整个工作区的一致性
- crate 名称使用 kebab-case (`codex-linux-sandbox`)，而 lib 名称使用 snake_case (`codex_linux_sandbox`)

### 2. 双目标配置

```toml
[[bin]]
name = "codex-linux-sandbox"
path = "src/main.rs"

[lib]
name = "codex_linux_sandbox"
path = "src/lib.rs"
```

**设计意图：**
- **Binary 目标**: 独立的 `codex-linux-sandbox` 可执行文件，可直接被 Node.js 版本的 Codex CLI 调用
- **Library 目标**: 暴露 `run_main()` 函数，供 `codex-exec` 和 `codex` multitool CLI 通过 arg0 检测机制复用

### 3. 平台特定依赖

```toml
[target.'cfg(target_os = "linux")'.dependencies]
clap = { workspace = true, features = ["derive"] }
codex-core = { workspace = true }
codex-protocol = { workspace = true }
codex-utils-absolute-path = { workspace = true }
landlock = { workspace = true }
libc = { workspace = true }
seccompiler = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
url = { workspace = true }
```

**关键依赖说明：**

| 依赖 | 用途 |
|------|------|
| `clap` | CLI 参数解析，使用 derive 宏简化定义 |
| `codex-core` | 核心错误类型和工具函数 |
| `codex-protocol` | 沙箱策略协议类型（`SandboxPolicy`, `FileSystemSandboxPolicy` 等） |
| `landlock` | Linux Landlock LSM 文件系统沙箱（legacy 路径） |
| `libc` | 底层系统调用（`prctl`, `fork`, `execvp` 等） |
| `seccompiler` | seccomp BPF 过滤器编译 |
| `serde`/`serde_json` | 策略序列化/反序列化 |
| `url` | 代理 URL 解析 |

### 4. 构建依赖

```toml
[build-dependencies]
cc = "1"
pkg-config = "0.3"
```

**用途：**
- `cc`: 在 `build.rs` 中编译 vendored bubblewrap C 代码
- `pkg-config`: 检测系统 libcap 库

## 具体技术实现

### 条件编译策略

所有 Linux 特定的依赖都使用 `target.'cfg(target_os = "linux")'` 条件，确保：
1. 在非 Linux 平台上编译时不会引入这些依赖
2. 相关代码模块使用 `#[cfg(target_os = "linux")]` 属性进行条件编译

### 与 Bazel 构建的差异处理

Cargo 构建通过 `build.rs` 动态编译 bubblewrap，而 Bazel 构建：
1. 禁用 `build_script_enabled = False`
2. 通过 `cc_library` 规则预编译 bubblewrap
3. 通过 `rustc_flags_extra` 注入 `vendored_bwrap_available` cfg

## 关键代码路径与文件引用

### 依赖关系图

```
Cargo.toml
├── [package]
│   └── name = "codex-linux-sandbox"
├── [[bin]]
│   └── src/main.rs (6行，直接调用 lib::run_main)
├── [lib]
│   └── src/lib.rs (27行，模块组织和 run_main 入口)
├── [target.'cfg(target_os = "linux")'.dependencies]
│   ├── clap → src/linux_run_main.rs (LandlockCommand CLI 定义)
│   ├── codex-protocol → 策略类型定义
│   ├── landlock → src/landlock.rs
│   ├── libc → 系统调用封装
│   ├── seccompiler → src/landlock.rs (seccomp 过滤器)
│   └── serde → 策略 JSON 序列化
└── [build-dependencies]
    ├── cc → build.rs (编译 bubblewrap C 代码)
    └── pkg-config → build.rs (检测 libcap)
```

### 源码模块结构

```
src/
├── main.rs          # Binary 入口，调用 lib::run_main
├── lib.rs           # Library 入口，条件编译组织模块
├── linux_run_main.rs    # 主逻辑：CLI 解析、策略解析、bwrap 调用
├── linux_run_main_tests.rs  # 单元测试
├── bwrap.rs         # Bubblewrap 参数构建和文件系统策略映射
├── launcher.rs      # 系统 bwrap 与 vendored bwrap 的选择和执行
├── vendored_bwrap.rs    # FFI 调用 vendored bubblewrap
├── landlock.rs      # seccomp 过滤器 + Landlock 文件系统规则（legacy）
└── proxy_routing.rs # 托管代理模式的网络路由桥接
```

## 依赖与外部交互

### 内部 Workspace 依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 错误类型 (`CodexErr`, `SandboxErr`) |
| `codex-protocol` | 沙箱策略协议 (`SandboxPolicy`, `FileSystemSandboxPolicy`, `NetworkSandboxPolicy`) |
| `codex-utils-absolute-path` | 绝对路径类型和工具 |

### 外部 Crate 依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `landlock` | workspace | Landlock LSM 规则设置 |
| `seccompiler` | workspace | seccomp BPF 过滤器编译 |
| `libc` | workspace | 底层系统调用 |

### 系统依赖

- **libcap**: Linux capabilities 库，用于 bubblewrap 的特权操作
- **/usr/bin/bwrap**: 系统 bubblewrap 可执行文件（优先使用）

## 风险、边界与改进建议

### 风险点

1. **平台限制**: 该 crate 仅在 Linux 上有完整功能，非 Linux 平台 `run_main()` 直接 panic
2. **构建复杂性**: 需要 C 编译器和 libcap 开发头文件
3. **特权要求**: bubblewrap 可能需要 setuid 或 CAP_SYS_ADMIN

### 边界条件

- `build.rs` 仅在目标平台为 Linux 时执行 vendored bubblewrap 编译
- 环境变量 `CODEX_BWRAP_SOURCE_DIR` 可覆盖 vendored bubblewrap 源码位置
- 非 Linux 目标在 `build.rs` 中提前返回，不编译 C 代码

### 改进建议

1. **依赖优化**: 考虑将 `landlock` 设为可选依赖（optional），因为当前主要使用 bubblewrap 路径
2. **文档完善**: 添加更详细的构建要求和系统依赖说明
3. **错误改进**: 非 Linux 平台的 panic 信息可以更友好，说明这是预期行为
4. **特性标志**: 考虑添加 feature flag 允许禁用 vendored bubblewrap，完全依赖系统 bwrap
