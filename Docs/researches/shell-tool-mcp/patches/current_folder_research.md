# shell-tool-mcp/patches 目录深度研究报告

## 1. 场景与职责

### 1.1 目录定位

`shell-tool-mcp/patches/` 是 Codex 项目中用于存放 **Bash 和 Zsh 补丁文件** 的关键目录。这些补丁实现了 `EXEC_WRAPPER` 机制，是 Codex 沙箱安全架构的核心基础设施。

### 1.2 核心职责

该目录及其补丁文件承担以下关键职责：

1. **execve 系统调用拦截**：通过修改 Bash/Zsh 源码，在 `execve(2)` 调用点注入钩子，允许外部程序接管命令执行流程
2. **命令执行管控**：实现从沙箱内到沙箱外的命令执行决策委托机制
3. **安全策略执行**：支持基于 `.rules` 文件的命令允许/拒绝/提示策略
4. **权限升级通道**：为需要特权执行的命令提供受控的升级路径

### 1.3 使用场景

- **MCP Server 场景**：当 Codex CLI 使用 `@openai/codex-shell-tool-mcp` 作为 MCP 服务器时，通过补丁后的 Bash 执行命令
- **ZshFork 场景**：Codex Rust 核心使用 `shell-escalation` crate 通过补丁后的 Zsh 执行命令
- **命令安全审计**：拦截所有外部命令执行，获取绝对路径进行策略匹配

---

## 2. 功能点目的

### 2.1 Bash 补丁 (`bash-exec-wrapper.patch`)

**目的**：在 Bash 的 `shell_execve` 函数中注入 `EXEC_WRAPPER` 环境变量检查逻辑。

**解决的问题**：
- 传统 shell 无法知道最终执行的命令绝对路径（受 PATH、alias、function 影响）
- 无法在执行前进行细粒度的安全策略检查
- 无法区分沙箱内执行和沙箱外升级执行

**关键行为**：
```c
// 当 EXEC_WRAPPER 环境变量设置且非空时：
// 1. 保存原始命令
// 2. 将 args 数组后移两位
// 3. args[0] = exec_wrapper (包装器路径)
// 4. args[1] = orig_command (原始命令)
// 5. command = exec_wrapper (实际执行包装器)
```

### 2.2 Zsh 补丁 (`zsh-exec-wrapper.patch`)

**目的**：在 Zsh 的 `zexecve` 函数中实现相同的 `EXEC_WRAPPER` 机制。

**与 Bash 补丁的差异**：
- Zsh 使用 `unmetafy` 处理元字符
- 使用 `inblank()` 而非 `whitespace()` 检查空白字符
- 通过 `argv - 2` 方式重新构造参数数组

### 2.3 整体架构目标

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Codex Core    │────▶│  EscalateServer  │────▶│  Patched Shell  │
│  (Rust 代码)     │     │  (shell-escalation)│    │ (Bash/Zsh)      │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
         ▲                                                │
         │                                                ▼
         │                                        ┌─────────────────┐
         │                                        │  Exec Wrapper   │
         │                                        │ (codex-execve-  │
         │                                        │    wrapper)     │
         │                                        └────────┬────────┘
         │                                                │
         │    ┌───────────────────────────────────────────┘
         │    │
         │    ▼
         │  ┌─────────────────────────────────────────────────────────┐
         └──│  EscalateRequest ──▶ Policy Check ──▶ EscalateResponse   │
            │         │                                    │           │
            │         ▼                                    ▼           │
            │   ┌─────────┐    ┌──────────┐    ┌──────────┐           │
            │   │  Allow  │───▶│ Escalate │───▶│  Deny    │           │
            │   └─────────┘    └──────────┘    └──────────┘           │
            └─────────────────────────────────────────────────────────┘
```

---

## 3. 具体技术实现

### 3.1 Bash 补丁技术细节

**文件位置**：`shell-tool-mcp/patches/bash-exec-wrapper.patch`

**目标文件**：`execute_cmd.c` (Bash 源码)

**补丁逻辑**：
```c
// 在 shell_execve 函数开头注入
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
  {
    char *orig_command = command;
    larray = strvec_len (args);
    // 将 args 数组后移两位，为 wrapper 和原始命令腾出空间
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;    // 包装器路径
    args[1] = orig_command;    // 原始命令作为第一个参数
    command = exec_wrapper;    // 实际执行包装器
  }
```

**关键数据流**：
1. 用户输入：`ls -la`
2. Bash 解析后准备执行：`execve("/bin/ls", ["ls", "-la"], env)`
3. 补丁拦截后变为：`execve("/path/to/codex-execve-wrapper", ["/path/to/codex-execve-wrapper", "/bin/ls", "ls", "-la"], env)`
4. 包装器通过 `CODEX_ESCALATE_SOCKET` 与 EscalateServer 通信
5. 根据策略决定：直接执行、升级执行或拒绝

### 3.2 Zsh 补丁技术细节

**文件位置**：`shell-tool-mcp/patches/zsh-exec-wrapper.patch`

**目标文件**：`Src/exec.c` (Zsh 源码)

**补丁逻辑**：
```c
// 在 zexecve 函数中注入
char **exec_argv;
char *orig_pth = pth;
char *exec_wrapper;

// ... unmetafy 处理 ...

exec_argv = argv;
if ((exec_wrapper = getenv("EXEC_WRAPPER")) &&
    *exec_wrapper && !inblank(*exec_wrapper)) {
    exec_argv = argv - 2;           // 前移指针，腾出空间
    exec_argv[0] = exec_wrapper;    // 包装器路径
    exec_argv[1] = orig_pth;        // 原始程序路径
    pth = exec_wrapper;             // 实际执行包装器
}

winch_unblock();
execve(pth, exec_argv, newenvp);
pth = orig_pth;  // 恢复原始路径（用于错误处理）
```

### 3.3 环境变量协议

| 环境变量 | 说明 | 设置方 | 消费方 |
|---------|------|--------|--------|
| `EXEC_WRAPPER` | execve 包装器可执行文件路径 | EscalateServer | 补丁后的 Bash/Zsh |
| `BASH_EXEC_WRAPPER` | `EXEC_WRAPPER` 的兼容别名 | EscalateServer | 旧版本补丁 |
| `CODEX_ESCALATE_SOCKET` | Unix socket 文件描述符 | EscalateServer | execve-wrapper |

### 3.4 通信协议

**协议定义**：`codex-rs/shell-escalation/src/unix/escalate_protocol.rs`

**消息类型**：
```rust
// 客户端 (execve-wrapper) 发送
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径
    pub argv: Vec<String>,       // 参数列表
    pub workdir: AbsolutePathBuf,// 工作目录
    pub env: HashMap<String, String>, // 环境变量
}

// 服务器响应
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                        // 在沙箱内直接执行
    Escalate,                   // 升级到沙箱外执行
    Deny { reason: Option<String> }, // 拒绝执行
}
```

**文件描述符传递**：
- 使用 `SCM_RIGHTS` 控制消息传递 stdin/stdout/stderr
- 支持跨进程的文件描述符重定向

---

## 4. 关键代码路径与文件引用

### 4.1 补丁文件本身

| 文件 | 行数 | 说明 |
|------|------|------|
| `shell-tool-mcp/patches/bash-exec-wrapper.patch` | 24 | Bash execute_cmd.c 补丁 |
| `shell-tool-mcp/patches/zsh-exec-wrapper.patch` | 34 | Zsh exec.c 补丁 |

### 4.2 调用方（上游）

**MCP Server 层**：
- `shell-tool-mcp/src/index.ts` - 入口点，选择并输出 Bash 路径
- `shell-tool-mcp/src/bashSelection.ts` - Bash 版本选择逻辑
- `shell-tool-mcp/src/constants.ts` - 支持的 Linux/macOS 版本定义

**Rust Core 层**：
- `codex-rs/shell-escalation/src/unix/escalate_server.rs` - 升级服务器实现
- `codex-rs/shell-escalation/src/unix/escalate_client.rs` - 客户端（execve-wrapper）
- `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` - 协议定义
- `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` - 与 Core 集成

### 4.3 被调用方（下游）

**execve-wrapper 二进制**：
- `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs` - 入口点
- `codex-rs/shell-escalation/src/unix/execve_wrapper.rs` - CLI 解析

**实际命令执行**：
- `codex-rs/core/src/sandboxing/` - 沙箱执行实现
- `codex-rs/linux-sandbox/` - Linux 特定沙箱
- `codex-rs/macos-seatbelt/` - macOS Seatbelt 沙箱

### 4.4 配置与构建

**构建配置**：
- `shell-tool-mcp/package.json` - NPM 包配置
- `shell-tool-mcp/tsup.config.ts` - TypeScript 构建配置
- `codex-rs/shell-escalation/Cargo.toml` - Rust crate 配置

**测试**：
- `shell-tool-mcp/tests/bashSelection.test.ts` - Bash 选择测试
- `shell-tool-mcp/tests/osRelease.test.ts` - OS 检测测试
- `codex-rs/shell-escalation/src/unix/escalate_server.rs` (tests 模块) - 协议测试

### 4.5 文档

- `shell-tool-mcp/README.md` - 使用说明和架构概述
- `codex-rs/shell-escalation/README.md` - 补丁应用指南

---

## 5. 依赖与外部交互

### 5.1 编译时依赖

**Bash 编译**：
```bash
# 依赖包（Ubuntu/Debian）
# - build-essential
# - libncurses-dev
# - 其他 Bash 编译依赖

# 配置选项
./configure --without-bash-malloc
```

**Zsh 编译**：
```bash
# 依赖包
# - build-essential
# - libncursesw5-dev
# - 其他 Zsh 编译依赖
```

### 5.2 运行时依赖

**系统调用**：
- `execve(2)` - 程序执行
- `socketpair(2)` - 创建通信 socket
- `sendmsg/recvmsg` - 带文件描述符传递的消息通信

**环境依赖**：
- `/etc/os-release` - Linux 发行版检测
- `uname -r` - macOS 版本检测

### 5.3 上游依赖（谁使用这些补丁）

1. **OpenAI 内部构建系统**：构建多平台 Bash/Zsh 二进制分发包
2. **`@openai/codex-shell-tool-mcp` NPM 包**：包含预编译的补丁 shell
3. **Codex CLI 用户**：通过 MCP 配置启用补丁 shell

### 5.4 下游依赖（补丁依赖什么）

1. **`codex-execve-wrapper` 二进制**：补丁将执行转发给此程序
2. **`CODEX_ESCALATE_SOCKET` 环境变量**：必须设置有效的 socket fd
3. **EscalateServer**：必须在父进程中运行，监听 socket

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

**安全风险**：
1. **环境变量注入**：如果 `EXEC_WRAPPER` 被恶意设置，可能拦截所有命令执行
   - 缓解：补丁检查 `EXEC_WRAPPER` 是否以空白字符开头（防止某些注入攻击）
   
2. **Socket 欺骗**：如果 `CODEX_ESCALATE_SOCKET` 指向恶意 socket
   - 缓解：使用文件描述符而非路径，减少被篡改可能

**兼容性风险**：
1. **Bash/Zsh 版本漂移**：补丁基于特定版本，升级可能需要重新打补丁
   - Bash 基准版本：`a8a1c2fac029404d3f42cd39f5a20f24b6e4fe4b`
   - Zsh 版本未明确标注

2. **glibc 兼容性**：Linux 二进制需要针对不同 glibc 版本构建
   - 当前支持：Ubuntu 24.04/22.04/20.04, Debian 12/11, CentOS-like 9

### 6.2 边界情况

**参数数组边界**：
```c
// Bash 补丁
memmove (args + 2, args, (++larray) * sizeof (char *));
// 假设 args 数组有足够空间，但原始数组可能刚好填满
```

**环境变量长度**：
- `EXEC_WRAPPER` 路径长度无显式限制
- 过长的路径可能导致栈溢出（取决于 shell 的缓冲区分配）

**并发处理**：
- 每个 execve 调用创建独立的 socket 连接
- 服务器使用 `tokio::spawn` 并发处理多个请求

### 6.3 改进建议

**短期改进**：

1. **增加版本标记**：
   ```c
   // 在补丁中添加版本标识，便于调试
   #define CODEX_EXEC_WRAPPER_PATCH_VERSION "1.0.0"
   ```

2. **增强错误处理**：
   - 当 `EXEC_WRAPPER` 指向不存在的文件时，当前行为是 execve 失败
   - 建议添加明确的错误消息输出到 stderr

3. **改进参数数组安全检查**：
   ```c
   // 添加数组边界检查
   if (larray + 2 > args_alloc_size) {
       // 处理溢出情况
   }
   ```

**中期改进**：

1. **统一 Bash/Zsh 补丁逻辑**：
   - 当前两个补丁实现相似但略有不同
   - 建议提取公共逻辑到共享头文件

2. **支持更多 Shell**：
   - 考虑为 fish、xonsh 等现代 shell 提供类似补丁

3. **动态配置**：
   - 支持通过配置文件而非仅环境变量控制行为
   - 允许某些命令绕过 wrapper（白名单）

**长期改进**：

1. **内核级解决方案**：
   - 考虑使用 Linux BPF 或 macOS kauth 实现更可靠的拦截
   - 减少对用户空间 shell 的依赖

2. **标准化提案**：
   - 向 Bash/Zsh 上游提交 `EXEC_WRAPPER` 支持补丁
   - 推动成为 shell 标准功能

### 6.4 测试建议

1. **增加压力测试**：
   - 高频并发 execve 调用
   - 大参数列表测试
   - 特殊字符和 Unicode 路径测试

2. **安全审计**：
   - 模糊测试环境变量处理
   - 检查内存安全（使用 AddressSanitizer）

3. **集成测试**：
   - 完整端到端测试（从 Codex CLI 到实际命令执行）
   - 不同 Linux 发行版和 macOS 版本测试

---

## 7. 附录

### 7.1 补丁应用示例

```bash
# Bash
git clone https://git.savannah.gnu.org/git/bash
cd bash
git checkout a8a1c2fac029404d3f42cd39f5a20f24b6e4fe4b
git apply /path/to/shell-tool-mcp/patches/bash-exec-wrapper.patch
./configure --without-bash-malloc
make -j"$(nproc)"

# Zsh
git clone https://github.com/zsh-users/zsh
cd zsh
git apply /path/to/shell-tool-mcp/patches/zsh-exec-wrapper.patch
./configure
make -j"$(nproc)"
```

### 7.2 相关文档链接

- [Codex .rules 文档](https://developers.openai.com/codex/local-config#rules-preview)
- [MCP Elicitation 规范](https://modelcontextprotocol.io/specification/draft/client/elicitation)
- [execve(2) 手册](https://man7.org/linux/man-pages/man2/execve.2.html)

### 7.3 文件引用汇总

```
shell-tool-mcp/
├── patches/
│   ├── bash-exec-wrapper.patch      # 本研究核心对象
│   └── zsh-exec-wrapper.patch       # 本研究核心对象
├── src/
│   ├── index.ts                     # MCP Server 入口
│   ├── bashSelection.ts             # Bash 版本选择
│   ├── constants.ts                 # 支持的平台定义
│   ├── types.ts                     # TypeScript 类型定义
│   ├── platform.ts                  # 目标三元组解析
│   └── osRelease.ts                 # /etc/os-release 解析
├── tests/
│   ├── bashSelection.test.ts        # Bash 选择测试
│   └── osRelease.test.ts            # OS 检测测试
├── README.md                        # 使用文档
└── package.json                     # NPM 配置

codex-rs/shell-escalation/
├── src/
│   ├── bin/main_execve_wrapper.rs   # execve-wrapper 入口
│   └── unix/
│       ├── mod.rs                   # 模块文档和导出
│       ├── escalate_server.rs       # 升级服务器实现
│       ├── escalate_client.rs       # 客户端实现
│       ├── escalate_protocol.rs     # 通信协议定义
│       ├── escalation_policy.rs     # 策略接口
│       ├── execve_wrapper.rs        # CLI 解析
│       └── socket.rs                # Socket 工具
├── README.md                        # 补丁应用指南
└── Cargo.toml                       # Crate 配置
```

---

*研究完成时间：2026-03-22*
*研究范围：shell-tool-mcp/patches 及其直接依赖*
