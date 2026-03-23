# command_runner_win.rs 研究文档

## 场景与职责

`command_runner_win.rs` 是 Windows 沙箱系统中**提升权限路径（elevated path）**的核心命令运行器实现。当 Codex CLI 在 Windows 上以 "Elevated" 沙箱级别运行时，该二进制文件会被启动在沙箱用户上下文中，负责：

1. **IPC 管道通信**：通过命名管道与父进程（CLI）建立双向通信通道
2. **受限令牌派生**：从沙箱用户令牌派生具有特定能力 SID 的受限令牌
3. **子进程启动**：通过 ConPTY（TTY 模式）或匿名管道（非 TTY 模式）启动目标进程
4. **I/O 流代理**：将子进程的 stdout/stderr 流式传输回父进程，接收 stdin 和终止信号
5. **生命周期管理**：管理子进程超时、退出码收集和资源清理

与**传统受限令牌路径（legacy restricted-token path）**不同，该运行器通过 IPC 协议与父进程解耦，支持更复杂的交互场景（如 TTY、长时间运行的进程）。

## 功能点目的

### 1. 进程启动与隔离
- **目的**：在沙箱用户上下文中启动目标命令，同时应用细粒度的访问控制策略
- **策略支持**：
  - `ReadOnly`：只读访问策略，使用 `create_readonly_token_with_caps_from`
  - `WorkspaceWrite`：工作区写入策略，使用 `create_workspace_write_token_with_caps_from`

### 2. 双模式 I/O 处理
- **TTY 模式（`tty=true`）**：使用 ConPTY 提供伪终端支持，适用于交互式命令（如 `vim`, `htop`）
- **管道模式（`tty=false`）**：使用匿名管道分离 stdout/stderr，适用于非交互式命令捕获

### 3. 工作目录连接点（CWD Junction）
- **目的**：当 Read ACL Helper 运行时，通过目录连接点（junction）绕过 ACL 限制
- **实现**：调用 `cwd_junction` 模块创建从 `%USERPROFILE%\.codex\.sandbox\cwd\` 到实际 CWD 的符号链接

### 4. 进程生命周期控制
- **超时处理**：支持通过 `timeout_ms` 配置进程最大运行时间
- **优雅终止**：接收 `Terminate` 消息时调用 `TerminateProcess` 强制结束子进程
- **作业对象（Job Object）**：创建 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 作业对象确保子进程树清理

## 具体技术实现

### 关键数据结构

```rust
/// IPC 生成的进程状态
struct IpcSpawnedProcess {
    log_dir: PathBuf,           // 日志目录路径
    pi: PROCESS_INFORMATION,    // Windows 进程信息（含进程/线程句柄）
    stdout_handle: HANDLE,      // 标准输出句柄
    stderr_handle: HANDLE,      // 标准错误句柄（TTY 模式下为 INVALID_HANDLE_VALUE）
    stdin_handle: Option<HANDLE>, // 标准输入句柄（可选）
    hpc_handle: Option<HANDLE>, // ConPTY 伪控制台句柄（TTY 模式下）
}
```

### 核心流程

#### 1. 主入口流程 (`main` 函数)
```
1. 解析命令行参数 --pipe-in 和 --pipe-out
2. 打开命名管道（CreateFileW）
3. 读取 SpawnRequest 帧（read_spawn_request）
4. 调用 spawn_ipc_process 创建子进程
5. 创建 Job Object 并关联子进程（create_job_kill_on_close）
6. 发送 SpawnReady 帧通知父进程
7. 启动输出读取线程（spawn_output_reader）
8. 启动输入处理线程（spawn_input_loop）
9. 等待子进程结束（WaitForSingleObject）
10. 发送 Exit 帧并退出
```

#### 2. 子进程创建流程 (`spawn_ipc_process`)
```
1. 隐藏当前用户配置文件目录（hide_current_user_profile_dir）
2. 解析沙箱策略（parse_policy）
3. 转换能力 SID 字符串为 SID 指针（convert_string_sid_to_sid）
4. 获取当前令牌用于限制（get_current_token_for_restriction）
5. 根据策略创建受限令牌：
   - ReadOnly -> create_readonly_token_with_caps_from
   - WorkspaceWrite -> create_workspace_write_token_with_caps_from
6. 允许空设备访问（allow_null_device）
7. 确定有效工作目录（effective_cwd，可能使用 junction）
8. 根据 tty 标志选择启动方式：
   - tty=true: spawn_conpty_process_as_user（ConPTY）
   - tty=false: spawn_process_with_pipes（匿名管道）
9. 关闭令牌句柄，返回 IpcSpawnedProcess
```

#### 3. 输出流处理 (`spawn_output_reader`)
```rust
// 在独立线程中运行
read_handle_loop(handle, move |chunk| {
    // 将读取的字节编码为 base64
    // 构造 Output 帧（含 stream 标识：Stdout/Stderr）
    // 通过管道写回父进程
})
```

#### 4. 输入处理循环 (`spawn_input_loop`)
```rust
loop {
    match read_frame(&mut reader) {
        Message::Stdin { payload } => {
            // 解码 base64 数据
            // 写入子进程 stdin 句柄（WriteFile）
        }
        Message::Terminate { .. } => {
            // 调用 TerminateProcess 结束子进程
        }
        // 忽略其他消息类型
    }
}
// 循环结束时关闭 stdin 句柄
```

### IPC 协议帧类型

| 方向 | 消息类型 | 用途 |
|------|----------|------|
| Parent -> Runner | `SpawnRequest` | 启动参数（命令、CWD、环境、策略等） |
| Parent -> Runner | `Stdin` | 标准输入数据（base64 编码） |
| Parent -> Runner | `Terminate` | 终止子进程信号 |
| Runner -> Parent | `SpawnReady` | 子进程已启动（含 PID） |
| Runner -> Parent | `Output` | 标准输出/错误数据 |
| Runner -> Parent | `Exit` | 子进程退出（含退出码和超时标志） |
| Runner -> Parent | `Error` | 错误信息（启动失败等） |

### 关键 Windows API 使用

| API | 用途 |
|-----|------|
| `CreateJobObjectW` + `SetInformationJobObject` | 创建带 `KILL_ON_JOB_CLOSE` 的作业对象 |
| `AssignProcessToJobObject` | 将子进程加入作业对象 |
| `CreateFileW` | 打开命名管道 |
| `WaitForSingleObject` | 等待子进程结束或超时 |
| `TerminateProcess` | 强制终止子进程 |
| `GetExitCodeProcess` | 获取子进程退出码 |
| `ClosePseudoConsole` | 关闭 ConPTY 句柄 |

## 关键代码路径与文件引用

### 当前文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `main` | 409-554 | 主入口，协调整个生命周期 |
| `spawn_ipc_process` | 186-316 | 核心进程创建逻辑 |
| `effective_cwd` | 162-184 | 确定有效工作目录（含 junction 逻辑） |
| `read_spawn_request` | 146-159 | 读取并验证初始帧 |
| `spawn_output_reader` | 319-344 | 启动输出流读取线程 |
| `spawn_input_loop` | 347-406 | 处理 stdin 和终止信号 |
| `create_job_kill_on_close` | 88-105 | 创建清理作业对象 |
| `send_error` | 128-143 | 发送错误帧 |
| `open_pipe` | 108-126 | 打开命名管道 |

### 依赖模块

```
command_runner_win.rs
├── cwd_junction.rs (mod cwd_junction)     # CWD junction 创建
├── read_acl_mutex.rs (mod read_acl_mutex) # ACL mutex 检测
└── 外部 crate 依赖：
    ├── codex_windows_sandbox::ipc_framed  # IPC 帧协议
    ├── codex_windows_sandbox::token       # 令牌操作
    ├── codex_windows_sandbox::process     # 进程创建
    ├── codex_windows_sandbox::conpty      # ConPTY 支持
    └── windows_sys::Win32::*              # Windows API
```

### 调用关系图

```
bin/command_runner.rs
    └── command_runner_win.rs::main()
        ├── open_pipe()                    # 打开命名管道
        ├── read_spawn_request()           # 读取启动请求
        ├── spawn_ipc_process()            # 创建子进程
        │   ├── hide_current_user_profile_dir()
        │   ├── parse_policy()
        │   ├── convert_string_sid_to_sid()
        │   ├── get_current_token_for_restriction()
        │   ├── create_*_token_with_caps_from()  # 受限令牌
        │   ├── effective_cwd()            # 可能调用 cwd_junction
        │   ├── spawn_conpty_process_as_user()   # TTY 模式
        │   └── spawn_process_with_pipes()       # 管道模式
        ├── create_job_kill_on_close()
        ├── spawn_output_reader()          # 启动输出线程
        ├── spawn_input_loop()             # 启动输入线程
        └── 等待子进程结束，发送 Exit 帧
```

## 依赖与外部交互

### 输入依赖

| 来源 | 类型 | 说明 |
|------|------|------|
| 命令行参数 | `--pipe-in`, `--pipe-out` | 命名管道路径 |
| IPC 帧 | `SpawnRequest` | 启动参数 |
| 环境变量 | `USERPROFILE` | 用于 junction 根目录 |

### 输出交互

| 目标 | 类型 | 说明 |
|------|------|------|
| 命名管道 | IPC 帧 | SpawnReady, Output, Exit, Error |
| 日志文件 | 文本 | 通过 `log_note` 记录诊断信息 |

### 外部系统交互

| 系统 | 交互方式 | 目的 |
|------|----------|------|
| Windows 安全子系统 | SID/令牌 API | 创建受限令牌 |
| Windows 进程管理 | CreateProcessAsUserW | 启动沙箱进程 |
| Windows 作业对象 | Job Object API | 进程树生命周期管理 |
| Windows 控制台 | ConPTY API | TTY 支持 |
| Windows 文件系统 | Junction（mklink） | CWD 重定向 |

## 风险、边界与改进建议

### 已知风险

1. **令牌句柄泄漏风险**
   - 在 `spawn_ipc_process` 中，如果 `create_*_token_with_caps_from` 失败，基础令牌 `base` 可能未正确关闭
   - 当前代码在成功路径会关闭 `base`，但错误路径需要检查

2. **ConPTY 资源泄漏**
   - `hpc_handle` 仅在成功路径关闭，如果 `spawn_conpty_process_as_user` 成功但后续逻辑 panic，可能泄漏

3. **管道连接超时**
   - `open_pipe` 使用 `CreateFileW` 打开管道，如果父进程未正确创建管道，可能无限阻塞

4. **Junction 残留**
   - 如果进程异常退出，`cwd_junction` 创建的 junction 可能残留在文件系统中

5. **权限提升边界**
   - 该运行器本身在沙箱用户上下文中运行，但创建受限令牌时需要小心处理 SID 内存（使用 `LocalFree`）

### 边界条件

| 边界 | 处理 |
|------|------|
| 空能力 SID 列表 | 显式检查 `cap_psids.is_empty()` 并返回错误 |
| 超时 | `WaitForSingleObject` 使用 `INFINITE` 或 `timeout_ms`，超时后发送 `128+64` 退出码 |
| 管道关闭 | `read_frame` 返回 `Ok(None)` 时优雅退出循环 |
| 无效帧版本 | 检查 `msg.version != 1` 并返回错误 |
| 意外消息类型 | 在输入循环中忽略不相关的消息类型 |

### 改进建议

1. **增强错误上下文**
   ```rust
   // 建议：在 spawn_ipc_process 的每个阶段添加更多上下文
   let policy = parse_policy(&req.policy_json_or_preset)
       .context("parse policy_json_or_preset in spawn_ipc_process")?;
   ```

2. **异步 I/O 考虑**
   - 当前使用阻塞 I/O 和独立线程，可考虑使用 Windows 重叠 I/O 或 async/await 提高并发效率

3. **Junction 清理机制**
   - 考虑在 runner 启动时清理过期的 junction，或添加定期清理任务

4. **管道连接超时**
   - 为 `CreateFileW` 添加超时机制，避免无限阻塞

5. **测试覆盖**
   - 当前文件没有单元测试，建议添加：
     - 帧序列化/反序列化测试
     - 错误帧生成测试
     - 超时处理测试

6. **日志增强**
   - 在关键路径（如令牌创建、进程启动）添加更多结构化日志，便于生产环境故障排查

7. **内存安全**
   - `cap_psids` 中的 SID 指针在 `allow_null_device` 调用后通过 `LocalFree` 释放，确保没有 use-after-free
