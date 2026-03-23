# bash-exec-wrapper.patch 研究文档

## 场景与职责

此补丁是 Codex Shell MCP 工具的核心组件之一，用于在 **Bash 源代码层面** 拦截 `execve(2)` 系统调用。它通过引入 `EXEC_WRAPPER` 环境变量机制，使得 Bash 在执行外部命令前，能够将执行请求转发给一个"包装器"程序（wrapper），从而实现：

1. **命令拦截与审计**：在执行任何外部命令前，先由 wrapper 进行权限检查
2. **权限提升（Escalation）**：允许某些命令在沙箱外执行
3. **命令拒绝（Deny）**：根据策略阻止危险命令的执行

这是 Codex 沙箱安全架构的关键一环——通过修改 Bash 本身，确保所有 `exec()` 调用都被监控，而非仅依赖上层钩子。

## 功能点目的

### 核心功能
- **EXEC_WRAPPER 环境变量支持**：当设置此变量时，Bash 不再直接执行目标命令，而是将执行委托给 wrapper 程序
- **参数重组**：将原始命令和参数重新包装，形成 `wrapper -> original_command -> args...` 的调用链
- **兼容性设计**：检查 wrapper 路径非空且不以空白字符开头，避免误触发

### 安全目标
- 解决 `$PATH` 劫持问题：通过拦截 `execve`，获取真实的可执行文件路径
- 解决别名/函数绕过问题：直接在 C 代码层面拦截，早于 shell 的别名解析

## 具体技术实现

### 关键代码分析

```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    char *orig_command = command;
    larray = strvec_len (args);
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;
    args[1] = orig_command;
    command = exec_wrapper;
}
```

### 执行流程

1. **环境变量检查**：从环境变量读取 `EXEC_WRAPPER`
2. **有效性验证**：确保路径非空且不以空白字符开头（`!whitespace(*exec_wrapper)`）
3. **参数数组扩展**：
   - 原参数数组：`[arg0, arg1, arg2, ..., NULL]`
   - 计算长度 `larray = strvec_len(args)`
   - 使用 `memmove` 将原参数后移 2 个位置
   - 新参数数组：`[wrapper, orig_command, arg0, arg1, arg2, ..., NULL]`
4. **命令替换**：将 `command` 变量指向 wrapper 路径
5. **执行**：调用 `execve(command, args, env)`，实际执行 wrapper

### 数据结构操作

| 变量 | 类型 | 说明 |
|------|------|------|
| `exec_wrapper` | `char*` | 从环境变量读取的 wrapper 路径 |
| `orig_command` | `char*` | 原始命令路径的备份 |
| `larray` | `size_t` | 参数数组长度 |
| `args` | `char**` | 参数数组指针，被原地修改 |
| `command` | `char*` | 最终传递给 `execve` 的可执行路径 |

### 协议交互

wrapper（`codex-execve-wrapper`）与 MCP 服务器之间通过 Unix Domain Socket 通信：

1. **环境变量传递**：`CODEX_ESCALATE_SOCKET` 指定 socket 文件描述符
2. **请求协议**：`EscalateRequest` 包含 file, argv, workdir, env
3. **响应协议**：`EscalateResponse` 包含 action（Run/Escalate/Deny）
4. **文件描述符转发**：在 Escalate 情况下，通过 `SuperExecMessage` 转发 stdin/stdout/stderr

## 关键代码路径与文件引用

### 补丁文件
- **位置**：`shell-tool-mcp/patches/bash-exec-wrapper.patch`
- **目标文件**：Bash 源码中的 `execute_cmd.c`
- **目标函数**：`shell_execve()`
- **应用位置**：`execute_cmd.c` 第 6129 行附近（在 `execve()` 调用之前）

### 相关实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/shell-escalation/src/unix/execve_wrapper.rs` | wrapper 的 CLI 入口，参数解析 |
| `codex-rs/shell-escalation/src/unix/escalate_client.rs` | 客户端逻辑，发送 EscalateRequest，处理响应 |
| `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 协议定义：请求/响应结构、环境变量常量 |
| `codex-rs/shell-escalation/src/unix/escalate_server.rs` | 服务器端逻辑，决策执行策略 |
| `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs` | wrapper 可执行文件的 main 入口 |

### 环境变量常量

```rust
// codex-rs/shell-escalation/src/unix/escalate_protocol.rs
pub const ESCALATE_SOCKET_ENV_VAR: &str = "CODEX_ESCALATE_SOCKET";
pub const EXEC_WRAPPER_ENV_VAR: &str = "EXEC_WRAPPER";
pub const LEGACY_BASH_EXEC_WRAPPER_ENV_VAR: &str = "BASH_EXEC_WRAPPER";  // 兼容旧版本
```

## 依赖与外部交互

### 编译依赖
- **Bash 源码**：基于 Bash commit `a8a1c2fac029404d3f42cd39f5a20f24b6e4fe4b`
- **编译配置**：`./configure --without-bash-malloc`

### 运行时依赖
- **wrapper 可执行文件**：`codex-execve-wrapper` 必须在 `EXEC_WRAPPER` 指定的路径
- **MCP 服务器**：通过 `CODEX_ESCALATE_SOCKET` 进行通信
- **libc**：使用标准 `execve(2)`、`getenv(3)`、`memmove(3)`

### 调用链

```
用户输入命令 (如 "ls -la")
    ↓
Bash 解析命令
    ↓
shell_execve() 准备执行 /bin/ls
    ↓
[PATCH 介入] 检查 EXEC_WRAPPER
    ↓
重组参数: [codex-execve-wrapper, /bin/ls, ls, -la]
    ↓
execve(codex-execve-wrapper, ...)
    ↓
codex-execve-wrapper 解析参数
    ↓
通过 CODEX_ESCALATE_SOCKET 发送 EscalateRequest
    ↓
MCP Server 决策 (Run/Escalate/Deny)
    ↓
执行原始命令或返回错误
```

## 风险、边界与改进建议

### 潜在风险

1. **内存安全问题**
   - `memmove(args + 2, args, (++larray) * sizeof(char *))` 假设 args 数组前有足够空间
   - 如果 args 数组是紧贴着栈底分配的，后移操作可能溢出
   - **缓解**：Bash 的参数数组通常有额外空间，但这不是标准保证

2. **环境变量注入**
   - 如果攻击者能控制 `EXEC_WRAPPER`，可以执行任意代码
   - **缓解**：wrapper 本身应该被严格保护，且环境变量继承需要审计

3. **兼容性问题**
   - 补丁针对特定 Bash 版本，升级 Bash 可能需要重新打补丁
   - 空白字符检查 `!whitespace(*exec_wrapper)` 可能不够严格

4. **性能开销**
   - 每个外部命令都增加了 IPC 往返（socket 通信）
   - 高频命令（如循环中的命令）可能产生显著延迟

### 边界条件

| 场景 | 行为 |
|------|------|
| `EXEC_WRAPPER` 未设置 | 正常执行，无拦截 |
| `EXEC_WRAPPER=""` | 正常执行（空字符串检查） |
| `EXEC_WRAPPER=" /path"` | 正常执行（空白字符开头检查） |
| `EXEC_WRAPPER` 指向不存在的文件 | `execve` 失败，返回 ENOENT |
| 参数数组为空 | `strvec_len` 返回 0，`memmove` 安全 |

### 改进建议

1. **更严格的验证**
   ```c
   // 建议增加路径存在性检查
   if (exec_wrapper && *exec_wrapper && !whitespace(*exec_wrapper)) {
       if (access(exec_wrapper, X_OK) != 0) {
           // 回退到直接执行或报错
       }
   }
   ```

2. **避免重复初始化**
   - 当前每次 `shell_execve` 都调用 `getenv`，可以缓存结果

3. **错误处理增强**
   - 当前补丁在 wrapper 执行失败时直接返回 `execve` 的错误
   - 建议增加更详细的日志，便于调试

4. **与 zsh 补丁统一**
   - 对比 `zsh-exec-wrapper.patch`，两者逻辑相似但实现细节有差异
   - 建议统一验证逻辑和错误处理

5. **文档化版本兼容性**
   - 明确记录测试过的 Bash 版本范围
   - 提供自动化测试脚本验证补丁应用

### 测试建议

```bash
# 基础功能测试
EXEC_WRAPPER=/path/to/codex-execve-wrapper bash -c "ls"

# 边界测试
EXEC_WRAPPER="" bash -c "ls"  # 应正常执行
EXEC_WRAPPER=" /path" bash -c "ls"  # 应正常执行（空格开头）

# 错误处理测试
EXEC_WRAPPER=/nonexistent bash -c "ls"  # 应报错
```
