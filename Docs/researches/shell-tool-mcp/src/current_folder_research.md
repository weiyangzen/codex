# shell-tool-mcp/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`shell-tool-mcp/src` 是 `@openai/codex-shell-tool-mcp` npm 包的核心 TypeScript 源码目录，负责**平台适配的 Bash 二进制文件选择逻辑**。该包是 Codex CLI 的 MCP (Model Context Protocol) 服务器组件，提供带沙箱拦截功能的 shell 执行能力。

### 1.2 核心职责

1. **平台检测与目标三元组解析**：根据 Node.js 的 `process.platform` 和 `process.arch` 确定目标平台三元组（如 `x86_64-unknown-linux-musl`）
2. **Linux 发行版识别**：解析 `/etc/os-release` 文件获取 Linux 发行版信息（ID、版本、衍生关系）
3. **Bash 变体智能选择**：根据平台和发行版信息，从预编译的 Bash 二进制文件中选择最合适的版本
4. **入口程序**：提供 CLI 入口点，输出选定的 Bash 路径供上层调用

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────────┐
│                     Codex CLI / MCP Server                       │
├─────────────────────────────────────────────────────────────────┤
│  codex-cli/bin/codex.js  │  codex-rs/mcp-server/...             │
│  (Node.js 启动器)         │  (Rust MCP 实现)                      │
├─────────────────────────────────────────────────────────────────┤
│  @openai/codex-shell-tool-mcp                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ shell-tool-mcp/src/                                         ││
│  │  - index.ts        (CLI 入口)                               ││
│  │  - platform.ts     (目标平台解析)                            ││
│  │  - osRelease.ts    (OS 信息读取)                            ││
│  │  - bashSelection.ts (Bash 变体选择)                         ││
│  │  - constants.ts    (支持的变体定义)                         ││
│  │  - types.ts        (类型定义)                               ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│  vendor/ 目录 (预编译二进制文件)                                  │
│  ├── x86_64-unknown-linux-musl/bash/ubuntu-24.04/bash           │
│  ├── aarch64-apple-darwin/bash/macos-15/bash                    │
│  └── ...                                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 平台适配 (platform.ts)

**目的**：将 Node.js 的运行时平台信息映射到 Rust 风格的 target triple，用于定位 vendor 目录中的预编译二进制文件。

**支持的矩阵**：
| Node.js Platform | Node.js Arch | Target Triple |
|-----------------|--------------|---------------|
| linux | x64 | x86_64-unknown-linux-musl |
| linux | arm64 | aarch64-unknown-linux-musl |
| darwin | x64 | x86_64-apple-darwin |
| darwin | arm64 | aarch64-apple-darwin |

### 2.2 OS 发行版识别 (osRelease.ts)

**目的**：在 Linux 系统上精确识别发行版和版本，确保选择兼容的 Bash 二进制文件（不同 glibc 版本的二进制文件不兼容）。

**解析逻辑**：
- 读取 `/etc/os-release` 文件（systemd 标准）
- 提取 `ID`, `ID_LIKE`, `VERSION_ID` 字段
- 处理带引号的值（如 `ID="ubuntu"`）
- 将 `ID_LIKE` 按空白字符分割为数组

### 2.3 Bash 变体选择 (bashSelection.ts)

**目的**：实现智能的 Bash 二进制文件选择策略，平衡**精确匹配**和**兼容性回退**。

**Linux 选择策略**（优先级从高到低）：
1. **版本精确匹配**：发行版 ID + 版本前缀都匹配（如 Ubuntu 24.04 → ubuntu-24.04）
2. **发行版回退**：仅 ID 匹配，使用第一个可用版本
3. **全局回退**：使用 `LINUX_BASH_VARIANTS[0]`（当前为 ubuntu-24.04）

**macOS 选择策略**：
- 根据 Darwin 内核主版本号选择（Darwin 24+ → macos-15）
- 向下兼容回退到最旧支持的版本

### 2.4 支持的 Bash 变体 (constants.ts)

**Linux 变体**（按优先级排序）：
| 变体名称 | 匹配的发行版 ID | 版本前缀 |
|---------|----------------|---------|
| ubuntu-24.04 | ubuntu | 24.04 |
| ubuntu-22.04 | ubuntu | 22.04 |
| ubuntu-20.04 | ubuntu | 20.04 |
| debian-12 | debian | 12 |
| debian-11 | debian | 11 |
| centos-9 | centos, rhel, rocky, almalinux | 9 |

**macOS 变体**：
| 变体名称 | 最低 Darwin 版本 |
|---------|-----------------|
| macos-15 | 24 (macOS 15.x) |
| macos-14 | 23 (macOS 14.x) |
| macos-13 | 22 (macOS 13.x) |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 主入口流程 (index.ts)

```typescript
async function main(): Promise<void> {
  // 1. 解析目标平台三元组
  const targetTriple = resolveTargetTriple(process.platform, process.arch);
  
  // 2. 构建 vendor 目录路径
  const vendorRoot = path.resolve(__dirname, "..", "vendor");
  const targetRoot = path.join(vendorRoot, targetTriple);
  
  // 3. 读取 OS 信息（仅 Linux）
  const osInfo = process.platform === "linux" ? readOsRelease() : null;
  
  // 4. 解析 Bash 路径
  const { path: bashPath } = resolveBashPath(
    targetRoot,
    process.platform,
    os.release(),
    osInfo,
  );
  
  // 5. 输出结果
  console.log(`Platform Bash is: ${bashPath}`);
}
```

#### 3.1.2 Linux Bash 选择算法 (bashSelection.ts)

```typescript
export function selectLinuxBash(bashRoot: string, info: OsReleaseInfo): BashSelection {
  // 阶段 1：收集候选变体
  const candidates = [];
  for (const variant of LINUX_BASH_VARIANTS) {
    // 检查 ID 匹配（直接匹配或 id_like 包含）
    const matchesId = variant.ids.includes(info.id) ||
                      variant.ids.some(id => info.idLike.includes(id));
    if (!matchesId) continue;
    
    // 检查版本前缀匹配
    const matchesVersion = versionId &&
      variant.versions.some(prefix => versionId.startsWith(prefix));
    
    candidates.push({ variant, matchesVersion });
  }

  // 阶段 2：优先选择版本匹配的
  const preferred = candidates.find(item => item.matchesVersion)?.variant;
  if (preferred) return { path: join(bashRoot, preferred.name, "bash"), variant: preferred.name };

  // 阶段 3：回退到发行版匹配
  const fallbackMatch = candidates.find(item => item.variant)?.variant;
  if (fallbackMatch) return { path: join(bashRoot, fallbackMatch.name, "bash"), variant: fallbackMatch.name };

  // 阶段 4：全局回退
  const fallback = LINUX_BASH_VARIANTS[0];
  return { path: join(bashRoot, fallback.name, "bash"), variant: fallback.name };
}
```

#### 3.1.3 OS Release 解析算法 (osRelease.ts)

```typescript
export function parseOsRelease(contents: string): OsReleaseInfo {
  const lines = contents.split("\n").filter(Boolean);
  const info: Record<string, string> = {};
  
  for (const line of lines) {
    const [rawKey, rawValue] = line.split("=", 2);
    if (!rawKey || rawValue === undefined) continue;
    
    const key = rawKey.toLowerCase();
    // 去除首尾的引号
    const value = rawValue.replace(/^"/, "").replace(/"$/, "");
    info[key] = value;
  }
  
  // 处理 ID_LIKE：按空白分割、小写、去空
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

### 3.2 数据结构

#### 3.2.1 核心类型定义 (types.ts)

```typescript
// Linux Bash 变体定义
export type LinuxBashVariant = {
  name: string;        // 如 "ubuntu-24.04"
  ids: Array<string>;  // 匹配的发行版 ID，如 ["ubuntu"]
  versions: Array<string>; // 版本前缀，如 ["24.04"]
};

// macOS Bash 变体定义
export type DarwinBashVariant = {
  name: string;        // 如 "macos-15"
  minDarwin: number;   // 最低 Darwin 主版本号
};

// OS 发行版信息
export type OsReleaseInfo = {
  id: string;          // 发行版 ID，如 "ubuntu"
  idLike: Array<string>; // 衍生关系，如 ["debian"]
  versionId: string;   // 版本号，如 "24.04"
};

// Bash 选择结果
export type BashSelection = {
  path: string;        // 完整路径，如 "/vendor/x86_64.../bash/ubuntu-24.04/bash"
  variant: string;     // 变体名称，如 "ubuntu-24.04"
};
```

### 3.3 协议与命令

#### 3.3.1 EXEC_WRAPPER 机制

`shell-tool-mcp` 提供的 Bash 二进制文件是经过**补丁修改**的特殊版本，支持 `EXEC_WRAPPER` 环境变量拦截机制：

**补丁原理**（`patches/bash-exec-wrapper.patch`）：
```c
// 在 shell_execve 函数中插入拦截逻辑
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace(*exec_wrapper)) {
  // 将原命令参数后移，插入 wrapper 路径
  memmove(args + 2, args, (++larray) * sizeof(char *));
  args[0] = exec_wrapper;  // wrapper 可执行文件
  args[1] = orig_command;  // 原命令路径
  command = exec_wrapper;
}
// 执行 wrapper，由 wrapper 决定是否允许/升级/拒绝执行
execve(command, args, env);
```

**执行流程**：
```
用户输入命令 → Bash 解析 → execve() 调用
                              ↓
                    [EXEC_WRAPPER 拦截]
                              ↓
                    codex-execve-wrapper (Rust)
                              ↓
                    通过 CODEX_ESCALATE_SOCKET 发送 EscalateRequest
                              ↓
                    codex-rs/shell-escalation EscalateServer
                              ↓
                    根据策略决定：
                    - Run: 在沙箱内执行
                    - Escalate: 提升到沙箱外执行
                    - Deny: 拒绝执行
```

#### 3.3.2 Escalation 协议

**环境变量**：
- `CODEX_ESCALATE_SOCKET`：Unix domain socket 文件描述符，用于 wrapper 与 server 通信
- `EXEC_WRAPPER` / `BASH_EXEC_WRAPPER`：execve wrapper 可执行文件路径

**消息类型**（定义在 `codex-rs/shell-escalation/src/unix/escalate_protocol.rs`）：

```rust
// Client → Server: 请求执行决策
pub struct EscalateRequest {
    pub file: PathBuf,        // 被拦截的可执行文件路径
    pub argv: Vec<String>,    // 参数列表
    pub workdir: AbsolutePathBuf,
    pub env: HashMap<String, String>,
}

// Server → Client: 执行决策响应
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,      // 在沙箱内直接执行
    Escalate, // 需要提升到沙箱外
    Deny { reason: Option<String> }, // 拒绝执行
}

// Client → Server: 传递文件描述符（用于 Escalate 情况）
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,  // stdin/stdout/stderr 的 FD 编号
}

// Server → Client: 执行结果
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 职责 | 关键导出 |
|-----|------|---------|
| `index.ts` | CLI 入口 | `main()` |
| `platform.ts` | 平台三元组解析 | `resolveTargetTriple(platform, arch)` |
| `osRelease.ts` | OS 发行版信息解析 | `readOsRelease(path?)`, `parseOsRelease(contents)` |
| `bashSelection.ts` | Bash 变体选择逻辑 | `resolveBashPath()`, `selectLinuxBash()`, `selectDarwinBash()` |
| `constants.ts` | 支持的变体定义 | `LINUX_BASH_VARIANTS`, `DARWIN_BASH_VARIANTS` |
| `types.ts` | TypeScript 类型定义 | `LinuxBashVariant`, `DarwinBashVariant`, `OsReleaseInfo`, `BashSelection` |

### 4.2 上游调用方

| 组件 | 路径 | 调用方式 |
|-----|------|---------|
| npm 包入口 | `shell-tool-mcp/package.json` | `"bin": { "mcp-server": "bin/mcp-server.js" }` |
| tsup 构建配置 | `shell-tool-mcp/tsup.config.ts` | `entry: { "mcp-server": "src/index.ts" }` |
| Codex CLI 测试 | `codex-rs/app-server/tests/suite/bash` | DotSlash 配置引用 npm 包 |

### 4.3 下游依赖（Rust 侧）

| 组件 | 路径 | 职责 |
|-----|------|------|
| shell-escalation | `codex-rs/shell-escalation/` | Unix shell 升级协议实现 |
| escalate_server | `codex-rs/shell-escalation/src/unix/escalate_server.rs` | Escalation 服务器 |
| escalate_client | `codex-rs/shell-escalation/src/unix/escalate_client.rs` | execve wrapper 客户端 |
| escalate_protocol | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 协议消息定义 |
| execve_wrapper | `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs` | wrapper 可执行文件入口 |

### 4.4 补丁文件

| 文件 | 说明 |
|-----|------|
| `patches/bash-exec-wrapper.patch` | Bash `execute_cmd.c` 的 EXEC_WRAPPER 补丁 |
| `patches/zsh-exec-wrapper.patch` | Zsh `Src/exec.c` 的 EXEC_WRAPPER 补丁 |

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

- **Node.js**: >= 18（package.json 中声明）
- **系统文件**: `/etc/os-release`（Linux 系统信息）
- **环境变量**: `process.platform`, `process.arch`, `os.release()`

### 5.2 构建依赖

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

### 5.3 外部交互

#### 5.3.1 与 vendor 目录的交互

```
shell-tool-mcp/vendor/
├── x86_64-unknown-linux-musl/
│   └── bash/
│       ├── ubuntu-24.04/bash
│       ├── ubuntu-22.04/bash
│       ├── ubuntu-20.04/bash
│       ├── debian-12/bash
│       ├── debian-11/bash
│       └── centos-9/bash
├── aarch64-unknown-linux-musl/
│   └── bash/...
├── x86_64-apple-darwin/
│   └── bash/...
└── aarch64-apple-darwin/
    └── bash/
        ├── macos-15/bash
        ├── macos-14/bash
        └── macos-13/bash
```

#### 5.3.2 与 Rust shell-escalation 的交互

```
┌─────────────────────────────────────────────────────────────┐
│                     Escalation Flow                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Bash (patched)                                          │
│     └── execve() 被拦截                                      │
│         └── EXEC_WRAPPER 环境变量指向                        │
│             codex-execve-wrapper (Rust 二进制)               │
│                                                              │
│  2. codex-execve-wrapper                                    │
│     └── 读取 CODEX_ESCALATE_SOCKET FD                        │
│         └── 发送 EscalateRequest                             │
│                                                              │
│  3. EscalateServer (在 codex-rs 中运行)                     │
│     └── 通过 EscalationPolicy 决定动作                       │
│         ├── Run → 返回 EscalateAction::Run                   │
│         ├── Escalate → 返回 EscalateAction::Escalate        │
│         └── Deny → 返回 EscalateAction::Deny                 │
│                                                              │
│  4. wrapper 根据响应执行                                     │
│     ├── Run → 直接 execve() 原命令                           │
│     ├── Escalate → 发送 FDs，等待 server 执行结果            │
│     └── Deny → 输出错误，退出码 1                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Linux 发行版覆盖不全

**风险**：当前仅支持 Ubuntu、Debian、CentOS/RHEL 系列。对于 Arch、Alpine、openSUSE 等发行版，会回退到 `ubuntu-24.04` 变体，可能因 glibc 版本不兼容导致二进制文件无法运行。

**缓解措施**：
- Ubuntu 24.04 使用较新的 glibc，向后兼容性较好
- 静态链接 musl 的 Rust 二进制与 glibc 链接的 Bash 组合使用

#### 6.1.2 macOS x86_64 支持缺失

**风险**：`DARWIN_BASH_VARIANTS` 定义了 macOS 13/14/15 的支持，但 `codex-rs/app-server/tests/suite/bash` 中的 DotSlash 配置注释说明 "macOS 13 builds (and therefore x86_64) were dropped"，意味着 x86_64 Mac 可能无法使用。

#### 6.1.3 OS Release 解析鲁棒性

**风险**：`parseOsRelease` 对 `/etc/os-release` 格式假设较简单：
- 仅处理简单的 `KEY="value"` 或 `KEY=value` 格式
- 不处理转义字符（如 `"value with \"quotes\""`）
- 不处理多行值

**实际影响**：现代发行版的 os-release 文件通常简单，风险较低。

#### 6.1.4 版本前缀匹配模糊性

**风险**：`versionId.startsWith(prefix)` 匹配可能导致误判：
- "24.04.1" 匹配 "24.04" ✓
- "24.04" 匹配 "24.0" ✗（但 "24.0" 不是有效版本前缀）

### 6.2 边界情况

#### 6.2.1 测试覆盖

| 测试文件 | 覆盖场景 |
|---------|---------|
| `tests/bashSelection.test.ts` | Linux 版本精确匹配、无匹配回退、Darwin 版本选择、Darwin 旧版本回退 |
| `tests/osRelease.test.ts` | 基本字段解析、缺失字段处理、id_like 多值解析 |

**未覆盖边界**：
- `/etc/os-release` 文件不存在时的行为（代码中有 try-catch 返回空对象）
- 版本号格式异常（如 "24.04.1-LTS"）
- 多个 id_like 值且指向不同变体时的优先级

#### 6.2.2 路径构造

```typescript
const vendorRoot = path.resolve(__dirname, "..", "vendor");
const targetRoot = path.join(vendorRoot, targetTriple);
const bashRoot = path.join(targetRoot, "bash");
const finalPath = path.join(bashRoot, variantName, "bash");
```

**边界**：假设 `__dirname` 是 `bin/` 目录（构建输出），且 `vendor/` 与 `bin/` 同级。

### 6.3 改进建议

#### 6.3.1 增加发行版支持

```typescript
// 建议添加的变体
{ name: "alpine-3.19", ids: ["alpine"], versions: ["3.19", "3.18"] },
{ name: "arch", ids: ["arch", "manjaro"], versions: [""] },  // 滚动发行版无版本
{ name: "opensuse-15", ids: ["opensuse-leap", "opensuse-tumbleweed"], versions: ["15"] },
```

#### 6.3.2 增强 OS Release 解析

- 使用更健壮的 INI 风格解析器
- 处理注释行（以 `#` 开头）
- 处理带引号值中的转义字符

#### 6.3.3 添加诊断日志

```typescript
// 建议增加调试输出
if (process.env.CODEX_SHELL_TOOL_DEBUG) {
  console.error(`[shell-tool-mcp] Platform: ${process.platform}`);
  console.error(`[shell-tool-mcp] OS Info: ${JSON.stringify(osInfo)}`);
  console.error(`[shell-tool-mcp] Selected variant: ${variant}`);
  console.error(`[shell-tool-mcp] Final path: ${bashPath}`);
}
```

#### 6.3.4 版本匹配算法优化

```typescript
// 建议：使用语义化版本比较替代字符串前缀匹配
import { compareVersions, satisfies } from 'compare-versions';

const matchesVersion = variant.versions.some(range => 
  satisfies(versionId, range)  // 支持 "^24.0.0" 或 ">=22.0.0 <24.0.0"
);
```

#### 6.3.5 运行时验证

```typescript
// 建议：验证选定的 Bash 可执行文件是否存在且可执行
import { access, constants } from 'node:fs/promises';

async function verifyBashPath(path: string): Promise<void> {
  try {
    await access(path, constants.X_OK);
  } catch {
    throw new Error(`Selected Bash binary not executable: ${path}`);
  }
}
```

#### 6.3.6 考虑添加 Zsh 支持

当前 `shell-tool-mcp` 仅处理 Bash，但 `codex-rs` 已支持 Zsh fork 模式。建议：
- 扩展目录结构支持 `vendor/{triple}/zsh/{variant}/zsh`
- 添加 `zshSelection.ts` 模块
- 统一 Bash/Zsh 选择逻辑

---

## 7. 附录

### 7.1 相关文档

- `shell-tool-mcp/README.md` - 包的使用说明和 MCP 协议细节
- `codex-rs/shell-escalation/README.md` - Rust 侧的 escalation 协议文档
- `codex-rs/docs/codex_mcp_interface.md` - MCP 接口规范

### 7.2 相关测试

- `shell-tool-mcp/tests/bashSelection.test.ts`
- `shell-tool-mcp/tests/osRelease.test.ts`
- `codex-rs/shell-escalation/src/unix/escalate_server.rs` (包含大量集成测试)

### 7.3 版本历史

- 当前版本：`0.0.0-dev`（开发中）
- 最新发布版本：`0.65.0`（与 codex-rs rust-v0.65.0 标签对应）
