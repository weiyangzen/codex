# codex-rs/core/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-core` crate 的文档入口，描述了该 crate 的核心定位：**实现 Codex 的业务逻辑层**，供各种 Rust 编写的 Codex UI（TUI、CLI、App Server）使用。

该文档重点说明了 `codex-core` 对平台特定辅助工具的依赖假设，详细描述了三个主要平台（macOS、Linux、Windows）的沙箱实现机制和安全策略。

## 功能点目的

### 1. 业务逻辑层定位

```markdown
This crate implements the business logic for Codex. It is designed to be used by the various Codex UIs written in Rust.
```

- **核心职责**：封装 AI 编程助手的业务逻辑
- **架构分层**：
  - `codex-core`：业务逻辑（此 crate）
  - `codex-cli`：命令行界面
  - `codex-tui`：终端用户界面
  - `codex-app-server`：IDE 集成服务器

### 2. 平台支持矩阵

文档详细说明了三个平台的沙箱支持：

| 平台 | 沙箱机制 | 关键组件 |
|------|----------|----------|
| macOS | Seatbelt (sandbox-exec) | `/usr/bin/sandbox-exec` |
| Linux | Landlock + bubblewrap | `codex-linux-sandbox` 二进制 |
| Windows | 受限令牌 + 特权提升 | 内置 Windows API |

## 具体技术实现

### macOS 沙箱实现

#### 基础机制
- **工具**：`/usr/bin/sandbox-exec` (Seatbelt)
- **策略消费**：Seatbelt 消费 `SandboxPolicy` 并强制执行
- **读写控制**：网络访问和文件系统读写根由 `SandboxPolicy` 控制

#### 权限配置文件扩展

Seatbelt 支持在 `SandboxPolicy` 之上叠加 macOS 权限配置文件扩展：

| 扩展配置 | 值 | 效果 |
|----------|-----|------|
| `macos_preferences` | `"readonly"` | 启用 cfprefs 读取和 `user-preference-read` |
| `macos_preferences` | `"readwrite"` | 增加 `user-preference-write` 和 cfprefs shm 写入 |
| `macos_automation` | `true` | 启用广泛的 Apple Events 发送权限 |
| `macos_automation` | `["com.apple.Notes", ...]` | 仅允许向指定 bundle ID 发送 Apple Events |
| `macos_launch_services` | `true` | 启用 LaunchServices 查找和打开操作 |
| `macos_accessibility` | `true` | 启用 `com.apple.axserver` mach lookup |
| `macos_calendar` | `true` | 启用 `com.apple.CalendarAgent` mach lookup |
| `macos_contacts` | `"read_only"` | 启用 Address Book 读取和 Contacts 读取服务 |
| `macos_contacts` | `"read_write"` | 增加 Address Book 写入和 keychain/temp 辅助 |

#### 工作区写入策略细节

```markdown
When using the workspace-write sandbox policy, the Seatbelt profile allows
writes under the configured writable roots while keeping `.git` (directory or
pointer file), the resolved `gitdir:` target, and `.codex` read-only.
```

- 允许写入：配置的 `writable_roots`
- 保持只读：`.git` 目录/指针文件、`gitdir:` 目标、`.codex` 目录

### Linux 沙箱实现

#### 双路径架构

Linux 支持两种沙箱路径：

1. **传统 Landlock 路径**（Legacy）：
   - 通过 `SandboxPolicy` / `sandbox_mode` 配置
   - 当分割文件系统策略与旧模型在 `cwd` 解析后等效时使用

2. **bubblewrap 路径**（新）：
   - 用于需要直接 `FileSystemSandboxPolicy` 执行的场景
   - 支持只读或拒绝的精细 carveout

#### 路径选择逻辑

```markdown
Split filesystem policies that need direct `FileSystemSandboxPolicy`
enforcement, such as read-only or denied carveouts under a broader writable
root, automatically route through bubblewrap.
```

- **自动路由**：当策略需要精细控制时自动使用 bubblewrap
- **回退条件**：当策略可以通过旧 `SandboxPolicy` 模型无损转换时使用 Landlock

#### 复杂场景示例

```markdown
That includes overlapping cases like `/repo = write`, `/repo/a = none`, `/repo/a/b = write`,
where the more specific writable child must reopen under a denied parent.
```

这种嵌套权限场景需要 bubblewrap 处理：
- `/repo`：可写
- `/repo/a`：拒绝访问
- `/repo/a/b`：可写（在拒绝的父目录下重新打开）

#### 二进制依赖

- **主二进制**：包含 `codex-core` 的二进制需要运行 `codex sandbox linux`（旧称 `codex debug landlock`）
- **arg0 检测**：当 `arg0` 为 `codex-linux-sandbox` 时触发沙箱模式
- **实现细节**：参见 `codex-arg0` crate

#### bubblewrap 优先级

```markdown
The Linux sandbox helper prefers `/usr/bin/bwrap` whenever it is available and
falls back to the vendored bubblewrap path otherwise.
```

- 优先使用系统 `/usr/bin/bwrap`
- 回退到内置的 bubblewrap
- **启动警告**：当系统 bwrap 缺失时，通过通知路径（而非直接打印）向用户显示警告

### Windows 沙箱实现

#### 传统策略支持

```markdown
Legacy `SandboxPolicy` / `sandbox_mode` configs are still supported on Windows.
```

- 保留对旧配置的支持

#### 特权后端（Elevated Backend）

```markdown
The elevated setup/runner backend supports legacy `ReadOnlyAccess::Restricted`
for `read-only` and `workspace-write` policies.
```

- 支持 `read-only` 和 `workspace-write` 策略
- 受限读取访问：
  - 显式可读的根目录
  - 命令的 `cwd`
  - 当使用 `workspace-write` 时，可写根也保持可读

#### 平台默认包含

```markdown
When `include_platform_defaults = true`, the elevated Windows backend adds
backend-managed system read roots required for basic execution, such as
`C:\Windows`, `C:\Program Files`, `C:\Program Files (x86)`, and
`C:\ProgramData`.
```

- `include_platform_defaults = true`：自动添加系统读取根目录
- `include_platform_defaults = false`：省略这些额外系统根

#### 非特权后端限制

```markdown
The unelevated restricted-token backend still supports the legacy full-read
Windows model only. Restricted read-only policies continue to fail closed there
instead of running with weaker read enforcement.
```

- 非特权受限令牌后端仅支持传统全读取模型
- 受限只读策略会**失败关闭**（fail closed），而非以较弱权限运行

#### 新权限系统支持

```markdown
New `[permissions]` / split filesystem policies remain supported on Windows
only when they round-trip through the legacy `SandboxPolicy` model without
changing semantics. Richer split-only carveouts still fail closed instead of
running with weaker enforcement.
```

- 新 `[permissions]` 系统仅在可无损转换为旧模型时支持
- 更丰富的分割 carveout 会失败关闭

### 全平台通用

#### apply_patch 虚拟 CLI

```markdown
Expects the binary containing `codex-core` to simulate the virtual `apply_patch` CLI when `arg1` is `--codex-run-as-apply-patch`.
```

- 当 `arg1` 为 `--codex-run-as-apply-patch` 时模拟 `apply_patch` CLI
- 实现细节：参见 `codex-arg0` crate

## 关键代码路径与文件引用

### 沙箱相关源码

| 平台 | 文件路径 | 说明 |
|------|----------|------|
| 通用 | `src/sandboxing/mod.rs` | 沙箱抽象和入口 |
| macOS | `src/seatbelt.rs` | Seatbelt 实现 |
| macOS | `src/seatbelt_permissions.rs` | 权限扩展处理 |
| Linux | `src/landlock.rs` | Landlock 实现 |
| Windows | `src/windows_sandbox.rs` | Windows 沙箱实现 |
| 通用 | `src/exec.rs` | 执行抽象 |

### 配置相关

| 文件 | 说明 |
|------|------|
| `src/config/mod.rs` | 配置加载，包含 `SandboxPolicy` 解析 |
| `src/config/permissions.rs` | 权限配置类型 |
| `src/protocol.rs` | `SandboxPolicy` 定义 |

### 相关 Crates

| Crate | 说明 |
|-------|------|
| `codex-arg0` | arg0/arg1 检测逻辑 |
| `codex-linux-sandbox` | Linux 沙箱二进制 |
| `codex-windows-sandbox` | Windows 沙箱实现 |

## 依赖与外部交互

### 外部系统工具

| 平台 | 工具 | 用途 |
|------|------|------|
| macOS | `/usr/bin/sandbox-exec` | Seatbelt 沙箱执行 |
| Linux | `/usr/bin/bwrap` | bubblewrap（优先） |
| Linux | vendored bubblewrap | 内置回退 |

### 配置接口

```rust
// SandboxPolicy 结构（简化）
pub struct SandboxPolicy {
    pub sandbox_mode: SandboxMode,  // read-only, workspace-write, danger-full-access
    pub writable_roots: Vec<PathBuf>,
    pub readable_roots: Vec<PathBuf>,
    pub network_access: bool,
    // ... macOS 扩展
    pub macos_seatbelt_profile_extensions: Option<MacOsSeatbeltProfileExtensions>,
}
```

### 运行时检测

- **macOS**：检测 `sandbox-exec` 存在性
- **Linux**：检测 `/usr/bin/bwrap` 存在性，显示警告
- **Windows**：检测特权级别，选择后端

## 风险、边界与改进建议

### 平台差异风险

1. **功能不对等**：
   - macOS 支持最丰富的权限扩展
   - Windows 非特权后端功能受限
   - Linux 需要外部二进制（bwrap）

2. **配置复杂性**：
   - 三个平台有不同的配置选项和限制
   - 用户可能困惑于跨平台行为差异

### 安全边界

1. **失败关闭原则**（Fail Closed）：
   - Windows 非特权后端和复杂权限场景会失败关闭
   - 这可能导致用户体验问题（Codex 拒绝运行）
   - 但确保了安全策略不被绕过

2. **权限升级路径**：
   - Linux：`codex-shell-escalation` crate
   - Windows：内置特权提升
   - macOS：依赖系统权限对话框

### 维护挑战

1. **多平台测试**：
   - 沙箱行为需要在三个平台上分别测试
   - CI 需要覆盖所有平台

2. **文档同步**：
   - README 中的描述需要与代码实现保持同步
   - 特别是权限扩展和配置选项

### 改进建议

1. **统一权限模型**：
   ```markdown
   # 当前：三个平台有不同的权限表达方式
   # 建议：提供平台无关的权限抽象，内部转换为平台特定实现
   ```

2. **更好的错误消息**：
   - 当沙箱策略无法执行时，提供清晰的解释
   - 建议用户如何调整配置

3. **配置验证**：
   - 在启动时验证沙箱配置的有效性
   - 提前发现不支持的组合

4. **文档增强**：
   - 添加配置示例
   - 说明常见场景的推荐配置
   - 平台特定注意事项清单

5. **沙箱调试工具**：
   - 提供 `codex sandbox test` 或类似命令
   - 帮助用户验证沙箱行为

6. **自动回退**：
   - 当首选沙箱机制不可用时，尝试替代方案
   - 同时向用户显示警告
