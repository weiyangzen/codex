# ConPTY 模块研究文档

## 文件信息
- **路径**: `codex-rs/windows-sandbox-rs/src/conpty/mod.rs`
- **大小**: 5,388 bytes
- **所属 crate**: `codex-windows-sandbox`

---

## 场景与职责

### 核心定位
ConPTY 模块是 Windows 沙箱系统中负责**伪终端（Pseudo Console）创建与管理**的核心组件。它封装了 Windows ConPTY API 的底层细节，为沙箱进程提供交互式终端支持。

### 使用场景
1. **TTY 模式执行**: 当 `unified_exec` 以 `tty=true` 运行时，需要通过 ConPTY 提供交互式终端体验
2. **遗留受限令牌路径**: 传统受限令牌沙箱路径中需要 PTY 支持的场景
3. **特权运行器路径**: 在提升权限的运行器（elevated runner）中创建带 PTY 的沙箱进程

### 设计原则
- **与 IPC 层解耦**: 不依赖 IPC 层，可被其他需要 PTY 的 Windows 沙箱流程复用
- **RAII 资源管理**: 通过 `Drop` trait 自动清理 ConPTY 句柄和管道
- **统一入口**: `spawn_conpty_process_as_user` 作为主要的共享入口点

---

## 功能点目的

### 1. ConPTY 实例管理 (`ConptyInstance`)

```rust
pub struct ConptyInstance {
    pub hpc: HANDLE,           // ConPTY 伪控制台句柄
    pub input_write: HANDLE,   // 输入管道写入端
    pub output_read: HANDLE,   // 输出管道读取端
    _desktop: LaunchDesktop,   // 桌面环境（防止过早释放）
}
```

**目的**: 封装 ConPTY 的核心句柄，确保资源生命周期正确管理。

**关键行为**:
- `Drop` 实现按正确顺序清理资源：先关闭管道，再关闭伪控制台
- `into_raw()` 允许消费者获取原始句柄而不触发清理

### 2. ConPTY 创建 (`create_conpty`)

**目的**: 创建指定尺寸的 ConPTY 实例。

**默认尺寸**: 80列 × 24行（标准终端尺寸）

**实现细节**:
- 调用 `RawConPty::new()` 创建底层 ConPTY
- 使用 `LaunchDesktop::prepare(false, None)` 准备默认桌面环境
- 将 `RawConPty` 的句柄转换为 Windows 句柄类型

### 3. 进程创建与 ConPTY 绑定 (`spawn_conpty_process_as_user`)

**目的**: 在指定用户令牌下创建带 ConPTY 的沙箱进程。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `h_token` | `HANDLE` | 用户主令牌（受限令牌或普通令牌） |
| `argv` | `&[String]` | 命令行参数数组 |
| `cwd` | `&Path` | 工作目录 |
| `env_map` | `&HashMap<String, String>` | 环境变量映射 |
| `use_private_desktop` | `bool` | 是否使用私有桌面 |
| `logs_base_dir` | `Option<&Path>` | 日志目录 |

**核心流程**:
1. 命令行参数转义与拼接（使用 `quote_windows_arg`）
2. 创建环境块（调用 `make_env_block`）
3. 初始化 `STARTUPINFOEXW` 结构
4. 准备桌面环境（`LaunchDesktop::prepare`）
5. 创建 ConPTY 实例（80×24 默认尺寸）
6. 创建并配置线程属性列表（`ProcThreadAttributeList`）
7. 设置 `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` 属性
8. 调用 `CreateProcessAsUserW` 创建进程

---

## 具体技术实现

### 关键数据结构

#### STARTUPINFOEXW 配置
```rust
let mut si: STARTUPINFOEXW = unsafe { std::mem::zeroed() };
si.StartupInfo.cb = std::mem::size_of::<STARTUPINFOEXW>() as u32;
si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
si.StartupInfo.hStdInput = INVALID_HANDLE_VALUE;
si.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
si.StartupInfo.hStdError = INVALID_HANDLE_VALUE;
```

**注意**: 标准句柄设置为 `INVALID_HANDLE_VALUE`，因为 ConPTY 会接管这些句柄。

#### 进程创建标志
```rust
EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT
```

- `EXTENDED_STARTUPINFO_PRESENT`: 启用扩展启动信息（`STARTUPINFOEXW`）
- `CREATE_UNICODE_ENVIRONMENT`: 使用 Unicode 环境块

### 关键流程

```
spawn_conpty_process_as_user
├── 命令行参数处理 (quote_windows_arg + join)
├── 环境块创建 (make_env_block)
├── STARTUPINFOEXW 初始化
├── LaunchDesktop::prepare
│   └── 创建或使用默认桌面
├── create_conpty
│   └── RawConPty::new(80, 24)
│       └── 创建管道 + PsuedoCon
├── ProcThreadAttributeList::new(1)
├── attrs.set_pseudoconsole(hpc)
│   └── UpdateProcThreadAttribute
│       └── PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
└── CreateProcessAsUserW
    └── 返回 (PROCESS_INFORMATION, ConptyInstance)
```

### 错误处理

创建失败时返回详细的错误信息，包含：
- Win32 错误码和描述
- 当前工作目录
- 完整命令行
- 环境块长度

```rust
return Err(anyhow::anyhow!(
    "CreateProcessAsUserW failed: {} ({}) | cwd={} | cmd={} | env_u16_len={}",
    err, format_last_error(err), cwd.display(), cmdline_str, env_block.len()
));
```

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 依赖内容 | 用途 |
|------|----------|------|
| `proc_thread_attr.rs` | `ProcThreadAttributeList` | 线程属性列表管理 |
| `../desktop.rs` | `LaunchDesktop` | 桌面环境准备 |
| `../winutil.rs` | `format_last_error`, `quote_windows_arg`, `to_wide` | 工具函数 |
| `../process.rs` | `make_env_block` | 环境块创建 |

### 外部依赖

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex-utils-pty` | `RawConPty` | 底层 ConPTY 实现 |
| `windows-sys` | `Win32::System::Console`, `Win32::System::Threading` | Win32 API |
| `anyhow` | `Result`, `anyhow!` | 错误处理 |

### 调用方

| 文件 | 调用函数 | 场景 |
|------|----------|------|
| `elevated/command_runner_win.rs` | `spawn_conpty_process_as_user` | 特权运行器 TTY 模式 |

---

## 依赖与外部交互

### Windows API 依赖

#### Console API
- `ClosePseudoConsole`: 关闭伪控制台

#### 进程管理 API
- `CreateProcessAsUserW`: 以指定用户身份创建进程
- `EXTENDED_STARTUPINFO_PRESENT`: 扩展启动信息标志
- `CREATE_UNICODE_ENVIRONMENT`: Unicode 环境标志
- `STARTF_USESTDHANDLES`: 使用标准句柄标志

### 与 RawConPty 的交互

```rust
// codex-rs/utils/pty/src/win/conpty.rs
pub struct RawConPty {
    con: PsuedoCon,
    input_write: FileDescriptor,
    output_read: FileDescriptor,
}
```

`RawConPty` 来自 `codex-utils-pty` crate，是对 `wezterm` 项目中 ConPTY 实现的封装（MIT 许可证）。它提供了：
- `new(cols, rows)`: 创建指定尺寸的 ConPTY
- `into_raw_handles()`: 获取底层句柄（不转移所有权）

### 与 LaunchDesktop 的交互

`LaunchDesktop` 负责准备进程运行的桌面环境：
- 默认桌面：`Winsta0\Default`
- 私有桌面：`Winsta0\CodexSandboxDesktop-{随机ID}`

ConPTY 进程需要正确的桌面设置，否则某些进程（如 PowerShell）可能因 `STATUS_DLL_INIT_FAILED` 失败。

---

## 风险、边界与改进建议

### 已知风险

#### 1. 硬编码终端尺寸
```rust
let conpty = create_conpty(80, 24)?;
```
**问题**: 终端尺寸固定为 80×24，无法动态调整。

**影响**: 在现代化宽屏终端中可能导致显示问题。

**建议**: 从调用方接收终端尺寸参数，或支持运行时 resize。

#### 2. 桌面句柄生命周期
```rust
conpty._desktop = desktop;
```
**问题**: `ConptyInstance` 持有 `LaunchDesktop`，但仅在 `spawn_conpty_process_as_user` 中更新。

**潜在问题**: `create_conpty` 中创建的 `_desktop` 在进程创建后可能被丢弃，但 `ConptyInstance` 仍持有它。

#### 3. 错误信息泄露风险
错误信息包含完整命令行和工作目录，在日志中可能泄露敏感信息。

### 边界条件

| 场景 | 行为 | 说明 |
|------|------|------|
| 空参数列表 | 正常处理 | `argv` 为空时生成空命令行 |
| 长环境变量 | 可能失败 | 环境块长度受 Win32 限制 |
| 特殊字符参数 | 正确转义 | `quote_windows_arg` 处理 |
| 无效工作目录 | 创建失败 | `CreateProcessAsUserW` 返回错误 |

### 改进建议

#### 1. 支持动态终端尺寸
```rust
pub fn spawn_conpty_process_as_user(
    h_token: HANDLE,
    argv: &[String],
    cwd: &Path,
    env_map: &HashMap<String, String>,
    use_private_desktop: bool,
    logs_base_dir: Option<&Path>,
    cols: i16,  // 新增
    rows: i16,  // 新增
) -> Result<(PROCESS_INFORMATION, ConptyInstance)>
```

#### 2. 添加 ConPTY 尺寸调整支持
考虑暴露 `ResizePseudoConsole` API，允许运行时调整终端尺寸。

#### 3. 改进错误处理
- 对敏感信息进行脱敏处理
- 添加结构化错误类型，便于调用方区分错误原因

#### 4. 文档完善
- 添加更多使用示例
- 说明 `use_private_desktop` 的使用场景和影响

### 测试建议

当前模块缺乏单元测试，建议添加：
1. `create_conpty` 成功/失败场景测试
2. 命令行参数转义正确性验证
3. 资源清理验证（通过句柄泄漏检测）
4. 与 `RawConPty` 集成的端到端测试

---

## 相关文档

- [Windows ConPTY API](https://docs.microsoft.com/en-us/windows/console/pseudoconsoles)
- [wezterm ConPTY 实现](https://github.com/wezterm/wezterm)
- `codex-rs/utils/pty/src/win/conpty.rs`: 底层 ConPTY 封装
- `codex-rs/windows-sandbox-rs/src/desktop.rs`: 桌面环境管理
