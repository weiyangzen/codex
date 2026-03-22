# shell-tool-mcp 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`shell-tool-mcp` 是 Codex 项目中一个**实验性的 MCP (Model Context Protocol) 服务器**，其核心职责是：

1. **提供受控的 Shell 执行环境**：通过 MCP 协议向 AI Agent 暴露 `shell` 工具，允许执行 shell 命令
2. **拦截 execve 系统调用**：通过补丁过的 Bash/Zsh 二进制文件，拦截所有子进程创建请求
3. **执行权限控制**：根据 `.rules` 配置文件决定命令是允许执行、需要人工确认，还是禁止执行
4. **沙箱逃逸（Escalation）**：对于需要更高权限的命令，支持在沙箱外以非特权方式执行

### 1.2 解决的问题

传统 shell 执行面临的安全问题：
- **PATH 欺骗**：`ls` 可能执行的是 `/malicious/ls` 而非 `/bin/ls`
- **别名劫持**：shell 别名或函数可能劫持标准命令
- **权限边界模糊**：难以区分哪些命令应该在沙箱内/外执行

`shell-tool-mcp` 通过在 `execve(2)` 层面拦截，**总是知道被调用程序的完整绝对路径**，从而提供更强的安全保证。

### 1.3 与主项目的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex CLI / TUI                          │
├─────────────────────────────────────────────────────────────────┤
│  codex-rs/core/src/mcp_connection_manager.rs (MCP 客户端管理)    │
├─────────────────────────────────────────────────────────────────┤
│  shell-tool-mcp (MCP 服务器 - Node.js 包装器)                   │
├─────────────────────────────────────────────────────────────────┤
│  codex-rs/shell-escalation (Rust - execve 拦截协议实现)          │
├─────────────────────────────────────────────────────────────────┤
│  Patched Bash/Zsh (C - 打补丁的 shell 二进制)                   │
└─────────────────────────────────────────────────────────────────┘
```

**注意**：当前 `shell-tool-mcp` 包**仅发布 shell 二进制文件**，不包含 Rust MCP 服务器二进制文件。

---

## 2. 功能点目的

### 2.1 核心功能模块

| 功能模块 | 目的 | 实现位置 |
|---------|------|---------|
| **平台检测** | 根据 OS/架构选择正确的二进制 | `src/platform.ts` |
| **Bash 选择** | 根据 Linux 发行版/macOS 版本选择兼容的 Bash | `src/bashSelection.ts` |
| **OS 信息解析** | 解析 `/etc/os-release` 获取 Linux 发行版信息 | `src/osRelease.ts` |
| **入口程序** | 报告选中的 Bash 二进制路径 | `src/index.ts` |

### 2.2 支持的系统矩阵

**Linux 发行版支持** (`src/constants.ts`):
```typescript
// 按优先级排序
- ubuntu-24.04 (ids: ["ubuntu"], versions: ["24.04"])
- ubuntu-22.04 (ids: ["ubuntu"], versions: ["22.04"])
- ubuntu-20.04 (ids: ["ubuntu"], versions: ["20.04"])
- debian-12   (ids: ["debian"], versions: ["12"])
- debian-11   (ids: ["debian"], versions: ["11"])
- centos-9    (ids: ["centos", "rhel", "rocky", "almalinux"], versions: ["9"])
```

**macOS 版本支持**:
```typescript
- macos-15 (minDarwin: 24)  // Darwin 24.x = macOS 15.x
- macos-14 (minDarwin: 23)
- macos-13 (minDarwin: 22)
```

**目标架构**:
```typescript
- x86_64-unknown-linux-musl
- aarch64-unknown-linux-musl
- x86_64-apple-darwin
- aarch64-apple-darwin
```

### 2.3 .rules 配置支持

用户通过 `.rules` 文件定义命令处理规则：

| decision 值 | 行为 |
|------------|------|
| `allow` | 命令被**提升**到沙箱外执行 |
| `prompt` | 通过 MCP elicitation 请求人工确认，确认后在沙箱外执行 |
| `forbidden` | 命令被拒绝，返回 exit code 1 和错误信息到 stderr |

未匹配规则的命令在沙箱内按原样执行。

---

## 3. 具体技术实现

### 3.1 数据结构与类型

**文件**: `src/types.ts`

```typescript
// Linux Bash 变体定义
export type LinuxBashVariant = {
  name: string;        // 如 "ubuntu-24.04"
  ids: Array<string>;  // 匹配的 ID，如 ["ubuntu"]
  versions: Array<string>; // 匹配的版本前缀，如 ["24.04"]
};

// macOS Bash 变体定义
export type DarwinBashVariant = {
  name: string;        // 如 "macos-15"
  minDarwin: number;   // 最小 Darwin 主版本号
};

// /etc/os-release 解析结果
export type OsReleaseInfo = {
  id: string;          // 如 "ubuntu"
  idLike: Array<string>; // 如 ["debian"]
  versionId: string;   // 如 "24.04"
};

// Bash 选择结果
export type BashSelection = {
  path: string;        // 完整路径，如 "/vendor/x86_64-unknown-linux-musl/bash/ubuntu-24.04/bash"
  variant: string;     // 变体名称
};
```

### 3.2 平台检测算法

**文件**: `src/platform.ts`

```typescript
export function resolveTargetTriple(
  platform: NodeJS.Platform,
  arch: NodeJS.Architecture,
): string {
  if (platform === "linux") {
    if (arch === "x64") return "x86_64-unknown-linux-musl";
    if (arch === "arm64") return "aarch64-unknown-linux-musl";
  } else if (platform === "darwin") {
    if (arch === "x64") return "x86_64-apple-darwin";
    if (arch === "arm64") return "aarch64-apple-darwin";
  }
  throw new Error(`Unsupported platform: ${platform} (${arch})`);
}
```

### 3.3 Bash 选择算法

**文件**: `src/bashSelection.ts`

**Linux 选择逻辑** (`selectLinuxBash`):
1. 遍历所有 `LINUX_BASH_VARIANTS`
2. 检查 `id` 匹配：`variant.ids.includes(info.id)` 或 `variant.ids.some(id => info.idLike.includes(id))`
3. 检查版本匹配：`versionId.startsWith(prefix)`
4. **优先选择**：版本完全匹配的变体
5. **降级选择**：ID 匹配但版本不匹配的变体
6. **最终回退**：第一个可用变体 (`LINUX_BASH_VARIANTS[0]`)

**macOS 选择逻辑** (`selectDarwinBash`):
1. 解析 Darwin 版本：`darwinMajor = parseInt(darwinRelease.split(".")[0])`
2. 找到第一个满足 `darwinMajor >= variant.minDarwin` 的变体
3. 无匹配时回退到第一个变体

**统一入口** (`resolveBashPath`):
```typescript
export function resolveBashPath(
  targetRoot: string,
  platform: NodeJS.Platform,
  darwinRelease = os.release(),
  osInfo: OsReleaseInfo | null = null,
): BashSelection {
  const bashRoot = path.join(targetRoot, "bash");
  if (platform === "linux") {
    if (!osInfo) throw new Error("Linux OS info is required");
    return selectLinuxBash(bashRoot, osInfo);
  }
  if (platform === "darwin") {
    return selectDarwinBash(bashRoot, darwinRelease);
  }
  throw new Error(`Unsupported platform: ${platform}`);
}
```

### 3.4 OS Release 解析

**文件**: `src/osRelease.ts`

```typescript
export function parseOsRelease(contents: string): OsReleaseInfo {
  const lines = contents.split("\n").filter(Boolean);
  const info: Record<string, string> = {};
  for (const line of lines) {
    const [rawKey, rawValue] = line.split("=", 2);
    if (!rawKey || rawValue === undefined) continue;
    const key = rawKey.toLowerCase();
    const value = rawValue.replace(/^"/, "").replace(/"$/, ""); // 去除引号
    info[key] = value;
  }
  // 解析 ID_LIKE 为数组
  const idLike = (info.id_like || "")
    .split(/\s+/)
    .map(item => item.trim().toLowerCase())
    .filter(Boolean);
  return {
    id: (info.id || "").toLowerCase(),
    idLike,
    versionId: info.version_id || "",
  };
}
```

### 3.5 EXEC_WRAPPER 补丁机制

**文件**: `patches/bash-exec-wrapper.patch`

在 Bash 的 `shell_execve` 函数中注入拦截逻辑：

```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    char *orig_command = command;
    larray = strvec_len (args);
    // 参数数组前移，为 wrapper 和原命令腾出位置
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;      // wrapper 程序
    args[1] = orig_command;      // 原命令
    command = exec_wrapper;      // 改为执行 wrapper
}
// 继续执行 execve
execve (command, args, env);
```

**Zsh 补丁** (`patches/zsh-exec-wrapper.patch`) 原理类似，在 `zexecve` 函数中实现。

### 3.6 Shell Escalation 协议 (Rust 层)

**文件**: `codex-rs/shell-escalation/src/unix/`

**核心协议流程**:

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────────┐
│ Command │     │ Server  │     │ Shell   │     │ Exec Wrapper│
└────┬────┘     └────┬────┘     └────┬────┘     └──────┬──────┘
     │               │               │                 │
     │               │─── 启动 shell ──>│                 │
     │               │               │                 │
     │               │               │── exec() ──────>│
     │               │               │                 │
     │               │<── EscalateReq ──│                 │
     │               │               │                 │
     │               │── EscalateResp ─>│                 │
     │               │               │                 │
     │               │<──────── fds ───│                 │
     │               │               │                 │
     │<── 执行结果 ──│               │                 │
     │               │               │                 │
```

**关键协议消息** (`escalate_protocol.rs`):

```rust
// 环境变量
pub const ESCALATE_SOCKET_ENV_VAR: &str = "CODEX_ESCALATE_SOCKET";
pub const EXEC_WRAPPER_ENV_VAR: &str = "EXEC_WRAPPER";
pub const LEGACY_BASH_EXEC_WRAPPER_ENV_VAR: &str = "BASH_EXEC_WRAPPER";

// 客户端 -> 服务器的请求
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径
    pub argv: Vec<String>,       // 参数数组
    pub workdir: AbsolutePathBuf,
    pub env: HashMap<String, String>,
}

// 服务器 -> 客户端的响应
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,        // 直接执行
    Escalate,   // 提升到沙箱外执行
    Deny { reason: Option<String> }, // 拒绝执行
}

// 提升执行时的决策
pub enum EscalationDecision {
    Run,
    Escalate(EscalationExecution),
    Deny { reason: Option<String> },
}

pub enum EscalationExecution {
    Unsandboxed,      // 无沙箱执行
    TurnDefault,      // 使用当前 turn 的默认沙箱
    Permissions(EscalationPermissions), // 指定权限
}
```

**Socket 通信** (`socket.rs`):
- 使用 Unix Domain Socket (SOCK_STREAM 和 SOCK_DGRAM)
- 支持通过 SCM_RIGHTS 传递文件描述符
- 帧格式：`[4字节长度前缀][JSON 负载]`
- 最大消息大小：8192 字节
- 最大 FD 数：16 个/消息

### 3.7 MCP Sandbox State 能力

**文件**: `codex-rs/core/src/mcp_connection_manager.rs`

`shell-tool-mcp` 声明的 MCP 能力：

```json
{
  "capabilities": {
    "experimental": {
      "codex/sandbox-state": {
        "version": "1.0.0"
      }
    }
  }
}
```

支持的方法：`codex/sandbox-state/update`

```rust
pub const MCP_SANDBOX_STATE_CAPABILITY: &str = "codex/sandbox-state";
pub const MCP_SANDBOX_STATE_METHOD: &str = "codex/sandbox-state/update";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SandboxState {
    pub sandbox_policy: SandboxPolicy,
    pub codex_linux_sandbox_exe: Option<PathBuf>,
    pub sandbox_cwd: PathBuf,
    #[serde(default)]
    pub use_legacy_landlock: bool,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 shell-tool-mcp 包结构

```
shell-tool-mcp/
├── README.md                          # 使用文档
├── package.json                       # npm 包配置 (@openai/codex-shell-tool-mcp)
├── tsconfig.json                      # TypeScript 配置
├── tsup.config.ts                     # 构建配置 (输出到 bin/mcp-server)
├── jest.config.cjs                    # 测试配置
├── .gitignore                         # 忽略 bin/ 和 node_modules/
├── patches/
│   ├── bash-exec-wrapper.patch       # Bash EXEC_WRAPPER 补丁
│   └── zsh-exec-wrapper.patch        # Zsh EXEC_WRAPPER 补丁
├── src/
│   ├── index.ts                       # 入口：报告选中的 Bash 路径
│   ├── types.ts                       # TypeScript 类型定义
│   ├── constants.ts                   # Linux/Darwin Bash 变体常量
│   ├── platform.ts                    # 目标三元组解析
│   ├── bashSelection.ts               # Bash 选择逻辑
│   └── osRelease.ts                   # /etc/os-release 解析
└── tests/
    ├── bashSelection.test.ts          # Bash 选择测试
    └── osRelease.test.ts              # OS 信息解析测试
```

### 4.2 相关 Rust 代码路径

```
codex-rs/
├── shell-escalation/                  # execve 拦截协议实现
│   ├── README.md
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── bin/
│       │   └── main_execve_wrapper.rs # codex-execve-wrapper 二进制入口
│       └── unix/
│           ├── mod.rs                 # 模块文档和导出
│           ├── escalate_protocol.rs   # 协议消息定义
│           ├── escalate_server.rs     # 服务器实现
│           ├── escalate_client.rs     # 客户端实现 (wrapper)
│           ├── escalation_policy.rs   # 策略 trait
│           ├── execve_wrapper.rs      # wrapper CLI
│           ├── socket.rs              # Socket 通信实现
│           └── stopwatch.rs           # 超时管理
│
└── core/src/
    ├── mcp_connection_manager.rs      # MCP 连接管理 (sandbox-state)
    └── tools/runtimes/
        ├── shell.rs                   # Shell 运行时
        └── shell/
            ├── unix_escalation.rs     # Unix 提升逻辑
            └── zsh_fork_backend.rs    # Zsh fork 后端
```

### 4.3 关键代码引用

| 功能 | 文件路径 | 行号范围 |
|-----|---------|---------|
| 平台三元组解析 | `src/platform.ts` | 1-21 |
| Linux Bash 选择 | `src/bashSelection.ts` | 10-66 |
| macOS Bash 选择 | `src/bashSelection.ts` | 68-95 |
| Bash 选择统一入口 | `src/bashSelection.ts` | 97-115 |
| OS Release 解析 | `src/osRelease.ts` | 4-34 |
| 程序入口 | `src/index.ts` | 9-23 |
| Bash 补丁 | `patches/bash-exec-wrapper.patch` | 全文件 |
| Zsh 补丁 | `patches/zsh-exec-wrapper.patch` | 全文件 |
| 协议常量 | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 10-18 |
| EscalateRequest | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 20-31 |
| EscalateResponse | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 34-37 |
| EscalationDecision | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 40-55 |
| EscalateServer | `codex-rs/shell-escalation/src/unix/escalate_server.rs` | 128-225 |
| EscalationSession | `codex-rs/shell-escalation/src/unix/escalate_server.rs` | 96-126 |
| 客户端 wrapper | `codex-rs/shell-escalation/src/unix/escalate_client.rs` | 37-130 |
| Socket 实现 | `codex-rs/shell-escalation/src/unix/socket.rs` | 全文件 |
| MCP sandbox-state | `codex-rs/core/src/mcp_connection_manager.rs` | 600-614 |

---

## 5. 依赖与外部交互

### 5.1 构建依赖

**TypeScript/Node.js 依赖** (`package.json`):
```json
{
  "devDependencies": {
    "@types/jest": "^29.5.14",
    "@types/node": "^20.19.18",
    "jest": "^29.7.0",
    "prettier": "^3.6.2",
    "ts-jest": "^29.3.4",
    "tsup": "^8.5.0",
    "typescript": "^5.9.2"
  }
}
```

### 5.2 运行时依赖

**Node.js 内置模块**:
- `node:os` - 平台检测 (`process.platform`, `process.arch`, `os.release()`)
- `node:path` - 路径处理
- `node:fs` - 文件读取 (`readFileSync`)

**外部二进制依赖** (通过 npm 包分发):
- `vendor/<target-triple>/bash/<variant>/bash` - 补丁过的 Bash
- `vendor/<target-triple>/bash/<variant>/zsh` - 补丁过的 Zsh

### 5.3 与 Rust 代码的交互

**环境变量传递**:
```bash
# shell-tool-mcp 设置
EXEC_WRAPPER=<path-to-codex-execve-wrapper>
BASH_EXEC_WRAPPER=<path-to-codex-execve-wrapper>  # 兼容旧版本
CODEX_ESCALATE_SOCKET=<fd-number>

# shell 启动时会读取这些变量，在 exec() 时调用 wrapper
```

**MCP 协议交互**:
```
Codex CLI (MCP Client) <--MCP Protocol--> shell-tool-mcp (MCP Server)
                                                    │
                                                    │ (内部调用)
                                                    ▼
                                          codex-execve-wrapper
                                                    │
                                                    │ (Unix Socket)
                                                    ▼
                                          codex-shell-escalation
```

### 5.4 配置集成

**Codex CLI 配置** (`~/.codex/config.toml`):
```toml
[features]
shell_tool = false  # 禁用默认 shell 工具

[mcp_servers.shell-tool]
command = "npx"
args = ["-y", "@openai/codex-shell-tool-mcp"]
```

**命令行使用**:
```bash
codex --disable shell_tool \
  --config 'mcp_servers.bash={command = "npx", args = ["-y", "@openai/codex-shell-tool-mcp"]}'
```

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 实验性状态
- **风险**：API 和实现可能不兼容地变化
- **缓解**：README 明确标注实验性，要求 CLI 版本与 MCP 服务器版本匹配

#### 6.1.2 平台支持限制
- **Linux**: 仅支持特定发行版和版本（Ubuntu 20.04-24.04, Debian 11-12, CentOS/RHEL 9 系列）
- **macOS**: 仅支持 13-15 版本
- **风险**：不支持的系统会抛出错误或回退到不理想的变体

#### 6.1.3 回退机制风险
```typescript
// bashSelection.ts:54-60
const fallback = LINUX_BASH_VARIANTS[0];  // ubuntu-24.04
if (fallback) {
  return {
    path: path.join(bashRoot, fallback.name, "bash"),
    variant: fallback.name,
  };
}
```
- **风险**：当系统完全无法识别时，回退到最新 Ubuntu 变体可能导致 glibc 兼容性问题
- **建议**：增加更严格的兼容性检查或提供更明确的错误信息

#### 6.1.4 版本匹配精度
```typescript
// bashSelection.ts:26-29
const matchesVersion = Boolean(
  versionId && variant.versions.some((prefix) => versionId.startsWith(prefix))
);
```
- **限制**：使用字符串前缀匹配，可能无法处理复杂的版本号（如 "24.04.1-LTS"）

#### 6.1.5 OS Release 解析鲁棒性
```typescript
// osRelease.ts:13
const value = rawValue.replace(/^"/, "").replace(/"$/, "");
```
- **风险**：简单的引号替换可能无法处理嵌套引号或转义字符
- **示例**：`VALUE="say \"hello\""` 会被错误解析

#### 6.1.6 Socket FD 继承
```rust
// escalate_server.rs:196
client_socket.set_cloexec(false)?;  // 允许跨 exec 继承
```
- **风险**：FD 泄漏到子进程，可能被恶意利用
- **缓解**：`after_spawn` 钩子确保 shell 启动后关闭父进程副本

### 6.2 测试覆盖

**现有测试** (`tests/`):
- `bashSelection.test.ts`: 2 个测试用例（Linux 精确匹配、回退；Darwin 兼容、回退）
- `osRelease.test.ts`: 3 个测试用例（基本解析、缺失字段、ID_LIKE 规范化）

**测试缺口**:
- 无集成测试验证完整的 shell -> wrapper -> escalation 流程
- 无测试覆盖错误路径（如无法读取 `/etc/os-release`）
- 无测试验证补丁后的 Bash 行为

### 6.3 改进建议

#### 6.3.1 增强平台检测
```typescript
// 建议：添加更详细的系统信息收集
export type SystemInfo = {
  targetTriple: string;
  platform: NodeJS.Platform;
  arch: NodeJS.Architecture;
  osRelease: string;
  osInfo: OsReleaseInfo | null;
  libcVersion?: string;  // 检测 musl vs glibc 版本
  kernelVersion?: string;
};
```

#### 6.3.2 改进版本匹配
```typescript
// 建议：使用语义化版本比较
import { compareVersions, validateVersion } from 'compare-versions';

const matchesVersion = variant.versions.some(v => 
  compareVersions(versionId, v) >= 0 && 
  compareVersions(versionId, nextVariantVersion(v)) < 0
);
```

#### 6.3.3 增强错误处理
```typescript
// 建议：提供更详细的诊断信息
export class BashSelectionError extends Error {
  constructor(
    message: string,
    public readonly systemInfo: SystemInfo,
    public readonly attemptedVariants: string[],
    public readonly suggestion?: string
  ) {
    super(message);
  }
}
```

#### 6.3.4 缓存机制
- 当前每次调用都重新解析 OS 信息
- 建议：添加简单的内存缓存，避免重复读取 `/etc/os-release`

#### 6.3.5 与 Rust 层的 tighter 集成
- 当前 `shell-tool-mcp` 仅作为 Bash 选择器
- 建议：将 Rust MCP 服务器二进制也打包到 npm 包中，提供完整的 MCP 服务器功能

#### 6.3.6 文档改进
- 添加架构图说明完整的数据流
- 添加 `.rules` 配置示例和最佳实践
- 添加故障排除指南

### 6.4 安全考虑

| 风险点 | 当前状态 | 建议 |
|-------|---------|------|
| execve wrapper 路径注入 | 使用绝对路径 | 验证路径在白名单内 |
| Socket FD 泄漏 | `cloexec(false)` 后及时关闭 | 使用 `close_range` 或 `fcntl` 确保清理 |
| 环境变量污染 | 过滤敏感变量 | 建立明确的环境变量白名单 |
| 命令注入 | 通过 `.rules` 控制 | 添加默认拒绝策略 |

---

## 7. 总结

`shell-tool-mcp` 是 Codex 安全架构中的关键组件，通过以下机制提供受控的 shell 执行环境：

1. **智能平台适配**：根据 OS/架构/发行版选择最优的补丁 shell 二进制
2. **execve 拦截**：通过 `EXEC_WRAPPER` 机制在系统调用层面拦截命令执行
3. **策略驱动**：支持 `.rules` 配置定义命令处理策略（allow/prompt/forbidden）
4. **MCP 集成**：通过 MCP 协议与 Codex CLI 通信，支持 sandbox-state 能力

该组件目前处于实验阶段，主要用于分发补丁过的 shell 二进制文件，核心的 MCP 服务器逻辑仍由 Rust 代码 (`codex-shell-escalation`) 实现。
