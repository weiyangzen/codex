# README.md 研究文档

## 场景与职责

`README.md` 是 `codex-linux-sandbox` crate 的文档入口，详细描述了该 crate 的功能、行为和配置选项。它面向开发者和高级用户，解释了 Linux 沙箱的实现机制、默认行为、配置方式以及与 legacy Landlock 路径的关系。

## 功能点目的

### 1. 产物说明

文档开篇明确该 crate 产出两个主要产物：

1. **独立可执行文件** (`codex-linux-sandbox`): 与 Node.js 版本的 Codex CLI 捆绑
2. **Library crate** (`codex_linux_sandbox`): 暴露 `run_main()` 函数供其他 CLI 复用

**多 CLI 复用机制：**
- `codex-exec` CLI 检测 arg0 是否为 `codex-linux-sandbox`，如果是则执行沙箱逻辑
- `codex` multitool CLI 同样支持此检测

### 2. Bubblewrap 优先级策略

```markdown
On Linux, the bubblewrap pipeline prefers the system `/usr/bin/bwrap` whenever
it is available. If `/usr/bin/bwrap` is missing, the helper still falls back to
the vendored bubblewrap path compiled into this binary.
```

**回退层级：**
1. 优先使用系统 `/usr/bin/bwrap`（如果存在）
2. 回退到编译时嵌入的 vendored bubblewrap
3. 当系统 bwrap 缺失时，Codex 会显示启动警告

### 3. 当前行为详细说明

#### 3.1 策略兼容性

- **Legacy `SandboxPolicy` / `sandbox_mode` 配置**: 保持向后兼容
- **Bubblewrap**: 默认文件系统沙箱管道
- **Landlock**: 作为显式 legacy 回退路径保留

#### 3.2 配置选项

```markdown
Set `features.use_legacy_landlock = true` (or CLI `-c use_legacy_landlock=true`)
to force the legacy Landlock fallback.
```

**使用场景：**
- 需要强制使用 legacy Landlock 而非 bubblewrap
- 某些特定环境 bubblewrap 无法正常工作

#### 3.3 策略转换规则

```markdown
The legacy Landlock fallback is used only when the split filesystem policy is
sandbox-equivalent to the legacy model after `cwd` resolution.
```

**关键逻辑：**
- 仅当 split filesystem policy 在 `cwd` 解析后与 legacy 模型等效时才使用 Landlock
- 不通过 legacy `SandboxPolicy` 模型回传的 split-only 文件系统策略继续使用 bubblewrap
- 这确保了嵌套的只读或拒绝 carveout 被保留

### 4. Bubblewrap 默认管道行为

#### 4.1 进程级限制

```markdown
When the default bubblewrap pipeline is active, the helper applies `PR_SET_NO_NEW_PRIVS` 
and a seccomp network filter in-process.
```

**安全机制：**
- `PR_SET_NO_NEW_PRIVS`: 防止特权提升
- seccomp 网络过滤器: 限制网络系统调用

#### 4.2 文件系统隔离

```markdown
When the default bubblewrap pipeline is active:
- the filesystem is read-only by default via `--ro-bind / /`
- writable roots are layered with `--bind <root> <root>`
```

**挂载顺序（重要）：**
1. `--ro-bind / /`: 默认只读根文件系统
2. `--bind <root> <root>`: 可写根目录覆盖
3. `--ro-bind`: 保护子路径（如 `.git`, `.codex`）重新设为只读

#### 4.3 路径特定性排序

```markdown
overlapping split-policy entries are applied in path-specificity order so narrower 
writable children can reopen broader read-only or denied parents while narrower 
denied subpaths still win.
```

**示例：**
```
/repo = write
/repo/a = none
/repo/a/b = write
```
结果：
- `/repo`: 可写
- `/repo/a`: 拒绝访问
- `/repo/a/b`: 重新开放为可写

#### 4.4 符号链接保护

```markdown
symlink-in-path and non-existent protected paths inside writable roots are blocked 
by mounting `/dev/null` on the symlink or first missing component.
```

**防护机制：**
- 在符号链接上挂载 `/dev/null` 阻止替换攻击
- 在第一个缺失的组件上挂载 `/dev/null` 阻止创建受保护路径

#### 4.5 命名空间隔离

```markdown
--unshare-user: 用户命名空间隔离
--unshare-pid: PID 命名空间隔离
--unshare-net: 网络命名空间隔离（网络受限且无代理路由时）
```

### 5. 托管代理模式 (Managed Proxy Mode)

```markdown
In managed proxy mode:
- the helper uses `--unshare-net` plus an internal TCP->UDS->TCP routing bridge
- after the bridge is live, seccomp blocks new AF_UNIX/socketpair creation
```

**网络架构：**
```
Sandbox 内进程 → TCP (localhost) → UDS (Unix Domain Socket) → TCP (Host 代理)
```

**安全增强：**
- 桥接建立后，seccomp 阻止新的 AF_UNIX/socketpair 创建
- 防止绕过代理路由直接创建 Unix socket

### 6. /proc 挂载控制

```markdown
--proc /proc: 默认挂载新的 /proc
--no-proc: 在限制性容器环境中跳过（当 --proc 被拒绝时）
```

**预检机制：**
- 代码中实现了 `preflight_proc_mount_support` 检测
- 如果预检失败，自动回退到 `--no-proc`

## 关键代码路径与文件引用

### 文档与实现对应

| 文档描述 | 实现文件 | 关键函数/结构 |
|---------|---------|--------------|
| Bubblewrap 参数构建 | `src/bwrap.rs` | `create_bwrap_command_args`, `create_filesystem_args` |
| 系统/vendored bwrap 选择 | `src/launcher.rs` | `preferred_bwrap_launcher`, `exec_bwrap` |
| seccomp 过滤器 | `src/landlock.rs` | `install_network_seccomp_filter_on_current_thread` |
| 代理路由桥接 | `src/proxy_routing.rs` | `prepare_host_proxy_route_spec`, `activate_proxy_routes_in_netns` |
| 主执行流程 | `src/linux_run_main.rs` | `run_main`, `run_bwrap_with_proc_fallback` |
| 策略解析 | `src/linux_run_main.rs` | `resolve_sandbox_policies` |

### 策略类型定义

策略类型定义在 `codex-protocol` crate 中：
- `SandboxPolicy`: Legacy 策略枚举
- `FileSystemSandboxPolicy`: 分离的文件系统策略
- `NetworkSandboxPolicy`: 分离的网络策略

### 调用方引用

```
codex-rs/core/src/sandboxing/mod.rs
├── create_linux_sandbox_command_args_for_policies() (在 landlock.rs 中定义)
└── 调用 codex-linux-sandbox 可执行文件

codex-rs/arg0/src/lib.rs
├── LINUX_SANDBOX_ARG0 = "codex-linux-sandbox"
└── arg0_dispatch() 检测并调用 codex_linux_sandbox::run_main()
```

## 依赖与外部交互

### 外部工具依赖

| 工具 | 用途 | 回退策略 |
|------|------|---------|
| `/usr/bin/bwrap` | 系统 bubblewrap | 使用 vendored bwrap |
| vendored bwrap | 编译时嵌入的 bubblewrap | 报错（必须可用） |

### 内核特性依赖

- **User Namespaces** (`CONFIG_USER_NS`): `--unshare-user` 需要
- **PID Namespaces** (`CONFIG_PID_NS`): `--unshare-pid` 需要
- **Network Namespaces** (`CONFIG_NET_NS`): `--unshare-net` 需要
- **Seccomp** (`CONFIG_SECCOMP`): seccomp 过滤器需要
- **Landlock** (`CONFIG_SECURITY_LANDLOCK`): legacy 路径需要

### 与 core crate 的交互

```
codex-core → ExecParams → process_exec_tool_call()
    ↓
codex-linux-sandbox 可执行文件
    ↓
Bubblewrap → 新的命名空间 → 用户命令
```

## 风险、边界与改进建议

### 风险点

1. **容器环境兼容性**:
   - 某些容器环境禁止 `--proc /proc` 或用户命名空间
   - 文档提到有预检和回退机制，但仍可能失败

2. **权限要求**:
   - bubblewrap 可能需要 setuid root 或 CAP_SYS_ADMIN
   - 在严格限制的环境中可能无法正常工作

3. **命名空间开销**:
   - 每个沙箱命令都创建新的 PID/用户/网络命名空间
   - 频繁执行可能有性能影响

### 边界条件

| 场景 | 行为 |
|------|------|
| 系统 bwrap 存在 | 优先使用系统版本 |
| 系统 bwrap 缺失 | 使用 vendored，显示警告 |
| `--proc` 被拒绝 | 自动回退到 `--no-proc` |
| 可写根包含符号链接 | 在符号链接上挂载 `/dev/null` 阻止替换 |
| 托管代理模式 | 阻止 AF_UNIX/socketpair 创建 |

### 改进建议

1. **文档增强**:
   - 添加故障排除指南，说明常见容器环境问题的解决方法
   - 提供检查清单帮助用户验证沙箱是否正确工作

2. **可观测性**:
   - 考虑添加详细模式输出实际使用的 bubblewrap 参数
   - 记录策略转换过程便于调试

3. **配置灵活性**:
   - 考虑允许用户自定义 bubblewrap 路径
   - 添加选项强制使用 vendored bwrap（忽略系统版本）

4. **测试覆盖**:
   - 文档提到 "CLI surface still uses legacy names like `codex debug landlock`"
   - 建议更新 CLI 名称以反映当前 bubblewrap 为主的实现
