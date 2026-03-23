# zsh-exec-wrapper.patch 研究文档

## 场景与职责

此补丁是 Codex Shell MCP 工具对 **Zsh 源代码** 的修改，功能与 Bash 补丁完全对应——在 Zsh 执行外部命令时拦截 `execve(2)` 调用。通过引入 `EXEC_WRAPPER` 环境变量机制，Zsh 在执行任何外部命令前，将执行委托给 wrapper 程序进行权限检查。

### 核心职责
1. **命令拦截**：在 Zsh 的 `zexecve()` 函数中插入钩子
2. **权限仲裁**：通过 wrapper 与 MCP 服务器通信，决定命令是运行、提升权限还是拒绝
3. **多 Shell 支持**：与 Bash 补丁共同工作，为用户提供一致的沙箱体验，无论使用哪种 shell

## 功能点目的

### 核心功能
- **EXEC_WRAPPER 环境变量支持**：当设置时，Zsh 将命令执行委托给 wrapper
- **参数重组**：构建 `wrapper -> original_command -> args...` 的调用链
- **元字符处理**：使用 `unmetafy` 处理 Zsh 内部的元字符编码
- **空白字符检查**：确保 wrapper 路径有效（非空且不以空白开头）

### 与 Bash 补丁的差异
- Zsh 使用 `inblank()` 而非 `whitespace()` 进行空白字符检查
- Zsh 的 `zexecve()` 函数签名和内部逻辑与 Bash 的 `shell_execve()` 不同
- Zsh 需要处理元字符（metafy）转换

## 具体技术实现

### 关键代码分析

```c
char **eep, **exec_argv;
char *orig_pth = pth;
char *exec_wrapper;

// ... 元字符处理 ...

exec_argv = argv;
if ((exec_wrapper = getenv("EXEC_WRAPPER")) &&
    *exec_wrapper && !inblank(*exec_wrapper)) {
    exec_argv = argv - 2;
    exec_argv[0] = exec_wrapper;
    exec_argv[1] = orig_pth;
    pth = exec_wrapper;
}
winch_unblock();
execve(pth, exec_argv, newenvp);
pth = orig_pth;
```

### 执行流程

1. **变量声明**：新增 `exec_argv`, `orig_pth`, `exec_wrapper`
2. **元字符处理**：`unmetafy(pth, NULL)` 将 Zsh 内部格式转换为普通 C 字符串
3. **环境变量检查**：读取 `EXEC_WRAPPER`
4. **有效性验证**：`!inblank(*exec_wrapper)` 检查不以空白字符开头
5. **参数数组前移**：与 Bash 不同，Zsh 使用 `argv - 2`（假设前面有空间）
6. **参数设置**：`exec_argv[0] = wrapper`, `exec_argv[1] = original_path`
7. **路径替换**：`pth = exec_wrapper`
8. **执行**：`execve(pth, exec_argv, newenvp)`
9. **恢复路径**：`pth = orig_pth`（用于后续错误处理）

### 数据结构操作

| 变量 | 类型 | 说明 |
|------|------|------|
| `exec_wrapper` | `char*` | 从环境变量读取的 wrapper 路径 |
| `orig_pth` | `char*` | 原始命令路径的备份 |
| `pth` | `char*` | 最终传递给 `execve` 的可执行路径（被修改后恢复）|
| `exec_argv` | `char**` | 实际传递给 `execve` 的参数数组 |
| `argv` | `char**` | 原始参数数组 |

### 参数数组转换对比

**Bash 补丁**：
```
原数组: [arg0, arg1, arg2, NULL]
操作: memmove(args + 2, args, ...)
新数组: [wrapper, orig, arg0, arg1, arg2, NULL]
```

**Zsh 补丁**：
```
原数组: [arg0, arg1, arg2, NULL]
操作: exec_argv = argv - 2
新数组: [wrapper, orig, arg0, arg1, arg2, NULL]
```

**关键区别**：
- Bash 使用 `memmove` 向后移动（假设数组后面有空间）
- Zsh 使用 `argv - 2` 向前移动（假设数组前面有空间）

### 元字符处理

Zsh 内部使用"元字符"（metafy）编码表示特殊字符：

```c
unmetafy(pth, NULL);  // 将 Zsh 内部格式转为普通 C 字符串
for (eep = argv; *eep; eep++)
    unmetafy(*eep, NULL);  // 同样处理所有参数
```

这是 Zsh 特有的，Bash 不需要这种处理。

## 关键代码路径与文件引用

### 补丁文件
- **位置**：`shell-tool-mcp/patches/zsh-exec-wrapper.patch`
- **目标文件**：Zsh 源码中的 `Src/exec.c`
- **目标函数**：`zexecve()`
- **应用位置**：`Src/exec.c` 第 507 行附近

### 相关实现文件

与 Bash 补丁共享相同的 Rust 实现：

| 文件 | 职责 |
|------|------|
| `codex-rs/shell-escalation/src/unix/execve_wrapper.rs` | wrapper CLI 入口 |
| `codex-rs/shell-escalation/src/unix/escalate_client.rs` | 客户端逻辑 |
| `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 协议定义 |
| `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs` | wrapper 可执行文件入口 |

### 环境变量

与 Bash 完全一致：
```rust
pub const EXEC_WRAPPER_ENV_VAR: &str = "EXEC_WRAPPER";
pub const ESCALATE_SOCKET_ENV_VAR: &str = "CODEX_ESCALATE_SOCKET";
```

## 依赖与外部交互

### 编译依赖
- **Zsh 源码**：需要与特定 Zsh 版本兼容
- **配置**：标准 Zsh 编译流程

### 运行时依赖
- **wrapper 可执行文件**：`codex-execve-wrapper`
- **MCP 服务器**：通过 socket 通信
- **libc**：`execve(2)`, `getenv(3)`

### Zsh 特有的依赖
- **`inblank()`**：Zsh 的空白字符检查函数
- **`unmetafy()`**：Zsh 元字符解码函数
- **`winch_unblock()`**：Zsh 窗口大小信号处理

### 调用链

```
用户输入 Zsh 命令
    ↓
Zsh 解析并准备执行
    ↓
zexecve() 被调用
    ↓
unmetafy() 处理元字符
    ↓
[PATCH 介入] 检查 EXEC_WRAPPER
    ↓
参数前移: exec_argv = argv - 2
    ↓
设置 exec_argv[0]=wrapper, exec_argv[1]=orig_pth
    ↓
winch_unblock() 解除窗口信号阻塞
    ↓
execve(pth, exec_argv, newenvp)
    ↓
[wrapper 执行]
    ↓
与 MCP 服务器通信决策
    ↓
执行或拒绝命令
```

## 风险、边界与改进建议

### 潜在风险

1. **数组越界风险（比 Bash 更严重）**
   ```c
   exec_argv = argv - 2;  // 假设 argv 前面有至少 2 个槽位
   ```
   - Zsh 的 `argv` 数组可能没有前置空间
   - 如果 `argv` 是栈上紧挨着其他变量的数组，`argv - 2` 可能访问无效内存
   - **风险等级**：高（可能导致崩溃或安全漏洞）

2. **元字符处理顺序**
   - `unmetafy` 在检查 `EXEC_WRAPPER` 之前调用
   - 如果 wrapper 路径包含需要元字符编码的字符，可能处理不正确

3. **信号状态**
   - `winch_unblock()` 在修改参数后调用
   - 如果信号处理与 wrapper 执行有竞态条件，可能产生问题

4. **路径恢复逻辑**
   ```c
   execve(pth, exec_argv, newenvp);
   pth = orig_pth;  // 仅在 execve 失败时执行
   ```
   - 这行代码在 `execve` 成功后不会执行（进程被替换）
   - 但代码位置可能引起静态分析工具的警告

### 边界条件

| 场景 | 行为 |
|------|------|
| `EXEC_WRAPPER` 未设置 | 正常执行，`exec_argv = argv` |
| `EXEC_WRAPPER=""` | 正常执行（空字符串检查失败） |
| `EXEC_WRAPPER=" /path"` | 正常执行（空白开头检查失败） |
| `argv` 前面空间不足 | **未定义行为**（可能崩溃） |
| `execve` 失败 | 恢复 `pth = orig_pth`，继续原有错误处理 |

### 与 Bash 补丁的对比

| 方面 | Bash | Zsh |
|------|------|-----|
| 数组扩展方向 | 向后（`args + 2`） | 向前（`argv - 2`） |
| 空白检查 | `whitespace()` | `inblank()` |
| 元字符处理 | 无 | `unmetafy()` |
| 路径恢复 | 无（不恢复） | 显式恢复 `pth` |
| 信号处理 | 无特殊处理 | `winch_unblock()` |

### 改进建议

1. **解决数组越界问题（关键）**
   ```c
   // 建议改为动态分配或类似 Bash 的方式
   if (exec_wrapper && *exec_wrapper && !inblank(*exec_wrapper)) {
       int argc = 0;
       while (argv[argc]) argc++;
       char **new_argv = zalloc((argc + 3) * sizeof(char*));
       new_argv[0] = exec_wrapper;
       new_argv[1] = orig_pth;
       memcpy(new_argv + 2, argv, (argc + 1) * sizeof(char*));
       exec_argv = new_argv;
       pth = exec_wrapper;
   }
   ```

2. **统一空白检查函数**
   - 考虑在两种补丁中使用相同的空白检查逻辑
   - 或者明确文档化为什么使用不同函数

3. **增加防御性检查**
   ```c
   // 检查 wrapper 可执行性
   if (access(exec_wrapper, X_OK) != 0) {
       // 记录警告，回退到直接执行
   }
   ```

4. **元字符处理优化**
   - 确保 wrapper 路径本身也经过适当的字符处理
   - 考虑在 `exec_wrapper` 赋值前对路径进行验证

5. **测试覆盖**
   ```bash
   # 建议的测试用例
   EXEC_WRAPPER=/path/to/wrapper zsh -c "echo test"
   EXEC_WRAPPER="" zsh -c "echo test"
   EXEC_WRAPPER=" /path" zsh -c "echo test"
   
   # 边界测试：长参数列表
   EXEC_WRAPPER=/path/to/wrapper zsh -c 'echo "$@"' -- $(seq 1 10000)
   
   # 特殊字符测试
   EXEC_WRAPPER=/path/to/wrapper zsh -c 'echo "hello\nworld"'
   ```

### 长期维护建议

1. **版本追踪**
   - 记录测试通过的 Zsh 版本
   - 建立 CI 流程测试补丁应用

2. **与上游协调**
   - 考虑向 Zsh 上游提交类似 `BASH_EXEC_WRAPPER` 的官方支持
   - 减少维护私有补丁的负担

3. **文档完善**
   - 在 `codex-rs/shell-escalation/README.md` 中增加 Zsh 特定的说明
   - 记录两种补丁的实现差异和设计决策
