# Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 项目 `codex-windows-sandbox` 的包管理清单文件，定义了 crate 的元数据、依赖关系、构建配置和二进制目标。该 crate 是 Codex CLI 的 Windows 沙箱实现，提供了在 Windows 平台上创建受限执行环境的能力。

## 功能点目的

### 1. 包元数据 (Package Metadata)
```toml
[package]
build = "build.rs"
edition = "2021"
license.workspace = true
name = "codex-windows-sandbox"
version.workspace = true
```
- **build**: 指定构建脚本为 `build.rs`，用于编译时嵌入 Windows 清单
- **edition**: 使用 Rust 2021 Edition
- **license/workspace**: 从工作区继承许可证配置
- **name**: crate 名称，使用连字符分隔（Rust 内部会转换为下划线）
- **version/workspace**: 从工作区继承版本号

### 2. 库目标 (Library Target)
```toml
[lib]
name = "codex_windows_sandbox"
path = "src/lib.rs"
```
- 定义库 crate 的入口点为 `src/lib.rs`
- 库名使用下划线分隔（`codex_windows_sandbox`）

### 3. 二进制目标 (Binary Targets)
```toml
[[bin]]
name = "codex-windows-sandbox-setup"
path = "src/bin/setup_main.rs"

[[bin]]
name = "codex-command-runner"
path = "src/bin/command_runner.rs"
```

该 crate 构建两个可执行文件：

| 二进制名称 | 入口文件 | 用途 |
|-----------|---------|------|
| `codex-windows-sandbox-setup` | `src/bin/setup_main.rs` | 沙箱设置工具，需要管理员权限运行，负责创建沙箱用户、配置 ACL、设置防火墙规则 |
| `codex-command-runner` | `src/bin/command_runner.rs` | 命令执行器，在沙箱用户上下文中运行，通过 IPC 与父进程通信 |

### 4. 核心依赖分析

#### 4.1 通用依赖
| 依赖 | 版本 | 用途 |
|------|------|------|
| `anyhow` | 1.0 | 错误处理 |
| `base64` | workspace | Base64 编码/解码（用于 IPC 负载） |
| `chrono` | 0.4.42 | 日期时间处理（日志记录） |
| `serde` / `serde_json` | 1.0 | 序列化/反序列化（配置、IPC） |
| `tempfile` | 3 | 临时文件创建 |
| `tokio` | workspace | 异步运行时 |

#### 4.2 内部工具依赖
| 依赖 | 用途 |
|------|------|
| `codex-utils-pty` | PTY（伪终端）工具 |
| `codex-utils-absolute-path` | 绝对路径处理 |
| `codex-utils-string` | 字符串工具 |
| `codex-protocol` | 协议定义（SandboxPolicy 等） |

#### 4.3 Windows 特定依赖

**windows (0.58)** - 高级 Windows API 绑定：
- `Win32_Foundation` - 基础类型和函数
- `Win32_NetworkManagement_WindowsFirewall` - 防火墙管理
- `Win32_System_Com` - COM 支持
- `Win32_System_Variant` - VARIANT 类型支持

**windows-sys (0.52)** - 底层 Windows API 绑定（条件编译 `cfg(windows)`）：
- 安全相关：`Win32_Security`, `Win32_Security_Authorization`, `Win32_Security_Cryptography`
- 进程/线程：`Win32_System_Threading`, `Win32_System_JobObjects`
- 文件系统：`Win32_Storage_FileSystem`
- 网络：`Win32_NetworkManagement_NetManagement`, `Win32_Networking_WinSock`
- UI：`Win32_UI_WindowsAndMessaging`, `Win32_UI_Shell`
- 注册表：`Win32_System_Registry`
- 控制台：`Win32_System_Console`
- 桌面：`Win32_System_StationsAndDesktops`

### 5. 开发依赖
```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
```
- 用于测试中的美观断言输出

### 6. 构建依赖
```toml
[build-dependencies]
winres = "0.1"
```
- `winres`: Windows 资源编译器，用于将 `.manifest` 文件嵌入可执行文件

### 7. Cargo Shear 配置
```toml
[package.metadata.cargo-shear]
ignored = ["codex-utils-pty", "tokio"]
```
- 告诉 `cargo-shear`（未使用依赖检测工具）忽略这些依赖
- 这些依赖可能在代码中被条件编译使用，但静态分析无法检测到

## 具体技术实现

### 沙箱架构
该 crate 实现了 Windows 沙箱的两种运行模式：

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex CLI (主进程)                       │
│                         (用户权限)                           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│         codex-windows-sandbox-setup.exe (提权)               │
│    - 创建沙箱用户 (CodexSandboxOffline/CodexSandboxOnline)   │
│    - 配置文件系统 ACL                                       │
│    - 设置防火墙规则                                         │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│          codex-command-runner.exe (沙箱用户)                 │
│    - 创建受限 Token                                         │
│    - 启动目标进程                                           │
│    - IPC 通信（stdin/stdout/stderr）                        │
└─────────────────────────────────────────────────────────────┘
```

### Token 创建流程
1. **ReadOnly 模式**: 使用 `create_readonly_token_with_cap` 创建只读 Token
2. **WorkspaceWrite 模式**: 使用 `create_workspace_write_token_with_caps_from` 创建带写入能力的 Token

### ACL 配置
- 使用 Windows ACL API (`SetEntriesInAclW`, `SetNamedSecurityInfoW`)
- 支持允许 (Allow) 和拒绝 (Deny) ACE
- 继承标志：`CONTAINER_INHERIT_ACE | OBJECT_INHERIT_ACE`

## 关键代码路径与文件引用

### 库入口
- `src/lib.rs` - 主库入口，条件编译 Windows 模块

### 二进制入口
- `src/bin/setup_main.rs` → `src/setup_main_win.rs` - 设置工具
- `src/bin/command_runner.rs` → `src/elevated/command_runner_win.rs` - 命令执行器

### 核心模块
| 模块 | 文件 | 功能 |
|------|------|------|
| ACL 管理 | `src/acl.rs` | 添加/删除/检查 ACE |
| Token 管理 | `src/token.rs` | 创建受限 Token |
| 设置编排 | `src/setup_orchestrator.rs` | 协调设置流程 |
| 设置主逻辑 | `src/setup_main_win.rs` | 提权设置逻辑 |
| 命令执行器 | `src/elevated/command_runner_win.rs` | IPC 命令执行 |
| 防火墙 | `src/firewall.rs` | Windows 防火墙规则 |
| 能力 SID | `src/cap.rs` | Capability SID 管理 |
| 路径规范化 | `src/path_normalization.rs` | 路径处理 |

## 依赖与外部交互

### 外部系统依赖
1. **Windows OS** - 需要 Windows 10/11
2. **Windows SDK** - 编译时需要
3. **管理员权限** - `codex-windows-sandbox-setup.exe` 需要 UAC 提权

### 与其他 crate 的关系
```
codex-cli
    └── codex-windows-sandbox (本 crate)
            ├── codex-protocol (协议定义)
            ├── codex-utils-pty (PTY 支持)
            ├── codex-utils-absolute-path (路径)
            └── codex-utils-string (字符串)
```

### 运行时依赖
- 沙箱用户账户：`CodexSandboxOffline`, `CodexSandboxOnline`
- 沙箱目录：`%USERPROFILE%/.codex/.sandbox/`
- 日志文件：`%USERPROFILE%/.codex/.sandbox/setup.log`

## 风险、边界与改进建议

### 安全风险
1. **UAC 提权**: 设置工具需要管理员权限，需确保代码安全
2. **Token 创建**: 受限 Token 的配置错误可能导致沙箱逃逸
3. **ACL 配置**: 错误的 ACL 可能允许未授权访问

### 平台限制
- **Windows Only**: 非 Windows 平台使用 stub 实现（返回错误）
- **版本要求**: 某些 API 可能需要较新的 Windows 版本

### 改进建议

1. **依赖优化**:
   ```toml
   # 考虑将 windows 和 windows-sys 统一
   # 当前同时使用两个 crate 可能增加编译时间
   ```

2. **功能标志**:
   ```toml
   [features]
   default = ["firewall"]
   firewall = []  # 可选禁用防火墙功能
   ```

3. **文档改进**:
   - 添加更多模块级文档说明沙箱架构
   - 提供安全审计指南

4. **测试增强**:
   - 当前 `cargo-shear` 忽略了 `tokio` 和 `codex-utils-pty`
   - 确保这些依赖确实被使用，或考虑移除

5. **构建优化**:
   - `winres` 仅 Windows 需要，可以考虑平台条件依赖
   ```toml
   [target.'cfg(windows)'.build-dependencies]
   winres = "0.1"
   ```

6. **版本管理**:
   - `SETUP_VERSION = 5` 在代码中硬编码
   - 考虑从 Cargo.toml 版本派生
